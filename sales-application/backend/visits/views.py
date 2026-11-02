from django.utils import timezone
from rest_framework import status
from rest_framework.exceptions import ValidationError
from rest_framework.generics import (
    ListCreateAPIView,
    RetrieveUpdateDestroyAPIView,
)
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.response import Response
from rest_framework.views import APIView

from attendance.models import Attendance
from common.scoping import DateRangeFilterMixin, ScopedQuerysetMixin, scope_to_user

from .checkpoints import Checkpoint
from .models import FieldVisit, FollowUp
from .serializers import (
    CheckpointSerializer,
    CompleteFollowUpSerializer,
    FieldVisitSerializer,
    FollowUpSerializer,
)

def for_target(queryset, params):
    """Narrow to one lead or customer, so a detail page asks for its own rows
    instead of downloading everything and filtering on the phone (#89). A
    value that is not a number is ignored rather than a server error."""
    for key in ("lead", "customer"):
        value = params.get(key, "")
        if value.isdigit():
            queryset = queryset.filter(**{f"{key}_id": int(value)})
    return queryset


# A visit belongs to the person who made it; a follow-up to the person who owes
# it, plus whoever scheduled it.
VISIT_OWNERS = ("user",)
FOLLOWUP_OWNERS = ("assigned_to", "created_by")


class VisitScopedMixin(ScopedQuerysetMixin):
    model = FieldVisit
    serializer_class = FieldVisitSerializer
    owner_fields = VISIT_OWNERS
    select_related_extra = ("lead", "customer")


class VisitListView(VisitScopedMixin, DateRangeFilterMixin, ListCreateAPIView):
    """GET/POST /api/visits/  —  ?from= ?to= ?outcome= ?lead= ?customer=

    Accepts multipart as well as JSON, so the app can post the visit and its
    photograph in one request rather than creating the record and then
    uploading to it.
    """

    parser_classes = [MultiPartParser, FormParser, JSONParser]

    def get_queryset(self):
        queryset = self.apply_date_range(super().get_queryset())
        params = self.request.query_params
        queryset = for_target(queryset, params)
        outcome = params.get("outcome")
        return queryset.filter(outcome=outcome) if outcome else queryset

    def perform_create(self, serializer):
        # A visit happens inside the working day: after check-in, before
        # check-out. Otherwise the travel route is built in the wrong order.
        day = Attendance.objects.filter(
            user=self.request.user, date=timezone.localdate()).first()
        if day is None:
            raise ValidationError(
                {"detail": "Check in first, then log the visit."})
        if day.check_out_at is not None:
            raise ValidationError(
                {"detail": "Your day is closed. Visits can't be logged "
                           "after check-out."})
        # Who and when come from the request, never the client.
        serializer.save(
            user=self.request.user,
            visited_at=timezone.now(),
            date=timezone.localdate(),
        )


class VisitDetailView(VisitScopedMixin, RetrieveUpdateDestroyAPIView):
    """GET/PATCH/DELETE /api/visits/<id>/"""


class FollowUpScopedMixin(ScopedQuerysetMixin):
    model = FollowUp
    serializer_class = FollowUpSerializer
    owner_fields = FOLLOWUP_OWNERS
    select_related_extra = ("lead", "customer")


class FollowUpListView(FollowUpScopedMixin, ListCreateAPIView):
    """GET/POST /api/visits/followups/  —  ?status= ?kind=a,b ?overdue=true ?due=today
    ?lead= ?customer="""

    def get_queryset(self):
        queryset = super().get_queryset()
        params = self.request.query_params
        if params.get("status"):
            queryset = queryset.filter(status=params["status"])
        if params.get("kind"):
            queryset = queryset.filter(kind__in=params["kind"].split(","))
        if params.get("overdue") == "true":
            queryset = queryset.filter(
                status=FollowUp.Status.PENDING, due_at__lt=timezone.now())
        if params.get("due") == "today":
            queryset = queryset.filter(due_at__date=timezone.localdate())
        return for_target(queryset, params)

    def perform_create(self, serializer):
        # Default to the person creating it, so nothing is scheduled ownerless.
        serializer.save(
            created_by=self.request.user,
            assigned_to=serializer.validated_data.get("assigned_to")
            or self.request.user,
        )


class FollowUpDetailView(FollowUpScopedMixin, RetrieveUpdateDestroyAPIView):
    """GET/PATCH/DELETE /api/visits/followups/<id>/"""


class FollowUpCompleteView(APIView):
    """POST /api/visits/followups/<id>/complete/ — mark it done."""

    def post(self, request, pk):
        followup = scope_to_user(
            FollowUp.objects.all(), request.user, FOLLOWUP_OWNERS,
        ).filter(pk=pk).first()

        if followup is None:
            return Response({"detail": "Follow-up not found."},
                            status=status.HTTP_404_NOT_FOUND)
        if followup.status != FollowUp.Status.PENDING:
            return Response(
                {"detail": f"This follow-up is already {followup.status}."},
                status=status.HTTP_409_CONFLICT,
            )

        payload = CompleteFollowUpSerializer(data=request.data)
        payload.is_valid(raise_exception=True)
        followup.mark_done(payload.validated_data.get("outcome_note", ""))
        return Response(FollowUpSerializer(followup).data)


class CheckpointListView(ScopedQuerysetMixin, DateRangeFilterMixin,
                         ListCreateAPIView):
    """GET/POST /api/visits/checkpoints/  —  ?from= ?to=
z
    One tap in the app: the phone sends where it is, and that is the record.
    Accepts multipart as well as JSON, since the note may arrive with a photo.
    """

    model = Checkpoint
    serializer_class = CheckpointSerializer
    owner_fields = ("user",)
    parser_classes = [MultiPartParser, FormParser, JSONParser]

    def get_queryset(self):
        return self.apply_date_range(super().get_queryset())

    def perform_create(self, serializer):
        # Who and when come from the request, never the client.
        serializer.save(
            user=self.request.user,
            recorded_at=timezone.now(),
            date=timezone.localdate(),
        )
