"""Scheduling notes survive delivery (#45), and every project's status is
worked out again from its milestones (#46, #47).

The audit found a customer showing "Not started" with its go-live done:
status was moved by delivering a milestone, and could be edited by hand, so
the two drifted. A customer with no milestones at all keeps what was entered
- there is nothing to work it out from.
"""

from collections import defaultdict

from django.db import migrations, models
from django.utils import timezone

STAGES = ("not_started", "design", "development", "uat", "live")
PROVES = {
    "design_approval": "development",
    "development_complete": "uat",
    "uat": "uat",
    "go_live": "live",
    "handover": "live",
}


def status_from(milestones):
    # A copy of delivery.models.project_status_from as written today;
    # migrations mustn't depend on code that may change.
    counted = [(m, s) for m, s, _ in milestones if s != "cancelled"]
    if not counted:
        return "not_started"
    reached = "design"
    for milestone, status in counted:
        target = PROVES.get(milestone)
        if status == "delivered" and target and STAGES.index(target) > STAGES.index(reached):
            reached = target
    return reached


def repair_project_status(apps, schema_editor):
    Customer = apps.get_model("crm", "Customer")
    Delivery = apps.get_model("delivery", "Delivery")
    by_customer = defaultdict(list)
    for customer_id, milestone, status, at in Delivery.objects.values_list(
            "customer_id", "milestone", "status", "delivered_at"):
        by_customer[customer_id].append((milestone, status, at))
    for customer_id, milestones in by_customer.items():
        status = status_from(milestones)
        Customer.objects.filter(pk=customer_id).exclude(
            project_status=status).update(project_status=status)
        if status == "live":
            went_live = [at for m, s, at in milestones
                         if s == "delivered" and at and PROVES.get(m) == "live"]
            if went_live:
                Customer.objects.filter(pk=customer_id, go_live_on__isnull=True).update(
                    go_live_on=timezone.localtime(min(went_live)).date())


class Migration(migrations.Migration):

    dependencies = [
        ("delivery", "0002_web_agency_pipeline"),
        ("crm", "0013_price_from_quote"),
    ]

    operations = [
        migrations.AddField(
            model_name="delivery",
            name="outcome_notes",
            field=models.TextField(blank=True),
        ),
        # Old delivered/cancelled rows keep their notes where they are: there
        # is no telling which part was written when.
        migrations.RunPython(repair_project_status, migrations.RunPython.noop),
    ]
