from django.utils import timezone
from rest_framework import status
from rest_framework.generics import ListAPIView
from rest_framework.response import Response
from rest_framework.views import APIView

from common.scoping import DateRangeFilterMixin, ScopedQuerysetMixin

from .models import Attendance
from .serializers import (
    AttendanceSerializer,
    CheckInSerializer,
    LocationPingSerializer,
)


class CheckInView(APIView):
    """POST /api/attendance/check-in/ — start today's work day."""

    def post(self, request):
        payload = CheckInSerializer(data=request.data)
        payload.is_valid(raise_exception=True)
        data = payload.validated_data

        today = timezone.localdate()
        if Attendance.objects.filter(user=request.user, date=today).exists():
            return Response(
                {"detail": "You have already checked in today."},
                status=status.HTTP_409_CONFLICT,
            )

        record = Attendance.objects.create(
            user=request.user,
            date=today,
            check_in_at=timezone.now(),
            kind=data["kind"],
            check_in_lat=data["lat"],
            check_in_lng=data["lng"],
            check_in_place=data.get("place", ""),
            note=data.get("note", ""),
        )
        return Response(AttendanceSerializer(record).data,
                        status=status.HTTP_201_CREATED)


class CheckOutView(APIView):
    """POST /api/attendance/check-out/ — end today's work day."""

    def post(self, request):
        payload = LocationPingSerializer(data=request.data)
        payload.is_valid(raise_exception=True)
        data = payload.validated_data

        record = Attendance.objects.filter(
            user=request.user, date=timezone.localdate(),
        ).first()

        if record is None:
            return Response(
                {"detail": "You have not checked in today."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if not record.is_open:
            return Response(
                {"detail": "You have already checked out today."},
                status=status.HTTP_409_CONFLICT,
            )

        record.check_out_at = timezone.now()
        record.check_out_lat = data["lat"]
        record.check_out_lng = data["lng"]
        record.check_out_place = data.get("place", "")
        if data.get("note"):
            record.note = data["note"]
        record.full_clean()
        record.save()
        return Response(AttendanceSerializer(record).data)


class AttendanceListView(ScopedQuerysetMixin, DateRangeFilterMixin, ListAPIView):
    """GET /api/attendance/ — history for everyone the caller may see, using
    the same visibility rule as every other module. Supports ?from= and ?to=.
    """

    model = Attendance
    serializer_class = AttendanceSerializer
    owner_fields = ("user",)

    def get_queryset(self):
        return self.apply_date_range(super().get_queryset())


class MyAttendanceView(AttendanceListView):
    """GET /api/attendance/me/ — the signed-in user's own history.

    Same filters as the team view, narrowed to one person.
    """

    def get_queryset(self):
        return super().get_queryset().filter(user=self.request.user)
