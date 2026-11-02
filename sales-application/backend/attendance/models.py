from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import models
from django.utils import timezone

from common.fields import latitude_field, longitude_field, place_field


class Attendance(models.Model):
    """One work day for one employee: where and when they started, and where
    and when they finished. Coordinates are plain decimals for now; they move
    to PostGIS point fields when geofencing arrives in Phase 3."""

    class Kind(models.TextChoices):
        """Where the day is being worked from.

        Chosen at check-in and not changed afterwards. A day that starts at a
        desk and drifts into the field is still one working day; where the
        person actually went is answered by the visits logged against it, not
        by editing this.
        """

        OFFICE = "office"
        FIELD = "field"

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="attendance_records",
    )
    # Stored explicitly rather than derived from check_in_at, so a day's record
    # stays findable by date regardless of timezone conversion at read time.
    date = models.DateField(default=timezone.localdate)

    kind = models.CharField(max_length=10, choices=Kind.choices,
                            default=Kind.OFFICE)

    check_in_at = models.DateTimeField(default=timezone.now)
    check_in_lat = latitude_field()
    check_in_lng = longitude_field()
    check_in_place = place_field()

    check_out_at = models.DateTimeField(null=True, blank=True)
    check_out_lat = latitude_field(null=True, blank=True)
    check_out_lng = longitude_field(null=True, blank=True)
    check_out_place = place_field()

    note = models.CharField(max_length=255, blank=True)

    class Meta:
        ordering = ("-date", "-check_in_at")
        constraints = [
            # One attendance row per person per day — blocks double check-in
            # even if two requests arrive at the same moment.
            models.UniqueConstraint(
                fields=["user", "date"], name="one_attendance_per_user_per_day",
            ),
        ]

    def __str__(self):
        return f"{self.user.username} — {self.date} ({self.kind})"

    @property
    def is_open(self):
        """Checked in but not yet checked out."""
        return self.check_out_at is None

    @property
    def hours_worked(self):
        if self.check_out_at is None:
            return None
        return round((self.check_out_at - self.check_in_at).total_seconds() / 3600, 2)

    def clean(self):
        super().clean()
        if self.check_out_at and self.check_out_at < self.check_in_at:
            raise ValidationError(
                {"check_out_at": "Check-out cannot be earlier than check-in."})
