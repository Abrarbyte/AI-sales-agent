"""The evening job: turn a day's raw activity into one row per person."""

import logging

from celery import shared_task
from django.contrib.auth import get_user_model
from django.db.models import Count, Q, Sum
from django.utils import timezone

from attendance.models import Attendance
from crm.models import Customer, Lead
from visits.models import FieldVisit, FollowUp

from .models import DailyReport

logger = logging.getLogger(__name__)
User = get_user_model()


def build_report_for(user, date):
    """Compute one person's figures for one day and store them.

    Written as a plain function so it can be called directly — from a test, or
    from `manage.py` to rebuild a day — without Celery or Redis running.
    """
    attendance = Attendance.objects.filter(user=user, date=date).first()

    visits = FieldVisit.objects.filter(user=user, date=date).aggregate(
        count=Count("id"),
        minutes=Sum("duration_minutes"),
    )

    leads = Lead.objects.filter(created_by=user, created_at__date=date).count()
    won = Lead.objects.filter(assigned_to=user, converted_at__date=date).count()
    customers = Customer.objects.filter(
        created_by=user, created_at__date=date).count()

    # Completed *that day*; pending and overdue are a snapshot at generation
    # time, since "overdue" is only meaningful relative to now.
    followups = FollowUp.objects.filter(assigned_to=user).aggregate(
        completed=Count("id", filter=Q(status=FollowUp.Status.DONE,
                                       completed_at__date=date)),
        pending=Count("id", filter=Q(status=FollowUp.Status.PENDING)),
        overdue=Count("id", filter=Q(status=FollowUp.Status.PENDING,
                                     due_at__lt=timezone.now())),
    )

    report, _ = DailyReport.objects.update_or_create(
        user=user, date=date,
        defaults={
            "checked_in": attendance is not None,
            "check_in_at": attendance.check_in_at if attendance else None,
            "check_out_at": attendance.check_out_at if attendance else None,
            "hours_worked": attendance.hours_worked if attendance else None,
            "visits_count": visits["count"] or 0,
            "visit_minutes": visits["minutes"] or 0,
            "leads_created": leads,
            "leads_won": won,
            "customers_created": customers,
            "followups_completed": followups["completed"],
            "followups_pending": followups["pending"],
            "followups_overdue": followups["overdue"],
        },
    )
    return report


@shared_task
def generate_daily_reports(date=None):
    """Build today's report for every active employee.

    Idempotent: running it twice for the same day updates the same rows rather
    than creating duplicates, so a retry after a failure is safe.
    """
    target_date = date or timezone.localdate()
    if isinstance(target_date, str):
        target_date = timezone.datetime.fromisoformat(target_date).date()

    users = User.objects.filter(is_active=True)
    built = 0
    for user in users:
        try:
            build_report_for(user, target_date)
            built += 1
        except Exception:
            # One person's bad data must not stop everyone else's report.
            logger.exception("Daily report failed for %s on %s",
                             user.username, target_date)

    logger.info("Daily reports generated: %s of %s for %s",
                built, users.count(), target_date)
    return {"date": str(target_date), "generated": built}
