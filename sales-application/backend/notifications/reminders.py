"""Turn follow-ups that are about to fall due into notifications.

    send_due_reminders()   # called by `manage.py send_reminders`, every minute

A pending follow-up gets three alerts at most: 30 minutes before, 10 minutes
before, and once when it has gone overdue. Each is recorded in
FollowUpReminder, so running this every minute - or twice in a minute - sends
nothing twice. Completed and cancelled follow-ups are never touched.
"""

from datetime import timedelta

from django.db import IntegrityError, transaction
from django.utils import timezone

from visits.models import FollowUp, FollowUpReminder

from .models import Notification


def _title(followup, offset):
    kind = followup.get_kind_display()
    if offset == 0:
        return f"{kind} overdue: {followup.target_name}"
    return f"{kind} in {offset} min: {followup.target_name}"


def _body(followup):
    when = timezone.localtime(followup.due_at).strftime("%H:%M")
    return followup.note or f"Due at {when}"


def send_due_reminders(now=None):
    """Send whatever is owed as of `now`. Returns the count sent."""
    now = now or timezone.now()
    sent = 0

    # Anything due in the next 30 minutes, or already past due but not yet
    # flagged overdue. A day-old overdue follow-up that already got its
    # alert is filtered out by the unique constraint, not by this query.
    window = FollowUp.objects.filter(
        status=FollowUp.Status.PENDING,
        due_at__lte=now + timedelta(minutes=30),
    ).select_related("assigned_to", "lead", "customer")

    for followup in window:
        minutes_left = (followup.due_at - now).total_seconds() / 60
        for offset in FollowUpReminder.OFFSETS:
            if minutes_left > offset:
                continue  # not yet time for this one
            if offset == 0 and minutes_left > 0:
                continue  # overdue only once it is actually past
            try:
                with transaction.atomic():
                    FollowUpReminder.objects.create(
                        followup=followup, offset_minutes=offset)
            except IntegrityError:
                continue  # already sent
            Notification.notify(
                followup.assigned_to,
                title=_title(followup, offset),
                kind=(Notification.Kind.FOLLOWUP_OVERDUE if offset == 0
                      else Notification.Kind.FOLLOWUP_DUE),
                body=_body(followup),
                link=f"/followups/{followup.pk}",
            )
            sent += 1
    return sent
