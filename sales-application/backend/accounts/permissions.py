from rest_framework.permissions import BasePermission

from .models import User


class RoleInPermission(BasePermission):
    """Base for role checks. Subclasses set `allowed_roles`.

    The `is_authenticated` check comes first: an anonymous request carries an
    AnonymousUser, which has no `role` attribute at all.
    """

    allowed_roles = ()

    def has_permission(self, request, view):
        return (
            request.user.is_authenticated
            and request.user.role in self.allowed_roles
        )


class IsAdminOrSuperAdmin(RoleInPermission):
    allowed_roles = User.ADMIN_ROLES


class IsManagerOrAbove(RoleInPermission):
    allowed_roles = User.MANAGER_ROLES
