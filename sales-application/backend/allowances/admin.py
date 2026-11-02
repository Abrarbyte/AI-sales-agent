from django.contrib import admin
from django.utils import timezone

from .models import AllowanceRate, TravelClaim


@admin.register(AllowanceRate)
class AllowanceRateAdmin(admin.ModelAdmin):
    list_display = ("rate_per_km", "effective_from", "updated_by", "created_at")
    list_filter = ("effective_from",)
    date_hierarchy = "effective_from"
    autocomplete_fields = ("updated_by",)

    def save_model(self, request, obj, form, change):
        # Stamp who set the rate without making them fill it in by hand.
        if obj.updated_by_id is None:
            obj.updated_by = request.user
        super().save_model(request, obj, form, change)


@admin.register(TravelClaim)
class TravelClaimAdmin(admin.ModelAdmin):
    list_display = ("user", "date", "distance_km", "rate_per_km", "amount",
                    "method", "is_estimate", "status", "approved_by")
    list_filter = ("status", "method", "is_estimate", "date")
    search_fields = ("user__username", "user__first_name", "user__last_name")
    date_hierarchy = "date"
    autocomplete_fields = ("user", "approved_by")
    # The money figures are a frozen snapshot - editing them by hand would
    # detach the amount from the distance and rate that produced it.
    readonly_fields = ("distance_km", "rate_per_km", "amount", "method",
                       "is_estimate", "flagged_legs", "created_at", "updated_at")
    actions = ("approve_selected",)

    @admin.action(description="Approve selected claims")
    def approve_selected(self, request, queryset):
        pending = queryset.exclude(status=TravelClaim.Status.APPROVED)
        updated = pending.update(
            status=TravelClaim.Status.APPROVED,
            approved_by=request.user,
            reviewed_at=timezone.now(),
        )
        self.message_user(request, f"{updated} claim(s) approved.")
