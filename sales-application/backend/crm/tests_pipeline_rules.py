"""The pipeline's rules, one test per rule, written from the audit.

Each test states the CORRECT behaviour. Where the code does not do that yet,
the test is marked `xfail(strict=True)` with its GitHub issue number: it is
expected to fail, and the suite stays green while it does.

Strict matters. When a fix makes one of these tests pass, pytest reports the
unexpected pass as a failure, so the fix's pull request has to remove the
marker - which is how "fixed" gets recorded, and why the bug cannot quietly
return afterwards.

The tests with no marker guard behaviour that is already right.

See docs/data-and-pipeline-audit.md for how each problem was found.
"""

from datetime import timedelta
from decimal import Decimal

import pytest
from django.core.management import call_command
from django.utils import timezone
from rest_framework.test import APITestCase

from accounts.models import User
from common.testing import (
    make_customer, make_lead, make_team, make_user, open_day,
)
from crm.models import Customer, Demo, Lead, LeadStageChange, Payment, Product
from crm.negotiations import Negotiation
from delivery.models import Delivery
from visits.models import FollowUp


def known_bug(issue, what):
    return pytest.mark.xfail(strict=True, reason=f"Issue #{issue}: {what}")


def refused(response):
    return response.status_code in (400, 403, 405, 409)


class PipelineTestCase(APITestCase):
    def setUp(self):
        self.admin, self.manager, self.employee, self.outsider = make_team()

    def as_(self, user):
        self.client.force_authenticate(user)
        return self.client

    def followup(self, lead, days=1):
        return FollowUp.objects.create(
            assigned_to=self.employee, created_by=self.employee, lead=lead,
            kind="call", due_at=timezone.now() + timedelta(days=days))


# --- Money --------------------------------------------------------------------

class MoneyRules(PipelineTestCase):
    def test_a_lead_needs_a_price_before_it_can_convert(self):
        lead = make_lead(owner=self.employee, status="proposal")
        r = self.as_(self.employee).post(f"/api/crm/leads/{lead.id}/convert/")
        self.assertTrue(refused(r), r.status_code)
        self.assertEqual(Customer.objects.count(), 0)

    def test_a_deposit_below_30_percent_is_refused(self):
        lead = make_lead(owner=self.employee, status="proposal",
                         value=Decimal("100000"), amount_paid=Decimal("29000"))
        r = self.as_(self.employee).post(f"/api/crm/leads/{lead.id}/convert/")
        self.assertEqual(r.status_code, 409)

    def test_paid_cannot_be_more_than_the_price(self):
        lead = make_lead(owner=self.employee, value=Decimal("50000"))
        r = self.as_(self.employee).patch(f"/api/crm/leads/{lead.id}/",
                                          {"amount_paid": "90000"}, format="json")
        self.assertTrue(refused(r), r.status_code)

    def test_a_negative_price_is_refused(self):
        lead = make_lead(owner=self.employee)
        r = self.as_(self.employee).patch(f"/api/crm/leads/{lead.id}/",
                                          {"value": "-5000"}, format="json")
        self.assertTrue(refused(r), r.status_code)


    def test_paid_cannot_be_negative(self):
        lead = make_lead(owner=self.employee, value=Decimal("50000"))
        r = self.as_(self.employee).patch(f"/api/crm/leads/{lead.id}/",
                                          {"amount_paid": "-1"}, format="json")
        self.assertTrue(refused(r), r.status_code)

    def test_a_payment_needs_a_price_first(self):
        lead = make_lead(owner=self.employee)
        r = self.as_(self.employee).patch(f"/api/crm/leads/{lead.id}/",
                                          {"amount_paid": "5000"}, format="json")
        self.assertTrue(refused(r), r.status_code)

    def test_the_price_cannot_drop_below_what_was_paid(self):
        lead = make_lead(owner=self.employee, value=Decimal("50000"),
                         amount_paid=Decimal("20000"))
        r = self.as_(self.employee).patch(f"/api/crm/leads/{lead.id}/",
                                          {"value": "10000"}, format="json")
        self.assertTrue(refused(r), r.status_code)

    def test_paid_in_full_is_fine(self):
        lead = make_lead(owner=self.employee)
        r = self.as_(self.employee).patch(f"/api/crm/leads/{lead.id}/",
                                          {"value": "50000", "amount_paid": "50000"}, format="json")
        self.assertEqual(r.status_code, 200, r.data)

    def test_an_old_lead_with_bad_numbers_can_still_have_its_notes_edited(self):
        """Saved before these rules. Only a change to the money is checked,
        so unrelated edits aren't blocked by a price nobody touched."""
        lead = make_lead(owner=self.employee, value=Decimal("40000"),
                         amount_paid=Decimal("70000"))
        r = self.as_(self.employee).patch(f"/api/crm/leads/{lead.id}/",
                                          {"notes": "Called back"}, format="json")
        self.assertEqual(r.status_code, 200, r.data)

    def test_the_admin_site_applies_the_same_rule(self):
        from django.core.exceptions import ValidationError
        lead = make_lead(owner=self.employee, value=Decimal("50000"))
        lead.amount_paid = Decimal("90000")
        with self.assertRaises(ValidationError):
            lead.full_clean()


# --- Stages -------------------------------------------------------------------

