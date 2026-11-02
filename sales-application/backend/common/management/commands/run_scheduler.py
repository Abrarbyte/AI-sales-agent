"""The three scheduled jobs in one long-running process.

    python manage.py run_scheduler

    every minute       send_reminders         (meeting alerts)
    daily at 00:05     generate_reports       (yesterday's daily reports)
    daily at 00:10     close_stale_leads      (30 quiet days -> closed)
    Monday at 00:15    compute_travel_claims  (last week's travel allowance)

One process, no Redis, no crontab to install: the deployment runs this as a
second container / service next to gunicorn. Each job is the same management
command you can run by hand, so a missed night is rebuilt with
`generate_reports --days N`. Exits cleanly on SIGTERM.
"""

import logging
import signal
import time
from datetime import timedelta

from django.core.management import call_command
from django.core.management.base import BaseCommand
from django.utils import timezone

log = logging.getLogger("scheduler")


class Command(BaseCommand):
    help = "Run send_reminders every minute and the nightly jobs once a day."

    def add_arguments(self, parser):
        parser.add_argument("--once", action="store_true",
                            help="Run one tick and exit (for tests and checks).")

    def handle(self, *args, **options):
        stop = False

        def _stop(*_):
            nonlocal stop
            stop = True

        signal.signal(signal.SIGTERM, _stop)
        signal.signal(signal.SIGINT, _stop)

        last_nightly = None
        last_weekly = None
        log.info("scheduler started")
        while not stop:
            tick_started = time.monotonic()
            now = timezone.localtime()

            self._run("send_reminders")

            # Nightly, once, after 00:05. Tracked by date so a restart at
            # 00:07 does not run it twice and a restart at 23:59 does not
            # skip it.
            if now.hour * 60 + now.minute >= 5 and last_nightly != now.date():
                self._run("generate_reports", "--date",
                          str((now - timedelta(days=1)).date()))
                self._run("close_stale_leads")
                last_nightly = now.date()

            # Weekly, once, early Monday, for the week that just ended. The
            # week is Monday-Sunday, so on a Monday "seven days ago" is the
            # start of the week being costed. Tracked by date like the nightly
            # jobs, so a restart does not run it twice.
            if (now.weekday() == 0 and now.hour * 60 + now.minute >= 15
                    and last_weekly != now.date()):
                self._run("compute_travel_claims", "--week",
                          str((now - timedelta(days=7)).date()))
                last_weekly = now.date()

            if options["once"]:
                break
            # Sleep out the rest of the minute, waking early on SIGTERM.
            for _ in range(int(max(1, 60 - (time.monotonic() - tick_started)))):
                if stop:
                    break
                time.sleep(1)
        log.info("scheduler stopped")

    def _run(self, name, *args):
        try:
            call_command(name, *args, verbosity=0)
        except Exception:  # noqa: BLE001 - one failing job must not stop the rest
            log.exception("%s failed", name)
