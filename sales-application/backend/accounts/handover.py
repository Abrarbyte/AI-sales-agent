"""Deactivating someone who still has work: it goes to a named person first.

Deactivation used to switch the account off and leave everything they owned
with them - open leads, booked follow-ups, customers, handovers - where nobody
could work it (#24). Now it can't happen until someone is chosen to take it
over (decided 29 Sep: the console asks who).

One place, used by every way of deactivating: the console (DELETE on the
employee endpoint), an API edit setting is_active to false, and the Django
admin site, which refuses and points to the console.
"""

from django.db import transaction


class OpenWork(Exception):
    """Raised when someone still has work and nobody was named to take it."""

    def __init__(self, person, counts):
        self.counts = counts
        super().__init__(
            f"{person.get_full_name() or person.username} still has "
            f"{describe(counts)}. Choose who takes it over.")


def _plural(n, word):
    return f"{n} {word}{'' if n == 1 else 's'}"


def describe(counts):
    parts = [_plural(counts[k], w) for k, w in (
        ("leads", "open lead"), ("followups", "booked follow-up"),
        ("customers", "customer"), ("handovers", "open handover")) if counts[k]]
    return ", ".join(parts[:-1]) + (" and " if len(parts) > 1 else "") + parts[-1]


def _querysets(person):
    from crm.models import Customer, Lead
    from delivery.models import Delivery
    from visits.models import FollowUp
    return {
        "leads": Lead.objects.filter(assigned_to=person, status__in=Lead.OPEN_STATUSES),
        "followups": FollowUp.objects.filter(assigned_to=person, status=FollowUp.Status.PENDING),
        "customers": Customer.objects.filter(assigned_to=person),
        "handovers": Delivery.objects.filter(assigned_to=person).exclude(
            status__in=Delivery.FINAL_STATUSES),
    }


def open_work(person):
    """How much each kind of work this person still owns."""
    return {name: qs.count() for name, qs in _querysets(person).items()}


def deactivate(person, *, take_over_by=None):
    """Hand this person's work to `take_over_by`, then switch them off.

    Raises OpenWork when they have work and nobody was named. Everything moves
    in one transaction, so no record is left half-moved.
    """
    counts = open_work(person)
    has_work = any(counts.values())
    if has_work and take_over_by is None:
        raise OpenWork(person, counts)
    with transaction.atomic():
        if has_work:
            from crm.negotiations import Negotiation
            open_leads = _querysets(person)["leads"]
            Negotiation.objects.filter(lead__in=open_leads, owner=person).update(owner=take_over_by)
            for qs in _querysets(person).values():
                qs.update(assigned_to=take_over_by)
        person.is_active = False
        person.save(update_fields=["is_active"])
    return counts
