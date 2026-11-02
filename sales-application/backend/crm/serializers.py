from django.db import transaction
from rest_framework import serializers
from rest_framework.validators import UniqueValidator

from accounts.models import User
from common.scoping import (
    ScopedQuerysetMixin, ScopedUserField, VisibleRecordField, scope_to_user,
)

from django.utils import timezone

from .models import (
    CONTACT_COPY_FIELDS, Customer, Demo, Lead, LeadStageChange, Negotiation,
    Payment, Product,
)
from .payments import rupees


def duplicate_error(record, user):
    """The refusal for a number that's already on a lead or customer (#30).

    Says which record has it, and gives its id for a link when the caller
    may open that record. Someone on another team is told who has the
    client, so they can talk to them, but gets no link that would 404.
    """
    found = {"kind": "lead" if isinstance(record, Lead) else "customer",
             "name": record.name, "owner": record.owner_label()}
    visible = scope_to_user(type(record).objects.filter(pk=record.pk), user,
                            ScopedQuerysetMixin.owner_fields)
    if visible.exists():
        found["id"] = record.pk
    return serializers.ValidationError(
        {"phone": [record.duplicate_message()], "duplicate": found})


class ProductSerializer(serializers.ModelSerializer):
    class Meta:
        model = Product
        fields = ("id", "name", "kind", "is_active", "created_at")
        read_only_fields = ("created_at",)


class PaymentSerializer(serializers.ModelSerializer):
    """One payment. The customer comes from the URL, the recorder from the
    request."""

    recorded_by_name = serializers.CharField(
        source="recorded_by.username", read_only=True, default=None)

    class Meta:
        model = Payment
        fields = ("id", "customer", "amount", "received_on", "method",
                  "reference", "notes", "lead", "recorded_by",
                  "recorded_by_name", "created_at")
        read_only_fields = ("customer", "lead", "recorded_by", "created_at")
        extra_kwargs = {"received_on": {"required": False}}

    def validate_received_on(self, value):
        if value > timezone.localdate():
            raise serializers.ValidationError("A payment can't be dated in the future.")
        return value

    def validate(self, attrs):
        customer = self.context["customer"]
        if customer.price is None:
            raise serializers.ValidationError({"amount": (
                "Set the customer's agreed price before recording a payment.")})
        if attrs["amount"] > customer.balance:
            raise serializers.ValidationError({"amount": (
                f"That's more than the {rupees(customer.balance)} still due.")})
        return attrs


class CustomerSerializer(serializers.ModelSerializer):
    assigned_to = ScopedUserField(required=False, allow_null=True)
    assigned_to_name = serializers.CharField(
        source="assigned_to.username", read_only=True, default=None)
    products = serializers.PrimaryKeyRelatedField(
        many=True, required=False, queryset=Product.objects.all())
    product_names = serializers.SerializerMethodField()
    # Derived from the latest delivery; a customer never sets it directly.
    delivery_status = serializers.CharField(read_only=True, allow_null=True)
    # The money after the sale (#41, #42): worked out from the payments.
    amount_paid = serializers.DecimalField(max_digits=12, decimal_places=2,
                                           read_only=True)
    balance = serializers.DecimalField(max_digits=12, decimal_places=2,
                                       read_only=True, allow_null=True)
    is_paid_in_full = serializers.BooleanField(read_only=True)
    payments = PaymentSerializer(many=True, read_only=True)

    class Meta:
        model = Customer
        fields = ("id",) + CONTACT_COPY_FIELDS + (
            "assigned_to", "assigned_to_name", "is_active",
            "customer_since", "products", "product_names",
            "support_status", "delivery_status",
            "project_status", "go_live_on", "domain", "hosting",
            "maintenance_plan", "maintenance_renews_on",
            "price", "amount_paid", "balance", "is_paid_in_full", "payments",
            "completed_at",
            "created_by", "created_at", "updated_at",
        )
        # Project status is worked out from the handover milestones, never
        # set by hand, so the two can't disagree (#47).
        read_only_fields = ("project_status", "completed_at", "created_by",
                            "created_at", "updated_at")

    def get_product_names(self, obj):
        return [p.name for p in obj.products.all()]

    def validate_price(self, value):
        paid = self.instance.amount_paid if self.instance is not None else 0
        if value is None and paid:
            raise serializers.ValidationError(
                "Payments have been recorded, so the price can't be cleared.")
        if value is not None and value < paid:
            raise serializers.ValidationError(
                f"The price can't be less than the {rupees(paid)} already paid.")
        return value

    def validate(self, attrs):
        attrs = super().validate(attrs)
        if self.instance is None or "phone" in attrs:
            other = Customer.duplicate_for(
                attrs.get("phone", getattr(self.instance, "phone", "")),
                pk=getattr(self.instance, "pk", None))
            if other:
                raise duplicate_error(other, self.context["request"].user)
        return attrs


