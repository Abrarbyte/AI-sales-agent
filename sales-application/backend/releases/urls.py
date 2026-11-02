from django.urls import path

from .views import LatestReleaseView

urlpatterns = [
    path("latest/", LatestReleaseView.as_view(), name="app-latest"),
]
