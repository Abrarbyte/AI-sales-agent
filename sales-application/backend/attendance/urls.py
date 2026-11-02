from django.urls import path

from .views import (
    AttendanceListView,
    CheckInView,
    CheckOutView,
    MyAttendanceView,
)

urlpatterns = [
    path("check-in/", CheckInView.as_view(), name="check-in"),
    path("check-out/", CheckOutView.as_view(), name="check-out"),
    path("me/", MyAttendanceView.as_view(), name="my-attendance"),
    path("", AttendanceListView.as_view(), name="attendance-list"),
]
