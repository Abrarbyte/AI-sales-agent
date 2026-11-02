from django.urls import path

from .views import (
    MarkAllReadView,
    MarkReadView,
    NotificationListView,
    UnreadCountView,
)

urlpatterns = [
    path("unread-count/", UnreadCountView.as_view(), name="unread-count"),
    path("read-all/", MarkAllReadView.as_view(), name="read-all"),
    path("<int:pk>/read/", MarkReadView.as_view(), name="mark-read"),
    path("", NotificationListView.as_view(), name="notification-list"),
]
