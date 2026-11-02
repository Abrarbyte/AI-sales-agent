from rest_framework import serializers

from .guards import check_change, check_create
from .models import User


class UserSerializer(serializers.ModelSerializer):
    """A person, as every screen needs to show them.

    `role` and `manager` are stored as a code and an id; a profile screen wants
    a name and a label. Both are resolved here rather than by a second request
    per row, which is what a list of twenty employees would otherwise cost.
    """

    full_name = serializers.SerializerMethodField()
    role_display = serializers.CharField(source="get_role_display",
                                         read_only=True)
    manager_name = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = ("id", "username", "first_name", "last_name", "full_name",
                  "email", "phone", "role", "role_display",
                  "manager", "manager_name",
                  # Read-only lifecycle fields. The admin console renders an
                  # active/inactive chip per person and sorts reps by tenure,
                  # neither of which it can do from the profile fields alone.
                  "is_active", "date_joined", "last_login")
        read_only_fields = ("role", "manager", "is_active", "date_joined",
                            "last_login")

    def get_full_name(self, user):
        """Falls back to the username: an account created without a first or
        last name still has to render as something."""
        return user.get_full_name() or user.username

    def get_manager_name(self, user):
        manager = user.manager
        if manager is None:
            return None
        return manager.get_full_name() or manager.username


class EmployeeWriteSerializer(serializers.ModelSerializer):
    """Used by admins to create/update staff accounts — unlike UserSerializer,
    role and manager are writable here."""

    password = serializers.CharField(write_only=True, required=False, min_length=8)
    # Who takes over their open work when is_active is set to false (#24).
    transfer_to = serializers.IntegerField(write_only=True, required=False)

    class Meta:
        model = User
        fields = ("id", "username", "first_name", "last_name", "email", "phone",
                  "role", "manager", "is_active", "password", "transfer_to")

    def validate(self, attrs):
        # Who may change whom: accounts/guards.py.
        requester = self.context["request"].user
        if self.instance is None:
            check_create(requester, attrs.get("role"))
        else:
            check_change(
                requester, self.instance,
                new_role=attrs.get("role"),
                deactivating=(self.instance.is_active
                              and attrs.get("is_active") is False),
            )
        return attrs

    def validate_manager(self, manager):
        if manager is not None and manager.role not in User.MANAGER_ROLES:
            raise serializers.ValidationError(
                "Manager must have the Manager, Admin, or Super Admin role.")
        return manager

    def create(self, validated_data):
        validated_data.pop("transfer_to", None)
        password = validated_data.pop("password", None)
        user = User(**validated_data)
        if password:
            user.set_password(password)
        else:
            user.set_unusable_password()
        user.full_clean(exclude=["password"])
        user.save()
        return user

    def update(self, instance, validated_data):
        # A username is what someone signs in with: fixed once the account
        # exists, so an edit can never change it by accident.
        validated_data.pop("username", None)
        password = validated_data.pop("password", None)
        transfer_to = validated_data.pop("transfer_to", None)
        if instance.is_active and validated_data.get("is_active") is False:
            # Switching someone off goes through the handover, however it is
            # requested, so their work is never left with nobody (#24).
            from .handover import OpenWork, deactivate
            from .views import valid_successor
            take_over_by = None
            if transfer_to is not None:
                take_over_by = valid_successor(self.context["request"].user, instance, transfer_to)
                if take_over_by is None:
                    raise serializers.ValidationError({"transfer_to": (
                        "Choose an active person, other than the one being deactivated.")})
            try:
                deactivate(instance, take_over_by=take_over_by)
            except OpenWork as e:
                raise serializers.ValidationError({"is_active": str(e)})
            validated_data.pop("is_active")
        for field, value in validated_data.items():
            setattr(instance, field, value)
        if password:
            instance.set_password(password)
            # A new password from an admin is also how a locked account is
            # let back in (accounts/login.py).
            instance.failed_logins, instance.locked_until = 0, None
        instance.full_clean(exclude=["password"])
        instance.save()
        return instance
