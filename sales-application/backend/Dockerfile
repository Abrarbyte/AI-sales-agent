# Sales API - Django under gunicorn.
#
#   docker build -t sales-api ./backend
#
# The same image runs the API (default command) and the scheduler
# (`manage.py run_scheduler`); docker-compose.yml wires both.

FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

# libpq for psycopg2, curl for the health check.
RUN apt-get update \
 && apt-get install -y --no-install-recommends libpq5 curl \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY . .
# A Windows checkout loses the execute bit, and Git there rewrites text
# files to CRLF. A shell script whose first line ends in a carriage return
# makes the kernel look for an interpreter with CR in its name; it finds
# nothing and the container exits immediately. Strip the carriage returns
# and restore the execute bit, so the image is right however the source was
# checked out. .gitattributes prevents it at the source; this is the belt
# to that pair of braces.
RUN tr -d '\015' < deploy-entrypoint.sh > /tmp/entrypoint.sh \
 && mv /tmp/entrypoint.sh deploy-entrypoint.sh \
 && chmod +x deploy-entrypoint.sh

# Uploads and collected static live on volumes, outside the image.
RUN mkdir -p /data/media /data/static \
 && useradd --create-home --uid 1000 app \
 && chown -R app:app /app /data
USER app

ENV MEDIA_ROOT=/data/media \
    STATIC_ROOT=/data/static \
    DJANGO_SETTINGS_MODULE=config.settings

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD curl -fsS http://localhost:8000/api/health/ || exit 1

ENTRYPOINT ["./deploy-entrypoint.sh"]
CMD ["web"]