class StageRules(PipelineTestCase):
    def converted_lead(self):
        customer = make_customer(owner=self.employee)
        return make_lead(owner=self.employee, status="converted",
                         converted_customer=customer, converted_at=timezone.now())

    def test_a_converted_lead_cannot_go_back_to_new(self):
        lead = self.converted_lead()
        r = self.as_(self.admin).patch(f"/api/crm/leads/{lead.id}/",
                                       {"status": "new"}, format="json")
        self.assertTrue(refused(r), r.status_code)

    def test_a_converted_lead_cannot_be_lost(self):
        lead = self.converted_lead()
        r = self.as_(self.admin).patch(f"/api/crm/leads/{lead.id}/",
                                       {"status": "closed", "lost_reason": "price"}, format="json")
        self.assertTrue(refused(r), r.status_code)

    def test_a_rep_cannot_move_a_lead_backwards(self):
        lead = make_lead(owner=self.employee, status="proposal")
        r = self.as_(self.employee).patch(f"/api/crm/leads/{lead.id}/",
                                          {"status": "new"}, format="json")
        self.assertTrue(refused(r), r.status_code)

    def test_a_converted_leads_other_details_can_still_be_edited(self):
        lead = self.converted_lead()
        r = self.as_(self.employee).patch(f"/api/crm/leads/{lead.id}/",
                                          {"notes": "Asked about SEO"}, format="json")
        self.assertEqual(r.status_code, 200, r.data)

    def test_an_older_app_sending_assigned_is_treated_as_new(self):
        """The Assigned stage was removed (#27). An app or console built
        before that still sends it; it must not fail."""
        lead = make_lead(owner=self.employee, status="new")
        r = self.as_(self.employee).patch(f"/api/crm/leads/{lead.id}/",
                                          {"status": "assigned"}, format="json")
        self.assertEqual(r.status_code, 200, r.data)
        lead.refresh_from_db()
        self.assertEqual(lead.status, "new")
        self.assertFalse(LeadStageChange.objects.exists())

    def test_a_manager_can_move_a_lead_back_with_a_reason_and_it_is_recorded(self):
        lead = make_lead(owner=self.employee, status="proposal")
        r = self.as_(self.manager).patch(f"/api/crm/leads/{lead.id}/", {
            "status": "new", "stage_change_reason": "Client wants a new quote"},
            format="json")
        self.assertEqual(r.status_code, 200, r.data)
        change = LeadStageChange.objects.get(lead=lead)
        self.assertEqual((change.from_status, change.to_status, change.changed_by, change.reason),
                         ("proposal", "new", self.manager, "Client wants a new quote"))

    def test_moving_back_needs_a_reason(self):
        lead = make_lead(owner=self.employee, status="proposal")
        r = self.as_(self.manager).patch(f"/api/crm/leads/{lead.id}/",
                                         {"status": "new"}, format="json")
        self.assertTrue(refused(r), r.status_code)
        lead.refresh_from_db()
        self.assertEqual(lead.status, "proposal")

    def test_an_admin_can_reopen_a_lost_lead_with_a_reason(self):
        lead = make_lead(owner=self.employee, status="closed", lost_reason="price")
        r = self.as_(self.admin).patch(f"/api/crm/leads/{lead.id}/", {
            "status": "new", "stage_change_reason": "They called back with a bigger budget"},
            format="json")
        self.assertEqual(r.status_code, 200, r.data)
        lead.refresh_from_db()
        self.assertEqual((lead.status, lead.lost_reason), ("new", ""))

    def test_a_lost_lead_can_be_reopened_where_its_records_put_it(self):
        """Reopening at Proposal was always refused, even with the proposal
        sent - found by trying the console's Reopen in a browser (#59)."""
        lead = make_lead(owner=self.employee, status="closed", lost_reason="price")
        Negotiation.objects.create(lead=lead, owner=self.employee, created_by=self.employee,
                                   status="proposal_sent")
        r = self.as_(self.manager).patch(f"/api/crm/leads/{lead.id}/", {
            "status": "proposal", "stage_change_reason": "Signed after all"}, format="json")
        self.assertEqual(r.status_code, 200, r.data)

    def test_a_reopened_lead_takes_its_price_from_its_quote(self):
        """A lead lost before #29 never had its quote copied to its price;
        back in the pipeline, it should show what the deal is worth."""
        lead = make_lead(owner=self.employee, status="closed", lost_reason="price")
        Negotiation.objects.create(lead=lead, owner=self.employee, created_by=self.employee)
        Negotiation.objects.filter(lead=lead).update(
            quoted_amount=Decimal("65000"), discount_pct=Decimal("5"))
        self.as_(self.manager).patch(f"/api/crm/leads/{lead.id}/", {
            "status": "negotiation", "stage_change_reason": "Back on"}, format="json")
        lead.refresh_from_db()
        self.assertEqual(lead.value, Decimal("61750"))

    def test_a_lost_lead_cannot_be_reopened_at_a_stage_it_never_reached(self):
        lead = make_lead(owner=self.employee, status="closed", lost_reason="price")
        Negotiation.objects.create(lead=lead, owner=self.employee, created_by=self.employee)
        r = self.as_(self.manager).patch(f"/api/crm/leads/{lead.id}/", {
            "status": "proposal", "stage_change_reason": "Signed after all"}, format="json")
        self.assertEqual(r.status_code, 400)

    def test_a_rep_cannot_reopen_a_lost_lead(self):
        lead = make_lead(owner=self.employee, status="closed", lost_reason="price")
        r = self.as_(self.employee).patch(f"/api/crm/leads/{lead.id}/", {
            "status": "new", "stage_change_reason": "They called back"}, format="json")
        self.assertTrue(refused(r), r.status_code)

    def test_the_lead_shows_its_history_of_steps_back(self):
        lead = make_lead(owner=self.employee, status="proposal")
        self.as_(self.manager).patch(f"/api/crm/leads/{lead.id}/", {
            "status": "new", "stage_change_reason": "Scope changed"}, format="json")
        data = self.as_(self.admin).get(f"/api/crm/leads/{lead.id}/").data
        self.assertEqual(data["stage_changes"][0]["reason"], "Scope changed")
        self.assertEqual(data["stage_changes"][0]["changed_by_name"], self.manager.username)

    def test_a_negotiation_cannot_be_opened_on_a_lost_lead(self):
        lead = make_lead(owner=self.employee, status="closed", lost_reason="price")
        r = self.as_(self.employee).post("/api/crm/negotiations/", {"lead": lead.id}, format="json")
        self.assertTrue(refused(r), r.status_code)

    def test_a_demo_cannot_be_logged_on_a_converted_lead(self):
        lead = self.converted_lead()
        r = self.as_(self.employee).post("/api/crm/demos/", {
            "lead": lead.id, "held_at": timezone.now().isoformat(),
            "outcome": "successful", "mode": "online", "product": "website"}, format="json")
        self.assertTrue(refused(r), r.status_code)

    def test_losing_a_lead_needs_a_reason(self):
        lead = make_lead(owner=self.employee, status="demo")
        r = self.as_(self.employee).patch(f"/api/crm/leads/{lead.id}/",
                                          {"status": "closed"}, format="json")
        self.assertTrue(refused(r), r.status_code)

    def test_a_demo_cannot_be_logged_on_a_lost_lead(self):
        lead = make_lead(owner=self.employee, status="closed", lost_reason="price")
        r = self.as_(self.employee).post("/api/crm/demos/", {
            "lead": lead.id, "held_at": timezone.now().isoformat(),
            "outcome": "successful", "mode": "online", "product": "website"}, format="json")
        self.assertTrue(refused(r), r.status_code)

    def test_nobody_can_delete_a_lead(self):
        lead = make_lead(owner=self.employee)
        r = self.as_(self.admin).delete(f"/api/crm/leads/{lead.id}/")
        self.assertTrue(refused(r), r.status_code)
        self.assertTrue(Lead.objects.filter(pk=lead.pk).exists())


class SimplerStagesRules(PipelineTestCase):
    """#27 and #28: New -> Demo -> Negotiation -> Proposal -> Customer / Lost,
    and the outcome recorded only on the lead."""

    def test_the_stages_are_named_as_people_say_them(self):
        self.assertNotIn("assigned", Lead.Status.values)
        self.assertEqual((Lead.Status.CONVERTED.label, Lead.Status.CLOSED.label),
                         ("Customer", "Lost"))
        self.assertEqual(set(Negotiation.Status.values),
                         {"in_progress", "proposal_sent", "on_hold"})

    def test_existing_data_moves_to_the_simpler_stages(self):
        import importlib
        from django.apps import apps
        from django.core.files.base import ContentFile
        simplify = importlib.import_module("crm.migrations.0012_simpler_stages").simplify
        was_assigned = make_lead(owner=self.employee, phone="9000000011")
        Lead.objects.filter(pk=was_assigned.pk).update(status="assigned")
        won_lead = make_lead(owner=self.employee, phone="9000000012")
        lost_lead = make_lead(owner=self.employee, phone="9000000013")
        won = Negotiation.objects.create(lead=won_lead, owner=self.employee, created_by=self.employee)
        won.proposal.save("proposal.pdf", ContentFile(b"%PDF-1.4"), save=True)
        lost = Negotiation.objects.create(lead=lost_lead, owner=self.employee, created_by=self.employee)
        Negotiation.objects.filter(pk=won.pk).update(status="won")
        Negotiation.objects.filter(pk=lost.pk).update(status="lost")
        simplify(apps, None)
        for obj in (was_assigned, won, lost):
            obj.refresh_from_db()
        self.assertEqual((was_assigned.status, won.status, lost.status),
                         ("new", "proposal_sent", "in_progress"))
        won.proposal.delete(save=False)

    def test_a_customer_s_negotiation_is_finished_and_never_slipping(self):
        customer = make_customer(owner=self.employee)
        lead = make_lead(owner=self.employee, status="converted", converted_customer=customer)
        n = Negotiation.objects.create(
            lead=lead, owner=self.employee, created_by=self.employee,
            expected_close_on=timezone.localdate() - timedelta(days=5))
        self.assertFalse(n.is_open)
        r = self.as_(self.admin).get("/api/crm/negotiations/?slipping=true")
        rows = r.data if isinstance(r.data, list) else r.data["results"]
        self.assertNotIn(n.id, [row["id"] for row in rows])


