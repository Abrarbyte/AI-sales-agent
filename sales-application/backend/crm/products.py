"""Products: what the company sells.

A short catalogue rather than free text on every record, so "Website (CMS)"
and "website cms" cannot become two different things in a report.
"""

from django.db import models


class Product(models.Model):
    class Kind(models.TextChoices):
        PRODUCT = "product"
        SERVICE = "service"

    name = models.CharField(max_length=120, unique=True)
    kind = models.CharField(max_length=10, choices=Kind.choices, default=Kind.PRODUCT)
    is_active = models.BooleanField(default=True)

    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ("name",)

    def __str__(self):
        return self.name
