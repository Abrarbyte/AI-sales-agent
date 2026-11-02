"""Generate daily reports by hand.

    python manage.py generate_reports              # today
    python manage.py generate_reports --date 2026-08-24
    python manage.py generate_reports --days 7     # backfill the last week

Useful in development (no Redis needed) and for rebuilding a day the scheduled
job missed.
"""

from datetime import timedelta

from django.core.management.base import BaseCommand
from django.utils import timezone

from analytics.tasks import generate_daily_reports


class Command(BaseCommand):
    help = "Generate daily reports for a date, or backfill several days."

    def add_arguments(self, parser):
        parser.add_argument("--date", help="YYYY-MM-DD (default: today)")
        parser.add_argument("--days", type=int, default=1,
                            help="How many days back to build, ending at --date")

    def handle(self, *args, **options):
        end = (
            timezone.datetime.fromisoformat(options["date"]).date()
            if options["date"] else timezone.localdate()
        )

        for offset in range(options["days"]):
            day = end - timedelta(days=offset)
            result = generate_daily_reports(date=day)
            self.stdout.write(self.style.SUCCESS(
                f"{result['date']}: {result['generated']} reports"))
