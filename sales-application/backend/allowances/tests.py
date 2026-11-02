"""Travel allowance: the rate, the distance, and the money frozen onto a claim.

The rules worth defending:
  * the rupees-per-km rate is dated, so changing it never rewrites past claims;
  * a claim's figures are a frozen snapshot, re-run only while still pending;
  * approving money is an admin's job, and claims are scoped like everything
    else - you see your own, a manager sees the team, an admin sees all.
"""
from datetime import date, timedelta
from decimal import ROUND_HALF_UP, Decimal
from unittest import mock

from django.core.management import call_command
from django.test import override_settings
from django.utils import timezone
from rest_framework.test import APITestCase

from attendance.models import Attendance
from common import distance
from common.testing import make_lead, make_team, make_visit

from .models import AllowanceRate, TravelClaim

# Two points about 1.4 km apart in Mumbai, used where a real distance is wanted.
A = ("19.076000", "72.877700")
B = ("19.086000", "72.885700")


def make_attendance(user, on, check_in=A, check_out=B):
    return Attendance.objects.create(
        user=user, date=on, kind=Attendance.Kind.FIELD,
        check_in_at=timezone.now(),
        check_in_lat=check_in[0], check_in_lng=check_in[1],
        check_out_at=timezone.now(),
        check_out_lat=check_out[0], check_out_lng=check_out[1],
    )


class RateTests(APITestCase):
    def test_current_picks_the_latest_rate_in_force(self):
        AllowanceRate.objects.create(rate_per_km="2.00", effective_from="2026-01-01")
        AllowanceRate.objects.create(rate_per_km="2.50", effective_from="2026-06-01")
        self.assertEqual(AllowanceRate.current(on=date(2026, 3, 1)).rate_per_km,
                         Decimal("2.00"))
        self.assertEqual(AllowanceRate.current(on=date(2026, 9, 1)).rate_per_km,
                         Decimal("2.50"))

    def test_current_is_none_before_any_rate_starts(self):
        AllowanceRate.objects.create(rate_per_km="2.50", effective_from="2026-06-01")
        self.assertIsNone(AllowanceRate.current(on=date(2026, 1, 1)))

    def test_seed_rate_is_present_from_migrations(self):
        """The ₹2.50 launch rate ships in a data migration."""
        self.assertTrue(
            AllowanceRate.objects.filter(rate_per_km=Decimal("2.50")).exists())


@override_settings(TRAVEL_DISTANCE_MODE="straight")
class MeasureDayTests(APITestCase):
    def setUp(self):
        self.admin, self.manager, self.employee, _ = make_team()

    def test_a_day_with_no_checkout_and_no_visits_is_zero(self):
        att = Attendance.objects.create(
            user=self.employee, date=date(2026, 9, 23),
            check_in_lat=A[0], check_in_lng=A[1])
        result = distance.measure_day(att, [])
        self.assertEqual(result["km"], 0.0)
        self.assertFalse(result["is_estimate"])

    def test_straight_line_applies_the_road_factor(self):
        att = make_attendance(self.employee, date(2026, 9, 23))
        result = distance.measure_day(att, [])
        self.assertEqual(result["method"], "straight")
        self.assertFalse(result["is_estimate"])
        self.assertGreater(result["km"], 0)

    @override_settings(TRAVEL_DISTANCE_MODE="road", GOOGLE_ROUTES_API_KEY="")
    def test_road_mode_without_a_key_falls_back_and_flags_estimate(self):
        att = make_attendance(self.employee, date(2026, 9, 23))
        result = distance.measure_day(att, [])
        self.assertEqual(result["method"], "straight")
        self.assertTrue(result["is_estimate"])

    @override_settings(TRAVEL_DISTANCE_MODE="road", GOOGLE_ROUTES_API_KEY="k")
    def test_road_mode_uses_the_api_when_it_answers(self):
        att = make_attendance(self.employee, date(2026, 9, 23))
        with mock.patch("common.distance.road_km", return_value=12.3) as road:
            result = distance.measure_day(att, [])
        road.assert_called_once()
        self.assertEqual(result["method"], "road")
        self.assertFalse(result["is_estimate"])
        self.assertEqual(result["km"], 12.3)

    def test_a_wild_gps_jump_is_flagged(self):
        # Check-in in Mumbai, check-out in Delhi: implausible for one day.
        att = make_attendance(self.employee, date(2026, 9, 23),
                              check_out=("28.613900", "77.209000"))
        result = distance.measure_day(att, [])
        self.assertTrue(result["flagged_legs"])


