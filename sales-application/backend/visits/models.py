from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import models
from django.utils import timezone

from common.fields import latitude_field, longitude_field, place_field


class FieldVisit(models.Model):
    """A salesperson physically visiting a lead or a customer.

    The visit points at exactly one of them — a lead before the sale, a customer
    after. Both are optional columns with a constraint enforcing "exactly one",
    rather than one generic link, so ordinary queries stay simple and the
    database itself rejects a visit attached to nothing or to both.
    """

    class Outcome(models.TextChoices):
        INTERESTED = "interested"
        NOT_INTERESTED = "not_interested"
        FOLLOW_UP = "follow_up"
        # The code is from the retail version; the words fit the work (#50).
        ORDER_PLACED = "order_placed", "Agreed to go ahead"
        NOT_AVAILABLE = "not_available"

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE,
        related_name="field_visits",
    )
    lead = models.ForeignKey(
        "crm.Lead", on_delete=models.CASCADE,
        null=True, blank=True, related_name="visits",
    )
    customer = models.ForeignKey(
        "crm.Customer", on_delete=models.CASCADE,
        null=True, blank=True, related_name="visits",
    )

    visited_at = models.DateTimeField(default=timezone.now)
    date = models.DateField(default=timezone.localdate)

    # Where the salesperson actually was — the proof the visit happened.
    lat = latitude_field()
    lng = longitude_field()
    place = place_field()

    # A photograph taken on site, stamped with the coordinates above.
    # Optional: a visit made where the camera was refused, or on a phone
    # without one, is still a real visit — the GPS fix is the proof that
    # matters, and that is required.
    photo = models.ImageField(upload_to="visits/%Y/%m/", null=True, blank=True)

    outcome = models.CharField(max_length=20, choices=Outcome.choices)
    notes = models.TextField(blank=True)
    duration_minutes = models.PositiveIntegerField(null=True, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ("-visited_at",)
        constraints = [
            models.CheckConstraint(
                # Exactly one of lead/customer must be set.
                condition=(
                    models.Q(lead__isnull=False, customer__isnull=True)
                    | models.Q(lead__isnull=True, customer__isnull=False)
                ),
                name="visit_targets_exactly_one_contact",
            ),
        ]
        indexes = [
            models.Index(fields=["user", "date"]),
            models.Index(fields=["date"]),
        ]

    def __str__(self):
        return f"{self.user.username} → {self.target_name} ({self.date})"

    @property
    def target_name(self):
        target = self.lead or self.customer
        return target.name if target else "—"

    def clean(self):
        super().clean()
        if bool(self.lead_id) == bool(self.customer_id):
            raise ValidationError(
                "A visit must name exactly one lead or one customer.")


# FollowUp lives in its own module for readability but must be imported here
# so Django's app registry discovers it.
from .followups import FollowUp  # noqa: E402,F401
from .reminders import FollowUpReminder  # noqa: E402,F401
