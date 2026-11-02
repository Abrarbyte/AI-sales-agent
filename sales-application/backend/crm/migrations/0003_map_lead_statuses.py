"""Move existing leads onto the shorter status list.

The funnel went from six states to four. Altering the choices alone would leave
rows holding values the model no longer knows about — they would display as raw
strings and never match a filter — so the data moves with the schema.

  contacted, qualified, proposal  ->  assigned   (all mean "being worked")
  won                             ->  converted
  lost                            ->  closed
  new                             ->  new        (unchanged)
"""

from django.db import migrations

FORWARD = {
    "contacted": "assigned",
    "qualified": "assigned",
    "proposal": "assigned",
    "won": "converted",
    "lost": "closed",
}

# Reversing cannot restore which of contacted/qualified/proposal a lead was —
# that distinction is gone once merged. `assigned` goes back to `contacted`,
# the earliest of the three, so a reversed migration understates progress
# rather than overstating it.
BACKWARD = {
    "assigned": "contacted",
    "converted": "won",
    "closed": "lost",
}


def apply(mapping, apps):
    Lead = apps.get_model("crm", "Lead")
    for old, new in mapping.items():
        Lead.objects.filter(status=old).update(status=new)


def forwards(apps, schema_editor):
    apply(FORWARD, apps)


def backwards(apps, schema_editor):
    apply(BACKWARD, apps)


class Migration(migrations.Migration):

    dependencies = [
        ("crm", "0002_alter_lead_status"),
    ]

    operations = [
        migrations.RunPython(forwards, backwards),
    ]
