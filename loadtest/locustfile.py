"""Load test for the SalesHub TEST COPY (ports 8011-8013, database
sales_tracker_loadtest). Never point this at the live server: it writes
follow-ups and edits lead notes.

    locust -f locustfile.py --headless -u 100 -r 10 -t 150s --host http://127.0.0.1

PACE=stress  each user tries 3 requests a second (the 300 req/s target)
PACE=normal  each user pauses 2-6 seconds between taps, like a person
"""
import itertools
import os
import random
from datetime import datetime, timedelta, timezone

from locust import HttpUser, between, constant_throughput, task

PORTS = itertools.cycle((8011, 8012, 8013))   # nginx would spread these
REPS = itertools.cycle(range(100))
MANAGERS = itertools.cycle(range(10))
PASSWORD = "loadtest-pw-123"
PACE = constant_throughput(3) if os.environ.get("PACE", "stress") == "stress" else between(2, 6)


class Person(HttpUser):
    abstract = True
    wait_time = PACE
    username = ""

    @property
    def base(self):
        # A different worker each request, as the real server's shared queue
        # would hand it to whichever is free (it does slightly better).
        return f"http://127.0.0.1:{next(PORTS)}"

    def on_start(self):
        r = self.client.post(f"{self.base}/api/auth/login/", name="sign in",
                             json={"username": self.username, "password": PASSWORD})
        self.auth = {"Authorization": f"Bearer {r.json()['access']}"}
        self.lead_ids = []

    def get(self, path, name):
        return self.client.get(self.base + path, headers=self.auth, name=name)


class Rep(Person):
    """A salesperson on the phone app: mostly reading their own work."""
    weight = 90

    def on_start(self):
        self.username = f"lt_rep{next(REPS)}"
        super().on_start()

    @task(5)
    def my_leads(self):
        r = self.get("/api/crm/leads/", "app: my leads")
        if r.ok:
            rows = r.json()
            rows = rows if isinstance(rows, list) else rows.get("results", [])
            self.lead_ids = [row["id"] for row in rows if row["status"] != "closed"]

    @task(5)
    def one_lead(self):
        if self.lead_ids:
            self.get(f"/api/crm/leads/{random.choice(self.lead_ids)}/", "app: one lead")

    @task(3)
    def my_followups(self):
        self.get("/api/visits/followups/", "app: my follow-ups")

    @task(2)
    def my_customers(self):
        self.get("/api/crm/customers/?active=true", "app: my customers")

    @task(2)
    def my_day(self):
        self.get("/api/analytics/dashboard/me/", "app: home screen")

    @task(2)
    def notifications(self):
        self.get("/api/notifications/", "app: notifications")

    @task(1)
    def my_handovers(self):
        self.get("/api/delivery/deliveries/", "app: my handovers")

    @task(1)
    def book_followup(self):
        if self.lead_ids:
            due = (datetime.now(timezone.utc) + timedelta(days=2)).isoformat()
            self.client.post(self.base + "/api/visits/followups/", headers=self.auth,
                             name="app: book a follow-up (write)",
                             json={"lead": random.choice(self.lead_ids), "kind": "call", "due_at": due})

    @task(1)
    def note_on_lead(self):
        if self.lead_ids:
            self.client.patch(f"{self.base}/api/crm/leads/{random.choice(self.lead_ids)}/",
                              headers=self.auth, name="app: write a note (write)",
                              json={"notes": "Called, will call back"})


class ConsoleUser(Person):
    """Someone on the admin console: it loads whole lists, all they can see."""
    abstract = True

    @task(3)
    def leads(self):
        self.get("/api/crm/leads/", f"console ({self.kind}): all leads")

    @task(2)
    def customers(self):
        self.get("/api/crm/customers/", f"console ({self.kind}): all customers")

    @task(2)
    def handovers(self):
        self.get("/api/delivery/deliveries/", f"console ({self.kind}): all handovers")

    @task(2)
    def followups(self):
        self.get("/api/visits/followups/", f"console ({self.kind}): all follow-ups")

    @task(1)
    def people(self):
        self.get("/api/auth/employees/", f"console ({self.kind}): people")

    @task(1)
    def dashboard(self):
        self.get("/api/analytics/dashboard/", f"console ({self.kind}): dashboard")


class Manager(ConsoleUser):
    weight = 8
    kind = "manager, 300 leads"

    def on_start(self):
        self.username = f"lt_mgr{next(MANAGERS)}"
        super().on_start()


class Admin(ConsoleUser):
    weight = 2
    kind = "admin, 3,000 leads"
    username = "lt_admin"


# MIX=office  the office today: 10 reps, 1 manager, 1 admin (run with -u 12)
# MIX=reps    reps only, to find what the app's own traffic can reach
_mix = os.environ.get("MIX", "")
if _mix == "office":
    Rep.fixed_count, Manager.fixed_count, Admin.fixed_count = 10, 1, 1
elif _mix == "reps":
    Manager.weight = Admin.weight = 0
    Manager.abstract = Admin.abstract = True

