"""Strictly one field each (#48, decided 29 Sep).

What the client wants was typed in four places - the lead's requirement, and
the negotiation's requirements, scope and proposed solution. Payment terms
were in three - the terms choice, a note, and free-text terms. Now: the
lead's requirement, and the terms choice plus one note.

Nothing typed is lost. Before the old columns go, their text is added to
the field that stays, labelled, and skipped where it's already there.
"""

from django.db import migrations, models


def merged(base, additions):
    """`base` with each (label, text) added on its own line, unless the text
    is empty or already in it. Also used by the tests."""
    lines = [base.strip()] if base.strip() else []
    for label, text in additions:
        text = (text or "").strip()
        if text and not any(text in line for line in lines):
            lines.append(f"{label}{text}")
    return "\n".join(lines)


def fold_into_one_field(apps, schema_editor):
    Negotiation = apps.get_model("crm", "Negotiation")
    Lead = apps.get_model("crm", "Lead")
    for n in Negotiation.objects.select_related("lead"):
        requirement = merged(n.lead.requirement, [
            ("", n.requirements), ("Scope: ", n.scope),
            ("Proposed: ", n.proposed_solution)])
        if requirement != n.lead.requirement:
            Lead.objects.filter(pk=n.lead_id).update(requirement=requirement)
        note = merged(n.payment_terms_note, [("", n.terms)])
        if note != n.payment_terms_note:
            Negotiation.objects.filter(pk=n.pk).update(payment_terms_note=note)


class Migration(migrations.Migration):

    dependencies = [
        ("crm", "0017_retire_retail_products"),
    ]

    operations = [
        # Longer first: folded-in terms may not fit the old 255 characters.
        migrations.AlterField(
            model_name="negotiation",
            name="payment_terms_note",
            field=models.TextField(blank=True),
        ),
        # Undoing brings the columns back empty; the text stays where it went.
        migrations.RunPython(fold_into_one_field, migrations.RunPython.noop),
        migrations.RemoveField(model_name="negotiation", name="proposed_solution"),
        migrations.RemoveField(model_name="negotiation", name="requirements"),
        migrations.RemoveField(model_name="negotiation", name="scope"),
        migrations.RemoveField(model_name="negotiation", name="terms"),
    ]
