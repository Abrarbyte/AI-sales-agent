from django.urls import path

from .views import DailyReportListView, DashboardView, MyDashboardView

urlpatterns = [
    path("dashboard/", DashboardView.as_view(), name="dashboard"),
    path("dashboard/me/", MyDashboardView.as_view(), name="my-dashboard"),
    path("reports/", DailyReportListView.as_view(), name="daily-reports"),
]
