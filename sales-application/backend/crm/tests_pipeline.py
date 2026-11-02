"""Demo and negotiation: the stages between "being worked" and "paid".

The rule under test is that the lead's status follows the records, never the
other way round: logging a demo moves it to `demo`, opening a negotiation
moves it to `negotiation`, losing one closes it, and none of those stages
can be set by hand without the record behind it.
"""

from datetime import timedelta
from decimal import Decimal

from django.utils import timezone
from rest_framework.test import APITestCase

from common.testing import make_lead, make_team
from crm.models import Demo, Lead, Negotiation, Product
from visits.models import FollowUp


def demo_payload(lead, **extra):
    return {
        "lead": lead.id,
        "held_at": timezone.now().isoformat(),
        "product": "Website (CMS)",
        "outcome": Demo.Outcome.SUCCESSFUL,
        **extra,
    }


class DemoTests(APITestCase):
    def setUp(self):
        self.admin, self.manager, self.employee, self.outsider = make_team()
        self.lead = make_lead("Shown", owner=self.employee,
                              status=Lead.Status.NEW)
        self.client.force_authenticate(self.employee)

    def test_logging_a_demo_moves_the_lead_to_demo(self):
        response = self.client.post("/api/crm/demos/", demo_payload(self.lead))
        self.assertEqual(response.status_code, 201, response.json())
        self.lead.refresh_from_db()
        self.assertEqual(self.lead.status, Lead.Status.DEMO)
        self.assertEqual(response.json()["given_by"], self.employee.id)

    def test_a_demo_does_not_pull_a_lead_backwards(self):
        self.lead.status = Lead.Status.NEGOTIATION
        self.lead.save()
        self.client.post("/api/crm/demos/", demo_payload(self.lead))
        self.lead.refresh_from_db()
        self.assertEqual(self.lead.status, Lead.Status.NEGOTIATION)

    def test_demo_cannot_be_set_by_hand(self):
        response = self.client.patch(
            f"/api/crm/leads/{self.lead.id}/", {"status": "demo"})
        self.assertEqual(response.status_code, 400)
        self.assertIn("status", response.json())

    def test_the_lead_row_carries_the_latest_demo(self):
        old = timezone.now() - timedelta(days=3)
        Demo.objects.create(lead=self.lead, held_at=old, product="Old",
                            outcome=Demo.Outcome.PARTIAL)
        Demo.objects.create(lead=self.lead, held_at=timezone.now(),
                            product="New", outcome=Demo.Outcome.SUCCESSFUL)
        row = self.client.get(f"/api/crm/leads/{self.lead.id}/").json()
        self.assertEqual(row["demo_count"], 2)
        self.assertEqual(row["latest_demo"]["product"], "New")
        self.assertEqual(row["latest_demo"]["outcome"], Demo.Outcome.SUCCESSFUL)

    def test_followup_must_belong_to_the_same_lead(self):
        other = make_lead("Other", owner=self.employee)
        followup = FollowUp.objects.create(
            assigned_to=self.employee, lead=other,
            due_at=timezone.now() + timedelta(days=1))
        response = self.client.post(
            "/api/crm/demos/", demo_payload(self.lead, followup=followup.id))
        self.assertEqual(response.status_code, 400)
        self.assertIn("followup", response.json())

    def test_outsider_cannot_see_the_demo(self):
        self.client.post("/api/crm/demos/", demo_payload(self.lead))
        self.client.force_authenticate(self.outsider)
        self.assertEqual(self.client.get("/api/crm/demos/").json(), [])

    def test_manager_sees_their_teams_demos(self):
        self.client.post("/api/crm/demos/", demo_payload(self.lead))
        self.client.force_authenticate(self.manager)
        self.assertEqual(len(self.client.get("/api/crm/demos/").json()), 1)


