"""Take the retail version's "Solar 5kW" out of the catalogue (#51).

Deleted where nothing uses it. Where a customer or a handover milestone
still points at it, it's switched off instead: those records keep their
history, and it no longer appears among the products to choose from.
"""

from django.db import migrations

RETAIL_PRODUCTS = ("Solar 5kW",)


def retire_retail_products(apps, schema_editor):
    Product = apps.get_model("crm", "Product")
    Delivery = apps.get_model("delivery", "Delivery")
    Customer = apps.get_model("crm", "Customer")
    for name in RETAIL_PRODUCTS:
        for product in Product.objects.filter(name__iexact=name):
            used = (Delivery.objects.filter(product=product).exists()
                    or Customer.objects.filter(products=product).exists())
            if used:
                product.is_active = False
                product.save(update_fields=["is_active"])
            else:
                product.delete()


class Migration(migrations.Migration):

    dependencies = [
        ("crm", "0016_remove_demo_interested"),
        ("delivery", "0003_outcome_notes_and_project_status"),
    ]

    operations = [
        migrations.RunPython(retire_retail_products, migrations.RunPython.noop),
    ]
