"""Demos: a lead was shown the product.

The step between being worked and putting money down. Kept as its own record,
not a flag on the lead, so a lead can be shown more than once and "how many
demos became customers" has an answer.
"""

from django.conf import settings
from django.db import models


class Demo(models.Model):
    class Outcome(models.TextChoices):
        SUCCESSFUL = "successful"
        PARTIAL = "partial"          # shown, but questions left open
        UNSUCCESSFUL = "unsuccessful"
        RESCHEDULED = "rescheduled"  # did not happen; another is booked

    lead = models.ForeignKey(
        "crm.Lead", on_delete=models.CASCADE, related_name="demos")
    given_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL,
        null=True, blank=True, related_name="demos_given")
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL,
        null=True, blank=True, related_name="demos_created")

    class Mode(models.TextChoices):
        ONLINE = "online"
        CLIENT_SITE = "client_site"
        OFFICE = "office"

    class Shown(models.TextChoices):
        PORTFOLIO = "portfolio"          # past work
        PROTOTYPE = "prototype"          # a mock-up / design for them
        LIVE_PROJECT = "live_project"    # a similar site/app running
        OTHER = "other"

    held_at = models.DateTimeField()
    product = models.CharField(max_length=150)
    mode = models.CharField(max_length=15, choices=Mode.choices, blank=True)
    shown = models.CharField(max_length=15, choices=Shown.choices, blank=True)
    # Who sat in from the client side. Names and roles, free text.
    attendees = models.CharField(max_length=200, blank=True)
    outcome = models.CharField(max_length=20, choices=Outcome.choices)
    feedback = models.TextField(blank=True)
    # The follow-up booked at the end of the demo, when there was one.
    followup = models.ForeignKey(
        "visits.FollowUp", on_delete=models.SET_NULL,
        null=True, blank=True, related_name="demos")
    notes = models.TextField(blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ("-held_at",)
        indexes = [models.Index(fields=["lead", "held_at"])]

    def __str__(self):
        return f"{self.product} -> {self.lead.name} ({self.held_at:%d %b})"