@override_settings(TRAVEL_DISTANCE_MODE="straight")
class ComputeCommandTests(APITestCase):
    def setUp(self):
        self.admin, self.manager, self.employee, _ = make_team()
        self.day = date(2026, 9, 23)
        AllowanceRate.objects.create(rate_per_km="2.50", effective_from="2026-09-01")

    def test_creates_a_claim_costed_at_the_rate(self):
        make_attendance(self.employee, self.day)
        call_command("compute_travel_claims", "--date", str(self.day), verbosity=0)
        claim = TravelClaim.objects.get(user=self.employee, date=self.day)
        # The claim reconciles by eye: shown distance × shown rate = shown amount.
        self.assertEqual(
            claim.amount,
            (claim.distance_km * Decimal("2.50")).quantize(
                Decimal("0.01"), rounding=ROUND_HALF_UP))
        self.assertEqual(claim.status, TravelClaim.Status.PENDING)

    def test_a_day_before_any_rate_is_left_uncosted(self):
        make_attendance(self.employee, date(2026, 1, 1))
        call_command("compute_travel_claims", "--date", "2026-01-01", verbosity=0)
        self.assertFalse(TravelClaim.objects.filter(date=date(2026, 1, 1)).exists())

    def test_rerun_refreshes_a_pending_claim(self):
        make_attendance(self.employee, self.day)
        call_command("compute_travel_claims", "--date", str(self.day), verbosity=0)
        TravelClaim.objects.filter(date=self.day).update(amount=Decimal("0.01"))
        call_command("compute_travel_claims", "--date", str(self.day), verbosity=0)
        claim = TravelClaim.objects.get(date=self.day)
        self.assertNotEqual(claim.amount, Decimal("0.01"))
        self.assertEqual(TravelClaim.objects.count(), 1)

    def test_rerun_leaves_an_approved_claim_untouched(self):
        make_attendance(self.employee, self.day)
        call_command("compute_travel_claims", "--date", str(self.day), verbosity=0)
        claim = TravelClaim.objects.get(date=self.day)
        claim.mark(TravelClaim.Status.APPROVED, self.admin)
        frozen = claim.amount
        TravelClaim.objects.filter(pk=claim.pk).update(amount=Decimal("999.99"))
        call_command("compute_travel_claims", "--date", str(self.day), verbosity=0)
        claim.refresh_from_db()
        # The compute job skipped it, so our manual 999.99 still stands - proof
        # the job did not rewrite a settled claim.
        self.assertEqual(claim.amount, Decimal("999.99"))
        self.assertNotEqual(frozen, Decimal("999.99"))

    def test_week_covers_monday_to_sunday(self):
        # 2026-09-23 is a Wednesday; its week is 21st (Mon) to 27th (Sun).
        make_attendance(self.employee, date(2026, 9, 21))
        make_attendance(self.employee, date(2026, 9, 27))
        call_command("compute_travel_claims", "--week", "2026-09-23", verbosity=0)
        self.assertEqual(TravelClaim.objects.count(), 2)