class NegotiationTests(APITestCase):
    def setUp(self):
        self.admin, self.manager, self.employee, self.outsider = make_team()
        self.lead = make_lead("Talking", owner=self.employee,
                              status=Lead.Status.DEMO,
                              requirement="Ten units by March",
                              value=Decimal("10000"))
        self.client.force_authenticate(self.employee)

    def open(self, **extra):
        return self.client.post("/api/crm/negotiations/", {
            "lead": self.lead.id, "decision_maker": "The owner", **extra})

    def test_opening_moves_the_lead(self):
        response = self.open()
        self.assertEqual(response.status_code, 201, response.json())
        self.lead.refresh_from_db()
        self.assertEqual(self.lead.status, Lead.Status.NEGOTIATION)
        # What they want stays on the lead, the one place for it (#48).
        self.assertEqual(self.lead.requirement, "Ten units by March")
        body = response.json()
        self.assertNotIn("requirements", body)
        self.assertEqual(body["owner"], self.employee.id)
        self.assertEqual(body["started_at"], str(timezone.localdate()))

    def test_one_negotiation_per_lead(self):
        self.open()
        response = self.open()
        self.assertEqual(response.status_code, 400)
        self.assertIn("lead", response.json())

    def test_negotiation_cannot_be_set_by_hand(self):
        response = self.client.patch(
            f"/api/crm/leads/{self.lead.id}/", {"status": "negotiation"})
        self.assertEqual(response.status_code, 400)

    def test_closing_date_cannot_precede_start(self):
        response = self.open(
            started_at="2026-09-10", expected_close_on="2026-09-01")
        self.assertEqual(response.status_code, 400)
        self.assertIn("expected_close_on", response.json())

    def test_a_negotiation_cannot_be_marked_won_or_lost(self):
        """The outcome lives on the lead (#28): win by converting, lose by
        marking the lead lost. A negotiation saying either used to disagree
        with its lead."""
        negotiation_id = self.open().json()["id"]
        for outcome in ("won", "lost"):
            response = self.client.patch(
                f"/api/crm/negotiations/{negotiation_id}/", {"status": outcome})
            self.assertEqual(response.status_code, 400, outcome)
            self.assertIn("mark the lead as lost", response.json()["status"][0])
        self.lead.refresh_from_db()
        self.assertEqual(self.lead.status, Lead.Status.NEGOTIATION)

    def test_convert_from_negotiation_sets_customer_since(self):
        self.open()
        self.lead.amount_paid = Decimal("3000")
        self.lead.save()
        response = self.client.post(f"/api/crm/leads/{self.lead.id}/convert/")
        self.assertEqual(response.status_code, 201, response.json())
        self.assertEqual(response.json()["customer_since"],
                         str(timezone.localdate()))
        self.assertIsNone(response.json()["delivery_status"])

    def test_a_closed_lead_cannot_convert(self):
        """Closed is an exit. A lead that comes back is reopened first, so
        the record shows it happened."""
        self.lead.status = Lead.Status.CLOSED
        self.lead.amount_paid = Decimal("3000")
        self.lead.save()
        response = self.client.post(f"/api/crm/leads/{self.lead.id}/convert/")
        self.assertEqual(response.status_code, 409)
        # Shown to people as "Lost" since #22; the stored value is still "closed".
        self.assertIn("lost", response.json()["detail"].lower())
        self.lead.refresh_from_db()
        self.assertFalse(self.lead.is_converted)

    def test_the_phone_flow_record_money_then_convert(self):
        """What the app's Convert sheet does: PATCH value + amount_paid,
        then POST /convert/. Pinned here so the two calls stay compatible."""
        response = self.client.patch(f"/api/crm/leads/{self.lead.id}/", {
            "value": "100000.00", "amount_paid": "30000.00"})
        self.assertEqual(response.status_code, 200, response.json())
        self.assertTrue(response.json()["deposit_met"])
        response = self.client.post(f"/api/crm/leads/{self.lead.id}/convert/")
        self.assertEqual(response.status_code, 201, response.json())
        customer = response.json()
        self.assertEqual(customer["name"], "Talking")
        self.assertEqual(customer["customer_since"], str(timezone.localdate()))
        # And the manager sees the new customer.
        self.client.force_authenticate(self.manager)
        names = [c["name"] for c in self.client.get("/api/crm/customers/").json()]
        self.assertIn("Talking", names)

    def test_convert_straight_from_demo(self):
        """The diagram allows Demo -> Customer without negotiating."""
        self.lead.amount_paid = Decimal("3000")
        self.lead.save()
        response = self.client.post(f"/api/crm/leads/{self.lead.id}/convert/")
        self.assertEqual(response.status_code, 201)

    def test_slipping_filter(self):
        negotiation_id = self.open(
            expected_close_on=str(timezone.localdate() - timedelta(days=1)),
            started_at=str(timezone.localdate() - timedelta(days=10)),
        ).json()["id"]
        rows = self.client.get("/api/crm/negotiations/?slipping=true").json()
        self.assertEqual([r["id"] for r in rows], [negotiation_id])
        self.assertTrue(rows[0]["is_slipping"])
        row = self.client.get(f"/api/crm/leads/{self.lead.id}/").json()
        self.assertTrue(row["negotiation"]["is_slipping"])


