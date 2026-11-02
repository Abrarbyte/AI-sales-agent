"""Where notifications come from.

Signals rather than calls inside each view: a lead can be reassigned from the
API, the admin panel, or a future import script, and all three should notify
the new owner. Hooking the model keeps that promise in one place.
"""

from django.db.models.signals import post_save, pre_save
from django.dispatch import receiver

from crm.models import Lead
from visits.models import FollowUp

from .models import Notification


@receiver(pre_save, sender=Lead)
def remember_previous_assignee(sender, instance, **kwargs):
    """Stash who owned this lead before the save, so post_save can tell whether
    the assignment actually changed rather than notifying on every edit."""
    if instance.pk:
        previous = sender.objects.filter(pk=instance.pk).only(
            "assigned_to_id").first()
        instance._previous_assignee_id = previous.assigned_to_id if previous else None
    else:
        instance._previous_assignee_id = None


@receiver(post_save, sender=Lead)
def notify_lead_assigned(sender, instance, created, **kwargs):
    previous_id = getattr(instance, "_previous_assignee_id", None)
    new_id = instance.assigned_to_id

    if new_id is None or new_id == previous_id:
        return
    # Don't tell someone they assigned a lead to themselves.
    if created and new_id == instance.created_by_id:
        return

    Notification.notify(
        instance.assigned_to,
        title=f"Lead assigned: {instance.name}",
        kind=Notification.Kind.LEAD_ASSIGNED,
        body=instance.company_name or instance.phone,
        link=f"/leads/{instance.pk}",
    )


@receiver(post_save, sender=FollowUp)
def notify_followup_assigned(sender, instance, created, **kwargs):
    """Tell someone when a follow-up is scheduled *for* them by someone else."""
    if not created or instance.assigned_to_id == instance.created_by_id:
        return

    Notification.notify(
        instance.assigned_to,
        title=f"Follow-up: {instance.target_name}",
        kind=Notification.Kind.FOLLOWUP_DUE,
        body=instance.note or f"{instance.get_kind_display()} due "
                              f"{instance.due_at:%d %b %H:%M}",
        link=f"/followups/{instance.pk}",
    )
