"""Who may switch off, re-role or edit whom.

Being an admin lets you manage people - but not every person. Before these
rules any admin could deactivate a super admin, promote anyone (themselves
included) to super admin, and a super admin could deactivate their own
account - even the last one, leaving nobody able to manage the top role.

Checked on the server, on every route that changes a person (create, edit,
deactivate), so no screen can get around it. A rule that depends on who is
asking is a 403; a rule about the state it would leave behind is a 400.
"""

from rest_framework.exceptions import PermissionDenied, ValidationError

from .models import User

SUPER = User.Role.SUPER_ADMIN

NOT_YOURSELF = "You can't deactivate your own account."
NOT_YOUR_ROLE = "You can't change your own role."
ONLY_SUPER_EDITS_SUPER = "Only a super admin can change a super admin's account."
ONLY_SUPER_MAKES_SUPER = "Only a super admin can give the super admin role."
LAST_SUPER = "At least one active super admin must remain."


def _is_last_active_super(person):
    return (person.role == SUPER and person.is_active
            and not User.objects.filter(role=SUPER, is_active=True)
            .exclude(pk=person.pk).exists())


def check_create(requester, role):
    if role == SUPER and requester.role != SUPER:
        raise PermissionDenied(ONLY_SUPER_MAKES_SUPER)


def check_change(requester, person, *, new_role=None, deactivating=False):
    """Raise if `requester` may not make this change to `person`.

    `new_role` is the role being set (None when the role is not changing).
    """
    if person.role == SUPER and requester.role != SUPER:
        raise PermissionDenied(ONLY_SUPER_EDITS_SUPER)
    if deactivating:
        if person.pk == requester.pk:
            raise ValidationError({"detail": NOT_YOURSELF})
        if _is_last_active_super(person):
            raise ValidationError({"detail": LAST_SUPER})
    if new_role is not None and new_role != person.role:
        if person.pk == requester.pk:
            raise ValidationError({"role": NOT_YOUR_ROLE})
        if new_role == SUPER and requester.role != SUPER:
            raise PermissionDenied(ONLY_SUPER_MAKES_SUPER)
        if _is_last_active_super(person):
            raise ValidationError({"role": LAST_SUPER})
