from django.contrib import admin

from .models import Attendance


@admin.register(Attendance)
class AttendanceAdmin(admin.ModelAdmin):
    list_display = ("user", "date", "kind", "check_in_at", "check_out_at",
                    "hours_worked")
    list_filter = ("kind", "date", "user__role")
    search_fields = ("user__username", "user__first_name", "user__last_name")
    date_hierarchy = "date"
    autocomplete_fields = ("user",)
