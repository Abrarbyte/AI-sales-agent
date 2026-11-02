from django.urls import path
from rest_framework_simplejwt.views import TokenRefreshView

from .login import LoginView
from .logout import LogoutView
from .views import EmployeeDetailView, EmployeeListView, MeView

urlpatterns = [
    path("login/", LoginView.as_view(), name="login"),
    path("refresh/", TokenRefreshView.as_view(), name="refresh"),
    path("logout/", LogoutView.as_view(), name="logout"),
    path("me/", MeView.as_view(), name="me"),
    path("employees/", EmployeeListView.as_view(), name="employees"),
    path("employees/<int:pk>/", EmployeeDetailView.as_view(), name="employee-detail"),
]
