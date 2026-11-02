from rest_framework import status
from rest_framework.generics import ListAPIView
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.permissions import IsAdminOrSuperAdmin, IsManagerOrAbove
from common.scoping import DateRangeFilterMixin, ScopedQuerysetMixin, scope_to_user

from .models import AllowanceRate, TravelClaim
from .serializers import (
    AllowanceRateSerializer,
    ClaimDecisionSerializer,
    TravelClaimSerializer,
)

CLAIM_OWNERS = ("user",)


class AllowanceRateView(APIView):
    """GET  /api/allowances/rate/  - the rate in force today (anyone signed in).
    POST /api/allowances/rate/  - set a new rate (admins only).

    Setting a rate adds a dated row rather than editing the live value, so past
    claims keep the rate they were paid at. Posting a row whose date already
    exists updates that day's rate instead of failing on the uniqueness rule.
    """

    def get_permissions(self):
        if self.request.method == "POST":
            return [IsAdminOrSuperAdmin()]
        return super().get_permissions()

    def get(self, request):
        rate = AllowanceRate.current()
        if rate is None:
            return Response({"detail": "No allowance rate has been set."},
                            status=status.HTTP_404_NOT_FOUND)
        return Response(AllowanceRateSerializer(rate).data)

    def post(self, request):
        payload = AllowanceRateSerializer(data=request.data)
        payload.is_valid(raise_exception=True)
        data = payload.validated_data

        rate, _created = AllowanceRate.objects.update_or_create(
            effective_from=data["effective_from"],
            defaults={
                "rate_per_km": data["rate_per_km"],
                "note": data.get("note", ""),
                "updated_by": request.user,
            },
        )
        return Response(AllowanceRateSerializer(rate).data,
                        status=status.HTTP_201_CREATED)


class TravelClaimListView(ScopedQuerysetMixin, DateRangeFilterMixin,
                          ListAPIView):
    """GET /api/allowances/claims/  -  ?from= ?to= ?status=

    Scoped like every other module: an employee sees their own claims, a
    manager their team's, an admin everyone's.
    """

    model = TravelClaim
    serializer_class = TravelClaimSerializer
    owner_fields = CLAIM_OWNERS

    def get_queryset(self):
        queryset = self.apply_date_range(super().get_queryset())
        claim_status = self.request.query_params.get("status")
        return queryset.filter(status=claim_status) if claim_status else queryset


class MyTravelClaimsView(TravelClaimListView):
    """GET /api/allowances/claims/me/ - the signed-in user's own claims."""

    def get_queryset(self):
        return super().get_queryset().filter(user=self.request.user)


class _ClaimDecisionView(APIView):
    """Shared base for the approve / query / reject actions. Each subclass sets
    the status it applies.

    A manager may decide their own team's claims and an admin everyone's, the
    same visibility rule as the list: the queryset below is scoped to the
    caller, so a manager simply cannot find - let alone approve - a claim
    outside their team. An employee is below this bar entirely.
    """

    permission_classes = [IsManagerOrAbove]
    new_status = None

    def post(self, request, pk):
        claim = scope_to_user(
            TravelClaim.objects.all(), request.user, CLAIM_OWNERS,
        ).filter(pk=pk).first()
        if claim is None:
            return Response({"detail": "Claim not found."},
                            status=status.HTTP_404_NOT_FOUND)

        payload = ClaimDecisionSerializer(data=request.data)
        payload.is_valid(raise_exception=True)
        claim.mark(self.new_status, request.user,
                   payload.validated_data.get("note", ""))
        return Response(TravelClaimSerializer(claim).data)


class ClaimApproveView(_ClaimDecisionView):
    """POST /api/allowances/claims/<id>/approve/"""
    new_status = TravelClaim.Status.APPROVED


class ClaimQueryView(_ClaimDecisionView):
    """POST /api/allowances/claims/<id>/query/ - send back for explanation."""
    new_status = TravelClaim.Status.QUERIED


class ClaimRejectView(_ClaimDecisionView):
    """POST /api/allowances/claims/<id>/reject/"""
    new_status = TravelClaim.Status.REJECTED