class NextFollowUpSerializer(serializers.Serializer):
    """Just enough for a list row: when, and what kind."""

    id = serializers.IntegerField()
    kind = serializers.CharField()
    due_at = serializers.DateTimeField()
    note = serializers.CharField()
    is_overdue = serializers.BooleanField()


class OpenLeadOnlyMixin:
    """Demos and negotiations belong to leads still in the pipeline. On a
    lost or converted lead they would hang off a finished record, and the
    lead's stage wouldn't move to match (issue #54)."""

    def validate_lead(self, lead):
        if lead.status == Lead.Status.CLOSED:
            raise serializers.ValidationError(
                "This lead was lost. A manager or admin must reopen it first.")
        if lead.status == Lead.Status.CONVERTED:
            raise serializers.ValidationError(
                "This lead is already a customer.")
        return lead


class FollowUpBelongsToLeadMixin:
    """A demo's or negotiation's follow-up must be about the same lead."""

    def validate_followup(self, value):
        if value is None:
            return value
        lead_id = self.initial_data.get("lead")
        if lead_id is None and self.instance is not None:
            lead_id = self.instance.lead_id
        if lead_id is not None and str(value.lead_id) != str(lead_id):
            raise serializers.ValidationError(
                "The follow-up must belong to this lead.")
        return value


class DemoSerializer(OpenLeadOnlyMixin, FollowUpBelongsToLeadMixin,
                     serializers.ModelSerializer):
    # Only a lead the caller can see (#73).
    lead = VisibleRecordField(Lead)
    given_by = ScopedUserField(required=False, allow_null=True)
    given_by_name = serializers.CharField(
        source="given_by.username", read_only=True, default=None)
    lead_name = serializers.CharField(source="lead.name", read_only=True)

    class Meta:
        model = Demo
        fields = (
            "id", "lead", "lead_name", "given_by", "given_by_name",
            "held_at", "product", "mode", "shown", "attendees",
            "outcome", "feedback",
            "followup", "notes", "created_by", "created_at", "updated_at",
        )
        read_only_fields = ("created_by", "created_at", "updated_at")


class NegotiationSerializer(OpenLeadOnlyMixin, FollowUpBelongsToLeadMixin,
                            serializers.ModelSerializer):
    # Only a lead the caller can see (#73), and one negotiation per lead.
    # Declaring the field drops DRF's automatic unique check, so it's here.
    lead = VisibleRecordField(Lead, validators=[UniqueValidator(
        queryset=Negotiation.objects.all(),
        message="This lead already has a negotiation; update it instead.")])
    owner = ScopedUserField(required=False, allow_null=True)
    owner_name = serializers.CharField(
        source="owner.username", read_only=True, default=None)
    lead_name = serializers.CharField(source="lead.name", read_only=True)
    is_open = serializers.BooleanField(read_only=True)
    is_slipping = serializers.BooleanField(read_only=True)

    class Meta:
        model = Negotiation
        fields = (
            "id", "lead", "lead_name", "owner", "owner_name",
            "started_at", "decision_maker", "objections",
            "expected_close_on", "status",
            "quoted_amount", "discount_pct", "payment_terms",
            "payment_terms_note", "timeline_weeks", "competitor", "proposal",
            "followup", "notes", "is_open", "is_slipping",
            "created_by", "created_at", "updated_at",
        )
        read_only_fields = ("created_by", "created_at", "updated_at")
        extra_kwargs = {
            "started_at": {"required": False},
        }

    def to_internal_value(self, data):
        # Won and lost are no longer negotiation statuses (#28). Say what to
        # do instead rather than just "not a valid choice".
        if hasattr(data, "get") and data.get("status") in ("won", "lost"):
            raise serializers.ValidationError({"status": [
                "A negotiation doesn't record the outcome any more. To win, "
                "convert the lead; to lose it, mark the lead as lost."]})
        return super().to_internal_value(data)

    def validate(self, attrs):
        attrs = super().validate(attrs)
        start = attrs.get("started_at", getattr(self.instance, "started_at", None))
        close = attrs.get("expected_close_on",
                          getattr(self.instance, "expected_close_on", None))
        if start and close and close < start:
            raise serializers.ValidationError(
                {"expected_close_on": "Cannot be before the start date."})
        return attrs


