"""A quote can't be negative, a discount is 0-100%, and deals already being
negotiated get their price from the quote (#29).

Three deals in the audit's second round were in negotiation with a quote but
no price on the lead, so the console showed no value and totals left them out.
From now on the quote fills the price as it is saved; this does the same once
for what is already there.
"""

from decimal import ROUND_HALF_UP, Decimal

import django.core.validators
from django.db import migrations, models

OPEN_STATUSES = ("new", "demo", "negotiation", "proposal")


def price_after_discount(quoted, discount_pct):
    # A copy of crm.negotiations.price_after_discount as it was when this
    # migration was written; migrations mustn't depend on code that may change.
    off = (discount_pct or Decimal("0")) / 100
    return (quoted * (1 - off)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def fill_price_from_quote(apps, schema_editor):
    """Open leads with no price take what their quote comes to. A lead with a
    price keeps it; a customer's or a lost lead's is history, left alone."""
    Negotiation = apps.get_model("crm", "Negotiation")
    Lead = apps.get_model("crm", "Lead")
    quoted = (Negotiation.objects
              .filter(quoted_amount__isnull=False, lead__value__isnull=True,
                      lead__status__in=OPEN_STATUSES)
              .values_list("lead_id", "quoted_amount", "discount_pct"))
    for lead_id, amount, discount in quoted:
        price = price_after_discount(amount, discount)
        if Decimal("0") <= price:
            Lead.objects.filter(pk=lead_id, value__isnull=True).update(value=price)


class Migration(migrations.Migration):

    dependencies = [
        ('crm', '0012_simpler_stages'),
    ]

    operations = [
        migrations.AlterField(
            model_name='negotiation',
            name='discount_pct',
            field=models.DecimalField(blank=True, decimal_places=2, max_digits=5, null=True, validators=[django.core.validators.MinValueValidator(0), django.core.validators.MaxValueValidator(100)]),
        ),
        migrations.AlterField(
            model_name='negotiation',
            name='quoted_amount',
            field=models.DecimalField(blank=True, decimal_places=2, max_digits=12, null=True, validators=[django.core.validators.MinValueValidator(0)]),
        ),
        # Undoing leaves the filled prices: they are the quote's, and a price
        # someone has since relied on shouldn't vanish.
        migrations.RunPython(fill_price_from_quote, migrations.RunPython.noop),
    ]
