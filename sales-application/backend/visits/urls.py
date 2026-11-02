from django.urls import path

from .views import (
    CheckpointListView,
    FollowUpCompleteView,
    FollowUpDetailView,
    FollowUpListView,
    VisitDetailView,
    VisitListView,
)

urlpatterns = [
    # Follow-up routes come first: a literal path must be matched before the
    # <int:pk> pattern, which would otherwise swallow "followups".
    path("checkpoints/", CheckpointListView.as_view(), name="checkpoint-list"),
    path("followups/", FollowUpListView.as_view(), name="followup-list"),
    path("followups/<int:pk>/", FollowUpDetailView.as_view(), name="followup-detail"),
    path("followups/<int:pk>/complete/", FollowUpCompleteView.as_view(),
         name="followup-complete"),
    path("", VisitListView.as_view(), name="visit-list"),
    path("<int:pk>/", VisitDetailView.as_view(), name="visit-detail"),
]
