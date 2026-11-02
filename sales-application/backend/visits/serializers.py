from django.utils import timezone
from rest_framework import serializers

from common.images import as_webp
from common.scoping import ScopedUserField, VisibleRecordField
from crm.models import Customer, Lead

from .checkpoints import Checkpoint
from .models import FieldVisit, FollowUp


class ExactlyOneContactMixin:
    """Both visits and follow-ups attach to exactly one lead or one customer."""

    def validate(self, attrs):
        attrs = super().validate(attrs)
        # On a partial update, fall back to what the record already holds.
        instance = getattr(self, "instance", None)
        lead = attrs.get("lead", getattr(instance, "lead", None))
        customer = attrs.get("customer", getattr(instance, "customer", None))
        if bool(lead) == bool(customer):
            raise serializers.ValidationError(
                "Provide exactly one of 'lead' or 'customer'.")
        return attrs


class FieldVisitSerializer(ExactlyOneContactMixin, serializers.ModelSerializer):
    # Only a lead or customer the caller can see (#73).
    lead = VisibleRecordField(Lead, required=False, allow_null=True)
    customer = VisibleRecordField(Customer, required=False, allow_null=True)
    username = serializers.CharField(source="user.username", read_only=True)
    target_name = serializers.CharField(read_only=True)

    class Meta:
        model = FieldVisit
        fields = (
            "id", "user", "username", "lead", "customer", "target_name",
            "visited_at", "date", "lat", "lng", "place", "photo",
            "outcome", "notes", "duration_minutes", "created_at",
        )
        # The client never states who visited or when — both come from the
        # request itself, so a visit cannot be logged for someone else.
        read_only_fields = ("user", "username", "visited_at", "date", "created_at")

    def validate_photo(self, value):
        # Stored as WebP whatever the client sent; see common/images.py.
        return as_webp(value)


class FollowUpSerializer(ExactlyOneContactMixin, serializers.ModelSerializer):
    # Only records the caller can see (#73); the visit it came out of is
    # one of theirs or their team's.
    lead = VisibleRecordField(Lead, required=False, allow_null=True)
    customer = VisibleRecordField(Customer, required=False, allow_null=True)
    visit = VisibleRecordField(FieldVisit, owner_fields=("user",),
                               required=False, allow_null=True)
    assigned_to = ScopedUserField(required=False)
    assigned_to_name = serializers.CharField(
        source="assigned_to.username", read_only=True, default=None)
    target_name = serializers.CharField(read_only=True)
    is_overdue = serializers.BooleanField(read_only=True)

    class Meta:
        model = FollowUp
        fields = (
            "id", "assigned_to", "assigned_to_name", "created_by",
            "lead", "customer", "target_name", "visit",
            "kind", "status", "due_at", "note",
            "completed_at", "outcome_note", "is_overdue",
            "created_at", "updated_at",
        )
        read_only_fields = (
            "created_by", "completed_at", "outcome_note",
            "created_at", "updated_at",
        )
         
    def validate_due_at(self, value):
        # Only when first scheduling — an existing follow-up may legitimately
        # sit in the past while it waits to be completed.
        if self.instance is None and value < timezone.now():
            raise serializers.ValidationError(
                "A follow-up cannot be scheduled in the past.")
        return value


class CompleteFollowUpSerializer(serializers.Serializer):
    outcome_note = serializers.CharField(
        max_length=255, required=False, allow_blank=True)


class CheckpointSerializer(serializers.ModelSerializer):
    username = serializers.CharField(source="user.username", read_only=True)

    class Meta:
        model = Checkpoint
        fields = (
            "id", "user", "username", "lat", "lng", "accuracy_m",
            "recorded_at", "date", "note", "photo",
        )
        # Who and when come from the request, never the client — the same rule
        # every other record here follows, and the reason a checkpoint can be
        # trusted as a record of where someone was.
        read_only_fields = ("user", "username", "recorded_at", "date")

    def validate_photo(self, value):
        # Stored as WebP whatever the client sent; see common/images.py.
        return as_webp(value)
