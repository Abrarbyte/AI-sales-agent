from django.urls import path

from .views import (
    CustomerCompleteView,
    CustomerDetailView,
    CustomerPaymentsView,
    CustomerReceiptView,
    CustomerListView,
    DemoDetailView,
    DemoListView,
    LeadConvertView,
    LeadDetailView,
    LeadListView,
    NegotiationDetailView,
    NegotiationListView,
    ProductDetailView,
    ProductListView,
)

urlpatterns = [
    path("leads/", LeadListView.as_view(), name="lead-list"),
    path("leads/<int:pk>/", LeadDetailView.as_view(), name="lead-detail"),
    path("leads/<int:pk>/convert/", LeadConvertView.as_view(), name="lead-convert"),
    path("demos/", DemoListView.as_view(), name="demo-list"),
    path("demos/<int:pk>/", DemoDetailView.as_view(), name="demo-detail"),
    path("negotiations/", NegotiationListView.as_view(), name="negotiation-list"),
    path("negotiations/<int:pk>/", NegotiationDetailView.as_view(),
         name="negotiation-detail"),
    path("customers/", CustomerListView.as_view(), name="customer-list"),
    path("customers/<int:pk>/", CustomerDetailView.as_view(), name="customer-detail"),
    path("customers/<int:pk>/payments/", CustomerPaymentsView.as_view(),
         name="customer-payments"),
    path("customers/<int:pk>/receipt.pdf", CustomerReceiptView.as_view(),
         name="customer-receipt"),
    path("customers/<int:pk>/complete/", CustomerCompleteView.as_view(),
         name="customer-complete"),
    path("products/", ProductListView.as_view(), name="product-list"),
    path("products/<int:pk>/", ProductDetailView.as_view(), name="product-detail"),
]
