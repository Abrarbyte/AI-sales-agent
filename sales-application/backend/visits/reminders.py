"""Reminders: the record that a follow-up alert was sent.

One row per (follow-up, offset), so the reminder job can run every minute
and never send the same alert twice. The offsets are minutes before due:
30 and 10 for the warnings, 0 for "it is now overdue".
"""

from django.db import models


class FollowUpReminder(models.Model):
    OFFSETS = (30, 10, 0)

    followup = models.ForeignKey(
        "visits.FollowUp", on_delete=models.CASCADE, related_name="reminders")
    offset_minutes = models.PositiveSmallIntegerField()
    sent_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["followup", "offset_minutes"],
                name="one_reminder_per_followup_offset"),
        ]

    def __str__(self):
        return f"{self.followup_id} @ -{self.offset_minutes}m"
