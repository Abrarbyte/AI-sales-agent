"""Seed the catalogue with what a web/app agency sells.

    manage.py seed_services

Idempotent: existing names are left alone, so it is safe on a live database
and at every deploy (deploy-entrypoint runs it after migrate).
"""
from django.core.management.base import BaseCommand

from crm.models import Product

SERVICES = [
    ("Website (static)", "product"),
    ("Website (CMS)", "product"),
    ("E-commerce website", "product"),
    ("Android app", "product"),
    ("iOS app", "product"),
    ("Web app", "product"),
    ("UI/UX design", "service"),
    ("Website redesign", "service"),
    ("Annual maintenance", "service"),
    ("Hosting & domain", "service"),
    ("SEO", "service"),
]


class Command(BaseCommand):
    help = "Create the default website/app services in the product catalogue."

    def handle(self, *args, **options):
        created = 0
        for name, kind in SERVICES:
            _, was_created = Product.objects.get_or_create(
                name=name, defaults={"kind": kind})
            created += was_created
        self.stdout.write(f"{created} added, {len(SERVICES) - created} already present")
