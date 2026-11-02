"""Shared field definitions, so a coordinate means the same thing everywhere."""

from django.core.validators import (
    MaxValueValidator, MinValueValidator, RegexValidator,
)
from django.db import models

# A dialable number: optional +, then 8-15 digits, with spaces or dashes
# allowed between groups. Rejects "abc" and "12345" without forcing one
# country's format on the field.
phone_validator = RegexValidator(
    regex=r"^\+?(?:[ -]?\d){8,15}$",
    message="Enter a valid phone number (8-15 digits, optional +).",
)


def phone_field(**kwargs):
    return models.CharField(max_length=20, validators=[phone_validator],
                            **kwargs)


def latitude_field(**kwargs):
    """Latitude in decimal degrees (-90 to 90), six places ≈ 0.1 m precision."""
    return models.DecimalField(
        max_digits=9, decimal_places=6,
        validators=[MinValueValidator(-90), MaxValueValidator(90)],
        **kwargs,
    )


def place_field(**kwargs):
    """A readable name for where a coordinate is - "Baner, Pune" - looked up
    on the phone when the fix is taken. Optional: an old app, no signal for
    the lookup, or nothing found all leave it blank, and the coordinates
    stay the record (#91)."""
    return models.CharField(max_length=255, blank=True, default="", **kwargs)


def longitude_field(**kwargs):
    """Longitude in decimal degrees (-180 to 180)."""
    return models.DecimalField(
        max_digits=10, decimal_places=6,
        validators=[MinValueValidator(-180), MaxValueValidator(180)],
        **kwargs,
    )
