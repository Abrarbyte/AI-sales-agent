"""Deliveries: getting what was sold to the customer.

Its own app because deliveries have their own people (whoever drives) and
their own lifecycle, the same reason visits are split from the CRM. A delivery
either lands, or it doesn't and someone records why and when to try again.
"""

from django.conf import settings
from django.db import models
from django.utils import timezone

from common.storage import validate_upload

#: The stages of a project, in order (#46).
PROJECT_STAGES = ("not_started", "design", "development", "uat", "live")


class Delivery(models.Model):
    # The stored codes are from the goods-delivery version; the words people
    # read fit a website/app milestone (#50).
    class Status(models.TextChoices):
        PENDING = "pending", "Scheduled"
        OUT_FOR_DELIVERY = "out_for_delivery", "In progress"
        DELIVERED = "delivered", "Done"
        # The last attempt failed; a retry is booked.
        NOT_DELIVERED = "not_delivered", "Blocked"
        CANCELLED = "cancelled", "Cancelled"

    FINAL_STATUSES = ("delivered", "cancelled")

    class Milestone(models.TextChoices):
        DESIGN_APPROVAL = "design_approval"
        DEVELOPMENT_COMPLETE = "development_complete"
        UAT = "uat"                  # client testing sign-off
        GO_LIVE = "go_live"
        HANDOVER = "handover"        # credentials, source, documents

    #: The project stage a delivered milestone proves has been reached.
    MILESTONE_PROJECT_STATUS = {
        "design_approval": "development",
        "development_complete": "uat",
        "uat": "uat",
        "go_live": "live",
        "handover": "live",
    }

    customer = models.ForeignKey(
        "crm.Customer", on_delete=models.CASCADE, related_name="deliveries")
    product = models.ForeignKey(
        "crm.Product", on_delete=models.PROTECT, related_name="deliveries")
    assigned_to = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL,
        null=True, blank=True, related_name="deliveries")
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL,
        null=True, blank=True, related_name="deliveries_created")

    # A service, or something collected, needs no run. The row still exists
    # so "what did this customer get" is one list.
    required = models.BooleanField(default=True)
    # Which step of the project this row hands over. A website or app is
    # delivered in stages, each with its own date and sign-off.
    milestone = models.CharField(
        max_length=25, choices=Milestone.choices, default=Milestone.HANDOVER)
    scheduled_on = models.DateField()
    # Copied from the customer when blank, then editable: a customer with an
    # office address may want the goods at a site.
    address = models.CharField(max_length=255, blank=True)
    status = models.CharField(
        max_length=20, choices=Status.choices, default=Status.PENDING)

    delivered_at = models.DateTimeField(null=True, blank=True)
    # Who on the client's side signed the milestone off.
    received_by = models.CharField("signed off by", max_length=120, blank=True)
    # A signed note, a photo of the goods at the door — whatever proves it.
    proof = models.FileField(upload_to="deliveries/%Y/%m/", null=True, blank=True,
                             validators=[validate_upload])
    # Written when it was scheduled: what to bring, who to ask for.
    notes = models.TextField(blank=True)
    # Written when it was delivered or cancelled. Its own field: delivering
    # used to overwrite the scheduling notes (#45).
    outcome_notes = models.TextField(blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ("-scheduled_on", "-id")
        verbose_name_plural = "deliveries"
        indexes = [
            models.Index(fields=["assigned_to", "status", "scheduled_on"]),
            models.Index(fields=["customer", "scheduled_on"]),
        ]

    def __str__(self):
        return f"{self.product} -> {self.customer.name} ({self.status})"

    @property
    def is_final(self):
        return self.status in self.FINAL_STATUSES

    @property
    def is_overdue(self):
        return (not self.is_final
                and self.scheduled_on < timezone.localdate())

    def save(self, *args, **kwargs):
        super().save(*args, **kwargs)
        # Scheduling, delivering or cancelling a milestone can each move the
        # project, so its status is worked out again every time (#47).
        refresh_project_status(self.customer)

    def mark_delivered(self, received_by="", proof=None, notes=""):
        self.status = self.Status.DELIVERED
        self.delivered_at = timezone.now()
        if received_by:
            self.received_by = received_by
        if proof is not None:
            self.proof = proof
        if notes:
            self.outcome_notes = notes
        self.save(update_fields=[
            "status", "delivered_at", "received_by", "proof", "outcome_notes",
            "updated_at"])


def project_status_from(milestones):
    """Where a project stands, from its milestones as (milestone, status)
    pairs (#47).

    Nothing scheduled: not started. Anything scheduled: at least Design, the
    first stage, which used to be skipped (#46). Each delivered milestone
    proves a later stage - design approved: Development; development done:
    client Testing; go-live or handover: Live. Cancelled ones don't count.
    """
    counted = [(m, s) for m, s in milestones if s != Delivery.Status.CANCELLED]
    if not counted:
        return "not_started"
    reached = "design"
    for milestone, status in counted:
        target = Delivery.MILESTONE_PROJECT_STATUS.get(milestone)
        if (status == Delivery.Status.DELIVERED and target
                and PROJECT_STAGES.index(target) > PROJECT_STAGES.index(reached)):
            reached = target
    return reached


def refresh_project_status(customer):
    """Set a customer's project status from its milestones, and its go-live
    date the first time it goes live. Never set any other way (#47)."""
    rows = list(customer.deliveries.values_list("milestone", "status", "delivered_at"))
    status = project_status_from((m, s) for m, s, _ in rows)
    # Completed is marked by hand once live, handed over and paid (#43).
    if status == "live" and customer.completed_at:
        status = "completed"
    changes = {}
    if status != customer.project_status:
        changes["project_status"] = status
    if status == "live" and customer.go_live_on is None:
        went_live = [at for m, s, at in rows
                     if s == Delivery.Status.DELIVERED and at
                     and Delivery.MILESTONE_PROJECT_STATUS.get(m) == "live"]
        changes["go_live_on"] = (timezone.localtime(min(went_live)).date()
                                 if went_live else timezone.localdate())
    if changes:
        type(customer).objects.filter(pk=customer.pk).update(
            **changes, updated_at=timezone.now())
        for field, value in changes.items():
            setattr(customer, field, value)


class DeliveryAttempt(models.Model):
    """One failed try. The delivery stays open until it lands."""

    class Reason(models.TextChoices):
        CONTENT_PENDING = "content_pending"      # client has not sent text/images
        FEEDBACK_PENDING = "feedback_pending"    # waiting on their approval
        SCOPE_CHANGE = "scope_change"
        PAYMENT_PENDING = "payment_pending"
        TECHNICAL_ISSUE = "technical_issue"
        CLIENT_UNAVAILABLE = "client_unavailable"
        OTHER = "other"

    delivery = models.ForeignKey(
        Delivery, on_delete=models.CASCADE, related_name="attempts")
    # Who takes the retry. Usually the same person; not always.
    assigned_to = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL,
        null=True, blank=True, related_name="delivery_attempts")
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL,
        null=True, blank=True, related_name="delivery_attempts_created")

    attempted_at = models.DateTimeField(default=timezone.now)
    reason = models.CharField(max_length=20, choices=Reason.choices)
    reason_note = models.CharField(max_length=255, blank=True)
    retry_on = models.DateField(null=True, blank=True)
    customer_contacted = models.BooleanField(default=False)
    notes = models.TextField(blank=True)

    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ("-attempted_at",)

    def __str__(self):
        return f"{self.delivery_id}: {self.reason} ({self.attempted_at:%d %b})"
