"""Sign-in, with the lockout rule.

Three wrong passwords in a row are refused; the third says one attempt is
left; a fourth locks the account for 30 minutes. The right password, or an
admin setting a new one, starts the count again.

The count is kept per account, not per sender, so a guessing program gains
nothing by changing its address. The cost is that anyone who knows a username
can lock that person out for half an hour - an admin unlocks them by setting
a new password.
"""

import math
from datetime import timedelta

from django.db.models import F
from django.utils import timezone
from rest_framework import exceptions
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer
from rest_framework_simplejwt.views import TokenObtainPairView

from .models import User

WRONG_PASSWORDS_ALLOWED = 3
LOCK_MINUTES = 30

NO_MATCH = "That username and password do not match."
LAST_ATTEMPT = (f"{NO_MATCH} One attempt left: another wrong password locks "
                f"this account for {LOCK_MINUTES} minutes.")


class AccountLocked(exceptions.APIException):
    status_code = 429
    default_code = "account_locked"


class LoginSerializer(TokenObtainPairSerializer):
    def validate(self, attrs):
        account = User.objects.filter(username=attrs[self.username_field], is_active=True).first()
        if account and account.locked_until:
            left = account.locked_until - timezone.now()
            if left > timedelta(0):
                minutes = math.ceil(left / timedelta(minutes=1))
                # Refused before the password is looked at: a locked account
                # tells a guesser nothing about whether the guess was right.
                raise AccountLocked(
                    f"Too many wrong passwords. Try again in {minutes} "
                    f"minute{'' if minutes == 1 else 's'}.")
            self.save_count(account, failed_logins=0, locked_until=None)
        try:
            data = super().validate(attrs)
        except exceptions.AuthenticationFailed:
            raise self.refusal(account) from None
        if account and account.failed_logins:
            self.save_count(account, failed_logins=0)
        return data

    def refusal(self, account):
        # An unknown or switched-off username is refused the same plain way.
        if account is None:
            return exceptions.AuthenticationFailed(NO_MATCH)
        # F(): two wrong tries arriving together must both be counted.
        self.save_count(account, failed_logins=F("failed_logins") + 1)
        account.refresh_from_db(fields=["failed_logins"])
        if account.failed_logins > WRONG_PASSWORDS_ALLOWED:
            self.save_count(account, failed_logins=0,
                            locked_until=timezone.now() + timedelta(minutes=LOCK_MINUTES))
            return AccountLocked(
                f"Too many wrong passwords. This account is locked for {LOCK_MINUTES} minutes.")
        if account.failed_logins == WRONG_PASSWORDS_ALLOWED:
            return exceptions.AuthenticationFailed(LAST_ATTEMPT)
        return exceptions.AuthenticationFailed(NO_MATCH)

    @staticmethod
    def save_count(account, **values):
        User.objects.filter(pk=account.pk).update(**values)


class LoginView(TokenObtainPairView):
    serializer_class = LoginSerializer
