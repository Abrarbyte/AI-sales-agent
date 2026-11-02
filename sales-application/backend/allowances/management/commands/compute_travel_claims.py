"""Cost each rep's travel into a TravelClaim, one per rep per day.

Run weekly (the week is Monday to Sunday), though it works over any range. It
is safe to re-run: a still-pending claim is refreshed with the latest figures,
an approved or rejected one is left exactly as it was decided.

    python manage.py compute_travel_claims              # today
    python manage.py compute_travel_claims --date 2026-09-21
    python manage.py compute_travel_claims --week 2026-09-21   # that Mon-Sun
    python manage.py compute_travel_claims --from 2026-09-01 --to 2026-09-07
"""
from datetime import timedelta
from decimal import ROUND_HALF_UP, Decimal

from django.core.management.base import BaseCommand, CommandError
from django.utils import timezone
from django.utils.dateparse import parse_date

from attendance.models import Attendance
from common.distance import measure_day
from visits.models import FieldVisit

from ...models import AllowanceRate, TravelClaim

CENTS = Decimal("0.01")


class Command(BaseCommand):
    help = "Compute travel allowance claims for a date, a week, or a range."

    def add_arguments(self, parser):
        parser.add_argument("--date", help="A single day, YYYY-MM-DD.")
        parser.add_argument("--week", help="Any day in the Mon-Sun week to run.")
        parser.add_argument("--from", dest="from_", help="Range start, inclusive.")
        parser.add_argument("--to", help="Range end, inclusive.")

    def handle(self, *args, **options):
        start, end = self._resolve_range(options)
        self.stdout.write(f"Computing travel claims {start} to {end}.")

        created = updated = skipped_settled = skipped_norate = 0
        day = start
        while day <= end:
            rate = AllowanceRate.current(on=day)
            if rate is None:
                # No rate in force for this day - leave it uncosted rather than
                # guess a number. Re-run once a rate is set.
                attendances = Attendance.objects.filter(date=day)
                if attendances.exists():
                    skipped_norate += attendances.count()
                    self.stderr.write(
                        f"  {day}: no allowance rate set; "
                        f"{attendances.count()} day(s) left uncosted.")
                day += timedelta(days=1)
                continue

            for attendance in Attendance.objects.filter(date=day).select_related("user"):
                outcome = self._write_claim(attendance, day, rate)
                if outcome == "created":
                    created += 1
                elif outcome == "updated":
                    updated += 1
                elif outcome == "settled":
                    skipped_settled += 1
            day += timedelta(days=1)

        self.stdout.write(self.style.SUCCESS(
            f"Done. {created} created, {updated} refreshed, "
            f"{skipped_settled} already settled, "
            f"{skipped_norate} uncosted (no rate)."))

    def _write_claim(self, attendance, day, rate):
        existing = TravelClaim.objects.filter(
            user=attendance.user, date=day).first()
        if existing and existing.is_settled:
            return "settled"

        visits = list(FieldVisit.objects.filter(
            user=attendance.user, date=day).order_by("visited_at"))
        measured = measure_day(attendance, visits)

        # Round the distance first, then cost that rounded figure, so the claim
        # reconciles: distance_km × rate_per_km equals amount exactly, which is
        # what a reviewer checks by eye.
        km = Decimal(str(measured["km"])).quantize(CENTS, rounding=ROUND_HALF_UP)
        amount = (km * rate.rate_per_km).quantize(CENTS, rounding=ROUND_HALF_UP)

        fields = {
            "distance_km": km,
            "rate_per_km": rate.rate_per_km,
            "amount": amount,
            "method": measured["method"],
            "is_estimate": measured["is_estimate"],
            "flagged_legs": measured["flagged_legs"],
            "status": TravelClaim.Status.PENDING,
        }
        _, created = TravelClaim.objects.update_or_create(
            user=attendance.user, date=day, defaults=fields)
        return "created" if created else "updated"

    def _resolve_range(self, options):
        provided = [k for k in ("date", "week", "from_", "to")
                    if options.get(k)]
        if options.get("date"):
            if len(provided) > 1:
                raise CommandError("--date cannot be combined with other dates.")
            d = self._parse(options["date"], "date")
            return d, d
        if options.get("week"):
            if len(provided) > 1:
                raise CommandError("--week cannot be combined with other dates.")
            d = self._parse(options["week"], "week")
            monday = d - timedelta(days=d.weekday())
            return monday, monday + timedelta(days=6)
        if options.get("from_") or options.get("to"):
            if not (options.get("from_") and options.get("to")):
                raise CommandError("--from and --to must be given together.")
            start = self._parse(options["from_"], "from")
            end = self._parse(options["to"], "to")
            if start > end:
                raise CommandError("--from must not be after --to.")
            return start, end
        today = timezone.localdate()
        return today, today

    @staticmethod
    def _parse(raw, name):
        value = parse_date(raw)
        if value is None:
            raise CommandError(f"--{name} must be a date in YYYY-MM-DD format.")
        return value
