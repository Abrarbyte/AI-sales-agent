from rest_framework_simplejwt.authentication import JWTAuthentication
from rest_framework_simplejwt.exceptions import InvalidToken
from rest_framework_simplejwt.settings import api_settings

from .models import RevokedAccessToken


class RevocableJWTAuthentication(JWTAuthentication):
    """JWT auth that also refuses access tokens signed out early (see
    RevokedAccessToken)."""

    def get_validated_token(self, raw_token):
        token = super().get_validated_token(raw_token)
        if RevokedAccessToken.objects.filter(jti=token[api_settings.JTI_CLAIM]).exists():
            raise InvalidToken("This session has been signed out.")
        return token
