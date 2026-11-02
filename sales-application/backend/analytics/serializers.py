from rest_framework import serializers

from .models import DailyReport


class DailyReportSerializer(serializers.ModelSerializer):
    username = serializers.CharField(source="user.username", read_only=True)
    full_name = serializers.CharField(source="user.get_full_name", read_only=True)
    was_productive = serializers.BooleanField(read_only=True)

    class Meta:
        model = DailyReport
        fields = (
            "id", "user", "username", "full_name", "date",
            "checked_in", "check_in_at", "check_out_at", "hours_worked",
            "visits_count", "visit_minutes",
            "leads_created", "leads_won", "customers_created",
            "followups_completed", "followups_pending", "followups_overdue",
            "was_productive", "generated_at",
        )
        # Reports are computed, never submitted.
        read_only_fields = fields
