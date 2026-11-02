from django import forms
from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin

from .handover import describe, open_work
from .models import User


class SalesUserChangeForm(BaseUserAdmin.form):
    def clean(self):
        cleaned = super().clean()
        # Unticking "active" here would leave their work with nobody (#24).
        # The console asks who takes it over, so send people there.
        if self.instance.pk and self.instance.is_active and cleaned.get("is_active") is False:
            counts = open_work(self.instance)
            if any(counts.values()):
                raise forms.ValidationError(
                    f"{self.instance.username} still has {describe(counts)}. "
                    "Deactivate them from the admin console, which asks who takes it over.")
        return cleaned


@admin.register(User)
class UserAdmin(BaseUserAdmin):
    form = SalesUserChangeForm
    list_display = ("username", "first_name", "last_name", "role", "manager", "is_active")
    list_filter = ("role", "is_active", "is_staff")
    search_fields = ("username", "first_name", "last_name", "email", "phone")

    fieldsets = BaseUserAdmin.fieldsets + (
        ("Sales team details", {"fields": ("role", "phone", "manager")}),
    )
    add_fieldsets = BaseUserAdmin.add_fieldsets + (
        ("Sales team details", {"fields": ("role", "phone", "manager")}),
    )

    def formfield_for_foreignkey(self, db_field, request, **kwargs):
        if db_field.name == "manager":
            kwargs["queryset"] = User.objects.filter(role__in=User.MANAGER_ROLES)
        return super().formfield_for_foreignkey(db_field, request, **kwargs)
