from datetime import timedelta

from django.db.models import Avg, Count, Q, Sum
from django.utils import timezone
from rest_framework.generics import ListAPIView
from rest_framework.response import Response
from rest_framework.views import APIView

from attendance.models import Attendance
from common.scoping import DateRangeFilterMixin, ScopedQuerysetMixin
from crm.models import Customer, Lead
from delivery.models import Delivery
from visits.models import FieldVisit, FollowUp

from .models import DailyReport
from .serializers import DailyReportSerializer
from rest_framework.exceptions import ValidationError



class DailyReportListView(ScopedQuerysetMixin, DateRangeFilterMixin, ListAPIView):
    """GET /api/analytics/reports/  —  ?from= ?to= ?user="""

    model = DailyReport
    serializer_class = DailyReportSerializer
    owner_fields = ("user",)

    def get_queryset(self):
        queryset = self.apply_date_range(super().get_queryset())
        user_id = self.request.query_params.get("user")
        if not user_id:
            return queryset
        if not user_id.isdigit():
            raise ValidationError({"user": "Expected a numeric user id."})
        return queryset.filter(user_id=int(user_id))



class DashboardView(APIView):
    """GET /api/analytics/dashboard/  —  ?days=7

    Live figures for everyone the caller may see. Deliberately computed on
    demand rather than read from DailyReport: a dashboard opened at 11am must
    include this morning's work, which last night's report cannot know about.
    """

    def get(self, request):
        try:
            days = max(1, min(int(request.query_params.get("days", 7)), 90))
        except (TypeError, ValueError):
            days = 7

        today = timezone.localdate()
        since = today - timedelta(days=days - 1)
        people = request.user.visible_users()
        now = timezone.now()

        attendance = Attendance.objects.filter(
            user__in=people, date__gte=since).aggregate(
            days_present=Count("id"),
            checked_in_today=Count("id", filter=Q(date=today)),
            still_out=Count("id", filter=Q(date=today, check_out_at__isnull=True)),
        )

        visits = FieldVisit.objects.filter(
            user__in=people, date__gte=since).aggregate(
            total=Count("id"),
            today=Count("id", filter=Q(date=today)),
            minutes=Sum("duration_minutes"),
            avg_minutes=Avg("duration_minutes"),
        )

        leads = Lead.objects.filter(
            Q(assigned_to__in=people) | Q(created_by__in=people))
        lead_stats = leads.aggregate(
            open_leads=Count("id", filter=~Q(status__in=[
                Lead.Status.CONVERTED, Lead.Status.CLOSED])),
            in_demo=Count("id", filter=Q(status=Lead.Status.DEMO)),
            in_negotiation=Count("id", filter=Q(status=Lead.Status.NEGOTIATION)),
            in_proposal=Count("id", filter=Q(status=Lead.Status.PROPOSAL)),
            won=Count("id", filter=Q(status=Lead.Status.CONVERTED)),
            lost=Count("id", filter=Q(status=Lead.Status.CLOSED)),
            new_in_period=Count("id", filter=Q(created_at__date__gte=since)),
        )

        followups = FollowUp.objects.filter(assigned_to__in=people).aggregate(
            pending=Count("id", filter=Q(status=FollowUp.Status.PENDING)),
            overdue=Count("id", filter=Q(status=FollowUp.Status.PENDING,
                                         due_at__lt=now)),
            due_today=Count("id", filter=Q(status=FollowUp.Status.PENDING,
                                           due_at__date=today)),
        )

        customers = Customer.objects.filter(
            Q(assigned_to__in=people) | Q(created_by__in=people),
            is_active=True,
        ).count()

        deliveries = Delivery.objects.filter(
            Q(assigned_to__in=people) | Q(customer__assigned_to__in=people),
        ).aggregate(
            pending=Count("id", filter=Q(status__in=[
                Delivery.Status.PENDING, Delivery.Status.OUT_FOR_DELIVERY])),
            due_today=Count("id", filter=Q(
                scheduled_on=today,
            ) & ~Q(status__in=Delivery.FINAL_STATUSES)),
            not_delivered=Count("id", filter=Q(
                status=Delivery.Status.NOT_DELIVERED)),
            delivered=Count("id", filter=Q(
                status=Delivery.Status.DELIVERED,
                delivered_at__date__gte=since)),
        )

        team_size = people.count()
        won = lead_stats["won"]
        closed = won + lead_stats["lost"]

        return Response({
            "period": {"from": since, "to": today, "days": days},
            "team": {
                "size": team_size,
                "checked_in_today": attendance["checked_in_today"],
                "still_checked_out": attendance["still_out"],
                "attendance_rate": _pct(attendance["checked_in_today"], team_size),
            },
            "visits": {
                "total": visits["total"],
                "today": visits["today"],
                "total_minutes": visits["minutes"] or 0,
                "average_minutes": round(visits["avg_minutes"] or 0, 1),
                "per_person_per_day": round(
                    visits["total"] / team_size / days, 2) if team_size else 0,
            },
            "pipeline": {
                "open_leads": lead_stats["open_leads"],
                "new_leads": lead_stats["new_in_period"],
                "in_demo": lead_stats["in_demo"],
                "in_negotiation": lead_stats["in_negotiation"],
                "in_proposal": lead_stats["in_proposal"],
                "won": won,
                "lost": lead_stats["lost"],
                "win_rate": _pct(won, closed),
                "active_customers": customers,
            },
            "followups": {
                "pending": followups["pending"],
                "overdue": followups["overdue"],
                "due_today": followups["due_today"],
            },
            "deliveries": {
                "pending": deliveries["pending"],
                "due_today": deliveries["due_today"],
                "not_delivered": deliveries["not_delivered"],
                "delivered": deliveries["delivered"],
            },
        })


class MyDashboardView(APIView):
    """GET /api/analytics/dashboard/me/ — the signed-in user's own day."""

    def get(self, request):
        today = timezone.localdate()
        now = timezone.now()
        attendance = Attendance.objects.filter(user=request.user, date=today).first()

        return Response({
            "date": today,
            "attendance": {
                "checked_in": attendance is not None,
                "check_in_at": attendance.check_in_at if attendance else None,
                "check_out_at": attendance.check_out_at if attendance else None,
                "hours_worked": attendance.hours_worked if attendance else None,
            },
            "visits_today": FieldVisit.objects.filter(
                user=request.user, date=today).count(),
            "followups": {
                "due_today": FollowUp.objects.filter(
                    assigned_to=request.user,
                    status=FollowUp.Status.PENDING,
                    due_at__date=today).count(),
                "overdue": FollowUp.objects.filter(
                    assigned_to=request.user,
                    status=FollowUp.Status.PENDING,
                    due_at__lt=now).count(),
            },
            "open_leads": Lead.objects.filter(
                assigned_to=request.user).exclude(
                status__in=[Lead.Status.CONVERTED,
                            Lead.Status.CLOSED]).count(),
        })


def _pct(part, whole):
    """Percentage, guarding the empty-team and no-closed-deals cases."""
    return round(part / whole * 100, 1) if whole else 0.0
