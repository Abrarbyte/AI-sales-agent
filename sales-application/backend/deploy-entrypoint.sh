#!/bin/sh
# Container entrypoint. `web` migrates, collects static and serves;
# `scheduler` runs the periodic jobs; anything else is passed to manage.py.
set -e

wait_for_db() {
  # Postgres in compose can take a few seconds to accept connections.
  for i in $(seq 1 30); do
    if python -c "import django,os; os.environ.setdefault('DJANGO_SETTINGS_MODULE','config.settings'); django.setup(); from django.db import connection; connection.ensure_connection()" 2>/dev/null; then
      return 0
    fi
    echo "waiting for database ($i)..."
    sleep 2
  done
  echo "database not reachable" >&2
  exit 1
}

case "$1" in
  web)
    wait_for_db
    python manage.py migrate --noinput
    python manage.py collectstatic --noinput
    python manage.py seed_services
    exec gunicorn config.wsgi:application \
      --bind 0.0.0.0:8000 \
      --workers "${WEB_CONCURRENCY:-3}" \
      --timeout 60 \
      --access-logfile - \
      --error-logfile -
    ;;
  scheduler)
    wait_for_db
    exec python manage.py run_scheduler
    ;;
  *)
    exec python manage.py "$@"
    ;;
esac
