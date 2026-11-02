"""Follow-ups: the next action someone owes a lead or customer.

Kept in the same app as visits because the two are one workflow — a visit ends
with "call them Tuesday", and Tuesday's follow-up ends with another visit.
"""

from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import models
from django.utils import timezone


class FollowUp(models.Model):
    class Kind(models.TextChoices):
        CALL = "call"
        VISIT = "visit"
        MEETING = "meeting"  # an appointment, in person, at a set time
        EMAIL = "email"
        MESSAGE = "message"

    class Status(models.TextChoices):
        PENDING = "pending"
        DONE = "done"
        CANCELLED = "cancelled"

    assigned_to = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE,
        related_name="followups",
    )
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL,
        null=True, blank=True, related_name="followups_created",
    )

    lead = models.ForeignKey(
        "crm.Lead", on_delete=models.CASCADE,
        null=True, blank=True, related_name="followups",
    )
    customer = models.ForeignKey(
        "crm.Customer", on_delete=models.CASCADE,
        null=True, blank=True, related_name="followups",
    )
    # The visit that prompted this, when there was one.
    visit = models.ForeignKey(
        "visits.FieldVisit", on_delete=models.SET_NULL,
        null=True, blank=True, related_name="followups",
    )

    kind = models.CharField(max_length=20, choices=Kind.choices, default=Kind.CALL)
    status = models.CharField(max_length=20, choices=Status.choices,
                              default=Status.PENDING)
    due_at = models.DateTimeField()
    note = models.CharField(max_length=255, blank=True)

    completed_at = models.DateTimeField(null=True, blank=True)
    outcome_note = models.CharField(max_length=255, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ("due_at",)
        constraints = [
            models.CheckConstraint(
                condition=(
                    models.Q(lead__isnull=False, customer__isnull=True)
                    | models.Q(lead__isnull=True, customer__isnull=False)
                ),
                name="followup_targets_exactly_one_contact",
            ),
        ]
        indexes = [
            # The query the app runs constantly: my pending work, soonest first.
            models.Index(fields=["assigned_to", "status", "due_at"]),
        ]

    def __str__(self):
        return f"{self.kind} → {self.target_name} ({self.due_at:%d %b})"

    @property
    def target_name(self):
        target = self.lead or self.customer
        return target.name if target else "—"

    @property
    def is_overdue(self):
        return self.status == self.Status.PENDING and self.due_at < timezone.now()

    def clean(self):
        super().clean()
        if bool(self.lead_id) == bool(self.customer_id):
            raise ValidationError(
                "A follow-up must name exactly one lead or one customer.")

    def mark_done(self, note=""):
        self.status = self.Status.DONE
        self.completed_at = timezone.now()
        if note:
            self.outcome_note = note
        self.save(update_fields=["status", "completed_at", "outcome_note", "updated_at"])
