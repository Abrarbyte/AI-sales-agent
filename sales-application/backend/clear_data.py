"""Clears all transactional data so records can be entered by hand.

KEEPS every user account - otherwise nobody could log in to enter anything.
DELETES leads, customers, visits, follow-ups, checkpoints, attendance,
daily reports and notifications.

    venv/Scripts/python clear_data.py

This is irreversible. The pre-seed snapshot is at:
    <scratchpad>/db_backup.json
restored with:  manage.py flush --noinput && manage.py loaddata db_backup.json
"""
import os

import django

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")
django.setup()

from accounts.models import User  # noqa: E402
from analytics.models import DailyReport  # noqa: E402
from attendance.models import Attendance  # noqa: E402
from crm.models import Customer, Lead  # noqa: E402
from notifications.models import Notification  # noqa: E402
# The visits app splits its models across modules: FieldVisit in models.py,
# which re-exports FollowUp, while Checkpoint keeps its own file.
from visits.checkpoints import Checkpoint  # noqa: E402
from visits.models import FieldVisit, FollowUp  # noqa: E402

REPORTED = (Lead, Customer, FieldVisit, FollowUp, Checkpoint,
            Attendance, DailyReport, Notification)

# Children before parents, so no foreign key is orphaned mid-delete.
DELETION_ORDER = (Notification, DailyReport, Checkpoint, FollowUp,
                  FieldVisit, Attendance, Lead, Customer)


def counts(label):
    print(f"{label}:")
    for model in REPORTED:
        print(f"  {model.__name__:<14}{model.objects.count():>6}")


counts("BEFORE")

total = sum(m.objects.count() for m in REPORTED)
if total == 0:
    print("\nNothing to delete.")
else:
    for model in DELETION_ORDER:
        deleted, _ = model.objects.all().delete()
        if deleted:
            print(f"  deleted {deleted:>5} from {model.__name__}")

print()
counts("AFTER")

print(f"\nUsers kept: {User.objects.count()}")
for user in User.objects.order_by("role", "username"):
    state = "active" if user.is_active else "inactive"
    print(f"  {user.username:<18} {user.role:<12} {state}")
