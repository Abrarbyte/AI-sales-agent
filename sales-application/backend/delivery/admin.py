from django.contrib import admin

from .models import Delivery, DeliveryAttempt


class DeliveryAttemptInline(admin.TabularInline):
    model = DeliveryAttempt
    extra = 0
    fields = ("attempted_at", "reason", "reason_note", "retry_on",
              "customer_contacted", "assigned_to")
    autocomplete_fields = ("assigned_to",)


@admin.register(Delivery)
class DeliveryAdmin(admin.ModelAdmin):
    list_display = ("customer", "product", "scheduled_on", "assigned_to",
                    "status", "delivered_at", "received_by")
    list_filter = ("status", "required")
    search_fields = ("customer__name", "customer__company_name",
                     "product__name", "received_by")
    date_hierarchy = "scheduled_on"
    autocomplete_fields = ("customer", "product", "assigned_to", "created_by")
    readonly_fields = ("created_at", "updated_at")
    inlines = (DeliveryAttemptInline,)
