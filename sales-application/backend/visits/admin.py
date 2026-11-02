from django.contrib import admin
from django.utils.html import format_html

from .checkpoints import Checkpoint
from .models import FieldVisit, FollowUp


@admin.register(FieldVisit)
class FieldVisitAdmin(admin.ModelAdmin):
    """The record of a day in the field.

    The photograph and the coordinates are the point of this table — they are
    the evidence a visit happened where and when it says — so both are on the
    list page rather than one click away.
    """

    list_display = ("user", "target_name", "date", "check_in_time",
                    "outcome", "where", "thumbnail")
    list_filter = ("outcome", "date", "user")
    search_fields = ("user__username", "lead__name", "customer__name", "notes")
    date_hierarchy = "date"
    autocomplete_fields = ("user", "lead", "customer")
    readonly_fields = ("preview", "map_link", "created_at")

    @admin.display(description="Time", ordering="visited_at")
    def check_in_time(self, visit):
        return visit.visited_at.strftime("%H:%M")

    @admin.display(description="Coordinates")
    def where(self, visit):
        """Links out to a map, so a coordinate pair can be checked in one
        click rather than copied into another tab."""
        return format_html(
            '<a href="https://www.google.com/maps?q={},{}" target="_blank" '
            'rel="noopener">{}, {}</a>',
            visit.lat, visit.lng, visit.lat, visit.lng,
        )

    @admin.display(description="Photo")
    def thumbnail(self, visit):
        if not visit.photo:
            return "—"
        return format_html(
            '<a href="{}" target="_blank" rel="noopener">'
            '<img src="{}" style="height:48px;border-radius:4px" /></a>',
            visit.photo.url, visit.photo.url,
        )

    @admin.display(description="Photo")
    def preview(self, visit):
        if not visit.photo:
            return "No photograph was taken for this visit."
        return format_html(
            '<img src="{}" style="max-width:420px;border-radius:8px" />',
            visit.photo.url,
        )

    @admin.display(description="Open in maps")
    def map_link(self, visit):
        return self.where(visit)


@admin.register(FollowUp)
class FollowUpAdmin(admin.ModelAdmin):
    list_display = ("assigned_to", "target_name", "kind", "due_at",
                    "status", "is_overdue")
    list_filter = ("status", "kind")
    search_fields = ("assigned_to__username", "lead__name", "customer__name", "note")
    date_hierarchy = "due_at"
    autocomplete_fields = ("assigned_to", "created_by", "lead", "customer", "visit")


@admin.register(Checkpoint)
class CheckpointAdmin(admin.ModelAdmin):
    """Where the salesperson has been, newest first.

    The coordinates link straight out to a map, because a pair of decimals is
    not something anyone can read as a place.
    """

    list_display = ("user", "date", "at", "where", "accuracy", "note",
                    "thumbnail")
    list_filter = ("date", "user")
    search_fields = ("user__username", "note")
    date_hierarchy = "date"
    autocomplete_fields = ("user",)
    readonly_fields = ("recorded_at", "date", "preview", "map_link")

    @admin.display(description="Time", ordering="recorded_at")
    def at(self, checkpoint):
        return checkpoint.recorded_at.strftime("%H:%M")

    @admin.display(description="Coordinates")
    def where(self, checkpoint):
        return format_html(
            '<a href="https://www.google.com/maps?q={},{}" target="_blank" '
            'rel="noopener">{}, {}</a>',
            checkpoint.lat, checkpoint.lng, checkpoint.lat, checkpoint.lng,
        )

    @admin.display(description="Accuracy")
    def accuracy(self, checkpoint):
        """A 500m fix and a 5m fix look the same once stored, and only one of
        them places him anywhere in particular."""
        if checkpoint.accuracy_m is None:
            return "—"
        return f"± {checkpoint.accuracy_m}m"

    @admin.display(description="Photo")
    def thumbnail(self, checkpoint):
        if not checkpoint.photo:
            return "—"
        return format_html(
            '<a href="{}" target="_blank" rel="noopener">'
            '<img src="{}" style="height:48px;border-radius:4px" /></a>',
            checkpoint.photo.url, checkpoint.photo.url,
        )

    @admin.display(description="Photo")
    def preview(self, checkpoint):
        if not checkpoint.photo:
            return "No photograph was attached."
        return format_html(
            '<img src="{}" style="max-width:420px;border-radius:8px" />',
            checkpoint.photo.url,
        )

    @admin.display(description="Open in maps")
    def map_link(self, checkpoint):
        return self.where(checkpoint)
