from django.contrib import admin

from .models import Notification


@admin.register(Notification)
class NotificationAdmin(admin.ModelAdmin):
    list_display = ("user", "kind", "title", "is_read", "created_at")
    list_filter = ("kind", "read_at")
    search_fields = ("user__username", "title", "body")
    autocomplete_fields = ("user",)
