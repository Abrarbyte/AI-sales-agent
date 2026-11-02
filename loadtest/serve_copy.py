"""Start the TEST COPY: the same code on the sales_tracker_loadtest database,
as 3 one-request-at-a-time worker processes on ports 8011-8013 - the shape of
the office server's gunicorn (3 sync workers). Ctrl+C or kill to stop."""
import os
import subprocess
import sys

BACKEND = r"C:\dev\Sales-Application\backend"
env = dict(os.environ,
           DB_NAME="sales_tracker_loadtest", DEBUG="false",
           ALLOWED_HOSTS="127.0.0.1,localhost",
           # Every virtual user signs in from this one machine; the per-IP
           # sign-in limit (20/min) would block the test itself.
           THROTTLE_ANON="100000/min")
procs = [subprocess.Popen(
    [os.path.join(BACKEND, "venv", "Scripts", "python.exe"), "-m", "waitress",
     "--listen", f"127.0.0.1:{port}", "--threads", "1", "--connection-limit", "400",
     "--backlog", "1024", "config.wsgi:application"],
    cwd=BACKEND, env=env) for port in (8011, 8012, 8013)]
print("test copy on 8011-8013, pids", [p.pid for p in procs], flush=True)
try:
    for p in procs:
        p.wait()
except KeyboardInterrupt:
    for p in procs:
        p.terminate()
    sys.exit(0)
