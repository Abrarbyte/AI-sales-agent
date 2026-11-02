"""Send follow-up reminders that are due right now.

    python manage.py send_reminders

Meant for a scheduler every minute (cron: `* * * * *`). Safe to run more
often, or to miss a run: every alert is recorded once it is sent, so a rerun
sends nothing twice and a late run catches up.
"""

from django.core.management.base import BaseCommand

from notifications.reminders import send_due_reminders


class Command(BaseCommand):
    help = "Create notifications for follow-ups due in 30/10 minutes or overdue."

    def handle(self, *args, **options):
        sent = send_due_reminders()
        self.stdout.write(self.style.SUCCESS(f"{sent} reminder(s) sent."))
