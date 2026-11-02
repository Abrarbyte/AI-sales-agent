from rest_framework import serializers

from .models import Attendance


class AttendanceSerializer(serializers.ModelSerializer):
    """Read-only view of an attendance record."""

    username = serializers.CharField(source="user.username", read_only=True)
    hours_worked = serializers.FloatField(read_only=True)
    is_open = serializers.BooleanField(read_only=True)

    class Meta:
        model = Attendance
        fields = (
            "id", "user", "username", "date", "kind",
            "check_in_at", "check_in_lat", "check_in_lng", "check_in_place",
            "check_out_at", "check_out_lat", "check_out_lng", "check_out_place",
            "note", "hours_worked", "is_open",
        )
        read_only_fields = fields


class LocationPingSerializer(serializers.Serializer):
    """What the mobile app sends for both check-in and check-out: just where
    it is. The user and the timestamp come from the request itself, never
    from the client, so neither can be faked."""

    lat = serializers.DecimalField(max_digits=9, decimal_places=6,
                                   min_value=-90, max_value=90)
    lng = serializers.DecimalField(max_digits=10, decimal_places=6,
                                   min_value=-180, max_value=180)
    note = serializers.CharField(max_length=255, required=False, allow_blank=True)
    # The place name the phone looked up for this fix; optional (#91).
    place = serializers.CharField(max_length=255, required=False,
                                  allow_blank=True)


class CheckInSerializer(LocationPingSerializer):
    """Check-in also carries where the day is being worked from. Check-out does
    not: the kind is settled when the day starts, so accepting it again at the
    end would only offer a way to disagree with it."""

    kind = serializers.ChoiceField(choices=Attendance.Kind.choices,
                                   default=Attendance.Kind.OFFICE)
