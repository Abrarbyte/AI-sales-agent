from rest_framework import serializers

from .models import Notification


class NotificationSerializer(serializers.ModelSerializer):
    is_read = serializers.BooleanField(read_only=True)

    class Meta:
        model = Notification
        fields = ("id", "kind", "title", "body", "link",
                  "is_read", "read_at", "created_at")
        # Notifications are raised by the system, never posted by a client.
        read_only_fields = fields
