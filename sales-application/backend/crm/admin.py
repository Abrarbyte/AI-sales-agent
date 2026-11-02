from django.contrib import admin

from .models import Customer, Demo, Lead, Negotiation, Payment, Product


class SetsCreatorMixin:
    """Fills in created_by with whoever adds the record here. Leads added
    through this site with no owner used to have no creator either, and so
    were visible to nobody (#13)."""

    def save_model(self, request, obj, form, change):
        if not change and obj.created_by_id is None:
            obj.created_by = request.user
        super().save_model(request, obj, form, change)


@admin.register(Product)
class ProductAdmin(admin.ModelAdmin):
    list_display = ("name", "kind", "is_active")
    list_filter = ("kind", "is_active")
    search_fields = ("name",)


@admin.register(Lead)
class LeadAdmin(SetsCreatorMixin, admin.ModelAdmin):
    list_display = ("name", "company_name", "project_type", "priority",
                    "phone", "status", "source",
                    "assigned_to", "created_at")
    list_filter = ("status", "project_type", "priority", "source", "city")
    search_fields = ("name", "company_name", "phone", "email", "requirement")
    autocomplete_fields = ("assigned_to", "created_by")
    readonly_fields = ("converted_customer", "converted_at", "created_at", "updated_at")

    def has_delete_permission(self, request, obj=None):
        # Nobody deletes these - mark a lead lost, deactivate a customer (#26).
        return False


@admin.register(Demo)
class DemoAdmin(SetsCreatorMixin, admin.ModelAdmin):
    list_display = ("lead", "product", "held_at", "outcome", "given_by")
    list_filter = ("outcome",)
    search_fields = ("lead__name", "lead__company_name", "product")
    date_hierarchy = "held_at"
    autocomplete_fields = ("lead", "given_by", "created_by", "followup")
    readonly_fields = ("created_at", "updated_at")


@admin.register(Negotiation)
class NegotiationAdmin(SetsCreatorMixin, admin.ModelAdmin):
    list_display = ("lead", "status", "decision_maker", "started_at",
                    "expected_close_on", "owner")
    list_filter = ("status",)
    search_fields = ("lead__name", "lead__company_name", "decision_maker")
    autocomplete_fields = ("lead", "owner", "created_by", "followup")
    readonly_fields = ("created_at", "updated_at")


class PaymentInline(admin.TabularInline):
    # Where a wrongly entered payment is put right: the API only adds them.
    model = Payment
    extra = 0
    fields = ("received_on", "amount", "method", "reference", "notes", "lead",
              "recorded_by")
    raw_id_fields = ("lead", "recorded_by")


@admin.register(Customer)
class CustomerAdmin(SetsCreatorMixin, admin.ModelAdmin):
    list_display = ("name", "company_name", "phone", "city", "assigned_to",
                    "customer_since", "support_status", "is_active")
    list_filter = ("is_active", "support_status", "city")
    search_fields = ("name", "company_name", "phone", "email")
    autocomplete_fields = ("assigned_to", "created_by")
    filter_horizontal = ("products",)
    inlines = (PaymentInline,)
    # Worked out from the handover milestones (#47).
    readonly_fields = ("project_status", "created_at", "updated_at")

    def has_delete_permission(self, request, obj=None):
        # Nobody deletes these - mark a lead lost, deactivate a customer (#26).
        return False
