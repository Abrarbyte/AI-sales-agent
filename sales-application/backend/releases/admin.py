from django.contrib import admin

from .models import AppRelease


@admin.register(AppRelease)
class AppReleaseAdmin(admin.ModelAdmin):
    list_display = ("version", "build", "min_build", "created_at")
    readonly_fields = ("created_at",)
    fields = ("version", "build", "apk", "notes", "min_build", "created_at")
