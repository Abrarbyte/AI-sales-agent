from django.urls import path

from .views import (
    AllowanceRateView,
    ClaimApproveView,
    ClaimQueryView,
    ClaimRejectView,
    MyTravelClaimsView,
    TravelClaimListView,
)

urlpatterns = [
    path("rate/", AllowanceRateView.as_view(), name="allowance-rate"),
    path("claims/", TravelClaimListView.as_view(), name="travel-claims"),
    path("claims/me/", MyTravelClaimsView.as_view(), name="my-travel-claims"),
    path("claims/<int:pk>/approve/", ClaimApproveView.as_view(),
         name="travel-claim-approve"),
    path("claims/<int:pk>/query/", ClaimQueryView.as_view(),
         name="travel-claim-query"),
    path("claims/<int:pk>/reject/", ClaimRejectView.as_view(),
         name="travel-claim-reject"),
]
