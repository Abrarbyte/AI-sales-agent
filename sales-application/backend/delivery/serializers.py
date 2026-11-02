from rest_framework import serializers

from common.images import as_webp
from common.scoping import ScopedUserField, VisibleRecordField
from common.storage import validate_upload
from crm.models import Customer

from .models import Delivery, DeliveryAttempt


class DeliveryAttemptSerializer(serializers.ModelSerializer):
    assigned_to = ScopedUserField(required=False, allow_null=True)
    assigned_to_name = serializers.CharField(
        source="assigned_to.username", read_only=True, default=None)

    class Meta:
        model = DeliveryAttempt
        fields = (
            "id", "delivery", "assigned_to", "assigned_to_name",
            "attempted_at", "reason", "reason_note", "retry_on",
            "customer_contacted", "notes", "created_by", "created_at",
        )
        read_only_fields = ("delivery", "created_by", "created_at")
        extra_kwargs = {"attempted_at": {"required": False}}


class DeliverySerializer(serializers.ModelSerializer):
    # Only a customer the caller can see (#73).
    customer = VisibleRecordField(Customer)
    assigned_to = ScopedUserField(required=False, allow_null=True)
    assigned_to_name = serializers.CharField(
        source="assigned_to.username", read_only=True, default=None)
    customer_name = serializers.CharField(source="customer.name", read_only=True)
    product_name = serializers.CharField(source="product.name", read_only=True)
    is_overdue = serializers.BooleanField(read_only=True)
    attempt_count = serializers.IntegerField(read_only=True, default=0)
    last_attempt = serializers.SerializerMethodField()

    class Meta:
        model = Delivery
        fields = (
            "id", "customer", "customer_name", "product", "product_name",
            "assigned_to", "assigned_to_name",
            "required", "milestone", "scheduled_on", "address", "status",
            "delivered_at", "received_by", "proof", "notes", "outcome_notes",
            "is_overdue", "attempt_count", "last_attempt",
            "created_by", "created_at", "updated_at",
        )
        # Delivered and its evidence come from /deliver/; the status from
        # /deliver/ and /attempts/. PATCH is for scheduling and reassigning.
        read_only_fields = (
            "status", "delivered_at", "received_by", "proof", "outcome_notes",
            "created_by", "created_at", "updated_at",
        )

    def get_last_attempt(self, obj):
        attempts = getattr(obj, "_last_attempts", None)
        if attempts is None:
            attempts = list(obj.attempts.all()[:1])
        if not attempts:
            return None
        a = attempts[0]
        return {
            "id": a.id,
            "reason": a.reason,
            "reason_note": a.reason_note,
            "attempted_at": a.attempted_at,
            "retry_on": a.retry_on,
            "customer_contacted": a.customer_contacted,
        }


class DeliverSerializer(serializers.Serializer):
    """Payload for marking a delivery done. Multipart, because of the proof."""

    received_by = serializers.CharField(max_length=120, required=False,
                                        allow_blank=True)
    proof = serializers.FileField(required=False, allow_null=True,
                                  validators=[validate_upload])
    notes = serializers.CharField(required=False, allow_blank=True)

    def validate_proof(self, value):
        # A photo is stored as WebP; anything else (a PDF, say) passes through
        # unchanged. See common/images.py.
        return as_webp(value)


class CancelSerializer(serializers.Serializer):
    notes = serializers.CharField(required=False, allow_blank=True)