class PriceAndDepositRules(PipelineTestCase):
    """#29: the quote is the lead's price until another is agreed.
    #32: the deposit follows the agreed payment terms (decided 29 Sep)."""

    def negotiate(self, lead, **fields):
        return self.as_(self.employee).post(
            "/api/crm/negotiations/", {"lead": lead.id, **fields}, format="json")

    def requote(self, negotiation_id, **fields):
        return self.as_(self.employee).patch(
            f"/api/crm/negotiations/{negotiation_id}/", fields, format="json")

    def price_of(self, lead):
        lead.refresh_from_db()
        return lead.value

    def test_the_quote_fills_an_empty_price(self):
        lead = make_lead(owner=self.employee, status="demo")
        r = self.negotiate(lead, quoted_amount="120000")
        self.assertEqual(r.status_code, 201, r.data)
        self.assertEqual(self.price_of(lead), Decimal("120000"))

    def test_the_price_is_the_quote_after_its_discount(self):
        lead = make_lead(owner=self.employee, status="demo")
        self.negotiate(lead, quoted_amount="200000", discount_pct="10")
        self.assertEqual(self.price_of(lead), Decimal("180000"))

    def test_a_revised_quote_revises_the_price_it_filled(self):
        lead = make_lead(owner=self.employee, status="demo")
        n = self.negotiate(lead, quoted_amount="150000").data["id"]
        self.requote(n, quoted_amount="140000")
        self.assertEqual(self.price_of(lead), Decimal("140000"))

    def test_a_price_agreed_by_hand_is_never_overwritten_by_the_quote(self):
        lead = make_lead(owner=self.employee, status="demo")
        n = self.negotiate(lead, quoted_amount="150000").data["id"]
        self.as_(self.employee).patch(f"/api/crm/leads/{lead.id}/",
                                      {"value": "135000"}, format="json")
        self.requote(n, quoted_amount="160000")
        self.assertEqual(self.price_of(lead), Decimal("135000"))

    def test_a_price_set_before_the_negotiation_is_kept(self):
        lead = make_lead(owner=self.employee, status="demo", value=Decimal("90000"))
        self.negotiate(lead, quoted_amount="120000")
        self.assertEqual(self.price_of(lead), Decimal("90000"))

    def test_a_quote_below_what_was_paid_leaves_the_price_alone(self):
        lead = make_lead(owner=self.employee, status="demo")
        n = self.negotiate(lead, quoted_amount="100000").data["id"]
        Lead.objects.filter(pk=lead.pk).update(amount_paid=Decimal("40000"))
        self.requote(n, quoted_amount="30000")
        self.assertEqual(self.price_of(lead), Decimal("100000"))

    def test_a_customer_s_price_is_not_changed_by_its_old_negotiation(self):
        lead = make_lead(owner=self.employee, status="demo")
        n = self.negotiate(lead, quoted_amount="100000").data["id"]
        Lead.objects.filter(pk=lead.pk).update(status="converted")
        self.requote(n, quoted_amount="80000")
        self.assertEqual(self.price_of(lead), Decimal("100000"))

    def test_a_negative_quote_or_a_discount_over_100_is_refused(self):
        lead = make_lead(owner=self.employee, status="demo")
        self.assertEqual(self.negotiate(lead, quoted_amount="-5").status_code, 400)
        self.assertEqual(self.negotiate(lead, quoted_amount="100",
                                        discount_pct="120").status_code, 400)
        self.assertEqual(self.negotiate(lead, quoted_amount="100",
                                        discount_pct="-1").status_code, 400)
        self.assertIsNone(self.price_of(lead))

    def test_deals_already_being_negotiated_get_their_price_from_the_quote(self):
        import importlib
        from django.apps import apps
        fill = importlib.import_module("crm.migrations.0013_price_from_quote").fill_price_from_quote
        empty = make_lead(owner=self.employee, status="negotiation", phone="9000000021")
        agreed = make_lead(owner=self.employee, status="negotiation", phone="9000000022",
                           value=Decimal("70000"))
        won = make_lead(owner=self.employee, status="converted", phone="9000000023")
        for lead in (empty, agreed, won):
            Negotiation.objects.create(lead=lead, owner=self.employee, created_by=self.employee)
        Negotiation.objects.update(quoted_amount=Decimal("100000"), discount_pct=Decimal("5"))
        Lead.objects.filter(pk__in=[empty.pk, won.pk]).update(value=None)
        fill(apps, None)
        self.assertEqual([self.price_of(x) for x in (empty, agreed, won)],
                         [Decimal("95000"), Decimal("70000"), None])

    # --- the deposit ---------------------------------------------------------

    def priced_lead(self, terms, paid):
        lead = make_lead(owner=self.employee, status="proposal",
                         value=Decimal("100000"), amount_paid=Decimal(paid))
        if terms is not None:
            Negotiation.objects.create(lead=lead, owner=self.employee,
                                       created_by=self.employee, payment_terms=terms)
        return lead

    def convert(self, lead):
        return self.as_(self.employee).post(f"/api/crm/leads/{lead.id}/convert/")

    def test_full_advance_needs_everything_paid(self):
        lead = self.priced_lead("full_advance", "99000")
        r = self.convert(lead)
        self.assertEqual(r.status_code, 409)
        self.assertEqual(Decimal(r.data["deposit_required"]), Decimal("100000"))
        self.assertIn("100%", r.data["detail"])
        Lead.objects.filter(pk=lead.pk).update(amount_paid=Decimal("100000"))
        self.assertEqual(self.convert(lead).status_code, 201)

    def test_half_and_half_needs_half(self):
        self.assertEqual(self.convert(self.priced_lead("half_half", "49000")).status_code, 409)
        self.assertEqual(self.convert(self.priced_lead("half_half", "50000")).status_code, 201)

    def test_30_percent_advance_needs_30_percent(self):
        self.assertEqual(self.convert(self.priced_lead("advance_30", "29000")).status_code, 409)
        self.assertEqual(self.convert(self.priced_lead("advance_30", "30000")).status_code, 201)

    def test_milestones_custom_or_no_terms_need_the_standard_30_percent(self):
        for terms in ("milestones", "custom", "", None):
            with self.subTest(terms=terms):
                Lead.objects.all().delete()
                self.assertEqual(self.convert(self.priced_lead(terms, "29000")).status_code, 409)
                self.assertEqual(self.convert(self.priced_lead(terms, "30000")).status_code, 201)
                # Payments protect a customer from deletion; clear them first.
                Payment.objects.all().delete()
                Customer.objects.all().delete()

    def test_the_lead_says_what_share_its_terms_ask_for(self):
        lead = self.priced_lead("half_half", "0")
        r = self.as_(self.employee).get(f"/api/crm/leads/{lead.id}/")
        self.assertEqual((Decimal(r.data["deposit_share"]), Decimal(r.data["deposit_required"])),
                         (Decimal("0.50"), Decimal("50000")))


# --- Follow-ups ---------------------------------------------------------------

class FollowUpRules(PipelineTestCase):
    def test_losing_a_lead_cancels_its_followups(self):
        lead = make_lead(owner=self.employee, status="negotiation")
        fu = self.followup(lead, days=2)
        self.as_(self.employee).patch(f"/api/crm/leads/{lead.id}/",
                                      {"status": "closed", "lost_reason": "price"}, format="json")
        fu.refresh_from_db()
        self.assertEqual(fu.status, "cancelled")

    def test_auto_close_skips_a_lead_with_a_booked_followup(self):
        lead = make_lead(owner=self.employee, status="new")
        self.followup(lead, days=1)
        Lead.objects.filter(pk=lead.pk).update(updated_at=timezone.now() - timedelta(days=40))
        call_command("close_stale_leads", verbosity=0)
        lead.refresh_from_db()
        self.assertEqual(lead.status, "new")

    def test_auto_close_records_no_response_as_the_reason(self):
        lead = make_lead(owner=self.employee, status="new")
        Lead.objects.filter(pk=lead.pk).update(updated_at=timezone.now() - timedelta(days=40))
        call_command("close_stale_leads", verbosity=0)
        lead.refresh_from_db()
        self.assertEqual((lead.status, lead.lost_reason), ("closed", "no_response"))

    def test_converting_moves_followups_to_the_customer(self):
        lead = make_lead(owner=self.employee, status="proposal",
                         value=Decimal("10000"), amount_paid=Decimal("3000"))
        fu = self.followup(lead, days=2)
        r = self.as_(self.employee).post(f"/api/crm/leads/{lead.id}/convert/")
        self.assertEqual(r.status_code, 201)
        fu.refresh_from_db()
        self.assertEqual(fu.customer_id, r.data["id"])


    def test_losing_is_done_on_the_lead_not_the_negotiation(self):
        """#28: marking a negotiation lost is refused, and nothing changes -
        the lead stays open and its follow-up stays booked."""
        lead = make_lead(owner=self.employee, status="negotiation")
        fu = self.followup(lead, days=2)
        n = Negotiation.objects.create(lead=lead, owner=self.employee, created_by=self.employee)
        r = self.as_(self.employee).patch(f"/api/crm/negotiations/{n.id}/", {"status": "lost"}, format="json")
        self.assertEqual(r.status_code, 400)
        lead.refresh_from_db()
        fu.refresh_from_db()
        self.assertEqual((lead.status, fu.status), ("negotiation", "pending"))

    def test_an_overdue_followup_does_not_stop_auto_close_and_is_cancelled(self):
        lead = make_lead(owner=self.employee, status="new")
        fu = self.followup(lead, days=-3)  # booked, and already missed
        Lead.objects.filter(pk=lead.pk).update(updated_at=timezone.now() - timedelta(days=40))
        call_command("close_stale_leads", verbosity=0)
        lead.refresh_from_db()
        fu.refresh_from_db()
        self.assertEqual((lead.status, lead.lost_reason, fu.status),
                         ("closed", "no_response", "cancelled"))

    def test_a_lost_lead_can_have_its_notes_edited_without_a_new_reason(self):
        lead = make_lead(owner=self.employee, status="closed", lost_reason="price")
        r = self.as_(self.employee).patch(f"/api/crm/leads/{lead.id}/",
                                          {"notes": "They said maybe next year"}, format="json")
        self.assertEqual(r.status_code, 200, r.data)

    def test_lost_is_what_closed_is_called(self):
        self.assertEqual(Lead.Status.CLOSED.label, "Lost")

    def test_old_lost_leads_with_no_reason_are_given_other(self):
        import importlib
        from django.apps import apps
        repair = importlib.import_module(
            "crm.migrations.0010_lead_status_lost_label").give_old_losses_a_reason
        old = make_lead(owner=self.employee, status="closed", lost_reason="")
        kept = make_lead(owner=self.employee, status="closed", lost_reason="price", phone="9990001112")
        repair(apps, None)
        old.refresh_from_db()
        kept.refresh_from_db()
        self.assertEqual((old.lost_reason, kept.lost_reason), ("other", "price"))


