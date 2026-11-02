"""Lead and customer visibility, assignment, and conversion.

The assignment tests are the important ones: `scoping.py` decides who may *see*
a record, and until recently nothing decided who a record could be assigned
*to*, so an employee could push work onto anyone in the company. That is fixed
by `ScopedUserField`, and pinned here.
"""

from datetime import timedelta

from decimal import Decimal

from django.core.management import call_command
from django.utils import timezone
from rest_framework.test import APITestCase

from common.scoping import scope_to_user
from common.testing import make_customer, make_lead, make_team
from crm.models import Customer, Lead


class LeadVisibilityTests(APITestCase):
    def setUp(self):
        self.admin, self.manager, self.employee, self.outsider = make_team()
        self.mine = make_lead("Mine", owner=self.employee)
        self.theirs = make_lead("Theirs", owner=self.outsider)
        # Brought in by the employee, since handed to another team: their
        # manager must still see it, which is why `created_by` is scoped too.
        self.handed_on = make_lead(
            "Handed on", owner=self.outsider, creator=self.employee)

    def names_for(self, user):
        self.client.force_authenticate(user)
        response = self.client.get("/api/crm/leads/")
        self.assertEqual(response.status_code, 200)
        return {row["name"] for row in response.json()}

    def test_employee_sees_their_own_and_what_they_brought_in(self):
        self.assertEqual(self.names_for(self.employee), {"Mine", "Handed on"})

    def test_manager_sees_their_teams_leads(self):
        self.assertEqual(self.names_for(self.manager), {"Mine", "Handed on"})

    def test_admin_sees_everything(self):
        self.assertEqual(
            self.names_for(self.admin), {"Mine", "Theirs", "Handed on"})

    def test_out_of_scope_lead_is_a_404_not_a_403(self):
        """It was never in the candidate set, so it does not exist to them."""
        self.client.force_authenticate(self.employee)
        response = self.client.get(f"/api/crm/leads/{self.theirs.id}/")
        self.assertEqual(response.status_code, 404)

    def test_search_stays_within_scope(self):
        self.client.force_authenticate(self.employee)
        response = self.client.get("/api/crm/leads/?search=Theirs")
        self.assertEqual(response.json(), [])


class AssignmentScopingTests(APITestCase):
    """An employee may not hand work to someone they cannot see."""

    def setUp(self):
        self.admin, self.manager, self.employee, self.outsider = make_team()
        self.client.force_authenticate(self.employee)

    def post_lead(self, assigned_to):
        return self.client.post(
            "/api/crm/leads/",
            {"name": "New Co", "phone": "9990003333",
             "assigned_to": assigned_to.id},
            format="json",
        )

    def test_can_assign_to_themselves(self):
        self.assertEqual(self.post_lead(self.employee).status_code, 201)

    def test_cannot_assign_to_another_team(self):
        response = self.post_lead(self.outsider)
        self.assertEqual(response.status_code, 400)
        self.assertIn("assigned_to", response.json())

    def test_cannot_assign_to_their_own_manager(self):
        """A manager sees their employee; the employee does not see them."""
        self.assertEqual(self.post_lead(self.manager).status_code, 400)

    def test_manager_can_assign_to_their_team_member(self):
        self.client.force_authenticate(self.manager)
        self.assertEqual(self.post_lead(self.employee).status_code, 201)

    def test_customers_are_scoped_the_same_way(self):
        response = self.client.post(
            "/api/crm/customers/",
            {"name": "New Co Ltd", "phone": "9990004444",
             "assigned_to": self.outsider.id},
            format="json",
        )
        self.assertEqual(response.status_code, 400)

    def test_reassigning_an_existing_lead_is_scoped_too(self):
        lead = make_lead("Mine", owner=self.employee)
        response = self.client.patch(
            f"/api/crm/leads/{lead.id}/",
            {"assigned_to": self.outsider.id},
            format="json",
        )
        self.assertEqual(response.status_code, 400)

    def test_created_by_comes_from_the_request(self):
        """Read-only on the serializer, so it cannot be forged."""
        response = self.client.post(
            "/api/crm/leads/",
            {"name": "New Co", "phone": "9990003333",
             "created_by": self.outsider.id},
            format="json",
        )
        self.assertEqual(response.status_code, 201)
        self.assertEqual(
            Lead.objects.get(pk=response.json()["id"]).created_by, self.employee)


