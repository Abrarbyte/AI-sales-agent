"""Check-in and check-out.

The rule worth defending: the client never says who is checking in or when.
Both come from the request itself, so attendance cannot be filed for someone
else or backdated — which is the whole reason GPS attendance is trusted.
"""

from django.utils import timezone
from rest_framework.test import APITestCase

from attendance.models import Attendance
from common.testing import make_team


class CheckInTests(APITestCase):
    def setUp(self):
        self.admin, self.manager, self.employee, self.outsider = make_team()
        self.client.force_authenticate(self.employee)

    def check_in(self, **overrides):
        payload = {"lat": "19.076000", "lng": "72.877700"}
        payload.update(overrides)
        return self.client.post(
            "/api/attendance/check-in/", payload, format="json")

    def test_check_in_records_the_caller_and_the_server_clock(self):
        response = self.check_in()
        self.assertEqual(response.status_code, 201)
        record = Attendance.objects.get()
        self.assertEqual(record.user, self.employee)
        self.assertEqual(record.date, timezone.localdate())

    def test_cannot_check_in_as_someone_else(self):
        """`user` is read-only, so naming another person is simply ignored."""
        self.check_in(user=self.outsider.id)
        self.assertEqual(Attendance.objects.get().user, self.employee)

    def test_cannot_backdate_a_check_in(self):
        """Date and time are server-stamped, so a client claiming otherwise is
        simply ignored."""
        self.check_in(date="2020-01-01", check_in_at="2020-01-01T09:00:00Z")
        record = Attendance.objects.get()
        self.assertEqual(record.date, timezone.localdate())
        self.assertEqual(record.check_in_at.date(), timezone.localdate())

    def test_second_check_in_the_same_day_is_a_conflict(self):
        self.check_in()
        self.assertEqual(self.check_in().status_code, 409)

    def test_coordinates_are_required(self):
        response = self.client.post(
            "/api/attendance/check-in/", {}, format="json")
        self.assertEqual(response.status_code, 400)

    def test_kind_defaults_to_office(self):
        """The common case needs no extra tap: a day is at a desk unless the
        person says otherwise."""
        self.check_in()
        self.assertEqual(Attendance.objects.get().kind, Attendance.Kind.OFFICE)

    def test_can_check_in_for_a_field_day(self):
        response = self.check_in(kind="field")
        self.assertEqual(response.status_code, 201)
        self.assertEqual(Attendance.objects.get().kind, Attendance.Kind.FIELD)
        self.assertEqual(response.data["kind"], "field")

    def test_an_unknown_kind_is_rejected(self):
        """Only the two the model defines — a typo must not become a third
        kind of working day that nothing else knows how to count."""
        response = self.check_in(kind="wfh")
        self.assertEqual(response.status_code, 400)
        self.assertIn("kind", response.data)

    def test_check_out_cannot_change_the_kind(self):
        """The kind is settled at check-in. Accepting it again at the end
        would only offer a way for one day to hold two answers."""
        self.check_in(kind="field")
        self.client.post(
            "/api/attendance/check-out/",
            {"lat": "19.076000", "lng": "72.877700", "kind": "office"},
            format="json")
        self.assertEqual(Attendance.objects.get().kind, Attendance.Kind.FIELD)

    def test_check_out_needs_a_check_in_first(self):
        """A 400 with a readable reason, not a 404 — the person is real, the
        day's record simply is not open yet."""
        response = self.client.post(
            "/api/attendance/check-out/",
            {"lat": "19.076000", "lng": "72.877700"}, format="json")
        self.assertEqual(response.status_code, 400)
        self.assertIn("not checked in", response.json()["detail"])

    def test_check_in_and_out_keep_the_place_name(self):
        self.check_in(place="Baner, Pune")
        response = self.client.post(
            "/api/attendance/check-out/",
            {"lat": "19.076000", "lng": "72.877700", "place": "Wakad, Pune"},
            format="json")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["check_in_place"], "Baner, Pune")
        self.assertEqual(response.json()["check_out_place"], "Wakad, Pune")

    def test_the_place_name_is_optional(self):
        self.assertEqual(self.check_in().status_code, 201)
        self.assertEqual(Attendance.objects.get().check_in_place, "")

    def test_check_out_closes_the_day(self):
        self.check_in()
        response = self.client.post(
            "/api/attendance/check-out/",
            {"lat": "19.076000", "lng": "72.877700"}, format="json")
        self.assertEqual(response.status_code, 200)
        record = Attendance.objects.get()
        self.assertIsNotNone(record.check_out_at)


class AttendanceVisibilityTests(APITestCase):
    def setUp(self):
        self.admin, self.manager, self.employee, self.outsider = make_team()
        for user in (self.employee, self.outsider):
            Attendance.objects.create(
                user=user, check_in_lat="19.076000", check_in_lng="72.877700")

    def usernames_for(self, user):
        self.client.force_authenticate(user)
        response = self.client.get("/api/attendance/")
        self.assertEqual(response.status_code, 200)
        return {row["username"] for row in response.json()}

    def test_employee_sees_only_their_own(self):
        self.assertEqual(self.usernames_for(self.employee), {"t_employee"})

    def test_manager_sees_their_teams(self):
        self.assertEqual(self.usernames_for(self.manager), {"t_employee"})

    def test_admin_sees_all(self):
        self.assertEqual(
            self.usernames_for(self.admin), {"t_employee", "t_outsider"})


class DateFilterTests(APITestCase):
    """`?from=` and `?to=` must reject junk with a 400, not raise a 500."""

    def setUp(self):
        self.admin, self.manager, self.employee, self.outsider = make_team()
        self.client.force_authenticate(self.employee)

    def test_a_malformed_from_is_a_bad_request(self):
        response = self.client.get("/api/attendance/?from=banana")
        self.assertEqual(response.status_code, 400)
        self.assertIn("from", response.json())

    def test_a_malformed_to_is_a_bad_request(self):
        self.assertEqual(
            self.client.get("/api/attendance/?to=99-99-99").status_code, 400)

    def test_a_valid_range_is_accepted(self):
        response = self.client.get(
            "/api/attendance/?from=2026-01-01&to=2026-12-31")
        self.assertEqual(response.status_code, 200)
