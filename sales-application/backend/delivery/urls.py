from django.urls import path

from .views import (
    AttemptListView,
    CancelView,
    DeliverView,
    DeliveryDetailView,
    DeliveryListView,
)

urlpatterns = [
    path("deliveries/", DeliveryListView.as_view(), name="delivery-list"),
    path("deliveries/<int:pk>/", DeliveryDetailView.as_view(), name="delivery-detail"),
    path("deliveries/<int:pk>/deliver/", DeliverView.as_view(), name="delivery-deliver"),
    path("deliveries/<int:pk>/cancel/", CancelView.as_view(), name="delivery-cancel"),
    path("deliveries/<int:pk>/attempts/", AttemptListView.as_view(),
         name="delivery-attempts"),
]