class RateApiTests(APITestCase):
    def setUp(self):
        self.admin, self.manager, self.employee, _ = make_team()
        AllowanceRate.objects.create(rate_per_km="2.50", effective_from="2026-09-01")

    def test_anyone_signed_in_can_read_the_current_rate(self):
        self.client.force_authenticate(self.employee)
        response = self.client.get("/api/allowances/rate/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["rate_per_km"], "2.50")

    def test_an_employee_cannot_set_the_rate(self):
        self.client.force_authenticate(self.employee)
        response = self.client.post(
            "/api/allowances/rate/",
            {"rate_per_km": "3.00", "effective_from": "2026-10-01"},
            format="json")
        self.assertEqual(response.status_code, 403)

    def test_an_admin_sets_a_new_rate_and_is_stamped_as_the_author(self):
        self.client.force_authenticate(self.admin)
        response = self.client.post(
            "/api/allowances/rate/",
            {"rate_per_km": "3.00", "effective_from": "2026-10-01"},
            format="json")
        self.assertEqual(response.status_code, 201)
        rate = AllowanceRate.objects.get(effective_from="2026-10-01")
        self.assertEqual(rate.rate_per_km, Decimal("3.00"))
        self.assertEqual(rate.updated_by, self.admin)

    def test_posting_an_existing_date_updates_that_rate(self):
        self.client.force_authenticate(self.admin)
        self.client.post(
            "/api/allowances/rate/",
            {"rate_per_km": "4.00", "effective_from": "2026-09-01"},
            format="json")
        self.assertEqual(AllowanceRate.objects.filter(
            effective_from="2026-09-01").count(), 1)
        self.assertEqual(AllowanceRate.current(on=date(2026, 9, 1)).rate_per_km,
                         Decimal("4.00"))


class ClaimApiTests(APITestCase):
    def setUp(self):
        self.admin, self.manager, self.employee, self.outsider = make_team()
        self.day = date(2026, 9, 23)
        for user in (self.employee, self.outsider):
            TravelClaim.objects.create(
                user=user, date=self.day, distance_km="5.00",
                rate_per_km="2.50", amount="12.50",
                method=TravelClaim.Method.STRAIGHT)

    def test_an_employee_sees_only_their_own_claims(self):
        self.client.force_authenticate(self.employee)
        response = self.client.get("/api/allowances/claims/")
        self.assertEqual(len(response.data), 1)
        self.assertEqual(response.data[0]["user"], self.employee.id)

    def test_a_manager_sees_the_teams_claims_not_an_outsiders(self):
        self.client.force_authenticate(self.manager)
        ids = {row["user"] for row in self.client.get(
            "/api/allowances/claims/").data}
        self.assertIn(self.employee.id, ids)
        self.assertNotIn(self.outsider.id, ids)

    def test_an_employee_cannot_approve_a_claim(self):
        claim = TravelClaim.objects.get(user=self.employee)
        self.client.force_authenticate(self.employee)
        response = self.client.post(
            f"/api/allowances/claims/{claim.pk}/approve/", {}, format="json")
        self.assertEqual(response.status_code, 403)
        claim.refresh_from_db()
        self.assertEqual(claim.status, TravelClaim.Status.PENDING)

    def test_an_admin_approves_a_claim(self):
        claim = TravelClaim.objects.get(user=self.employee)
        self.client.force_authenticate(self.admin)
        response = self.client.post(
            f"/api/allowances/claims/{claim.pk}/approve/",
            {"note": "ok"}, format="json")
        self.assertEqual(response.status_code, 200)
        claim.refresh_from_db()
        self.assertEqual(claim.status, TravelClaim.Status.APPROVED)
        self.assertEqual(claim.approved_by, self.admin)
        self.assertEqual(claim.note, "ok")

    def test_a_manager_queries_their_own_teams_claim(self):
        """A manager decides their team's claims - here the employee reports to
        the manager, so the query is allowed."""
        claim = TravelClaim.objects.get(user=self.employee)
        self.client.force_authenticate(self.manager)
        response = self.client.post(
            f"/api/allowances/claims/{claim.pk}/query/",
            {"note": "explain the detour"}, format="json")
        self.assertEqual(response.status_code, 200)
        claim.refresh_from_db()
        self.assertEqual(claim.status, TravelClaim.Status.QUERIED)

    def test_a_manager_cannot_decide_an_outsiders_claim(self):
        """Scoping still holds: a claim outside the manager's team is not even
        visible, so acting on it reads as 'not found', never an approval."""
        claim = TravelClaim.objects.get(user=self.outsider)
        self.client.force_authenticate(self.manager)
        response = self.client.post(
            f"/api/allowances/claims/{claim.pk}/approve/", {}, format="json")
        self.assertEqual(response.status_code, 404)
        claim.refresh_from_db()
        self.assertEqual(claim.status, TravelClaim.Status.PENDING)

    def test_an_admin_queries_a_claim_back(self):
        claim = TravelClaim.objects.get(user=self.employee)
        self.client.force_authenticate(self.admin)
        response = self.client.post(
            f"/api/allowances/claims/{claim.pk}/query/",
            {"note": "explain the detour"}, format="json")
        self.assertEqual(response.status_code, 200)
        claim.refresh_from_db()
        self.assertEqual(claim.status, TravelClaim.Status.QUERIED)
