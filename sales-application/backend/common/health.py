"""GET /api/health/ — is the server up and can it reach its database.

No authentication, no body to speak of: a load balancer or uptime monitor
hits it every few seconds. Returns 503 rather than 500 when the database is
unreachable so the check reads as "unhealthy", not "crashed".
"""

import logging

from django.db import connection
from django.http import JsonResponse

logger = logging.getLogger(__name__)


def health(request):
    try:
        with connection.cursor() as cursor:
            cursor.execute("SELECT 1")
        return JsonResponse({"status": "ok", "database": "ok"})
    except Exception:  # noqa: BLE001 - any failure is "unhealthy"
        # Anyone can open this page, so the reason (which names the database
        # host and user) goes to the server log, not into the reply.
        logger.exception("Health check: database unreachable")
        return JsonResponse(
            {"status": "unhealthy", "database": "unavailable"}, status=503)
