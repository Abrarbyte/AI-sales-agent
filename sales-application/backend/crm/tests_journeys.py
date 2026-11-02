"""Forty leads, each walked through the whole pipeline over the API, then
checked as a set (#11).

The audit ran this by hand from a scratch file: twenty journeys in round 1,
twenty more in round 2, then looked for anything that didn't add up. It
found most of the bugs fixed since. This keeps it: every journey goes
through the same API the phone app and console use, and the checks at the
end are the ones the audit made - now they run on every pull request.

Each journey varies the deal: size, discount, payment terms, how many
demos, who owns it, and how it ends (a customer paid in full and completed,
a customer still paying, lost at some stage, lost then reopened and won, or
a returning client's second project).
"""

from datetime import timedelta
from decimal import Decimal

from django.utils import timezone
from rest_framework.test import APITestCase

from accounts.models import User
from common.testing import make_team, make_user
from crm.models import Customer, Lead, Product
from crm.negotiations import Negotiation, price_after_discount
from delivery.models import Delivery, project_status_from
from visits.models import FollowUp

TERMS = ("full_advance", "half_half", "advance_30", "milestones")
SHARE = {"full_advance": Decimal("1.00"), "half_half": Decimal("0.50")}
MILESTONES = ("design_approval", "development_complete", "uat", "go_live", "handover")
ENDINGS = ("completed", "paying", "lost_at_demo", "lost_at_negotiation",
           "lost_at_proposal", "reopened_and_won", "returning_client", "still_open")