class LeadDemoSummarySerializer(serializers.ModelSerializer):
    """The latest demo, embedded on a lead row - in full, so the console
    can show what was presented and what the client said without another
    request per lead."""

    given_by_name = serializers.CharField(
        source="given_by.username", read_only=True, default=None)

    class Meta:
        model = Demo
        fields = ("id", "held_at", "product", "outcome",
                  "mode", "shown", "attendees", "feedback", "notes",
                  "given_by_name")


class LeadNegotiationSummarySerializer(serializers.ModelSerializer):
    """The negotiation, embedded on a lead row."""

    is_slipping = serializers.BooleanField(read_only=True)

    class Meta:
        model = Negotiation
        fields = ("id", "status", "decision_maker", "expected_close_on",
                  "quoted_amount", "payment_terms", "is_slipping",
                  "started_at", "objections", "discount_pct",
                  "payment_terms_note", "timeline_weeks", "competitor",
                  "proposal", "notes")


class LeadStageChangeSerializer(serializers.ModelSerializer):
    changed_by_name = serializers.CharField(
        source="changed_by.username", read_only=True, default=None)

    class Meta:
        model = LeadStageChange
        fields = ("from_status", "to_status", "changed_by_name", "reason",
                  "changed_at")


class LeadSerializer(serializers.ModelSerializer):
    assigned_to = ScopedUserField(required=False, allow_null=True)
    assigned_to_name = serializers.CharField(
        source="assigned_to.username", read_only=True, default=None)
    is_converted = serializers.BooleanField(read_only=True)
    # Derived, so a screen can show what is still owed without recomputing the
    # rule — and without being able to disagree with the server about it.
    deposit_required = serializers.DecimalField(
        max_digits=12, decimal_places=2, read_only=True)
    # The share the agreed payment terms ask for, e.g. 0.50 for half-and-half.
    deposit_share = serializers.DecimalField(
        max_digits=3, decimal_places=2, read_only=True)
    deposit_met = serializers.BooleanField(read_only=True)
    next_followup = NextFollowUpSerializer(read_only=True, allow_null=True)
    demo_count = serializers.IntegerField(read_only=True, default=0)
    latest_demo = serializers.SerializerMethodField()
    negotiation = serializers.SerializerMethodField()
    stage_changes = LeadStageChangeSerializer(many=True, read_only=True)
    # Why a manager or admin is moving the lead back or reopening it.
    # Required for exactly those moves (issue #15); saved as a LeadStageChange.
    stage_change_reason = serializers.CharField(
        write_only=True, required=False, allow_blank=True)

    class Meta:
        model = Lead
        fields = ("id",) + CONTACT_COPY_FIELDS + (
            "status", "source", "requirement",
            "designation", "industry", "project_type", "platforms",
            "existing_url", "reference_links", "budget", "expected_start",
            "priority", "lost_reason",
            "assigned_to", "assigned_to_name",
            "value", "amount_paid", "deposit_required", "deposit_share",
            "deposit_met",
            "is_converted", "converted_customer", "converted_at",
            "next_followup", "demo_count", "latest_demo", "negotiation",
            "stage_changes", "stage_change_reason",
            "created_by", "created_at", "updated_at",
        )
        read_only_fields = (
            "created_by", "created_at", "updated_at",
            "converted_customer", "converted_at",
        )

    def get_latest_demo(self, obj):
        demos = getattr(obj, "_latest_demos", None)
        if demos is None:
            demos = list(obj.demos.all()[:1])
        return (LeadDemoSummarySerializer(demos[0], context=self.context).data
                if demos else None)

    def get_negotiation(self, obj):
        # Reverse one-to-one raises when absent. Views select_related it, so
        # this is a cache hit either way.
        try:
            negotiation = obj.negotiation
        except Negotiation.DoesNotExist:
            return None
        return LeadNegotiationSummarySerializer(
            negotiation, context=self.context).data

    def to_internal_value(self, data):
        # The "assigned" stage was removed (#27). An older app or console
        # still sending it means "this lead has an owner", which is New.
        if hasattr(data, "get") and data.get("status") == "assigned":
            data = data.copy()
            data["status"] = Lead.Status.NEW
        return super().to_internal_value(data)

    def create(self, validated_data):
        validated_data.pop("stage_change_reason", None)
        return super().create(validated_data)

    def update(self, instance, validated_data):
        reason = validated_data.pop("stage_change_reason", "").strip()
        from_status = instance.status
        to_status = validated_data.get("status", from_status)
        with transaction.atomic():
            lead = super().update(instance, validated_data)
            if Lead.is_step_back(from_status, to_status):
                LeadStageChange.objects.create(
                    lead=lead, from_status=from_status, to_status=to_status,
                    changed_by=self.context["request"].user, reason=reason)
            if to_status == Lead.Status.CLOSED and from_status != Lead.Status.CLOSED:
                Lead.cancel_open_followups([lead.id])
            # Back in the pipeline: a lead lost before the quote filled the
            # price (#29) takes it now, so it shows what the deal is worth.
            if (from_status not in Lead.OPEN_STATUSES
                    and to_status in Lead.OPEN_STATUSES):
                negotiation = getattr(lead, "negotiation", None)
                if negotiation is not None:
                    lead.follow_quote(was=None, now=negotiation.offered_price)
        return lead

    def validate(self, attrs):
        # Moving a lead back, or reopening a lost one, is a judgement call:
        # only a manager or admin may do it, and they must say why (#15).
        new_status = attrs.get("status")
        if (self.instance is not None and new_status
                and Lead.is_step_back(self.instance.status, new_status)):
            user = self.context["request"].user
            if user.role not in User.MANAGER_ROLES:
                raise serializers.ValidationError({"status": (
                    "Only a manager or admin can move a lead back or reopen it.")})
            if not attrs.get("stage_change_reason", "").strip():
                raise serializers.ValidationError({"stage_change_reason": (
                    "Say why this lead is moving back.")})

        # The same client twice (#30, decided 29 Sep: blocked). Checked when
        # the number or the stage changes, which covers reopening a lost lead
        # whose client has since been added again.
        if self.instance is None or attrs.keys() & {"phone", "status"}:
            other = Lead.duplicate_for(
                attrs.get("phone", getattr(self.instance, "phone", "")),
                status=attrs.get("status", getattr(self.instance, "status", Lead.Status.NEW)),
                pk=getattr(self.instance, "pk", None))
            if other:
                raise duplicate_error(other, self.context["request"].user)

        # Money is checked only when money is being changed. A lead saved
        # before these rules may hold numbers they'd refuse, and editing its
        # notes must not be blocked by a price nobody touched.
        if attrs.keys() & {"value", "amount_paid", "budget"}:
            errors = Lead.money_errors(
                attrs.get("value", getattr(self.instance, "value", None)),
                attrs.get("amount_paid", getattr(self.instance, "amount_paid", None)),
                attrs.get("budget", getattr(self.instance, "budget", None)),
            )
            if errors:
                raise serializers.ValidationError(errors)

        # A customer's lead: its contact details live on the customer (#52).
        errors = Lead.contact_errors(self.instance, attrs)
        if errors:
            raise serializers.ValidationError(errors)

        # The stage rules, one copy shared with the Django admin site (#53):
        # a record behind each stage, a customer's lead stays put, a lost
        # lead says why.
        status = attrs.get("status", getattr(self.instance, "status", Lead.Status.NEW))
        reason = attrs.get("lost_reason",
                           getattr(self.instance, "lost_reason", ""))
        if self.instance is None or "status" in attrs:
            errors = Lead.stage_errors(
                self.instance, status,
                converted_customer_id=getattr(self.instance, "converted_customer_id", None),
                lost_reason=reason)
            if errors:
                raise serializers.ValidationError(errors)
        # A lost reason on an open lead is noise.
        if status != Lead.Status.CLOSED and reason:
            attrs["lost_reason"] = ""
        if attrs.get("platforms") and attrs.get("project_type") not in (
                None, "", Lead.ProjectType.ANDROID_APP, Lead.ProjectType.IOS_APP,
                Lead.ProjectType.WEB_APP, Lead.ProjectType.WEBSITE_AND_APP):
            attrs["platforms"] = ""
        return attrs
