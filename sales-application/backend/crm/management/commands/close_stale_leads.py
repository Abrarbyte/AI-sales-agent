"""Close leads nobody has touched in a month.

A lead that has sat untouched since it was created is not a lead any more, but
it still crowds the salesperson's list and still counts as open on the
dashboard. Closing it is honest about that.

Closed, not deleted: how many leads went cold is worth knowing, and it is the
same question as how the month went.

Run daily. Until Redis and Celery beat are in place on the server, run it by
hand or from a scheduled task:

    python manage.py close_stale_leads
    python manage.py close_stale_leads --dry-run
"""

from datetime import timedelta

from django.core.management.base import BaseCommand
from django.utils import timezone

from crm.models import Lead
from visits.models import FollowUp


class Command(BaseCommand):
    help = "Close leads with no activity for Lead.STALE_AFTER_DAYS."

    def add_arguments(self, parser):
        parser.add_argument(
            "--days", type=int, default=Lead.STALE_AFTER_DAYS,
            help=f"Days of silence before closing (default {Lead.STALE_AFTER_DAYS}).",
        )
        parser.add_argument(
            "--dry-run", action="store_true",
            help="List what would close, and change nothing.",
        )

    def handle(self, *args, **options):
        days = options["days"]
        cutoff = timezone.now() - timedelta(days=days)

        # Converted and already-closed leads are finished; only the live ones
        # can go stale. `updated_at` rather than `created_at`, so a lead that
        # is being worked stays open.
        stale = Lead.objects.filter(
            status=Lead.Status.NEW,
            updated_at__lt=cutoff,
        ).exclude(
            # A call or meeting still booked means someone is working the
            # lead, however long since it was edited (#21). A follow-up
            # already overdue doesn't count - that is the silence this
            # command is here to catch.
            id__in=FollowUp.objects.filter(
                status=FollowUp.Status.PENDING, due_at__gte=timezone.now(),
            ).values("lead_id"),
        )

        if not stale.exists():
            self.stdout.write(f"No leads have been quiet for {days} days.")
            return

        for lead in stale:
            self.stdout.write(
                f"  {lead.name} — last touched {lead.updated_at:%d %b %Y}"
            )

        if options["dry_run"]:
            self.stdout.write(self.style.WARNING(
                f"{stale.count()} lead(s) would close. Nothing was changed."))
            return

        # `update()` deliberately: it does not bump `updated_at`, so the record
        # still shows when the lead actually went quiet rather than when this
        # command happened to run.
        # Always with a reason (#22): this is the one case where the reason is
        # certain. Leftover overdue follow-ups are cancelled with it (#20).
        ids = list(stale.values_list("id", flat=True))
        count = Lead.objects.filter(id__in=ids).update(
            status=Lead.Status.CLOSED, lost_reason=Lead.LostReason.NO_RESPONSE)
        Lead.cancel_open_followups(ids)
        self.stdout.write(self.style.SUCCESS(
            f"Closed {count} lead(s) quiet for {days} days or more."))