class LeadConversionTests(APITestCase):
    def setUp(self):
        self.admin, self.manager, self.employee, self.outsider = make_team()
        # Priced, with the 30% deposit paid: ready to convert. A lead needs a
        # price to convert (issue #16), so the tests below start from one.
        self.lead = make_lead("Acme", owner=self.employee,
                              company_name="Acme Ltd", city="Mumbai",
                              value=Decimal("10000.00"),
                              amount_paid=Decimal("3000.00"))
        self.client.force_authenticate(self.employee)

    def convert(self, lead=None):
        return self.client.post(
            f"/api/crm/leads/{(lead or self.lead).id}/convert/")

    def test_conversion_copies_the_contact_details_across(self):
        response = self.convert()
        self.assertEqual(response.status_code, 201)
        # The view returns the new customer itself, not a wrapper.
        customer = Customer.objects.get(pk=response.json()["id"])
        self.assertEqual(customer.name, "Acme")
        self.assertEqual(customer.company_name, "Acme Ltd")
        self.assertEqual(customer.city, "Mumbai")

    def test_conversion_marks_the_lead_converted_and_links_the_two(self):
        self.convert()
        self.lead.refresh_from_db()
        self.assertEqual(self.lead.status, Lead.Status.CONVERTED)
        self.assertTrue(self.lead.is_converted)

    def test_converting_twice_is_a_conflict(self):
        self.convert()
        self.assertEqual(self.convert().status_code, 409)

    def test_cannot_convert_a_lead_outside_your_scope(self):
        theirs = make_lead("Theirs", owner=self.outsider)
        self.assertEqual(self.convert(theirs).status_code, 404)

    def test_converted_cannot_be_set_by_hand(self):
        """Converting is what makes it converted, so the customer exists."""
        response = self.client.patch(
            f"/api/crm/leads/{self.lead.id}/",
            {"status": Lead.Status.CONVERTED},
            format="json",
        )
        self.assertEqual(response.status_code, 400)

    def priced(self, value, paid):
        """A lead with an agreed price and something paid against it."""
        Lead.objects.filter(pk=self.lead.pk).update(
            value=Decimal(value), amount_paid=Decimal(paid))
        self.lead.refresh_from_db()
        return self.lead

    def test_a_lead_with_nothing_paid_cannot_convert(self):
        self.priced("10000.00", "0.00")
        response = self.convert()
        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.data["deposit_required"], Decimal("3000.00"))
        self.assertEqual(response.data["outstanding"], Decimal("3000.00"))
        self.assertFalse(Customer.objects.filter(name=self.lead.name).exists())

    def test_just_under_thirty_percent_is_not_enough(self):
        """The boundary is the whole rule — a rounding slip here would let
        every lead through a rupee short."""
        self.priced("10000.00", "2999.99")
        self.assertEqual(self.convert().status_code, 409)

    def test_exactly_thirty_percent_converts(self):
        self.priced("10000.00", "3000.00")
        self.assertEqual(self.convert().status_code, 201)

    def test_more_than_thirty_percent_converts(self):
        self.priced("10000.00", "9999.00")
        self.assertEqual(self.convert().status_code, 201)

    def test_the_deposit_is_rounded_to_the_paisa(self):
        """30% of 1000.01 is 300.003. Stored money has two decimal places, so
        it has to land on one of them rather than raise."""
        lead = self.priced("1000.01", "0.00")
        self.assertEqual(lead.deposit_required, Decimal("300.00"))

    def test_the_lead_reports_what_is_owed(self):
        """A screen must be able to show the shortfall without recomputing the
        rule and risking a different answer."""
        self.priced("10000.00", "1000.00")
        data = self.client.get(f"/api/crm/leads/{self.lead.id}/").data
        self.assertEqual(data["deposit_required"], "3000.00")
        self.assertFalse(data["deposit_met"])


