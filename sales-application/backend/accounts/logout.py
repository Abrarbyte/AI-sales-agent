"""Sign-out that the server knows about.

Before this the apps only forgot their tokens; the server kept accepting
them, so a copied token stayed good for up to 30 days. Now both halves die
the moment someone signs out: the refresh token is blacklisted and the access
token that made this request is recorded as revoked.
"""

from datetime import datetime, timezone as dt_timezone

from django.utils import timezone
from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.exceptions import TokenError
from rest_framework_simplejwt.settings import api_settings
from rest_framework_simplejwt.tokens import RefreshToken

from .models import RevokedAccessToken


class LogoutView(APIView):
    def post(self, request):
        raw_refresh = request.data.get("refresh")
        if raw_refresh:
            try:
                refresh = RefreshToken(raw_refresh)
                # Only your own: a token someone else holds is theirs to end.
                if str(refresh[api_settings.USER_ID_CLAIM]) == str(request.user.pk):
                    refresh.blacklist()
            except TokenError:
                pass  # already expired or blacklisted - nothing left to end

        access = request.auth
        RevokedAccessToken.objects.get_or_create(
            jti=access[api_settings.JTI_CLAIM],
            defaults={"expires_at": datetime.fromtimestamp(access["exp"], tz=dt_timezone.utc)},
        )
        # Housekeeping: an expired token is refused on its own; drop its row.
        RevokedAccessToken.objects.filter(expires_at__lt=timezone.now()).delete()
        return Response(status=status.HTTP_205_RESET_CONTENT)
