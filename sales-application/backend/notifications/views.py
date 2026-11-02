from django.utils import timezone
from rest_framework import status
from rest_framework.generics import ListAPIView
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import Notification
from .serializers import NotificationSerializer


class NotificationListView(ListAPIView):
    """GET /api/notifications/  —  ?unread=true

    Always the caller's own. Notifications are personal, so there is no
    role-based widening here: a manager does not read their team's messages.
    """

    serializer_class = NotificationSerializer

    def get_queryset(self):
        queryset = Notification.objects.filter(user=self.request.user)
        if self.request.query_params.get("unread") == "true":
            queryset = queryset.filter(read_at__isnull=True)
        return queryset


class UnreadCountView(APIView):
    """GET /api/notifications/unread-count/ — the number on the bell icon."""

    def get(self, request):
        count = Notification.objects.filter(
            user=request.user, read_at__isnull=True).count()
        return Response({"unread": count})


class MarkReadView(APIView):
    """POST /api/notifications/<id>/read/"""

    def post(self, request, pk):
        notification = Notification.objects.filter(
            user=request.user, pk=pk).first()
        if notification is None:
            return Response({"detail": "Notification not found."},
                            status=status.HTTP_404_NOT_FOUND)
        notification.mark_read()
        return Response(NotificationSerializer(notification).data)


class MarkAllReadView(APIView):
    """POST /api/notifications/read-all/"""

    def post(self, request):
        updated = Notification.objects.filter(
            user=request.user, read_at__isnull=True,
        ).update(read_at=timezone.now())
        return Response({"marked_read": updated})