# --- People -------------------------------------------------------------------

class PeopleRules(PipelineTestCase):
    def test_a_lead_cannot_be_given_to_a_deactivated_rep(self):
        gone = make_user("t_gone", is_active=False)
        lead = make_lead(owner=self.employee)
        r = self.as_(self.admin).patch(f"/api/crm/leads/{lead.id}/",
                                       {"assigned_to": gone.id}, format="json")
        self.assertTrue(refused(r), r.status_code)

    def test_deactivating_a_rep_with_open_leads_needs_someone_to_take_over(self):
        make_lead(owner=self.employee, status="negotiation")
        r = self.as_(self.admin).delete(f"/api/auth/employees/{self.employee.id}/")
        self.assertTrue(refused(r), r.status_code)
        self.employee.refresh_from_db()
        self.assertTrue(self.employee.is_active)


class HandoverOnDeactivationRules(PipelineTestCase):
    def setUp(self):
        super().setUp()
        self.colleague = make_user("t_colleague", manager=self.manager)

    def give_work(self):
        from delivery.models import Delivery
        lead = make_lead(owner=self.employee, status="negotiation")
        n = Negotiation.objects.create(lead=lead, owner=self.employee, created_by=self.employee)
        fu = self.followup(lead, days=3)
        customer = make_customer(owner=self.employee)
        product = Product.objects.create(name="Site", kind="product")
        handover = Delivery.objects.create(customer=customer, product=product, assigned_to=self.employee,
                                           milestone="go_live", scheduled_on=timezone.localdate())
        return lead, n, fu, customer, handover

    def test_deactivating_with_someone_named_hands_everything_over(self):
        lead, n, fu, customer, handover = self.give_work()
        r = self.as_(self.admin).delete(
            f"/api/auth/employees/{self.employee.id}/?transfer_to={self.colleague.id}")
        self.assertEqual(r.status_code, 200, r.data)
        for obj in (lead, fu, customer, handover):
            obj.refresh_from_db()
            self.assertEqual(obj.assigned_to, self.colleague, type(obj).__name__)
        n.refresh_from_db()
        self.employee.refresh_from_db()
        self.assertEqual((n.owner, self.employee.is_active), (self.colleague, False))
        self.assertEqual(r.data["moved"], {"leads": 1, "followups": 1, "customers": 1, "handovers": 1})

    def test_the_refusal_says_what_is_still_open(self):
        self.give_work()
        r = self.as_(self.admin).delete(f"/api/auth/employees/{self.employee.id}/")
        self.assertEqual(r.status_code, 409)
        self.assertEqual(r.data["open_work"], {"leads": 1, "followups": 1, "customers": 1, "handovers": 1})
        self.assertIn("1 open lead, 1 booked follow-up, 1 customer and 1 open handover", r.data["detail"])

    def test_someone_with_no_open_work_is_deactivated_straight_away(self):
        r = self.as_(self.admin).delete(f"/api/auth/employees/{self.colleague.id}/")
        self.assertEqual(r.status_code, 200, r.data)
        self.colleague.refresh_from_db()
        self.assertFalse(self.colleague.is_active)

    def test_work_cannot_go_to_an_inactive_person_or_back_to_themselves(self):
        self.give_work()
        gone = make_user("t_gone2", is_active=False)
        for target in (gone.id, self.employee.id, 999999):
            r = self.as_(self.admin).delete(
                f"/api/auth/employees/{self.employee.id}/?transfer_to={target}")
            self.assertEqual(r.status_code, 400, target)
        self.employee.refresh_from_db()
        self.assertTrue(self.employee.is_active)

    def test_switching_off_through_an_edit_takes_the_same_route(self):
        self.give_work()
        r = self.as_(self.admin).patch(f"/api/auth/employees/{self.employee.id}/",
                                       {"is_active": False}, format="json")
        self.assertEqual(r.status_code, 400)
        r = self.as_(self.admin).patch(f"/api/auth/employees/{self.employee.id}/",
                                       {"is_active": False, "transfer_to": self.colleague.id}, format="json")
        self.assertEqual(r.status_code, 200, r.data)
        self.assertEqual(Lead.objects.get(assigned_to=self.colleague).status, "negotiation")

    def test_the_admin_site_refuses_to_untick_active_while_work_is_open(self):
        from accounts.admin import SalesUserChangeForm
        from django.forms.models import model_to_dict
        self.give_work()
        data = model_to_dict(self.employee)
        data.update(is_active=False, password=self.employee.password, date_joined=self.employee.date_joined)
        form = SalesUserChangeForm(data=data, instance=self.employee)
        self.assertFalse(form.is_valid())
        self.assertIn("admin console", str(form.errors))

    def test_a_followup_cannot_be_given_to_a_deactivated_rep(self):
        gone = make_user("t_gone3", is_active=False)
        lead = make_lead(owner=self.employee)
        r = self.as_(self.admin).post("/api/visits/followups/", {
            "lead": lead.id, "assigned_to": gone.id, "kind": "call",
            "due_at": (timezone.now() + timedelta(days=1)).isoformat()}, format="json")
        self.assertTrue(refused(r), r.status_code)


# --- Visibility and duplicates ------------------------------------------------

class VisibilityAndDuplicateRules(PipelineTestCase):
    def test_an_admin_sees_a_lead_with_no_owner_and_no_creator(self):
        lead = make_lead(owner=None, creator=None)
        r = self.as_(self.admin).get("/api/crm/leads/")
        rows = r.data if isinstance(r.data, list) else r.data["results"]
        self.assertIn(lead.id, [row["id"] for row in rows])

    def test_an_admin_sees_a_customer_with_no_owner_and_no_creator(self):
        customer = make_customer(owner=None, creator=None)
        r = self.as_(self.admin).get("/api/crm/customers/")
        rows = r.data if isinstance(r.data, list) else r.data["results"]
        self.assertIn(customer.id, [row["id"] for row in rows])

    def test_a_manager_still_sees_only_their_team(self):
        lead = make_lead(owner=None, creator=None)
        r = self.as_(self.manager).get("/api/crm/leads/")
        rows = r.data if isinstance(r.data, list) else r.data["results"]
        self.assertNotIn(lead.id, [row["id"] for row in rows])

    def test_the_admin_site_fills_in_who_created_a_lead(self):
        from django.contrib import admin
        from django.test import RequestFactory
        request = RequestFactory().post("/admin/crm/lead/add/")
        request.user = self.admin
        lead = Lead(name="Walk-in", phone="9990007777")
        admin.site._registry[Lead].save_model(request, lead, form=None, change=False)
        self.assertEqual(Lead.objects.get(pk=lead.pk).created_by, self.admin)

    def test_converting_links_to_the_existing_customer_with_that_phone(self):
        existing = make_customer(owner=self.employee, phone="9000000001")
        lead = make_lead(owner=self.employee, phone="9000000001", status="proposal",
                         value=Decimal("10000"), amount_paid=Decimal("3000"))
        self.as_(self.employee).post(f"/api/crm/leads/{lead.id}/convert/")
        lead.refresh_from_db()
        self.assertEqual(Customer.objects.filter(phone="9000000001").count(), 1)
        self.assertEqual(lead.converted_customer_id, existing.id)


