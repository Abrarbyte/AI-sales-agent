"""Notifications are personal.

Deliberately stricter than the role rule: a manager reads their team's leads
and attendance, but not their messages. That is a decision worth pinning,
because "scope it like everything else" is the obvious change to make later
and it would be wrong.
"""

from rest_framework.test import APITestCase

from common.testing import make_team
from notifications.models import Notification


class NotificationScopeTests(APITestCase):
    def setUp(self):
        self.admin, self.manager, self.employee, self.outsider = make_team()
        self.mine = Notification.objects.create(
            user=self.employee, kind="system", title="Yours", body="")
        self.theirs = Notification.objects.create(
            user=self.outsider, kind="system", title="Theirs", body="")

    def titles_for(self, user):
        self.client.force_authenticate(user)
        response = self.client.get("/api/notifications/")
        self.assertEqual(response.status_code, 200)
        return {row["title"] for row in response.json()}

    def test_you_only_read_your_own(self):
        self.assertEqual(self.titles_for(self.employee), {"Yours"})

    def test_a_manager_does_not_read_their_teams_messages(self):
        self.assertEqual(self.titles_for(self.manager), set())

    def test_an_admin_does_not_either(self):
        self.assertEqual(self.titles_for(self.admin), set())

    def test_cannot_mark_someone_elses_as_read(self):
        self.client.force_authenticate(self.employee)
        response = self.client.post(
            f"/api/notifications/{self.theirs.id}/read/", {}, format="json")
        self.assertEqual(response.status_code, 404)
        self.theirs.refresh_from_db()
        self.assertIsNone(self.theirs.read_at)

    def test_unread_count_is_your_own(self):
        self.client.force_authenticate(self.employee)
        response = self.client.get("/api/notifications/unread-count/")
        self.assertEqual(response.json()["unread"], 1)

    def test_read_all_only_touches_yours(self):
        self.client.force_authenticate(self.employee)
        self.client.post("/api/notifications/read-all/", {}, format="json")
        self.mine.refresh_from_db()
        self.theirs.refresh_from_db()
        self.assertIsNotNone(self.mine.read_at)
        self.assertIsNone(self.theirs.read_at)