class ProductTests(APITestCase):
    def setUp(self):
        self.admin, self.manager, self.employee, self.outsider = make_team()

    def test_employee_reads_but_cannot_add(self):
        Product.objects.create(name="Website (CMS)")
        self.client.force_authenticate(self.employee)
        self.assertEqual(len(self.client.get("/api/crm/products/").json()), 1)
        response = self.client.post("/api/crm/products/", {"name": "Battery"})
        self.assertEqual(response.status_code, 403)

    def test_manager_adds(self):
        self.client.force_authenticate(self.manager)
        response = self.client.post(
            "/api/crm/products/", {"name": "Battery", "kind": "product"})
        self.assertEqual(response.status_code, 201)

    def test_customer_carries_products(self):
        product = Product.objects.create(name="Website (CMS)")
        self.client.force_authenticate(self.employee)
        response = self.client.post("/api/crm/customers/", {
            "name": "Bought", "phone": "9990003333",
            "products": [product.id], "support_status": "open",
        })
        self.assertEqual(response.status_code, 201, response.json())
        self.assertEqual(response.json()["product_names"], ["Website (CMS)"])
        self.assertEqual(response.json()["support_status"], "open")



class PhoneValidationTests(APITestCase):
    """Phone numbers must be dialable on every record that carries one."""

    def setUp(self):
        _, _, self.employee, _ = make_team()
        self.client.force_authenticate(self.employee)

    def test_lead_rejects_non_numeric_phone(self):
        r = self.client.post("/api/crm/leads/", {"name": "X", "phone": "abc"},
                             format="json")
        self.assertEqual(r.status_code, 400)
        self.assertIn("phone", r.json())

    def test_lead_accepts_international_format(self):
        r = self.client.post("/api/crm/leads/",
                             {"name": "X", "phone": "+91 98200-00000"},
                             format="json")
        self.assertEqual(r.status_code, 201)


class WebAgencyPipelineTests(APITestCase):
    """The fields and stage a website/app agency needs."""

    def setUp(self):
        _, _, self.employee, _ = make_team()
        self.client.force_authenticate(self.employee)

    def test_lead_carries_project_fields(self):
        r = self.client.post("/api/crm/leads/", {
            "name": "Ravi", "phone": "9820011111", "company_name": "Ravi Cafe",
            "designation": "Owner", "industry": "restaurant",
            "project_type": "android_app", "platforms": "both",
            "existing_url": "https://ravicafe.example.com",
            "budget": "80000", "priority": "hot",
        }, format="json")
        self.assertEqual(r.status_code, 201, r.json())
        row = r.json()
        self.assertEqual(row["project_type"], "android_app")
        self.assertEqual(row["platforms"], "both")
        self.assertEqual(row["priority"], "hot")

    def test_platforms_only_for_apps(self):
        r = self.client.post("/api/crm/leads/", {
            "name": "X", "phone": "9820011111",
            "project_type": "website", "platforms": "both",
        }, format="json")
        self.assertEqual(r.status_code, 201)
        self.assertEqual(r.json()["platforms"], "")

    def test_lost_reason_only_when_closed(self):
        lead = make_lead("Open one", owner=self.employee)
        r = self.client.patch(f"/api/crm/leads/{lead.id}/",
                              {"lost_reason": "price"}, format="json")
        self.assertEqual(r.json()["lost_reason"], "")
        r = self.client.patch(f"/api/crm/leads/{lead.id}/",
                              {"status": "closed", "lost_reason": "price"},
                              format="json")
        self.assertEqual(r.json()["lost_reason"], "price")

    def test_proposal_sent_is_its_own_stage(self):
        lead = make_lead("Quote me", owner=self.employee,
                         status=Lead.Status.NEW)
        r = self.client.post("/api/crm/negotiations/", {
            "lead": lead.id, "quoted_amount": "120000",
            "payment_terms": "advance_30", "timeline_weeks": 6,
        }, format="json")
        self.assertEqual(r.status_code, 201, r.json())
        lead.refresh_from_db()
        self.assertEqual(lead.status, Lead.Status.NEGOTIATION)

        self.client.patch(f"/api/crm/negotiations/{r.json()['id']}/",
                          {"status": "proposal_sent"}, format="json")
        lead.refresh_from_db()
        self.assertEqual(lead.status, Lead.Status.PROPOSAL)

        # Not by hand while no proposal has been sent: the stage must have
        # the negotiation's record behind it.
        other = make_lead("Not yet", owner=self.employee, phone="9990001234")
        self.client.post("/api/crm/negotiations/", {"lead": other.id}, format="json")
        r = self.client.patch(f"/api/crm/leads/{other.id}/",
                              {"status": "proposal"}, format="json")
        self.assertEqual(r.status_code, 400)

    def test_proposal_stage_counts_as_open_and_can_convert(self):
        lead = make_lead("Ready", owner=self.employee,
                         status=Lead.Status.PROPOSAL, value=Decimal("10000"),
                         amount_paid=Decimal("3000"))
        r = self.client.post(f"/api/crm/leads/{lead.id}/convert/", {},
                             format="json")
        self.assertEqual(r.status_code, 201, r.json())
