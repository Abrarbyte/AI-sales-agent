from django.conf import settings
from django.db import models
from django.utils import timezone


class Notification(models.Model):
    """A message for one person, shown in the app's bell icon.

    Stored in our own database rather than fired straight at a push service, so
    a user who was offline still sees what they missed, and so the history can
    be read back. Push delivery (Phase 4) becomes an extra step on top of this,
    not a replacement for it.
    """

    class Kind(models.TextChoices):
        FOLLOWUP_DUE = "followup_due"
        FOLLOWUP_OVERDUE = "followup_overdue"
        LEAD_ASSIGNED = "lead_assigned"
        VISIT_LOGGED = "visit_logged"
        ATTENDANCE_MISSING = "attendance_missing"
        REPORT_READY = "report_ready"
        GENERAL = "general"

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE,
        related_name="notifications",
    )
    kind = models.CharField(max_length=30, choices=Kind.choices,
                            default=Kind.GENERAL)
    title = models.CharField(max_length=120)
    body = models.CharField(max_length=255, blank=True)

    # Where tapping it should take you, e.g. "/leads/42". Kept as a plain
    # string so the app decides how to route it, and the backend need not know
    # about screens.
    link = models.CharField(max_length=200, blank=True)

    read_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ("-created_at",)
        indexes = [
            # The query the bell icon runs: my unread, newest first.
            models.Index(fields=["user", "read_at", "-created_at"]),
        ]

    def __str__(self):
        return f"{self.user.username}: {self.title}"

    @property
    def is_read(self):
        return self.read_at is not None

    def mark_read(self):
        if self.read_at is None:
            self.read_at = timezone.now()
            self.save(update_fields=["read_at"])

    @classmethod
    def notify(cls, user, title, *, kind=Kind.GENERAL, body="", link=""):
        """The one way notifications get created.

        Every caller goes through here so that adding push delivery later means
        editing this method, not hunting down scattered `objects.create` calls.
        """
        return cls.objects.create(
            user=user, kind=kind, title=title, body=body, link=link)
