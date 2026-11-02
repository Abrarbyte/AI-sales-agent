"""Fill the LOAD TEST database: 1 admin, 10 managers, 100 reps; 30 leads per
rep (3,000) at every stage, with demos, negotiations and follow-ups; 5
customers per rep (500) with payments and handover milestones.

Run with DB_NAME=sales_tracker_loadtest. Refuses any other database.
"""
import random
from datetime import timedelta
from decimal import Decimal

from django.contrib.auth.hashers import make_password
from django.db import connection
from django.utils import timezone

from accounts.models import User
from crm.models import Customer, Demo, Lead, Negotiation, Payment, Product
from delivery.models import Delivery, refresh_project_status
from visits.models import FollowUp

assert connection.settings_dict["NAME"] == "sales_tracker_loadtest", "wrong database"
assert not Lead.objects.exists(), "already seeded"

random.seed(7)
now, today = timezone.now(), timezone.localdate()
PASSWORD = "loadtest-pw-123"
hashed = make_password(PASSWORD)  # one hash, reused: hashing 111 times is slow

User.objects.create(username="lt_admin", role="super_admin", password=hashed,
                    first_name="Load", last_name="Admin")
managers = [User.objects.create(username=f"lt_mgr{m}", role="manager", password=hashed,
                                first_name="Manager", last_name=str(m)) for m in range(10)]
reps = [User.objects.create(username=f"lt_rep{r}", role="employee", password=hashed,
                            manager=managers[r % 10], first_name="Rep", last_name=str(r))
        for r in range(100)]
product = Product.objects.create(name="Website (CMS)")

STAGES = ["new"] * 8 + ["demo"] * 5 + ["negotiation"] * 5 + ["proposal"] * 4 + ["closed"] * 8
leads, n = [], 0
for rep in reps:
    for stage in STAGES:
        n += 1
        leads.append(Lead(
            name=f"Contact {n}", company_name=f"Company {n}", phone=f"9{n:09d}",
            city="Pune", status=stage, source="referral", project_type="website",
            requirement=f"Website with enquiry form for company {n}",
            assigned_to=rep, created_by=rep,
            lost_reason="price" if stage == "closed" else "",
            value=Decimal(random.randrange(40, 900) * 1000) if stage in ("negotiation", "proposal") else None))
Lead.objects.bulk_create(leads, batch_size=500)
leads = list(Lead.objects.order_by("id"))

Demo.objects.bulk_create([
    Demo(lead=l, held_at=now - timedelta(days=random.randrange(1, 20)), product="Website (CMS)",
         outcome="successful", mode="online", given_by=l.assigned_to, created_by=l.assigned_to)
    for l in leads if l.status != "new"], batch_size=500)
Negotiation.objects.bulk_create([
    Negotiation(lead=l, owner=l.assigned_to, created_by=l.assigned_to,
                quoted_amount=l.value, payment_terms=random.choice(["advance_30", "half_half", "milestones"]),
                status="proposal_sent" if l.status == "proposal" else "in_progress",
                expected_close_on=today + timedelta(days=random.randrange(-5, 30)))
    for l in leads if l.status in ("negotiation", "proposal")], batch_size=500)
FollowUp.objects.bulk_create([
    FollowUp(lead=l, assigned_to=l.assigned_to, created_by=l.assigned_to, kind="call",
             due_at=now + timedelta(days=random.randrange(-3, 10)))
    for l in leads if l.status not in ("closed",) and l.id % 2 == 0], batch_size=500)

customers, n = [], 0
for rep in reps:
    for _ in range(5):
        n += 1
        customers.append(Customer(
            name=f"Client {n}", company_name=f"Client Co {n}", phone=f"8{n:09d}", city="Pune",
            assigned_to=rep, created_by=rep, price=Decimal(random.randrange(60, 600) * 1000)))
Customer.objects.bulk_create(customers, batch_size=500)
customers = list(Customer.objects.order_by("id"))
Payment.objects.bulk_create([
    Payment(customer=c, amount=(c.price * Decimal("0.3")).quantize(Decimal("1")),
            received_on=today - timedelta(days=20), method="upi", recorded_by=c.assigned_to)
    for c in customers] + [
    Payment(customer=c, amount=(c.price * Decimal("0.3")).quantize(Decimal("1")),
            received_on=today - timedelta(days=5), method="bank_transfer", recorded_by=c.assigned_to)
    for c in customers if c.id % 2 == 0], batch_size=500)
deliveries = []
for c in customers:
    for i, m in enumerate(("design_approval", "development_complete", "go_live")):
        done = i < c.id % 3
        deliveries.append(Delivery(
            customer=c, product=product, assigned_to=c.assigned_to, created_by=c.assigned_to,
            milestone=m, scheduled_on=today + timedelta(days=7 * i - 7),
            status="delivered" if done else "pending",
            delivered_at=now - timedelta(days=3) if done else None,
            received_by="Client" if done else ""))
Delivery.objects.bulk_create(deliveries, batch_size=500)
for c in customers:  # bulk_create skips the save hook that sets project status
    refresh_project_status(c)

print("users", User.objects.count(), "| leads", Lead.objects.count(),
      "| customers", Customer.objects.count(), "| demos", Demo.objects.count(),
      "| negotiations", Negotiation.objects.count(), "| follow-ups", FollowUp.objects.count(),
      "| payments", Payment.objects.count(), "| milestones", Delivery.objects.count())
