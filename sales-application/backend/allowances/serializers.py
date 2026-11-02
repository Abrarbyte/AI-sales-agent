from rest_framework import serializers

from .models import AllowanceRate, TravelClaim


class AllowanceRateSerializer(serializers.ModelSerializer):
    """The rupees-per-km rate. Writable so the console can set a new one;
    `updated_by` is stamped from the request, never accepted from the client."""

    updated_by_name = serializers.CharField(
        source="updated_by.username", read_only=True)
    # No UniqueValidator: posting an existing effective_from is how you *change*
    # that day's rate, which the view handles with update_or_create. The default
    # ModelSerializer validator would reject it as a duplicate before we got there.
    effective_from = serializers.DateField(validators=[])

    class Meta:
        model = AllowanceRate
        fields = ("id", "rate_per_km", "effective_from",
                  "updated_by", "updated_by_name", "note", "created_at")
        read_only_fields = ("id", "updated_by", "updated_by_name", "created_at")


class TravelClaimSerializer(serializers.ModelSerializer):
    """Read-only view of a day's claim. The figures are frozen on the record,
    so nothing here is writable - a decision is made through the approve/query
    endpoints, not by patching fields."""

    username = serializers.CharField(source="user.username", read_only=True)
    approved_by_name = serializers.CharField(
        source="approved_by.username", read_only=True)

    class Meta:
        model = TravelClaim
        fields = (
            "id", "user", "username", "date",
            "distance_km", "rate_per_km", "amount",
            "method", "is_estimate", "flagged_legs",
            "status", "approved_by", "approved_by_name", "reviewed_at",
            "note", "created_at", "updated_at",
        )
        read_only_fields = fields


class ClaimDecisionSerializer(serializers.Serializer):
    """The body of an approve or query action: just an optional note explaining
    the decision. The status comes from which endpoint was called."""

    note = serializers.CharField(required=False, allow_blank=True,
                                 max_length=2000)
