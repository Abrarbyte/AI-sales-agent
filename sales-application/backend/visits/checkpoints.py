"""Checkpoints: where the salesperson was, and when.

A deliberately thin record. Wherever he goes he taps once and his position is
stored — nothing else is required. That is the whole feature, and keeping it
that way is the point: a checkpoint that demanded a reason, a contact and an
outcome would not get tapped.

Distinct from `FieldVisit`, which is a business record: it must name exactly one
lead or customer and say how the meeting went. A checkpoint asserts only "I was
here at this time", which is what location tracking actually needs.
"""

from django.conf import settings
from django.db import models
from django.utils import timezone

from common.fields import latitude_field, longitude_field


class Checkpoint(models.Model):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE,
        related_name="checkpoints",
    )

    # Where he was. Required — a checkpoint without coordinates is nothing.
    lat = latitude_field()
    lng = longitude_field()

    # How good the fix was, in metres, as the phone reported it. Worth keeping:
    # a reading accurate to 5m and one accurate to 500m look identical once
    # stored, and only one of them means he was really there.
    accuracy_m = models.PositiveIntegerField(null=True, blank=True)

    # Server clock, not the phone's, so a checkpoint cannot be backdated.
    recorded_at = models.DateTimeField(default=timezone.now)
    date = models.DateField(default=timezone.localdate)

    # Both optional, both his choice.
    note = models.CharField(max_length=255, blank=True)
    photo = models.ImageField(upload_to="checkpoints/%Y/%m/", null=True, blank=True)

    class Meta:
        ordering = ("-recorded_at",)
        indexes = [
            # The query the admin runs constantly: one person's day, in order.
            models.Index(fields=["user", "date"]),
        ]

    def __str__(self):
        return f"{self.user} @ {self.lat},{self.lng} ({self.recorded_at:%d %b %H:%M})"