class DuplicatePhoneRules(PipelineTestCase):
    """#30, decided 29 Sep: the same client can't be added twice. A second
    open lead, or a second customer, with a number already on one is refused,
    and the refusal says which record has it. A new lead for an existing
    customer (their next project) or for a lost lead's client is fine."""

    def add_lead(self, user, phone, **fields):
        return self.as_(user).post("/api/crm/leads/", {
            "name": "Second try", "phone": phone, **fields}, format="json")

    def add_customer(self, user, phone):
        return self.as_(user).post("/api/crm/customers/", {
            "name": "Second try", "phone": phone}, format="json")

    def test_a_second_open_lead_with_the_same_number_is_refused(self):
        first = make_lead("Sharma Tuition", owner=self.employee, phone="9000000031", status="demo")
        r = self.add_lead(self.employee, "9000000031")
        self.assertEqual(r.status_code, 400)
        self.assertIn("Sharma Tuition", r.data["phone"][0])
        self.assertEqual(int(r.data["duplicate"]["id"]), first.id)
        self.assertEqual(r.data["duplicate"]["kind"], "lead")
        self.assertEqual(Lead.objects.count(), 1)

    def test_numbers_match_however_they_were_typed(self):
        make_lead(owner=self.employee, phone="+91 90000-00032")
        self.assertEqual(self.add_lead(self.employee, "9000000032").status_code, 400)

    def test_a_new_project_for_an_existing_customer_is_fine(self):
        make_customer(owner=self.employee, phone="9000000033")
        self.assertEqual(self.add_lead(self.employee, "9000000033").status_code, 201)

    def test_a_lost_lead_s_client_can_be_tried_again(self):
        make_lead(owner=self.employee, phone="9000000034", status="closed", lost_reason="price")
        self.assertEqual(self.add_lead(self.employee, "9000000034").status_code, 201)

    def test_changing_a_lead_s_number_to_one_on_another_open_lead_is_refused(self):
        make_lead(owner=self.employee, phone="9000000035")
        mine = make_lead(owner=self.employee, phone="9000000036")
        r = self.as_(self.employee).patch(f"/api/crm/leads/{mine.id}/",
                                          {"phone": "9000000035"}, format="json")
        self.assertEqual(r.status_code, 400)

    def test_an_old_duplicate_can_still_be_edited(self):
        make_lead(owner=self.employee, phone="9000000037")
        old = make_lead(owner=self.employee, phone="9000000037")
        r = self.as_(self.employee).patch(f"/api/crm/leads/{old.id}/",
                                          {"notes": "Called again", "phone": "9000000037"},
                                          format="json")
        self.assertEqual(r.status_code, 200, r.data)

    def test_reopening_a_lost_lead_whose_number_is_now_on_an_open_one_is_refused(self):
        lost = make_lead(owner=self.employee, phone="9000000038", status="closed", lost_reason="price")
        make_lead(owner=self.employee, phone="9000000038")
        r = self.as_(self.manager).patch(f"/api/crm/leads/{lost.id}/", {
            "status": "new", "stage_change_reason": "They called back"}, format="json")
        self.assertEqual(r.status_code, 400)

    def test_someone_on_another_team_is_told_but_not_given_the_link(self):
        make_lead("Rane School", owner=self.outsider, phone="9000000039")
        r = self.add_lead(self.employee, "9000000039")
        self.assertEqual(r.status_code, 400)
        self.assertIn("Rane School", r.data["phone"][0])
        self.assertNotIn("id", r.data["duplicate"])

    def test_a_second_customer_with_the_same_number_is_refused(self):
        first = make_customer("Om Gym", owner=self.employee, phone="9000000040", is_active=False)
        r = self.add_customer(self.employee, "9000000040")
        self.assertEqual(r.status_code, 400)
        self.assertIn("Om Gym", r.data["phone"][0])
        self.assertEqual((r.data["duplicate"]["kind"], int(r.data["duplicate"]["id"])),
                         ("customer", first.id))

    def test_changing_a_customer_s_number_to_another_customer_s_is_refused(self):
        make_customer(owner=self.employee, phone="9000000041")
        mine = make_customer(owner=self.employee, phone="9000000042")
        r = self.as_(self.employee).patch(f"/api/crm/customers/{mine.id}/",
                                          {"phone": "9000000041"}, format="json")
        self.assertEqual(r.status_code, 400)

    def test_the_admin_site_applies_the_same_rule(self):
        from django.core.exceptions import ValidationError
        make_lead(owner=self.employee, phone="9000000043")
        with self.assertRaises(ValidationError) as caught:
            Lead(name="Again", phone="9000000043").full_clean()
        self.assertIn("phone", caught.exception.message_dict)
        make_customer(owner=self.employee, phone="9000000044")
        with self.assertRaises(ValidationError):
            Customer(name="Again", phone="9000000044").full_clean()


class ConversionLinkingAndDeletionRules(PipelineTestCase):
    def ready_lead(self, phone, **extra):
        return make_lead(owner=self.employee, phone=phone, status="proposal",
                         value=Decimal("10000"), amount_paid=Decimal("3000"), **extra)

    def test_linking_says_so_and_returns_the_existing_customer(self):
        existing = make_customer(owner=self.employee, phone="9000000001")
        lead = self.ready_lead("9000000001")
        r = self.as_(self.employee).post(f"/api/crm/leads/{lead.id}/convert/")
        self.assertEqual(r.status_code, 200, r.data)
        self.assertEqual((r.data["id"], r.data["linked_to_existing"]), (existing.id, True))

    def test_a_new_client_still_gets_a_new_customer(self):
        lead = self.ready_lead("9000000002")
        r = self.as_(self.employee).post(f"/api/crm/leads/{lead.id}/convert/")
        self.assertEqual(r.status_code, 201, r.data)
        self.assertFalse(r.data["linked_to_existing"])

    def test_a_returning_client_s_second_project_converts_into_the_same_customer(self):
        """A website, then an app: two leads, one customer. The link used to
        be one-to-one, so the second conversion could not be linked at all."""
        first = self.ready_lead("9000000003")
        customer_id = self.as_(self.employee).post(f"/api/crm/leads/{first.id}/convert/").data["id"]
        second = self.ready_lead("9000000003", name="Same client, app project")
        r = self.as_(self.employee).post(f"/api/crm/leads/{second.id}/convert/")
        self.assertEqual((r.status_code, r.data["id"]), (200, customer_id), r.data)
        self.assertEqual(Customer.objects.get(pk=customer_id).origin_leads.count(), 2)

    def test_phone_numbers_match_however_they_were_typed(self):
        existing = make_customer(owner=self.employee, phone="+91 98100 00004")
        lead = self.ready_lead("9810000004")
        r = self.as_(self.employee).post(f"/api/crm/leads/{lead.id}/convert/")
        self.assertEqual(r.data["id"], existing.id)

    def test_followups_move_to_the_existing_customer(self):
        existing = make_customer(owner=self.employee, phone="9000000005")
        lead = self.ready_lead("9000000005")
        fu = self.followup(lead, days=2)
        self.as_(self.employee).post(f"/api/crm/leads/{lead.id}/convert/")
        fu.refresh_from_db()
        self.assertEqual((fu.customer_id, fu.lead_id), (existing.id, None))

    def test_nobody_can_delete_a_customer(self):
        customer = make_customer(owner=self.employee)
        r = self.as_(self.admin).delete(f"/api/crm/customers/{customer.id}/")
        self.assertTrue(refused(r), r.status_code)
        self.assertTrue(Customer.objects.filter(pk=customer.pk).exists())

    def test_the_admin_site_offers_no_delete_for_leads_or_customers(self):
        from django.contrib import admin
        for model in (Lead, Customer):
            self.assertFalse(admin.site._registry[model].has_delete_permission(None))

    def test_converted_leads_with_no_customer_are_given_one(self):
        import importlib
        from django.apps import apps
        repair = importlib.import_module(
            "crm.migrations.0011_converted_customer_many_leads").give_converted_leads_their_customer
        broken = make_lead(owner=self.employee, status="converted", phone="9000000006",
                           company_name="Broken Co")
        repair(apps, None)
        broken.refresh_from_db()
        self.assertIsNotNone(broken.converted_customer)
        self.assertEqual((broken.converted_customer.company_name, broken.converted_customer.assigned_to),
                         ("Broken Co", self.employee))


# --- Handovers ----------------------------------------------------------------

