"""Each follow-up gets its 30-minute, 10-minute and overdue alert exactly
once, however often the job runs, and never once it is done."""

from datetime import timedelta

from django.core.management import call_command
from django.utils import timezone
from rest_framework.test import APITestCase

from common.testing import make_lead, make_team
from notifications.models import Notification
from notifications.reminders import send_due_reminders
from visits.models import FollowUp, FollowUpReminder


class ReminderTests(APITestCase):
    def setUp(self):
        self.admin, self.manager, self.employee, self.outsider = make_team()
        self.lead = make_lead("Meet", owner=self.employee)
        # Assigned by the rep to themself, so the "scheduled for you" signal
        # stays quiet and only the reminders show up in the count.
        self.followup = FollowUp.objects.create(
            assigned_to=self.employee, created_by=self.employee,
            lead=self.lead, kind=FollowUp.Kind.MEETING,
            due_at=timezone.now() + timedelta(hours=2), note="Site survey")

    def mine(self):
        return Notification.objects.filter(user=self.employee)

    def run_at(self, minutes_before_due):
        return send_due_reminders(
            now=self.followup.due_at - timedelta(minutes=minutes_before_due))

    def test_nothing_until_thirty_minutes_out(self):
        self.assertEqual(self.run_at(45), 0)
        self.assertEqual(self.mine().count(), 0)

    def test_thirty_then_ten_then_overdue_once_each(self):
        self.assertEqual(self.run_at(30), 1)
        self.assertEqual(self.run_at(29), 0)  # rerun: nothing new
        self.assertEqual(self.run_at(10), 1)
        self.assertEqual(self.run_at(5), 0)
        self.assertEqual(self.run_at(-1), 1)  # one minute past due
        self.assertEqual(self.run_at(-60), 0)  # an hour later: still once
        titles = list(self.mine().order_by("created_at")
                      .values_list("title", flat=True))
        self.assertEqual(titles, [
            "Meeting in 30 min: Meet",
            "Meeting in 10 min: Meet",
            "Meeting overdue: Meet",
        ])
        self.assertEqual(FollowUpReminder.objects.count(), 3)

    def test_a_late_run_catches_up_in_one_pass(self):
        """The job missed the 30 and 10 marks; the first run after due sends
        all three at once rather than one per run."""
        self.assertEqual(self.run_at(-2), 3)
        self.assertEqual(self.run_at(-3), 0)

    def test_completed_followups_are_left_alone(self):
        self.followup.mark_done("Met them")
        self.assertEqual(self.run_at(10), 0)
        self.assertEqual(self.run_at(-10), 0)

    def test_overdue_uses_the_overdue_kind(self):
        self.run_at(-1)
        kinds = set(self.mine().values_list("kind", flat=True))
        self.assertIn(Notification.Kind.FOLLOWUP_OVERDUE, kinds)

    def test_the_command_runs(self):
        self.followup.due_at = timezone.now() + timedelta(minutes=5)
        self.followup.save()
        call_command("send_reminders")
        # 30 and 10 both owed at five minutes out.
        self.assertEqual(self.mine().count(), 2)

    def test_the_bell_sees_them(self):
        self.run_at(30)
        self.client.force_authenticate(self.employee)
        count = self.client.get("/api/notifications/unread-count/").json()
        self.assertEqual(count["unread"], 1)
        rows = self.client.get("/api/notifications/").json()
        self.assertEqual(rows[0]["link"], f"/followups/{self.followup.id}")

    def test_kind_filter_lists_meetings(self):
        FollowUp.objects.create(
            assigned_to=self.employee, lead=self.lead,
            kind=FollowUp.Kind.CALL,
            due_at=timezone.now() + timedelta(hours=1))
        self.client.force_authenticate(self.employee)
        rows = self.client.get(
            "/api/visits/followups/?kind=meeting,visit").json()
        self.assertEqual([r["kind"] for r in rows], ["meeting"])
