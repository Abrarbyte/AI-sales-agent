"""Seed the agreed launch rate so the feature works the moment it ships.

₹2.50/km was the decision of 23 Sep 2026 (see SALES_APP_WORK.md). Only inserted
if no rate exists yet, so re-running or deploying over an edited rate never
overwrites what a Super Admin has since set.
"""
from decimal import Decimal

from django.db import migrations


def seed_rate(apps, schema_editor):
    AllowanceRate = apps.get_model("allowances", "AllowanceRate")
    if AllowanceRate.objects.exists():
        return
    AllowanceRate.objects.create(
        rate_per_km=Decimal("2.50"),
        # The date the rate was agreed, so claims back to then cost correctly.
        effective_from="2026-09-23",
        note="Launch rate, agreed 23 Sep 2026.",
    )


def unseed_rate(apps, schema_editor):
    # Remove only the exact row this migration added, and only if untouched.
    AllowanceRate = apps.get_model("allowances", "AllowanceRate")
    AllowanceRate.objects.filter(
        effective_from="2026-09-23",
        rate_per_km=Decimal("2.50"),
        note="Launch rate, agreed 23 Sep 2026.",
    ).delete()


class Migration(migrations.Migration):

    dependencies = [
        ("allowances", "0001_initial"),
    ]

    operations = [
        migrations.RunPython(seed_rate, unseed_rate),
    ]