class HandoverRules(PipelineTestCase):
    """#45: a milestone's scheduling notes survive delivering it.
    #46: a project passes through Design. #47: its status is worked out from
    its milestones, never set by hand."""

    def setUp(self):
        super().setUp()
        self.customer = make_customer(owner=self.employee)
        self.product = Product.objects.create(name="Test website", kind="product")

    def schedule(self, milestone, days=0, **extra):
        return Delivery.objects.create(
            customer=self.customer, product=self.product, assigned_to=self.employee,
            milestone=milestone,
            scheduled_on=timezone.localdate() + timedelta(days=days), **extra)

    def deliver(self, handover, **fields):
        return self.as_(self.employee).post(
            f"/api/delivery/deliveries/{handover.id}/deliver/", fields, format="multipart")

    def status(self):
        self.customer.refresh_from_db()
        return self.customer.project_status

    def test_delivering_keeps_the_scheduling_notes(self):
        handover = self.schedule("design_approval", notes="Bring the signed design brief")
        self.deliver(handover, received_by="Client", notes="Signed off")
        handover.refresh_from_db()
        self.assertIn("Bring the signed design brief", handover.notes)
        self.assertEqual(handover.outcome_notes, "Signed off")

    def test_cancelling_keeps_the_scheduling_notes_too(self):
        handover = self.schedule("go_live", notes="Needs DNS access")
        self.as_(self.employee).post(f"/api/delivery/deliveries/{handover.id}/cancel/",
                                     {"notes": "Client postponed"}, format="json")
        handover.refresh_from_db()
        self.assertEqual((handover.notes, handover.outcome_notes),
                         ("Needs DNS access", "Client postponed"))

    def test_nothing_scheduled_means_not_started(self):
        self.assertEqual(self.status(), "not_started")

    def test_scheduling_the_first_milestone_starts_design(self):
        self.as_(self.employee).post("/api/delivery/deliveries/", {
            "customer": self.customer.id, "product": self.product.id,
            "milestone": "design_approval",
            "scheduled_on": str(timezone.localdate())}, format="json")
        self.assertEqual(self.status(), "design")

    def test_a_project_goes_through_every_stage_in_order(self):
        steps = [self.schedule(m, days=i) for i, m in enumerate(
            ("design_approval", "development_complete", "uat", "go_live"))]
        seen = [self.status()]
        for step in steps:
            self.deliver(step, received_by="Client")
            seen.append(self.status())
        self.assertEqual(seen, ["design", "development", "uat", "uat", "live"])

    def test_going_live_records_the_go_live_date(self):
        self.deliver(self.schedule("go_live"), received_by="Client")
        self.customer.refresh_from_db()
        self.assertEqual(self.customer.go_live_on, timezone.localdate())

    def test_cancelling_the_only_milestone_puts_it_back_to_not_started(self):
        handover = self.schedule("design_approval")
        self.assertEqual(self.status(), "design")
        self.as_(self.employee).post(f"/api/delivery/deliveries/{handover.id}/cancel/",
                                     {}, format="json")
        self.assertEqual(self.status(), "not_started")

    def test_project_status_cannot_be_set_by_hand(self):
        self.as_(self.employee).patch(f"/api/crm/customers/{self.customer.id}/",
                                      {"project_status": "live"}, format="json")
        self.assertEqual(self.status(), "not_started")

    def test_mismatched_projects_are_repaired_from_their_milestones(self):
        import importlib
        from django.apps import apps
        repair = importlib.import_module(
            "delivery.migrations.0003_outcome_notes_and_project_status").repair_project_status
        went_live = self.schedule("go_live")
        Delivery.objects.filter(pk=went_live.pk).update(
            status="delivered", delivered_at=timezone.now())
        from crm.models import Customer
        Customer.objects.filter(pk=self.customer.pk).update(project_status="not_started")
        by_hand = make_customer(owner=self.employee, phone="9000000051")
        Customer.objects.filter(pk=by_hand.pk).update(project_status="live")
        repair(apps, None)
        by_hand.refresh_from_db()
        # Evidence wins; with no milestones at all, what was entered stays.
        self.assertEqual((self.status(), by_hand.project_status), ("live", "live"))


# --- After the sale: the customer's own price and payments -------------------

class CustomerMoneyRules(PipelineTestCase):
    """#41: each customer has its own agreed price, and the deposit becomes
    its first payment. #42: every payment is recorded, the balance shown, and
    a final Payment Receipt (not a GST invoice) is ready once it's ₹0."""

    def convert(self, value="100000", paid="30000", phone="9000000061", **extra):
        lead = make_lead(owner=self.employee, status="proposal", phone=phone,
                         value=Decimal(value), amount_paid=Decimal(paid), **extra)
        r = self.as_(self.employee).post(f"/api/crm/leads/{lead.id}/convert/")
        self.assertIn(r.status_code, (200, 201), r.data)
        return Customer.objects.get(pk=r.data["id"])

    def pay(self, customer, amount, user=None, **extra):
        return self.as_(user or self.employee).post(
            f"/api/crm/customers/{customer.id}/payments/",
            {"amount": amount, "method": "upi", "reference": "UTR123", **extra},
            format="json")

    def customer_row(self, customer, user=None):
        return self.as_(user or self.employee).get(f"/api/crm/customers/{customer.id}/").data

    def test_converting_gives_the_customer_its_price_and_the_deposit_as_first_payment(self):
        customer = self.convert()
        row = self.customer_row(customer)
        self.assertEqual(Decimal(row["price"]), Decimal("100000"))
        self.assertEqual(Decimal(row["amount_paid"]), Decimal("30000"))
        self.assertEqual(Decimal(row["balance"]), Decimal("70000"))
        self.assertEqual(len(row["payments"]), 1)
        self.assertEqual(Decimal(row["payments"][0]["amount"]), Decimal("30000"))

    def test_a_returning_client_s_next_project_adds_to_the_price(self):
        first = self.convert(value="100000", paid="30000")
        second = self.convert(value="50000", paid="15000", name="Acme again")
        self.assertEqual(first.id, second.id)
        row = self.customer_row(first)
        self.assertEqual((Decimal(row["price"]), Decimal(row["amount_paid"]), len(row["payments"])),
                         (Decimal("150000"), Decimal("45000"), 2))

    def test_recording_a_payment_lowers_the_balance(self):
        customer = self.convert()
        r = self.pay(customer, "20000", received_on=str(timezone.localdate()))
        self.assertEqual(r.status_code, 201, r.data)
        row = self.customer_row(customer)
        self.assertEqual(Decimal(row["balance"]), Decimal("50000"))
        self.assertEqual(row["payments"][-1]["reference"], "UTR123")

    def test_a_payment_cannot_be_more_than_the_balance(self):
        customer = self.convert()
        r = self.pay(customer, "70001")
        self.assertEqual(r.status_code, 400)
        self.assertIn("70,000", str(r.data))

    def test_a_payment_must_be_positive_and_not_in_the_future(self):
        customer = self.convert()
        self.assertEqual(self.pay(customer, "0").status_code, 400)
        self.assertEqual(self.pay(customer, "-5").status_code, 400)
        tomorrow = timezone.localdate() + timedelta(days=1)
        self.assertEqual(self.pay(customer, "100", received_on=str(tomorrow)).status_code, 400)

    def test_a_customer_added_directly_needs_a_price_before_a_payment(self):
        customer = make_customer(owner=self.employee)
        r = self.pay(customer, "1000")
        self.assertEqual(r.status_code, 400)
        self.assertIn("price", str(r.data).lower())
        r = self.as_(self.employee).patch(f"/api/crm/customers/{customer.id}/",
                                          {"price": "40000"}, format="json")
        self.assertEqual(r.status_code, 200, r.data)
        self.assertEqual(self.pay(customer, "1000").status_code, 201)

    def test_the_price_cannot_drop_below_what_was_paid_or_go_negative(self):
        customer = self.convert()
        for price in ("29999", "-1"):
            r = self.as_(self.employee).patch(f"/api/crm/customers/{customer.id}/",
                                              {"price": price}, format="json")
            self.assertEqual(r.status_code, 400, price)

    def test_no_receipt_while_a_balance_is_due(self):
        customer = self.convert()
        r = self.as_(self.employee).get(f"/api/crm/customers/{customer.id}/receipt.pdf")
        self.assertEqual(r.status_code, 409)
        self.assertIn("70,000", r.data["detail"])

    def test_the_receipt_is_ready_once_paid_in_full(self):
        customer = self.convert()
        self.pay(customer, "70000")
        self.assertTrue(self.customer_row(customer)["is_paid_in_full"])
        r = self.as_(self.employee).get(f"/api/crm/customers/{customer.id}/receipt.pdf")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r["Content-Type"], "application/pdf")
        self.assertIn("receipt", r["Content-Disposition"].lower())
        self.assertTrue(b"".join(r.streaming_content if r.streaming else [r.content]).startswith(b"%PDF"))

    def test_no_receipt_when_more_was_paid_than_the_price(self):
        """Old data has this (Om Gym: ₹70,000 paid on ₹40,000). A receipt
        showing a negative balance would be wrong; put it right first."""
        customer = self.convert()
        Payment.objects.create(customer=customer, amount=Decimal("80000"))
        r = self.as_(self.employee).get(f"/api/crm/customers/{customer.id}/receipt.pdf")
        self.assertEqual(r.status_code, 409)
        self.assertIn("10,000", r.data["detail"])

    def test_someone_on_another_team_sees_no_payments_or_receipt(self):
        customer = self.convert()
        self.assertEqual(self.as_(self.outsider).get(
            f"/api/crm/customers/{customer.id}/payments/").status_code, 404)
        self.assertEqual(self.pay(customer, "100", user=self.outsider).status_code, 404)
        self.assertEqual(self.as_(self.outsider).get(
            f"/api/crm/customers/{customer.id}/receipt.pdf").status_code, 404)

    def test_existing_customers_get_their_price_and_deposit_from_their_lead(self):
        import importlib
        from django.apps import apps
        backfill = importlib.import_module(
            "crm.migrations.0014_customer_price_and_payments").give_customers_their_money
        customer = make_customer(owner=self.employee, phone="9000000071")
        make_lead(owner=self.employee, phone="9000000071", status="converted",
                  converted_customer=customer, value=Decimal("80000"),
                  amount_paid=Decimal("24000"))
        backfill(apps, None)
        customer.refresh_from_db()
        self.assertEqual(customer.price, Decimal("80000"))
        self.assertEqual([p.amount for p in customer.payments.all()], [Decimal("24000")])



