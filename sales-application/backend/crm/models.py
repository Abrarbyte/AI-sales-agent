from datetime import timedelta
from decimal import ROUND_HALF_UP, Decimal

from django.conf import settings
from django.core.exceptions import ValidationError
from django.core.validators import MinValueValidator
from django.db import models
from django.utils import timezone

from common.fields import latitude_field, longitude_field, phone_field

# The contact details a lead hands over when it becomes a customer.
# Conversion is driven by this list so the two can never drift apart.
CONTACT_COPY_FIELDS = (
    "name", "company_name", "phone", "email",
    "address", "city", "lat", "lng", "notes",
)

# Once a lead is a customer, the customer holds these and the lead's copy is
# history (#52, decided 29 Sep). Notes aren't among them: a note on the lead
# is about the lead.
CUSTOMER_OWNED_FIELDS = tuple(f for f in CONTACT_COPY_FIELDS if f != "notes")


def phone_key(phone):
    """A phone number reduced to its last ten digits, so "+91 98100 00101"
    and "9810000101" compare equal. "" when too short to mean anything."""
    digits = "".join(ch for ch in (phone or "") if ch.isdigit())[-10:]
    return digits if len(digits) >= 8 else ""


class ContactBase(models.Model):
    """Fields shared by leads and customers, so the two stay consistent and a
    lead can be copied to a customer field-for-field on conversion.

    NOTE: single-company design. If this ever becomes a product sold to several
    companies, a `company` foreign key goes here and on `User`, and every
    queryset gains a filter on it.
    """

    name = models.CharField(max_length=120)
    company_name = models.CharField(max_length=150, blank=True)
    phone = phone_field()
    email = models.EmailField(blank=True)
    address = models.CharField(max_length=255, blank=True)
    city = models.CharField(max_length=80, blank=True)

    # Where the place actually is, for routing and (Phase 3) geofencing.
    lat = latitude_field(null=True, blank=True)
    lng = longitude_field(null=True, blank=True)

    notes = models.TextField(blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        abstract = True

    @classmethod
    def with_same_phone(cls, phone, queryset=None):
        """The records in `queryset` (default: all) with `phone`'s number,
        however either was typed."""
        key = phone_key(phone)
        if not key:
            return []
        rows = cls.objects.all() if queryset is None else queryset
        # Typed numbers end in a digit, so this narrows the scan cheaply.
        return [r for r in rows.filter(phone__endswith=key[-1])
                if phone_key(r.phone) == key]

    def owner_label(self):
        owner = getattr(self, "assigned_to", None)
        return (owner.get_full_name() or owner.username) if owner else "nobody"


class Lead(ContactBase):
    """Someone who might buy. Becomes a Customer once they do."""

    class Status(models.TextChoices):
        """The states a lead is actually in here.

        Demo and negotiation are not set by hand: logging a Demo or opening a
        Negotiation moves the lead there, so the stage always has a record
        behind it. A status nobody maintains is worse than none — it looks
        like information.
        """

        # There used to be an "assigned" stage between New and Demo. Every
        # lead always has an owner and nothing ever moved a lead there, so it
        # was removed (#27, decided 29 Sep); those leads became New.
        NEW = "new"                  # not yet shown our work
        DEMO = "demo"                # shown our work, deciding
        NEGOTIATION = "negotiation"  # scope and price on the table
        PROPOSAL = "proposal"        # a written quote is with them
        # Shown as "Customer" (decided 29 Sep); stored as "converted".
        CONVERTED = "converted", "Customer"  # became a customer
        # Shown as "Lost" everywhere (#22). The stored value stays "closed",
        # so no data moves.
        CLOSED = "closed", "Lost"    # went nowhere, or went quiet for 30 days

    #: Statuses a lead can still move forward from.
    OPEN_STATUSES = ("new", "demo", "negotiation", "proposal")

    #: A lead nobody has touched for this long is closed by
    #: `manage.py close_stale_leads`. Not deleted — how many leads went cold is
    #: worth knowing, and it is the same question as how the month went.
    STALE_AFTER_DAYS = 30

    #: How much of the agreed value must be paid before a lead may become a
    #: customer. A deposit is what separates someone who says they will buy
    #: from someone who has.
    DEPOSIT_SHARE = Decimal("0.30")

    #: The deposit each kind of payment terms asks for instead (#32, decided
    #: 29 Sep). Milestones, custom terms, or nothing agreed yet: DEPOSIT_SHARE.
    DEPOSIT_BY_TERMS = {
        "full_advance": Decimal("1.00"),
        "half_half": Decimal("0.50"),
        "advance_30": Decimal("0.30"),
    }

    #: How far along each open stage is.
    STAGE_RANK = {"new": 0, "demo": 1, "negotiation": 2, "proposal": 3}

    @staticmethod
    def cancel_open_followups(lead_ids):
        """Cancel the pending follow-ups of leads that were just lost.

        Every way a lead can be lost calls this - by hand, through its
        negotiation, and the nightly auto-close - so a rep is never reminded
        about a dead lead (#20). update() on purpose: one query, and the
        reminder job only ever looks at pending follow-ups.
        """
        from visits.models import FollowUp  # visits depends on crm
        return FollowUp.objects.filter(
            lead_id__in=lead_ids, status=FollowUp.Status.PENDING,
        ).update(status=FollowUp.Status.CANCELLED, updated_at=timezone.now())

    @classmethod
    def is_step_back(cls, from_status, to_status):
        """True when a change moves a lead back: to an earlier open stage, or
        from lost back into the pipeline (a reopen)."""
        if to_status not in cls.STAGE_RANK:
            return False
        if from_status == cls.Status.CLOSED:
            return True
        return (from_status in cls.STAGE_RANK
                and cls.STAGE_RANK[to_status] < cls.STAGE_RANK[from_status])

    class Source(models.TextChoices):
        FIELD_VISIT = "field_visit"      # cold visit to their office/shop
        REFERRAL = "referral"            # someone sent them
        EXISTING_CLIENT = "existing_client"
        PHONE = "phone"
        WHATSAPP = "whatsapp"
        WEBSITE = "website"              # enquiry form on our site
        SOCIAL_MEDIA = "social_media"    # Instagram / LinkedIn / Facebook
        GOOGLE = "google"                # search / ads
        OTHER = "other"

    class ProjectType(models.TextChoices):
        WEBSITE = "website"
        ECOMMERCE = "ecommerce"
        ANDROID_APP = "android_app"
        IOS_APP = "ios_app"
        WEB_APP = "web_app"
        WEBSITE_AND_APP = "website_and_app"
        REDESIGN = "redesign"
        MAINTENANCE = "maintenance"
        OTHER = "other"

    class Platforms(models.TextChoices):
        ANDROID = "android"
        IOS = "ios"
        BOTH = "both"

    class Industry(models.TextChoices):
        RESTAURANT = "restaurant"
        HEALTHCARE = "healthcare"
        EDUCATION = "education"
        REAL_ESTATE = "real_estate"
        RETAIL = "retail"
        MANUFACTURING = "manufacturing"
        SERVICES = "services"
        ECOMMERCE = "ecommerce"
        OTHER = "other"

    class Priority(models.TextChoices):
        HOT = "hot"
        WARM = "warm"
        COLD = "cold"

    class LostReason(models.TextChoices):
        PRICE = "price"
        OTHER_AGENCY = "other_agency"
        IN_HOUSE = "in_house"
        NO_BUDGET = "no_budget"
        NO_RESPONSE = "no_response"
        NOT_A_FIT = "not_a_fit"
        OTHER = "other"

    status = models.CharField(max_length=20, choices=Status.choices, default=Status.NEW)
    source = models.CharField(max_length=20, choices=Source.choices, default=Source.OTHER)

    # Who at the client we are talking to, and what business they are in -
    # a portfolio is pitched by industry, and an owner decides faster than
    # a marketing executive.
    designation = models.CharField(max_length=80, blank=True)
    industry = models.CharField(
        max_length=20, choices=Industry.choices, blank=True)

    # What they want built. The project type drives the pitch and the quote;
    # platforms only matter for apps.
    project_type = models.CharField(
        max_length=20, choices=ProjectType.choices, blank=True)
    platforms = models.CharField(
        max_length=10, choices=Platforms.choices, blank=True)
    # "Do you have one now?" - almost always the first question.
    existing_url = models.URLField(blank=True)
    # Sites or apps they pointed at as "something like this".
    reference_links = models.TextField(blank=True)

    # Their number and their date, as distinct from our quote and our plan.
    budget = models.DecimalField(max_digits=12, decimal_places=2,
                                 null=True, blank=True)
    expected_start = models.DateField(null=True, blank=True)

    priority = models.CharField(
        max_length=10, choices=Priority.choices, default=Priority.WARM)
    # Filled when a lead is closed without converting. Without it the
    # console can count lost deals but never say why.
    lost_reason = models.CharField(
        max_length=20, choices=LostReason.choices, blank=True)

    # What they actually want. Free text — a product line, a quantity, a
    # problem — because the next salesperson to open this lead needs to know
    # why it exists, not just that it does.
    requirement = models.TextField(blank=True)

    # What the deal is worth, once agreed. Null until then — a lead nobody has
    # quoted yet has no value, which is different from a value of zero.
    value = models.DecimalField(max_digits=12, decimal_places=2,
                                null=True, blank=True)

    # What has actually been received against it. Not a payment ledger: one
    # running total, which is all the deposit rule needs. A real ledger, with
    # dates and methods, is its own model when invoicing arrives.
    amount_paid = models.DecimalField(max_digits=12, decimal_places=2,
                                      default=Decimal("0.00"))

    assigned_to = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL,
        null=True, blank=True, related_name="leads",
    )
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL,
        null=True, blank=True, related_name="leads_created",
    )

    # Set when this lead becomes a customer, so the history isn't lost.
    # Many leads to one customer: a returning client's second project (a site,
    # then an app) converts into the customer they already are (#19). This
    # was one-to-one, which made linking the second lead impossible.
    converted_customer = models.ForeignKey(
        "crm.Customer", on_delete=models.SET_NULL,
        null=True, blank=True, related_name="origin_leads",
    )
    converted_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ("-created_at",)
        indexes = [
            models.Index(fields=["status"]),
            models.Index(fields=["project_type"]),
            models.Index(fields=["assigned_to", "status"]),
        ]

    def __str__(self):
        return f"{self.name} ({self.status})"

    @property
    def is_converted(self):
        return self.converted_customer_id is not None

    @property
    def deposit_share(self):
        """The share of the price to be paid before converting, from the
        payment terms agreed in the negotiation."""
        negotiation = getattr(self, "negotiation", None)
        terms = negotiation.payment_terms if negotiation else ""
        return self.DEPOSIT_BY_TERMS.get(terms, self.DEPOSIT_SHARE)

    @property
    def deposit_required(self):
        """What must be paid before this lead may convert.

        Zero when no value has been agreed - for display only. A lead with no
        price can't convert at all (LeadConvertView refuses it first), so this
        zero never lets one through.
        """
        if not self.value:
            return Decimal("0.00")
        return (self.value * self.deposit_share).quantize(
            Decimal("0.01"), rounding=ROUND_HALF_UP)

    @property
    def deposit_met(self):
        """Whether enough has been paid to convert. Rounds in the customer's
        favour by a paisa at most, which is the right direction to err."""
        return self.amount_paid >= self.deposit_required

    def follow_quote(self, *, was, now):
        """Take what the negotiation's quote comes to as this lead's price (#29).

        The price follows the quote while it is empty or still what the last
        quote came to. A price typed in by hand is an agreed price and is left
        alone; so is the price of a lead that is no longer open, and a quote
        below what has already been paid.
        """
        if now is None:
            return
        still_the_quote = models.Q(value__isnull=True)
        if was is not None:
            still_the_quote |= models.Q(value=was)
        if (Lead.objects
                .filter(still_the_quote, pk=self.pk,
                        status__in=self.OPEN_STATUSES, amount_paid__lte=now)
                .update(value=now, updated_at=timezone.now())):
            self.value = now

    @property
    def is_stale(self):
        """Nothing has happened to this lead for STALE_AFTER_DAYS.

        Measured from the last edit rather than creation, so working a lead —
        a note, a status change, anything — keeps it alive.
        """
        if self.status in (self.Status.CONVERTED, self.Status.CLOSED):
            return False
        cutoff = timezone.now() - timedelta(days=self.STALE_AFTER_DAYS)
        return self.updated_at < cutoff

    @property
    def next_followup(self):
        """The soonest pending follow-up, or None.

        Views that list leads prefetch these into `_next_followups` so a page
        of leads costs one extra query, not one per row.
        """
        prefetched = getattr(self, "_next_followups", None)
        if prefetched is not None:
            return prefetched[0] if prefetched else None
        return self.followups.filter(status="pending").order_by("due_at").first()

    @classmethod
    def duplicate_for(cls, phone, *, status, pk=None):
        """The open lead that already has this number, if saving a lead with
        `phone` and `status` would make the same client twice (#30).

        Only an open lead clashes, and only with another open lead: a new
        project for a customer, or another try at a lost lead's client, is
        fine. Nothing is checked unless the lead is new, or its number or
        openness is changing, so a duplicate from before this rule can still
        be edited.
        """
        if status not in cls.OPEN_STATUSES:
            return None
        before = cls.objects.filter(pk=pk).values("phone", "status").first() if pk else None
        if (before and phone_key(before["phone"]) == phone_key(phone)
                and before["status"] in cls.OPEN_STATUSES):
            return None
        pool = cls.objects.filter(status__in=cls.OPEN_STATUSES).exclude(pk=pk)
        return max(cls.with_same_phone(phone, pool), key=lambda r: r.pk, default=None)

    def duplicate_message(self):
        return (f"This number is already on an open lead: {self.name}, with "
                f"{self.owner_label()}. Work that lead instead of adding another.")

    def clean(self):
        super().clean()
        other = Lead.duplicate_for(self.phone, status=self.status, pk=self.pk)
        if other:
            raise ValidationError({"phone": other.duplicate_message()})
        stored = Lead.objects.filter(pk=self.pk).first() if self.pk else None
        errors = self.stage_errors(
            stored, self.status, converted_customer_id=self.converted_customer_id,
            lost_reason=self.lost_reason)
        errors.update(self.contact_errors(
            stored, {f: getattr(self, f) for f in CUSTOMER_OWNED_FIELDS}))
        errors.update(self.money_errors(self.value, self.amount_paid, self.budget))
        if errors:
            raise ValidationError(errors)

    @staticmethod
    def contact_errors(stored, changes):
        """Edits to a customer's lead's contact details, refused (#52): the
        customer holds them now, so the two can't drift apart. Sending the
        same value back is fine. Used by clean() and the API serializer."""
        if stored is None or not stored.converted_customer_id:
            return {}
        return {field: "This lead is now a customer; edit their details on the customer."
                for field, value in changes.items()
                if field in CUSTOMER_OWNED_FIELDS and value != getattr(stored, field)}

    @classmethod
    def stage_errors(cls, stored, new_status, *, converted_customer_id=None,
                     lost_reason=""):
        """The stage rules, stated once (#53). The model's clean() (the Django
        admin site) and the API serializer both call this; each used to have
        its own copy, and each missed some of it.

        `stored` is the lead as saved (None when adding one), `new_status`
        where it's going. Returns {field: message}, empty when the move is
        allowed. A lead staying where it is is always fine, so an old lead
        can have its notes edited. Who may move a lead back, and why, needs
        the person acting, so the API checks that itself.
        """
        old = stored.status if stored is not None else None
        if new_status == old:
            return {}
        errors = {}
        if stored is not None and stored.converted_customer_id:
            # A customer's lead is finished; moving it would put a paying
            # client back in the pipeline or count them as lost (#14).
            errors["status"] = "This lead is already a customer, so its stage can't change."
        elif new_status == cls.Status.CONVERTED and not converted_customer_id:
            errors["status"] = "Mark a lead converted by converting it to a customer."
        # Demo, negotiation and proposal each have a record behind them.
        elif new_status == cls.Status.DEMO and not (
                stored is not None and stored.demos.exists()):
            errors["status"] = "Log a demo to move a lead here."
        elif new_status == cls.Status.NEGOTIATION and not (
                stored is not None and Negotiation.objects.filter(lead=stored).exists()):
            errors["status"] = "Open a negotiation to move a lead here."
        elif new_status == cls.Status.PROPOSAL and not (
                stored is not None and Negotiation.objects.filter(
                    lead=stored, status=Negotiation.Status.PROPOSAL_SENT).exists()):
            errors["status"] = "Mark the negotiation's proposal as sent to move a lead here."
        # A lost lead says why (#22).
        if new_status == cls.Status.CLOSED and not lost_reason:
            errors["lost_reason"] = "Say why the lead was lost."
        return errors

    @staticmethod
    def money_errors(value, amount_paid, budget=None):
        """The money rules, stated once. The model's clean() (the Django admin
        site) and the API serializer both call this, so the two can't drift
        apart the way the status rule did.

        Returns {field: message}, empty when the numbers are sound.
        """
        errors = {}
        for field, amount, what in (("value", value, "The price"),
                                    ("amount_paid", amount_paid, "The amount paid"),
                                    ("budget", budget, "The budget")):
            if amount is not None and amount < 0:
                errors[field] = f"{what} can't be negative."
        if errors:
            return errors
        paid = amount_paid or Decimal("0")
        if paid > 0 and not value:
            errors["amount_paid"] = "Set the price before recording a payment."
        elif value and paid > value:
            errors["amount_paid"] = (
                f"Paid (₹{paid:,.0f}) can't be more than the price (₹{value:,.0f}).")
        return errors