class FortyJourneys(APITestCase):

    @classmethod
    def setUpTestData(cls):
        cls.admin, cls.manager, cls.rep, _ = make_team()
        cls.rep2 = make_user("t_employee2", User.Role.EMPLOYEE, manager=cls.manager)
        cls.product = Product.objects.create(name="Website (CMS)")

    # --- the API, as each person uses it -----------------------------------

    def call(self, user, method, url, data=None, fmt="json", expect=(200, 201)):
        self.client.force_authenticate(user)
        r = getattr(self.client, method)(url, data or {}, format=fmt)
        self.assertIn(r.status_code, expect, f"{method.upper()} {url}: {getattr(r, 'data', '')}")
        return getattr(r, "data", None)  # the receipt is a PDF, not JSON

    def journey(self, n):
        ending = ENDINGS[n % len(ENDINGS)]
        terms = TERMS[n % len(TERMS)]
        quote = Decimal(10000 + (n * 37 % 120) * 10000)          # 10k .. 12L
        discount = Decimal(n % 4 * 5)                            # 0, 5, 10, 15 %
        price = price_after_discount(quote, discount)
        rep = self.rep if n % 3 else self.rep2
        soon = (timezone.now() + timedelta(days=1 + n % 5)).isoformat()

        lead = self.call(rep, "post", "/api/crm/leads/", {
            "name": f"Client {n}", "company_name": f"Company {n}",
            "phone": f"98{n:08d}", "project_type": "website",
            "requirement": f"Website for company {n}", "source": "referral"})
        lead_id = lead["id"]
        self.call(rep, "post", "/api/visits/followups/", {
            "lead": lead_id, "kind": "call", "due_at": soon})

        # One or two demos; a first one that was rescheduled for some.
        if n % 5 == 0:
            self.call(rep, "post", "/api/crm/demos/", self.demo(lead_id, "rescheduled"))
        self.call(rep, "post", "/api/crm/demos/", self.demo(lead_id, "successful"))
        if ending == "lost_at_demo":
            return self.lose(rep, lead_id, "no_budget")

        # Some are handed to the other rep half way through.
        if n % 7 == 0:
            rep = self.rep2 if rep == self.rep else self.rep
            self.call(self.manager, "patch", f"/api/crm/leads/{lead_id}/",
                      {"assigned_to": rep.id})

        neg = self.call(rep, "post", "/api/crm/negotiations/", {
            "lead": lead_id, "quoted_amount": str(quote), "discount_pct": str(discount),
            "payment_terms": terms, "timeline_weeks": 2 + n % 14,
            "expected_close_on": str(timezone.localdate() + timedelta(days=10))})
        if ending == "lost_at_negotiation":
            return self.lose(rep, lead_id, "other_agency")
        if ending == "still_open":
            return

        self.call(rep, "patch", f"/api/crm/negotiations/{neg['id']}/",
                  {"status": "proposal_sent"})
        if ending == "lost_at_proposal":
            return self.lose(rep, lead_id, "price")
        if ending == "reopened_and_won":
            self.lose(rep, lead_id, "no_response")
            self.call(self.manager, "patch", f"/api/crm/leads/{lead_id}/", {
                "status": "proposal", "stage_change_reason": "They called back"})

        # Converting before the deposit is in is refused, then allowed.
        deposit = (price * SHARE.get(terms, Decimal("0.30"))).quantize(Decimal("0.01"))
        if n % 2 == 0 and deposit > 0:
            self.call(rep, "post", f"/api/crm/leads/{lead_id}/convert/", expect=(409,))
        self.call(rep, "patch", f"/api/crm/leads/{lead_id}/", {"amount_paid": str(deposit)})
        customer = self.call(rep, "post", f"/api/crm/leads/{lead_id}/convert/")

        if ending == "returning_client":
            # Their next project: same phone, converts into the same customer.
            again = self.call(rep, "post", "/api/crm/leads/", {
                "name": f"Client {n}", "phone": f"98{n:08d}", "requirement": "An app too"})
            n2 = self.call(rep, "post", "/api/crm/negotiations/", {
                "lead": again["id"], "quoted_amount": "50000", "payment_terms": "advance_30"})
            self.call(rep, "patch", f"/api/crm/negotiations/{n2['id']}/",
                      {"status": "proposal_sent"})
            self.call(rep, "patch", f"/api/crm/leads/{again['id']}/", {"amount_paid": "15000"})
            linked = self.call(rep, "post", f"/api/crm/leads/{again['id']}/convert/")
            self.assertEqual(linked["id"], customer["id"])
            return

        # Milestones from the console; the balance paid in two parts.
        cid = customer["id"]
        steps = MILESTONES if ending == "completed" else MILESTONES[:2]
        for i, milestone in enumerate(steps):
            d = self.call(self.admin, "post", "/api/delivery/deliveries/", {
                "customer": cid, "product": self.product.id, "milestone": milestone,
                "scheduled_on": str(timezone.localdate() + timedelta(days=i))})
            self.call(rep, "post", f"/api/delivery/deliveries/{d['id']}/deliver/",
                      {"received_by": f"Client {n}"}, fmt="multipart")
        balance = Decimal(self.call(rep, "get", f"/api/crm/customers/{cid}/")["balance"])
        if balance > 0:
            first = (balance / 2).quantize(Decimal("0.01"))
            self.call(rep, "post", f"/api/crm/customers/{cid}/payments/",
                      {"amount": str(first), "method": "upi", "reference": f"UTR{n}"})
            if ending == "completed":
                self.call(self.admin, "post", f"/api/crm/customers/{cid}/complete/",
                          expect=(409,))
                self.call(rep, "post", f"/api/crm/customers/{cid}/payments/",
                          {"amount": str(balance - first), "method": "bank_transfer"})
        if ending == "completed":
            self.call(self.admin, "post", f"/api/crm/customers/{cid}/complete/")
            self.call(self.admin, "get", f"/api/crm/customers/{cid}/receipt.pdf")

    def demo(self, lead_id, outcome):
        return {"lead": lead_id, "held_at": timezone.now().isoformat(),
                "outcome": outcome, "mode": "online", "product": "Website (CMS)"}

    def lose(self, rep, lead_id, reason):
        self.call(rep, "patch", f"/api/crm/leads/{lead_id}/",
                  {"status": "closed", "lost_reason": reason})

    # --- the checks, across every journey ----------------------------------

    def test_forty_journeys_add_up(self):
        for n in range(40):
            with self.subTest(journey=n):
                self.journey(n)

        leads = list(Lead.objects.select_related("converted_customer"))
        self.assertEqual(len(leads), 45)  # 40, plus 5 returning clients' second projects

        # Every lead is on a real stage; a customer's lead has its customer.
        for lead in leads:
            self.assertIn(lead.status, Lead.Status.values)
            self.assertEqual(lead.status == "converted", lead.converted_customer_id is not None)

        # A lost lead says why, and nothing is still booked for it.
        lost = [lead for lead in leads if lead.status == "closed"]
        self.assertEqual(len(lost), 15)
        self.assertTrue(all(lead.lost_reason for lead in lost))
        self.assertFalse(FollowUp.objects.filter(
            lead__in=lost, status=FollowUp.Status.PENDING).exists())

        # A deal with a quote shows a price; won and lost live on the lead.
        for lead in leads:
            neg = getattr(lead, "negotiation", None)
            if neg is not None and neg.quoted_amount is not None and lead.status != "closed":
                self.assertIsNotNone(lead.value, lead.name)
        self.assertEqual(set(Negotiation.objects.values_list("status", flat=True)) - set(
            Negotiation.OPEN_STATUSES), set())

        # The deposit was in, by the agreed terms, before anyone converted.
        for lead in leads:
            if lead.status == "converted":
                self.assertGreaterEqual(lead.amount_paid, lead.deposit_required, lead.name)

        # Customers: one per client, price from their leads, never overpaid,
        # status from milestones, completed only when handed over and paid.
        customers = list(Customer.objects.prefetch_related("payments", "origin_leads", "deliveries"))
        self.assertEqual(len(customers), 20)
        self.assertEqual(len({c.phone for c in customers}), 20)
        for c in customers:
            self.assertEqual(c.price, sum(lead.value for lead in c.origin_leads.all()), c.name)
            self.assertLessEqual(c.amount_paid, c.price, c.name)
            derived = project_status_from(
                (d.milestone, d.status) for d in c.deliveries.all())
            if c.completed_at:
                self.assertEqual((c.project_status, c.balance), ("completed", 0))
                self.assertTrue(c.deliveries.filter(
                    milestone="handover", status=Delivery.Status.DELIVERED).exists())
            else:
                self.assertEqual(c.project_status, derived, c.name)
        self.assertEqual(sum(1 for c in customers if c.completed_at), 5)

        # No two open leads for the same client.
        open_phones = [lead.phone for lead in leads if lead.status in Lead.OPEN_STATUSES]
        self.assertEqual(len(open_phones), len(set(open_phones)))
