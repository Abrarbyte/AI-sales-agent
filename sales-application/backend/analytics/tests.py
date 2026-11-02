"""The dashboard and the daily report list.

Mostly about query parameters: three endpoints take user input straight into a
filter, and each one used to answer a malformed value with a 500.
"""

from rest_framework.test import APITestCase

from common.testing import make_lead, make_team, make_visit


class ReportFilterTests(APITestCase):
    def setUp(self):
        self.admin, self.manager, self.employee, self.outsider = make_team()
        self.client.force_authenticate(self.employee)

    def test_a_malformed_date_is_a_bad_request(self):
        response = self.client.get("/api/analytics/reports/?from=banana")
        self.assertEqual(response.status_code, 400)
        self.assertIn("from", response.json())

    def test_a_non_numeric_user_id_is_a_bad_request(self):
        response = self.client.get("/api/analytics/reports/?user=abc")
        self.assertEqual(response.status_code, 400)
        self.assertIn("user", response.json())

    def test_a_numeric_user_id_is_accepted(self):
        response = self.client.get(
            f"/api/analytics/reports/?user={self.employee.id}")
        self.assertEqual(response.status_code, 200)

    def test_a_user_id_cannot_widen_the_scope(self):
        """The filter narrows an already-scoped queryset; it cannot escape it."""
        response = self.client.get(
            f"/api/analytics/reports/?user={self.outsider.id}")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), [])


class DashboardTests(APITestCase):
    def setUp(self):
        self.admin, self.manager, self.employee, self.outsider = make_team()
        self.lead = make_lead("Mine", owner=self.employee)
        make_visit(self.employee, lead=self.lead)
        make_visit(self.outsider, lead=make_lead("Theirs", owner=self.outsider))
        self.client.force_authenticate(self.employee)

    def test_days_is_clamped_rather_than_trusted(self):
        for value in ("0", "-5", "9999", "abc", ""):
            response = self.client.get(f"/api/analytics/dashboard/?days={value}")
            self.assertEqual(response.status_code, 200, msg=f"days={value!r}")
            days = response.json()["period"]["days"]
            self.assertGreaterEqual(days, 1, msg=f"days={value!r}")
            self.assertLessEqual(days, 90, msg=f"days={value!r}")

    def test_the_dashboard_counts_only_what_the_caller_may_see(self):
        response = self.client.get("/api/analytics/dashboard/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["team"]["size"], 1)

    def test_a_manager_sees_their_whole_team(self):
        self.client.force_authenticate(self.manager)
        response = self.client.get("/api/analytics/dashboard/")
        self.assertEqual(response.json()["team"]["size"], 2)

    def test_my_dashboard_is_always_just_me(self):
        self.client.force_authenticate(self.manager)
        response = self.client.get("/api/analytics/dashboard/me/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["visits_today"], 0)
