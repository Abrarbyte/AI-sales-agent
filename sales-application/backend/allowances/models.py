"""Travel allowance: what a rep is paid for the distance they covered.

Two records, kept apart on purpose:

  * AllowanceRate - the rupees-per-km the company pays. A short history, not a
    single value, so changing the rate never rewrites what was already paid.
  * TravelClaim    - one rep, one day: the distance, the rate used, and the
    money owed, all frozen at the moment they were calculated.

The distance itself is not stored here as a live calculation. It is computed
once from the day's points (see common.distance) and written onto the claim, so
a later change to the method or the rate leaves settled days alone.
"""
from django.conf import settings
from django.core.validators import MinValueValidator
from django.db import models
from django.utils import timezone


class AllowanceRate(models.Model):
    """A rate per km, in force from a date until the next one supersedes it.

    Append-only in spirit: to change the rate you add a row with a later
    `effective_from`, you do not edit an old one. `current()` picks the row in
    force today, so a claim computed today is costed at today's rate and a
    claim computed last week keeps the rate it was costed at.
    """

    rate_per_km = models.DecimalField(
        max_digits=6, decimal_places=2,
        validators=[MinValueValidator(0)],
        help_text="Rupees paid per kilometre travelled.",
    )
    # The day this rate starts to apply. Dated, not timestamped: a rate is a
    # policy decision for a period, not an instant.
    effective_from = models.DateField(default=timezone.localdate)

    # Who set it, for the audit trail. Kept even if that person is later
    # removed, so the history does not develop holes.
    updated_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL,
        null=True, blank=True, related_name="allowance_rates_set",
    )
    note = models.CharField(max_length=255, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ("-effective_from", "-created_at")
        constraints = [
            # One rate decision per day. A second change on the same day edits
            # that day's row rather than leaving two rows the picker must
            # choose between.
            models.UniqueConstraint(
                fields=["effective_from"],
                name="one_allowance_rate_per_effective_date",
            ),
        ]

    def __str__(self):
        return f"₹{self.rate_per_km}/km from {self.effective_from}"

    @classmethod
    def current(cls, on=None):
        """The rate in force on `on` (default today), or None if none is set.

        Callers decide what "none set" means for them; the compute job treats
        it as "do not cost anything yet" rather than guessing a number.
        """
        on = on or timezone.localdate()
        return (cls.objects.filter(effective_from__lte=on)
                .order_by("-effective_from").first())


class TravelClaim(models.Model):
    """One rep's travel for one day, costed and awaiting approval.

    The numbers are a snapshot, not a formula: `distance_km` and `rate_per_km`
    are written when the claim is computed and never recomputed, so the figure
    a manager approves is the figure that was shown. Re-running the compute job
    for a day refreshes a still-pending claim; it leaves an approved one alone.
    """

    class Method(models.TextChoices):
        ROAD = "road", "Road distance (Routes API)"
        STRAIGHT = "straight", "Straight-line estimate"

    class Status(models.TextChoices):
        PENDING = "pending", "Pending"
        APPROVED = "approved", "Approved"
        QUERIED = "queried", "Queried"
        REJECTED = "rejected", "Rejected"

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE,
        related_name="travel_claims",
    )
    date = models.DateField()

    distance_km = models.DecimalField(max_digits=8, decimal_places=2)
    rate_per_km = models.DecimalField(max_digits=6, decimal_places=2)
    amount = models.DecimalField(max_digits=12, decimal_places=2)

    method = models.CharField(max_length=10, choices=Method.choices)
    # True when the Routes API was unreachable and straight-line stood in, so
    # the console can show the figure as an estimate rather than a measurement.
    is_estimate = models.BooleanField(default=False)

    # Legs the distance code judged too long to be real travel (a GPS jump).
    # Kept as the raw list so a reviewer sees exactly what was doubted.
    flagged_legs = models.JSONField(default=list, blank=True)

    status = models.CharField(max_length=10, choices=Status.choices,
                              default=Status.PENDING)
    approved_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL,
        null=True, blank=True, related_name="travel_claims_reviewed",
    )
    reviewed_at = models.DateTimeField(null=True, blank=True)
    note = models.TextField(blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ("-date", "user__username")
        constraints = [
            # One claim per rep per day - the day is the unit of travel.
            models.UniqueConstraint(
                fields=["user", "date"],
                name="one_travel_claim_per_user_per_day",
            ),
        ]
        indexes = [
            models.Index(fields=["date"]),
            models.Index(fields=["user", "date"]),
            models.Index(fields=["status"]),
        ]

    def __str__(self):
        return f"{self.user.username} — {self.date}: ₹{self.amount} ({self.status})"

    @property
    def is_settled(self):
        """Decided one way or another - no longer refreshed by the compute job."""
        return self.status in (self.Status.APPROVED, self.Status.REJECTED)

    def mark(self, status, by, note=""):
        """Record a review decision. The caller has already checked the actor
        may approve; this only writes the outcome."""
        self.status = status
        self.approved_by = by
        self.reviewed_at = timezone.now()
        if note:
            self.note = note
        self.save(update_fields=["status", "approved_by", "reviewed_at",
                                 "note", "updated_at"])
