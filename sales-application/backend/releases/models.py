"""Phone app releases, so the app can update itself from this server (#94).

An admin uploads each new APK here; the phone compares its own build number
with the latest one and offers the update. Nothing goes through a store.
"""

from django.core.validators import FileExtensionValidator
from django.db import models


class AppRelease(models.Model):
    version = models.CharField(
        max_length=20, help_text='What people see, e.g. "1.2.0".')
    build = models.PositiveIntegerField(
        unique=True,
        help_text="The number after + in pubspec.yaml (1.2.0+3 is build 3). "
                  "Must go up with every release.")
    # Stored under a random name like every upload (common/storage.py), which
    # also means a phone can never be handed an old cached file as new. The
    # download page names the saved file "saleshub-<version>.apk".
    apk = models.FileField(
        upload_to="app/", verbose_name="APK file",
        validators=[FileExtensionValidator(["apk"])])
    notes = models.TextField(
        blank=True, help_text="What changed, in plain words. Shown to reps.")
    min_build = models.PositiveIntegerField(
        default=0,
        help_text="Phones older than this build must update before carrying "
                  "on. Leave 0 unless the release fixes something serious.")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ("-build",)

    def __str__(self):
        return f"{self.version} (build {self.build})"
