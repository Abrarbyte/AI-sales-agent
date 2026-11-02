from django.contrib import admin

from .models import DailyReport


@admin.register(DailyReport)
class DailyReportAdmin(admin.ModelAdmin):
    list_display = ("user", "date", "checked_in", "hours_worked",
                    "visits_count", "leads_created", "followups_completed")
    list_filter = ("date", "checked_in", "user__role")
    search_fields = ("user__username", "user__first_name", "user__last_name")
    date_hierarchy = "date"
    autocomplete_fields = ("user",)

    def has_add_permission(self, request):
        # Reports are computed by the evening job, never typed in.
        return False
