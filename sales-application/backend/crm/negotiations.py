"""Negotiations: the deal is on the table.

One per lead. A second round is the same negotiation with its status moved,
not a new record: the objections and terms from the first round are exactly
what the second round is about.
"""

from decimal import ROUND_HALF_UP, Decimal

from django.conf import settings
from django.core.validators import MaxValueValidator, MinValueValidator
from django.db import models
from django.utils import timezone

from common.storage import validate_upload


def price_after_discount(quoted, discount_pct):
    """What a quote comes to once its discount is taken off; None with no
    quote. Migration 0013 keeps its own copy."""
    if quoted is None:
        return None
    off = (discount_pct or Decimal("0")) / 100
    return (quoted * (1 - off)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


class Negotiation(models.Model):
    class Status(models.TextChoices):
        # Won and lost were here too, a second record of the deal's outcome
        # that could disagree with the lead's. The outcome now lives only on
        # the lead: win = convert, lose = mark the lead lost (#28).
        IN_PROGRESS = "in_progress"
        PROPOSAL_SENT = "proposal_sent"
        ON_HOLD = "on_hold"

    OPEN_STATUSES = ("in_progress", "proposal_sent", "on_hold")

    lead = models.OneToOneField(
        "crm.Lead", on_delete=models.CASCADE, related_name="negotiation")
    owner = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL,
        null=True, blank=True, related_name="negotiations")
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL,
        null=True, blank=True, related_name="negotiations_created")

    class PaymentTerms(models.TextChoices):
        ADVANCE_30 = "advance_30"        # 30% to start, rest on go-live
        HALF_HALF = "half_half"
        MILESTONES = "milestones"
        FULL_ADVANCE = "full_advance"
        CUSTOM = "custom"

    started_at = models.DateField(default=timezone.localdate)

    # The commercial side of the quote. `quoted_amount` is what we asked,
    # before `discount_pct` comes off. The lead's `value` is what was finally
    # agreed; until someone agrees a different one, it follows the quote (#29).
    quoted_amount = models.DecimalField(max_digits=12, decimal_places=2,
                                        null=True, blank=True,
                                        validators=[MinValueValidator(0)])
    discount_pct = models.DecimalField(max_digits=5, decimal_places=2,
                                       null=True, blank=True,
                                       validators=[MinValueValidator(0),
                                                   MaxValueValidator(100)])
    # Strictly one field each (#48, decided 29 Sep): what the client wants
    # is the lead's `requirement`, and payment is `payment_terms` plus this
    # one note. The negotiation's requirements, scope, proposed solution and
    # free-text terms were folded into those by migration crm 0018.
    payment_terms = models.CharField(
        max_length=15, choices=PaymentTerms.choices, blank=True)
    payment_terms_note = models.TextField(blank=True)
    timeline_weeks = models.PositiveSmallIntegerField(null=True, blank=True)
    # Another agency they are comparing us with, and what it quoted.
    competitor = models.CharField(max_length=150, blank=True)
    proposal = models.FileField(upload_to="proposals/%Y/%m/", null=True,
                                blank=True, validators=[validate_upload])
    # Who actually signs off. Often not the person on the lead.
    decision_maker = models.CharField(max_length=120, blank=True)
    objections = models.TextField(blank=True)
    expected_close_on = models.DateField(null=True, blank=True)
    status = models.CharField(
        max_length=20, choices=Status.choices, default=Status.IN_PROGRESS)
    followup = models.ForeignKey(
        "visits.FollowUp", on_delete=models.SET_NULL,
        null=True, blank=True, related_name="negotiations")
    notes = models.TextField(blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ("-started_at",)
        indexes = [models.Index(fields=["status", "expected_close_on"])]

    def __str__(self):
        return f"{self.lead.name} ({self.status})"

    def save(self, *args, **kwargs):
        # What the quote came to before this save, so the lead can tell
        # whether its price is still the quote's (#29).
        before = None
        if self.pk:
            row = (Negotiation.objects.filter(pk=self.pk)
                   .values_list("quoted_amount", "discount_pct").first())
            before = price_after_discount(*row) if row else None
        super().save(*args, **kwargs)
        self.lead.follow_quote(was=before, now=self.offered_price)

    @property
    def offered_price(self):
        return price_after_discount(self.quoted_amount, self.discount_pct)

    @property
    def is_open(self):
        # Open while its lead is: a customer's or a lost lead's negotiation
        # is finished, whatever its own status says.
        from .models import Lead
        return (self.status in self.OPEN_STATUSES
                and self.lead.status in Lead.OPEN_STATUSES)

    @property
    def is_slipping(self):
        """Past the expected close and still open."""
        return (self.is_open and self.expected_close_on is not None
                and self.expected_close_on < timezone.localdate())