class Customer(ContactBase):
    """Someone who has bought. Created directly, or by converting a lead."""

    assigned_to = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL,
        null=True, blank=True, related_name="customers",
    )
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL,
        null=True, blank=True, related_name="customers_created",
    )
    is_active = models.BooleanField(default=True)

    # The agreed price for everything they've bought: the converted lead's,
    # plus each later project's (#41). Null for a customer added directly
    # until someone agrees one. Payments are rows of their own (Payment).
    price = models.DecimalField(max_digits=12, decimal_places=2,
                                null=True, blank=True,
                                validators=[MinValueValidator(0)])

    # When the project was marked completed, and by whom (#43). Cleared when
    # a new project for the same client converts into this customer.
    completed_at = models.DateTimeField(null=True, blank=True)
    completed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL,
        null=True, blank=True, related_name="customers_completed")

    class SupportStatus(models.TextChoices):
        NONE = "none"          # nothing open
        OPEN = "open"          # an issue is being handled
        RESOLVED = "resolved"  # last issue closed

    # When they became a customer: the conversion date, or whatever is entered
    # when a customer is back-filled. `created_at` is when the *row* was made,
    # which is a different question.
    customer_since = models.DateField(default=timezone.localdate)
    products = models.ManyToManyField(
        "crm.Product", blank=True, related_name="customers")
    # A flag, not a ticket system. Becomes a model when support is tracked.
    support_status = models.CharField(
        max_length=10, choices=SupportStatus.choices, default=SupportStatus.NONE)

    class ProjectStatus(models.TextChoices):
        NOT_STARTED = "not_started"
        DESIGN = "design"
        DEVELOPMENT = "development"
        UAT = "uat"            # client is testing
        LIVE = "live"
        # Live, handed over and paid for: nothing left to do (#43). Only
        # reached through the "complete" action, which checks both.
        COMPLETED = "completed"

    class Hosting(models.TextChoices):
        OURS = "ours"
        CLIENT = "client"
        NONE = "none"          # an app store build, or not our concern

    class MaintenancePlan(models.TextChoices):
        NONE = "none"
        MONTHLY = "monthly"
        YEARLY = "yearly"

    # Where the build stands, worked out from the handover milestones
    # (delivery.models.refresh_project_status) and never set by hand (#47).
    project_status = models.CharField(
        max_length=15, choices=ProjectStatus.choices,
        default=ProjectStatus.NOT_STARTED)
    go_live_on = models.DateField(null=True, blank=True)
    domain = models.CharField(max_length=150, blank=True)
    hosting = models.CharField(
        max_length=10, choices=Hosting.choices, default=Hosting.NONE)
    # Maintenance is the repeat revenue; the renewal date is what the
    # console reminds about.
    maintenance_plan = models.CharField(
        max_length=10, choices=MaintenancePlan.choices,
        default=MaintenancePlan.NONE)
    maintenance_renews_on = models.DateField(null=True, blank=True)

    class Meta:
        ordering = ("-created_at",)
        indexes = [models.Index(fields=["assigned_to", "is_active"])]

    def __str__(self):
        return self.name

    @property
    def amount_paid(self):
        # Sums the prefetched rows when a view prefetched them.
        return sum((p.amount for p in self.payments.all()), Decimal("0.00"))

    @property
    def balance(self):
        """Still to be paid; None while no price has been agreed."""
        return None if self.price is None else self.price - self.amount_paid

    @property
    def is_paid_in_full(self):
        return bool(self.price) and self.amount_paid >= self.price

    def completion_gaps(self):
        """What still stands between this project and Completed (#43):
        the handover delivered, and nothing owed. Empty when it's ready."""
        from .payments import rupees
        gaps = []
        if not self.deliveries.filter(milestone="handover", status="delivered").exists():
            gaps.append("the handover milestone hasn't been delivered")
        if self.price is None:
            gaps.append("no price has been agreed")
        elif self.balance > 0:
            gaps.append(f"{rupees(self.balance)} is still due")
        elif self.balance < 0:
            gaps.append(f"more has been received than the price "
                        f"({rupees(-self.balance)} over)")
        return gaps

    @property
    def is_overpaid(self):
        """More received than the price - only old data can hold this now."""
        return self.price is not None and self.amount_paid > self.price

    @classmethod
    def duplicate_for(cls, phone, *, pk=None):
        """The customer that already has this number, if saving one with
        `phone` would make the same client twice (#30). Active or not: a
        client who comes back is reactivated, not added again. Checked only
        for a new customer or a changed number."""
        before = cls.objects.filter(pk=pk).values_list("phone", flat=True).first() if pk else None
        if before is not None and phone_key(before) == phone_key(phone):
            return None
        pool = cls.objects.exclude(pk=pk) if pk else cls.objects.all()
        return max(cls.with_same_phone(phone, pool),
                   key=lambda c: (c.is_active, c.pk), default=None)

    def duplicate_message(self):
        inactive = "" if self.is_active else " (no longer active)"
        return (f"This number already belongs to a customer: {self.name}"
                f"{inactive}, with {self.owner_label()}.")

    def clean(self):
        super().clean()
        other = Customer.duplicate_for(self.phone, pk=self.pk)
        if other:
            raise ValidationError({"phone": other.duplicate_message()})

    @property
    def delivery_status(self):
        """Status of the most recent delivery, or None if nothing was ever
        scheduled. Views prefetch into `_latest_deliveries`."""
        latest = getattr(self, "_latest_deliveries", None)
        if latest is None:
            latest = list(self.deliveries.order_by("-scheduled_on", "-id")[:1])
        return latest[0].status if latest else None


from .demos import Demo  # noqa: E402,F401
from .negotiations import Negotiation  # noqa: E402,F401
from .payments import Payment  # noqa: E402,F401
from .products import Product  # noqa: E402,F401
from .stage_changes import LeadStageChange  # noqa: E402,F401
