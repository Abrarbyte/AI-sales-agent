from django.apps import AppConfig


class NotificationsConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "notifications"

    def ready(self):
        # Importing registers the signal receivers. Done here, not at module
        # import time, because the models must be loaded first.
        from . import signals  # noqa: F401
