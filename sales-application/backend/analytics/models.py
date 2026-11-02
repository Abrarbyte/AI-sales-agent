from django.conf import settings
from django.db import models


class DailyReport(models.Model):
    """One person's numbers for one day, computed once each evening.

    Stored rather than calculated on demand: the figures are a permanent record
    of what happened that day. Recomputing them next month would give different
    answers as leads move on, and a month of dashboard queries would rescan
    every visit and attendance row.
    """

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE,
        related_name="daily_reports",
    )
    date = models.DateField()

    # Attendance
    checked_in = models.BooleanField(default=False)
    check_in_at = models.DateTimeField(null=True, blank=True)
    check_out_at = models.DateTimeField(null=True, blank=True)
    hours_worked = models.DecimalField(
        max_digits=5, decimal_places=2, null=True, blank=True)

    # Field work
    visits_count = models.PositiveIntegerField(default=0)
    visit_minutes = models.PositiveIntegerField(default=0)

    # Pipeline movement
    leads_created = models.PositiveIntegerField(default=0)
    leads_won = models.PositiveIntegerField(default=0)
    customers_created = models.PositiveIntegerField(default=0)

    # Follow-ups
    followups_completed = models.PositiveIntegerField(default=0)
    followups_pending = models.PositiveIntegerField(default=0)
    followups_overdue = models.PositiveIntegerField(default=0)

    generated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ("-date", "user__username")
        constraints = [
            models.UniqueConstraint(
                fields=["user", "date"], name="one_report_per_user_per_day",
            ),
        ]
        indexes = [models.Index(fields=["date"])]

    def __str__(self):
        return f"{self.user.username} — {self.date}"

    @property
    def was_productive(self):
        """A rough flag for the dashboard: showed up and did something."""
        return self.checked_in and (self.visits_count > 0
                                    or self.followups_completed > 0)
