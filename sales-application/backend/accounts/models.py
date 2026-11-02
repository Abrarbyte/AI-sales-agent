from django.contrib.auth.models import AbstractUser, UserManager as DjangoUserManager
from django.core.exceptions import ValidationError

from common.fields import phone_field
from django.db import models


class UserManager(DjangoUserManager):
    """Keeps `role` in step with Django's own superuser flag.

    Permission here is decided by `role`, not by `is_superuser` - but
    `manage.py createsuperuser` knows nothing about `role`, so it used to
    produce an account that was a Django superuser and still an `employee`
    to us. That account could reach the Django admin and was turned away by
    the console, which is a confusing first five minutes for whoever is
    deploying. A superuser is now a super_admin unless told otherwise.
    """

    def create_superuser(self, *args, **kwargs):
        kwargs.setdefault("role", self.model.Role.SUPER_ADMIN)
        return super().create_superuser(*args, **kwargs)


class User(AbstractUser):
    class Role(models.TextChoices):
        SUPER_ADMIN = "super_admin"
        ADMIN = "admin"
        # Team leader == manager while the team is ~10 people.
        # Add TEAM_LEADER = "team_leader" as a separate choice if the team grows.
        MANAGER = "manager"
        EMPLOYEE = "employee"

    # Role groups, defined once. Every permission check, admin filter, and
    # queryset rule reads from these — so adding a role means editing one place.
    ADMIN_ROLES = (Role.ADMIN, Role.SUPER_ADMIN)
    MANAGER_ROLES = (Role.MANAGER,) + ADMIN_ROLES

    objects = UserManager()

    role = models.CharField(max_length=20, choices=Role.choices, default=Role.EMPLOYEE)
    phone = phone_field(blank=True)
    manager = models.ForeignKey(
        "self", null=True, blank=True,
        on_delete=models.SET_NULL, related_name="team_members",
    )
    # Sign-in lockout: wrong passwords in a row, and until when the account
    # is locked. The rule itself is in accounts/login.py.
    failed_logins = models.PositiveSmallIntegerField(default=0, editable=False)
    locked_until = models.DateTimeField(null=True, blank=True, editable=False)
# Added clean method to prevent a user from being their own manager
#but during update or bluk update it can cause the MANAGER loop
    def clean(self):
        super().clean()
        if self.manager_id is not None and self.manager_id == self.id:
            raise ValidationError({"manager": "A user cannot be their own manager."})

    def visible_users(self):
        """Which people this user may see. Every module's visibility rule is
        built on this, so it is defined here and nowhere else."""
        if self.role in self.ADMIN_ROLES:
            return User.objects.all()
        if self.role == self.Role.MANAGER:
            return User.objects.filter(models.Q(id=self.id) | models.Q(manager=self))
        return User.objects.filter(id=self.id)

    def __str__(self):
        return f"{self.username} ({self.role})"


class RevokedAccessToken(models.Model):
    """An access token signed out before it expired.

    simplejwt's blacklist only covers refresh tokens; an access token is
    checked by signature alone, so a copy of one would keep working for the
    rest of its eight hours after the person signed out. Its id is kept here
    until then, and accounts/authentication.py refuses it. Per token, not per
    person: signing out on the laptop leaves the phone signed in.
    """

    jti = models.CharField(max_length=255, unique=True)
    expires_at = models.DateTimeField(db_index=True)
