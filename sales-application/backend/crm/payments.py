"""Payments: money received from a customer, one row per payment.

The lead kept one running total, which was enough for the deposit rule. After
the sale that isn't enough: the balance is paid in parts, each with its own
date and method, and the client needs a receipt once it's all in (#41, #42).
"""

from decimal import Decimal

from django.conf import settings
from django.core.validators import MinValueValidator
from django.db import models
from django.utils import timezone


def rupees(value, symbol="₹"):
    """An amount the way it's written in India: ₹1,50,000 or ₹1,234.50.

    `symbol` is swapped for "Rs." in the PDF, whose built-in fonts have no ₹.
    """
    value = Decimal(value or 0).quantize(Decimal("0.01"))
    whole, paise = f"{abs(value):.2f}".split(".")
    if len(whole) > 3:
        head, groups = whole[:-3], [whole[-3:]]
        while len(head) > 2:
            groups.insert(0, head[-2:])
            head = head[:-2]
        whole = ",".join([head] + groups)
    return f"{'-' if value < 0 else ''}{symbol}{whole}{'' if paise == '00' else '.' + paise}"


class Payment(models.Model):
    class Method(models.TextChoices):
        UPI = "upi", "UPI"
        BANK_TRANSFER = "bank_transfer", "Bank transfer"
        CASH = "cash", "Cash"
        CHEQUE = "cheque", "Cheque"
        CARD = "card", "Card"
        OTHER = "other", "Other"

    customer = models.ForeignKey(
        "crm.Customer", on_delete=models.PROTECT, related_name="payments")
    amount = models.DecimalField(
        max_digits=12, decimal_places=2,
        validators=[MinValueValidator(Decimal("0.01"))])
    received_on = models.DateField(default=timezone.localdate)
    method = models.CharField(max_length=15, choices=Method.choices,
                              default=Method.OTHER)
    # The UTR, cheque number or card slip: what proves it arrived.
    reference = models.CharField(max_length=120, blank=True)
    notes = models.TextField(blank=True)
    # Set for a deposit paid while the customer was still a lead: which one.
    lead = models.ForeignKey(
        "crm.Lead", on_delete=models.SET_NULL, null=True, blank=True,
        related_name="payments")
    recorded_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL,
        null=True, blank=True, related_name="payments_recorded")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ("received_on", "id")

    def __str__(self):
        return f"{rupees(self.amount)} from {self.customer} on {self.received_on}"