class ScopeToUserTests(APITestCase):
    """The helper itself, including how it fails."""

    def setUp(self):
        self.admin, self.manager, self.employee, self.outsider = make_team()
        make_lead("Mine", owner=self.employee)
        make_lead("Theirs", owner=self.outsider)

    def test_empty_owner_fields_raises_rather_than_returning_everything(self):
        """An empty Q would filter nothing — failing open, in the worst place."""
        with self.assertRaises(ValueError):
            scope_to_user(Lead.objects.all(), self.employee, ())

    def test_no_duplicates_when_both_owner_fields_match(self):
        """The OR compiles to one WHERE over one table, not a join, so a row
        satisfying both branches still comes back once."""
        lead = make_lead("Both", owner=self.employee, creator=self.employee)
        rows = scope_to_user(
            Lead.objects.all(), self.employee, ("assigned_to", "created_by"))
        self.assertEqual(list(rows).count(lead), 1)

    def test_unassigned_records_are_invisible_to_everyone_but_admins(self):
        orphan = make_lead("Orphan")
        visible = scope_to_user(
            Lead.objects.all(), self.employee, ("assigned_to", "created_by"))
        self.assertNotIn(orphan, visible)


class StaleLeadTests(APITestCase):
    """Leads nobody has touched for a month close themselves."""

    def setUp(self):
        self.admin, self.manager, self.employee, self.outsider = make_team()

    def age(self, lead, days):
        """Backdate `updated_at`, which `auto_now` would otherwise overwrite."""
        Lead.objects.filter(pk=lead.pk).update(
            updated_at=timezone.now() - timedelta(days=days))
        lead.refresh_from_db()
        return lead

    def test_a_quiet_lead_closes(self):
        lead = self.age(make_lead("Quiet", owner=self.employee), 31)
        call_command("close_stale_leads", verbosity=0)
        lead.refresh_from_db()
        self.assertEqual(lead.status, Lead.Status.CLOSED)

    def test_a_lead_touched_recently_stays_open(self):
        lead = self.age(make_lead("Busy", owner=self.employee), 29)
        call_command("close_stale_leads", verbosity=0)
        lead.refresh_from_db()
        self.assertEqual(lead.status, Lead.Status.NEW)

    def test_a_converted_lead_is_left_alone(self):
        """It is finished, not stalled — reopening it as closed would lie."""
        lead = make_lead("Sold", owner=self.employee)
        customer = make_customer("Sold Ltd", owner=self.employee)
        Lead.objects.filter(pk=lead.pk).update(
            status=Lead.Status.CONVERTED, converted_customer=customer)
        self.age(lead, 90)
        call_command("close_stale_leads", verbosity=0)
        lead.refresh_from_db()
        self.assertEqual(lead.status, Lead.Status.CONVERTED)

    def test_dry_run_changes_nothing(self):
        lead = self.age(make_lead("Quiet", owner=self.employee), 31)
        call_command("close_stale_leads", "--dry-run", verbosity=0)
        lead.refresh_from_db()
        self.assertEqual(lead.status, Lead.Status.NEW)

    def test_closing_does_not_touch_updated_at(self):
        """The record should still show when the lead went quiet, not when the
        command happened to run."""
        lead = self.age(make_lead("Quiet", owner=self.employee), 31)
        before = lead.updated_at
        call_command("close_stale_leads", verbosity=0)
        lead.refresh_from_db()
        self.assertEqual(lead.updated_at, before)

    def test_the_threshold_is_configurable(self):
        lead = self.age(make_lead("Quiet", owner=self.employee), 10)
        call_command("close_stale_leads", "--days", "7", verbosity=0)
        lead.refresh_from_db()
        self.assertEqual(lead.status, Lead.Status.CLOSED)

    def test_is_stale_agrees_with_the_command(self):
        fresh = make_lead("Fresh", owner=self.employee)
        stale = self.age(make_lead("Stale", owner=self.employee), 31)
        self.assertFalse(fresh.is_stale)
        self.assertTrue(stale.is_stale)