class CompletedRules(PipelineTestCase):
    """#43: a Completed step after Live, only once the handover is delivered
    and nothing is owed. Otherwise it says what's missing."""

    def setUp(self):
        super().setUp()
        self.customer = make_customer(owner=self.employee, price=Decimal("100000"))
        self.product = Product.objects.create(name="Test website", kind="product")

    def handover(self, delivered=True):
        d = Delivery.objects.create(
            customer=self.customer, product=self.product, assigned_to=self.employee,
            milestone="handover", scheduled_on=timezone.localdate())
        if delivered:
            d.mark_delivered(received_by="Client")
        return d

    def paid(self, amount="100000"):
        Payment.objects.create(customer=self.customer, amount=Decimal(amount))

    def complete(self, user=None):
        return self.as_(user or self.employee).post(
            f"/api/crm/customers/{self.customer.id}/complete/")

    def status(self):
        self.customer.refresh_from_db()
        return self.customer.project_status

    def test_it_needs_the_handover_delivered(self):
        self.handover(delivered=False)
        self.paid()
        r = self.complete()
        self.assertEqual(r.status_code, 409)
        self.assertIn("handover", r.data["detail"].lower())
        self.assertNotEqual(self.status(), "completed")

    def test_it_needs_nothing_owed(self):
        self.handover()
        self.paid("60000")
        r = self.complete()
        self.assertEqual(r.status_code, 409)
        self.assertIn("40,000", r.data["detail"])
        self.assertEqual(self.status(), "live")

    def test_it_says_everything_that_is_missing(self):
        r = self.complete()
        self.assertEqual(r.status_code, 409)
        self.assertEqual(len(r.data["missing"]), 2, r.data)

    def test_handed_over_and_paid_is_completed(self):
        self.handover()
        self.paid()
        r = self.complete()
        self.assertEqual(r.status_code, 200, r.data)
        self.assertEqual(r.data["project_status"], "completed")
        self.customer.refresh_from_db()
        self.assertIsNotNone(self.customer.completed_at)

    def test_completed_stays_completed_when_a_milestone_is_saved(self):
        d = self.handover()
        self.paid()
        self.complete()
        d.save()
        self.assertEqual(self.status(), "completed")

    def test_a_new_project_for_the_client_reopens_it(self):
        self.handover()
        self.paid()
        self.complete()
        lead = make_lead(owner=self.employee, phone=self.customer.phone, status="proposal",
                         value=Decimal("50000"), amount_paid=Decimal("15000"))
        self.as_(self.employee).post(f"/api/crm/leads/{lead.id}/convert/")
        self.customer.refresh_from_db()
        self.assertIsNone(self.customer.completed_at)
        self.assertEqual(self.customer.project_status, "live")

    def test_someone_on_another_team_cannot_complete_it(self):
        self.handover()
        self.paid()
        self.assertEqual(self.complete(user=self.outsider).status_code, 404)


class ScopedWriteRules(PipelineTestCase):
    """#73: someone who can't see a lead or customer can't add records to it
    either - the same as if it didn't exist. Found while building #44."""

    def setUp(self):
        super().setUp()
        self.lead = make_lead(owner=self.employee, status="new", phone="9000000081")
        self.customer = make_customer(owner=self.employee, phone="9000000082")
        self.product = Product.objects.create(name="Test website", kind="product")
        self.soon = (timezone.now() + timedelta(days=1)).isoformat()
        # Logging a visit now needs an open working day (#87).
        for user in User.objects.all():
            open_day(user)

    def add(self, user, what):
        path, body, fmt = {
            "delivery": ("/api/delivery/deliveries/", {
                "customer": self.customer.id, "product": self.product.id,
                "scheduled_on": str(timezone.localdate())}, "json"),
            "demo": ("/api/crm/demos/", {
                "lead": self.lead.id, "held_at": timezone.now().isoformat(),
                "outcome": "successful", "mode": "online", "product": "website"}, "json"),
            "negotiation": ("/api/crm/negotiations/", {"lead": self.lead.id}, "json"),
            "visit_lead": ("/api/visits/", {
                "lead": self.lead.id, "outcome": "interested",
                "lat": "18.5", "lng": "73.8"}, "multipart"),
            "visit_customer": ("/api/visits/", {
                "customer": self.customer.id, "outcome": "interested",
                "lat": "18.5", "lng": "73.8"}, "multipart"),
            "followup_lead": ("/api/visits/followups/", {
                "lead": self.lead.id, "kind": "call", "due_at": self.soon}, "json"),
            "followup_customer": ("/api/visits/followups/", {
                "customer": self.customer.id, "kind": "call", "due_at": self.soon}, "json"),
        }[what]
        return self.as_(user).post(path, body, format=fmt)

    KINDS = ("delivery", "demo", "negotiation", "visit_lead", "visit_customer",
             "followup_lead", "followup_customer")

    def test_someone_on_another_team_cannot_add_to_them(self):
        for kind in self.KINDS:
            with self.subTest(kind):
                r = self.add(self.outsider, kind)
                self.assertEqual(r.status_code, 400, (kind, r.status_code))
                self.assertIn("does not exist", str(r.data))
        self.assertFalse(Delivery.objects.exists())
        self.assertFalse(Negotiation.objects.exists())
        self.assertFalse(FollowUp.objects.exists())

    def test_the_owner_their_manager_and_admins_still_can(self):
        for user, kind in ((self.employee, "visit_lead"), (self.manager, "followup_customer"),
                           (self.admin, "delivery"), (self.employee, "demo")):
            with self.subTest((user.username, kind)):
                r = self.add(user, kind)
                self.assertEqual(r.status_code, 201, (kind, r.data))


class CleanupRules(PipelineTestCase):
    """Batch 5: #49 a demo keeps only its outcome; #51 the retail product
    is gone from the catalogue."""

    def test_a_demo_keeps_only_its_outcome(self):
        lead = make_lead(owner=self.employee, status="new", phone="9000000091")
        # An older app still sends "interested"; it's ignored, not an error.
        r = self.as_(self.employee).post("/api/crm/demos/", {
            "lead": lead.id, "held_at": timezone.now().isoformat(),
            "outcome": "successful", "mode": "online", "product": "website",
            "interested": True}, format="json")
        self.assertEqual(r.status_code, 201, r.data)
        self.assertNotIn("interested", r.data)
        row = self.as_(self.employee).get(f"/api/crm/leads/{lead.id}/").data
        self.assertNotIn("interested", row["latest_demo"])

    def test_the_retail_product_is_retired(self):
        import importlib
        from django.apps import apps
        retire = importlib.import_module(
            "crm.migrations.0017_retire_retail_products").retire_retail_products
        unused = Product.objects.create(name="Solar 5kW")
        retire(apps, None)
        self.assertFalse(Product.objects.filter(pk=unused.pk).exists())
        used = Product.objects.create(name="solar 5KW")
        customer = make_customer(owner=self.employee, phone="9000000092")
        customer.products.add(used)
        retire(apps, None)
        used.refresh_from_db()
        # Still there for the customer who has it, but off the catalogue.
        self.assertFalse(used.is_active)


