from django.db import transaction
from django.db.models import Count, Prefetch
from django.utils import timezone
from rest_framework import status
from rest_framework.generics import (
    ListAPIView,
    ListCreateAPIView,
    RetrieveUpdateDestroyAPIView,
)
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.response import Response
from rest_framework.views import APIView

from common.scoping import ScopedQuerysetMixin, scope_to_user

from .models import Delivery, DeliveryAttempt
from .serializers import (
    CancelSerializer,
    DeliverSerializer,
    DeliveryAttemptSerializer,
    DeliverySerializer,
)

# The driver, whoever booked it, and the account owner may all see it.
DELIVERY_OWNERS = ("assigned_to", "created_by", "customer__assigned_to")

LAST_ATTEMPT_PREFETCH = Prefetch(
    "attempts", queryset=DeliveryAttempt.objects.all(), to_attr="_last_attempts")


def delivery_rows(queryset):
    return (queryset
            .prefetch_related(LAST_ATTEMPT_PREFETCH)
            .annotate(attempt_count=Count("attempts", distinct=True)))


def scoped_delivery(request, pk):
    return scope_to_user(
        Delivery.objects.select_related("customer", "product"),
        request.user, DELIVERY_OWNERS,
    ).filter(pk=pk).first()


class DeliveryScopedMixin(ScopedQuerysetMixin):
    model = Delivery
    serializer_class = DeliverySerializer
    owner_fields = DELIVERY_OWNERS
    select_related_extra = ("customer", "product")

    def get_queryset(self):
        return delivery_rows(super().get_queryset())


class DeliveryListView(DeliveryScopedMixin, ListCreateAPIView):
    """GET/POST /api/delivery/deliveries/
    ?customer= ?status= ?assigned_to= ?date=today ?overdue=true
    """

    def get_queryset(self):
        queryset = super().get_queryset()
        params = self.request.query_params
        if params.get("customer"):
            queryset = queryset.filter(customer_id=params["customer"])
        if params.get("status"):
            queryset = queryset.filter(status=params["status"])
        if params.get("assigned_to"):
            queryset = queryset.filter(assigned_to_id=params["assigned_to"])
        if params.get("date") == "today":
            queryset = queryset.filter(scheduled_on=timezone.localdate())
        if params.get("overdue") == "true":
            queryset = queryset.filter(
                scheduled_on__lt=timezone.localdate(),
            ).exclude(status__in=Delivery.FINAL_STATUSES)
        return queryset

    def perform_create(self, serializer):
        data = serializer.validated_data
        customer = data["customer"]
        serializer.save(
            created_by=self.request.user,
            assigned_to=data.get("assigned_to") or customer.assigned_to
            or self.request.user,
            # The goods go where the customer is unless told otherwise.
            address=data.get("address") or ", ".join(
                part for part in (customer.address, customer.city) if part),
        )


class DeliveryDetailView(DeliveryScopedMixin, RetrieveUpdateDestroyAPIView):
    """GET/PATCH/DELETE /api/delivery/deliveries/<id>/"""

    def perform_destroy(self, instance):
        # Cancel, never delete: what was scheduled is part of the record.
        instance.status = Delivery.Status.CANCELLED
        instance.save(update_fields=["status", "updated_at"])


class DeliverView(APIView):
    """POST /api/delivery/deliveries/<id>/deliver/ — it landed.

    Multipart: `received_by`, `proof` (file), `notes`.
    """

    parser_classes = (MultiPartParser, FormParser, JSONParser)

    def post(self, request, pk):
        delivery = scoped_delivery(request, pk)
        if delivery is None:
            return Response({"detail": "Delivery not found."},
                            status=status.HTTP_404_NOT_FOUND)
        if delivery.is_final:
            return Response(
                {"detail": f"This delivery is already {delivery.status}."},
                status=status.HTTP_409_CONFLICT)

        payload = DeliverSerializer(data=request.data)
        payload.is_valid(raise_exception=True)
        delivery.mark_delivered(**payload.validated_data)
        delivery = delivery_rows(Delivery.objects.filter(pk=pk)).get()
        return Response(DeliverySerializer(delivery).data)


class CancelView(APIView):
    """POST /api/delivery/deliveries/<id>/cancel/"""

    def post(self, request, pk):
        delivery = scoped_delivery(request, pk)
        if delivery is None:
            return Response({"detail": "Delivery not found."},
                            status=status.HTTP_404_NOT_FOUND)
        if delivery.is_final:
            return Response(
                {"detail": f"This delivery is already {delivery.status}."},
                status=status.HTTP_409_CONFLICT)
        payload = CancelSerializer(data=request.data)
        payload.is_valid(raise_exception=True)
        delivery.status = Delivery.Status.CANCELLED
        # Why it was cancelled goes beside the scheduling notes, not over
        # them (#45).
        if payload.validated_data.get("notes"):
            delivery.outcome_notes = payload.validated_data["notes"]
        delivery.save(update_fields=["status", "outcome_notes", "updated_at"])
        delivery = delivery_rows(Delivery.objects.filter(pk=pk)).get()
        return Response(DeliverySerializer(delivery).data)


class AttemptListView(ListAPIView):
    """GET/POST /api/delivery/deliveries/<id>/attempts/

    POST records a failed attempt: the delivery becomes `not_delivered`, the
    retry date becomes its new scheduled date, and a new driver, if named,
    takes it over.
    """

    serializer_class = DeliveryAttemptSerializer

    def get_delivery(self):
        return scoped_delivery(self.request, self.kwargs["pk"])

    def get_queryset(self):
        delivery = self.get_delivery()
        if delivery is None:
            return DeliveryAttempt.objects.none()
        return delivery.attempts.select_related("assigned_to")

    def post(self, request, pk):
        delivery = self.get_delivery()
        if delivery is None:
            return Response({"detail": "Delivery not found."},
                            status=status.HTTP_404_NOT_FOUND)
        if delivery.is_final:
            return Response(
                {"detail": f"This delivery is already {delivery.status}."},
                status=status.HTTP_409_CONFLICT)

        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        with transaction.atomic():
            attempt = serializer.save(
                delivery=delivery,
                created_by=request.user,
                assigned_to=data.get("assigned_to") or delivery.assigned_to,
            )
            delivery.status = Delivery.Status.NOT_DELIVERED
            fields = ["status", "updated_at"]
            if attempt.retry_on:
                delivery.scheduled_on = attempt.retry_on
                fields.append("scheduled_on")
            if attempt.assigned_to_id != delivery.assigned_to_id:
                delivery.assigned_to = attempt.assigned_to
                fields.append("assigned_to")
            delivery.save(update_fields=fields)

        return Response(DeliveryAttemptSerializer(attempt).data,
                        status=status.HTTP_201_CREATED)
