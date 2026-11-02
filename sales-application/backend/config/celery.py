"""Celery setup: background jobs that run outside a web request.

The daily report is the reason this exists — nobody should wait for it, and it
must run at a fixed time whether anyone is using the app or not.
"""

import os

from celery import Celery
from celery.schedules import crontab

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")

app = Celery("sales_tracker")
app.config_from_object("django.conf:settings", namespace="CELERY")
app.autodiscover_tasks()

# Fixed schedule, kept in code rather than the database: there is one job and it
# runs at one time. django-celery-beat would only be worth it if the schedule
# needed editing from the admin panel.
app.conf.beat_schedule = {
    "daily-sales-report": {
        "task": "analytics.tasks.generate_daily_reports",
        # 19:30 IST — after the field team has finished for the day.
        "schedule": crontab(hour=19, minute=30),
    },
}
