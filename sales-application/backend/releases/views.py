from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import AppRelease


class LatestReleaseView(APIView):
    """GET /api/app/latest/ - the newest phone app build.

    Open to everyone: the download page and a signed-out app both need it,
    and it says nothing private - a version number and a file link.
    """

    permission_classes = [AllowAny]
    authentication_classes = []

    def get(self, request):
        release = AppRelease.objects.first()
        if release is None:
            return Response({"detail": "No app release uploaded yet."},
                            status=404)
        url = release.apk.url
        return Response({
            "version": release.version,
            "build": release.build,
            # A path on this server; the page and the app add their own host.
            "url": url if url.startswith("/") else f"/{url}",
            "notes": release.notes,
            "min_build": release.min_build,
            "size_mb": round(release.apk.size / (1024 * 1024), 1),
            "released_at": release.created_at,
        })