class StageRuleInOnePlaceRules(PipelineTestCase):
    """#53: the lead-stage rule was written twice - in the model (the Django
    admin site) and the serializer (the API) - and each missed some of it.
    Now one rule, used by both, so they refuse the same things."""

    def admin_edit(self, lead, **changes):
        """What the Django admin site does: change fields, then full_clean()."""
        from django.core.exceptions import ValidationError
        for field, value in changes.items():
            setattr(lead, field, value)
        try:
            lead.full_clean()
        except ValidationError as e:
            return e.message_dict
        return {}

    def test_the_admin_site_cannot_skip_to_demo_without_a_demo(self):
        lead = make_lead(owner=self.employee, status="new", phone="9000000101")
        self.assertIn("status", self.admin_edit(lead, status="demo"))

    def test_the_admin_site_cannot_skip_to_proposal_without_one_sent(self):
        lead = make_lead(owner=self.employee, status="new", phone="9000000102")
        Negotiation.objects.create(lead=lead, owner=self.employee, created_by=self.employee)
        self.assertIn("status", self.admin_edit(lead, status="proposal"))

    def test_the_admin_site_needs_a_reason_to_lose_a_lead(self):
        lead = make_lead(owner=self.employee, status="demo", phone="9000000103")
        self.assertIn("lost_reason", self.admin_edit(lead, status="closed"))

    def test_the_admin_site_cannot_move_a_customer_s_lead(self):
        customer = make_customer(owner=self.employee, phone="9000000104")
        lead = make_lead(owner=self.employee, status="converted", phone="9000000104",
                         converted_customer=customer)
        self.assertIn("status", self.admin_edit(lead, status="new"))

    def test_the_admin_site_still_allows_what_the_records_back(self):
        lead = make_lead(owner=self.employee, status="new", phone="9000000105")
        Negotiation.objects.create(lead=lead, owner=self.employee, created_by=self.employee,
                                   status="proposal_sent")
        self.assertEqual(self.admin_edit(lead, status="proposal"), {})

    def test_the_api_cannot_add_a_lead_straight_into_demo(self):
        r = self.as_(self.employee).post("/api/crm/leads/", {
            "name": "Skipper", "phone": "9000000106", "status": "demo"}, format="json")
        self.assertEqual(r.status_code, 400)
        self.assertIn("status", r.data)

    def test_the_api_and_the_admin_site_say_the_same_thing(self):
        lead = make_lead(owner=self.employee, status="new", phone="9000000107")
        api = self.as_(self.manager).patch(f"/api/crm/leads/{lead.id}/",
                                           {"status": "demo"}, format="json").data["status"]
        admin_site = self.admin_edit(lead, status="demo")["status"]
        self.assertEqual(str(api[0]), admin_site[0])


class ProjectWordsRules(PipelineTestCase):
    """#50: words left from the goods-delivery version, renamed to fit a
    website/app project (decided 29 Sep). The stored codes don't change."""

    def test_handovers_and_visits_use_project_words(self):
        from visits.models import FieldVisit
        status = dict(Delivery.Status.choices)
        self.assertEqual((status["pending"], status["out_for_delivery"], status["delivered"],
                          status["not_delivered"]), ("Scheduled", "In progress", "Done", "Blocked"))
        self.assertEqual(Delivery._meta.get_field("received_by").verbose_name, "signed off by")
        self.assertEqual(dict(FieldVisit.Outcome.choices)["order_placed"], "Agreed to go ahead")


class ContactSourceRules(PipelineTestCase):
    """#52, decided 29 Sep: once a lead is a customer, the customer holds the
    contact details. The lead's copy is history and can't be edited, so the
    two can't drift apart."""

    def setUp(self):
        super().setUp()
        self.customer = make_customer(owner=self.employee, phone="9000000111")
        self.lead = make_lead(owner=self.employee, status="converted", phone="9000000111",
                              converted_customer=self.customer)

    def edit(self, lead, **changes):
        return self.as_(self.employee).patch(f"/api/crm/leads/{lead.id}/", changes,
                                             format="json")

    def test_a_customer_s_lead_keeps_its_contact_details(self):
        for field, value in (("phone", "9000000112"), ("name", "Someone else"),
                             ("email", "new@example.com"), ("city", "Mumbai")):
            with self.subTest(field):
                r = self.edit(self.lead, **{field: value})
                self.assertEqual(r.status_code, 400)
                self.assertIn("customer", str(r.data[field][0]).lower())
        self.lead.refresh_from_db()
        self.assertEqual(self.lead.phone, "9000000111")

    def test_sending_the_same_details_back_is_fine(self):
        r = self.edit(self.lead, phone="9000000111", name=self.lead.name)
        self.assertEqual(r.status_code, 200, r.data)

    def test_its_notes_can_still_be_written(self):
        self.assertEqual(self.edit(self.lead, notes="Paid the rest in cash").status_code, 200)

    def test_an_open_lead_s_details_can_be_edited(self):
        lead = make_lead(owner=self.employee, status="new", phone="9000000113")
        self.assertEqual(self.edit(lead, city="Mumbai").status_code, 200)

    def test_the_admin_site_applies_the_same_rule(self):
        from django.core.exceptions import ValidationError
        self.lead.phone = "9000000114"
        with self.assertRaises(ValidationError) as caught:
            self.lead.full_clean()
        self.assertIn("phone", caught.exception.message_dict)


class OneFieldEachRules(PipelineTestCase):
    """#48, decided 29 Sep: strictly one field each. What the client wants
    is the lead's requirement; payment is the terms choice plus one note."""

    def test_a_negotiation_has_one_place_for_each(self):
        names = {f.name for f in Negotiation._meta.get_fields()}
        self.assertEqual(names & {"requirements", "scope", "proposed_solution", "terms"}, set())
        self.assertEqual(Negotiation._meta.get_field("payment_terms_note").get_internal_type(),
                         "TextField")

    def test_an_older_app_sending_the_old_fields_still_saves(self):
        lead = make_lead(owner=self.employee, status="demo", phone="9000000121",
                         requirement="Shop website")
        r = self.as_(self.employee).post("/api/crm/negotiations/", {
            "lead": lead.id, "requirements": "Shop website", "scope": "10 pages",
            "terms": "50% now"}, format="json")
        self.assertEqual(r.status_code, 201, r.data)
        lead.refresh_from_db()
        self.assertEqual(lead.requirement, "Shop website")

    def test_old_text_is_kept_when_the_fields_are_merged(self):
        import importlib
        merge = importlib.import_module("crm.migrations.0018_one_field_each").merged
        self.assertEqual(
            merge("Shop website", [("", "Shop website"), ("Scope: ", "10 pages"),
                                   ("Proposed: ", ""), ("Proposed: ", "WooCommerce")]),
            "Shop website\nScope: 10 pages\nProposed: WooCommerce")
        self.assertEqual(merge("", [("", "Half now")]), "Half now")


class QueryCountRules(PipelineTestCase):
    """The Leads list and the Excel export asked the database once per lead
    (who gave the demo, the next follow-up, the attempts on a milestone).
    Found 30 Sep by counting queries: 15 -> 45 and 32 -> 99 as leads went
    from 10 to 40. The count must not grow with the data."""

    def add_leads(self, start, count):
        product, _ = Product.objects.get_or_create(name="Test website")
        for i in range(start, start + count):
            lead = make_lead(f"Lead {i}", owner=self.employee, status="demo",
                             phone=f"97{i:08d}")
            Demo.objects.create(lead=lead, held_at=timezone.now(), product="Website",
                                outcome="successful", given_by=self.employee,
                                created_by=self.employee)
            self.followup(lead, days=2)
            customer = make_customer(f"Customer {i}", owner=self.employee,
                                     phone=f"96{i:08d}")
            Delivery.objects.create(customer=customer, product=product,
                                    assigned_to=self.employee, milestone="go_live",
                                    scheduled_on=timezone.localdate())

    def queries(self, url):
        from django.db import connection
        from django.test.utils import CaptureQueriesContext
        with CaptureQueriesContext(connection) as ctx:
            r = self.as_(self.admin).get(url)
            self.assertEqual(r.status_code, 200)
            getattr(r, "content", None)
        return len(ctx.captured_queries)

    def test_the_leads_list_and_export_do_not_slow_down_as_leads_grow(self):
        urls = ("/api/crm/leads/", "/api/export/pipeline.xlsx")
        self.add_leads(0, 3)
        few = [self.queries(u) for u in urls]
        self.add_leads(3, 9)
        many = [self.queries(u) for u in urls]
        self.assertEqual(few, many)
