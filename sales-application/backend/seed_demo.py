"""Seeds a realistic demo dataset for showing the admin console.

DEMO DATA ONLY. Existing rows are left untouched except that the three
`test_*` accounts get presentable display names - their usernames and
passwords are unchanged, so anything that logs in as them still works.

Restore the previous state with:
    manage.py flush --noinput && manage.py loaddata db_backup.json
"""
import os
import random
from datetime import timedelta
from decimal import Decimal

import django

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")
django.setup()

from django.utils import timezone  # noqa: E402

from accounts.models import User  # noqa: E402
from analytics.models import DailyReport  # noqa: E402
from attendance.models import Attendance  # noqa: E402
from crm.models import Customer, Lead  # noqa: E402
from visits.models import FieldVisit, FollowUp  # noqa: E402

rng = random.Random(2026)
today = timezone.localdate()
now = timezone.now()

# Pune, so the map pins and addresses read as one city.
CITY = "Pune"
LAT, LNG = 18.5204, 73.8567

REPS = [
    ("aditi.patil", "Aditi", "Patil"),
    ("rohit.deshmukh", "Rohit", "Deshmukh"),
    ("karan.joshi", "Karan", "Joshi"),
    ("meera.bhosale", "Meera", "Bhosale"),
    ("nikhil.sawant", "Nikhil", "Sawant"),
    ("sneha.kulkarni", "Sneha", "Kulkarni"),
    ("vikram.rane", "Vikram", "Rane"),
    ("pooja.gaikwad", "Pooja", "Gaikwad"),
]

ACCOUNTS = [
    "Vertex Cloud Systems", "NorthPeak Analytics", "Halcyon DataWorks",
    "Meridian Logistics", "Ironbark Software", "Cobalt Retail Group",
    "Sunstone Financial", "Aperture Manufacturing", "Blue Harbour Media",
    "Trellis Healthcare", "Quarry Lane Foods", "Vantage Point Realty",
    "Silverline Textiles", "Orbit Education", "Kestrel Security",
    "Fernwood Hospitality", "Granite Peak Mining", "Lumen Diagnostics",
    "Anchor Freight", "Copperfield Energy", "Rivera Consulting",
    "Wavelength Telecom", "Foundry Digital", "Larkspur Pharma",
    "Beacon Insurance", "Tidewater Marine", "Solstice Apparel",
    "Northgate Automotive", "Emberline Chemicals", "Palisade Robotics",
]

CONTACTS = [
    "Anil Kumar", "Sunita Rao", "Rajesh Menon", "Kavita Iyer", "Sanjay Gupta",
    "Neha Shah", "Arjun Reddy", "Divya Nair", "Manish Agarwal", "Preeti Sharma",
]

print("Seeding demo data...")

# --- people ---------------------------------------------------------------

# Give the existing test accounts presentable names; usernames stay put.
renames = {
    "test_mgr": ("Priya", "Nair"),
    "test_emp": ("Amit", "Kulkarni"),
    "test_other": ("Sagar", "More"),
}
for username, (first, last) in renames.items():
    User.objects.filter(username=username).update(first_name=first, last_name=last)

admin = User.objects.get(username="admin")
if not admin.first_name:
    admin.first_name, admin.last_name = "Abrar", "Patel"
    admin.save(update_fields=["first_name", "last_name"])

# The manager everyone reports to, so the hierarchy has a real shape.
manager = User.objects.filter(username="test_mgr").first()

created_reps = []
for username, first, last in REPS:
    user, made = User.objects.get_or_create(
        username=username,
        defaults=dict(
            first_name=first, last_name=last,
            email=f"{username}@aarmarks.example",
            phone=f"98{rng.randint(10000000, 99999999)}",
            role=User.Role.EMPLOYEE,
            manager=manager,
            is_active=True,
        ),
    )
    if made:
        user.set_unusable_password()
        # Joined between 4 and 20 months ago, so tenure varies.
        user.date_joined = now - timedelta(days=rng.randint(120, 600))
        user.last_login = now - timedelta(hours=rng.randint(1, 40))
        user.save()
    created_rep = user
    created_reps.append(created_rep)

# One rep left inactive, so the status column is not uniformly green.
inactive = created_reps[-1]
inactive.is_active = False
inactive.save(update_fields=["is_active"])

active_reps = [r for r in created_reps if r.is_active]
print(f"  reps: {len(created_reps)} ({len(active_reps)} active)")

# --- leads ----------------------------------------------------------------

# A pipeline that looks like a working quarter: mostly assigned, a healthy
# won count, a few losses, a trickle of untouched new leads.
STATUS_MIX = (
    [Lead.Status.NEW] * 22
    + [Lead.Status.CONVERTED] * 14
    + [Lead.Status.CLOSED] * 6
    + [Lead.Status.NEW] * 4
)
SOURCES = [s[0] for s in Lead.Source.choices]

made_leads = 0
converted_leads = []
for i, account in enumerate(ACCOUNTS * 2):
    if made_leads >= len(STATUS_MIX):
        break
    status = STATUS_MIX[made_leads]
    owner = rng.choice(active_reps)
    created = now - timedelta(days=rng.randint(0, 75), hours=rng.randint(0, 23))

    lead = Lead(
        name=rng.choice(CONTACTS),
        company_name=f"{account}" if i < len(ACCOUNTS) else f"{account} (Div II)",
        phone=f"98{rng.randint(10000000, 99999999)}",
        email=f"contact{made_leads}@example.com",
        address=f"{rng.randint(1, 400)} Magarpatta Rd",
        city=CITY,
        lat=LAT + rng.uniform(-0.06, 0.06),
        lng=LNG + rng.uniform(-0.06, 0.06),
        notes="Interested in the content syndication programme.",
        status=status,
        source=rng.choice(SOURCES),
        assigned_to=None if status == Lead.Status.NEW else owner,
        created_by=admin,
        # A deal worth quoting: 40k-260k, so revenue reads as real money.
        value=Decimal(rng.randrange(40, 260) * 1000),
    )
    lead.save()
    Lead.objects.filter(pk=lead.pk).update(created_at=created, updated_at=created)

    if status == Lead.Status.CONVERTED:
        customer = Customer.objects.create(
            name=lead.name, company_name=lead.company_name, phone=lead.phone,
            email=lead.email, address=lead.address, city=lead.city,
            lat=lead.lat, lng=lead.lng, notes=lead.notes,
            assigned_to=lead.assigned_to, created_by=admin, is_active=True,
        )
        paid = (lead.value * Decimal(rng.choice([25, 50, 100]))) / Decimal(100)
        Lead.objects.filter(pk=lead.pk).update(
            converted_customer=customer,
            converted_at=created + timedelta(days=rng.randint(2, 20)),
            amount_paid=paid,
        )
        converted_leads.append(lead)
    made_leads += 1

print(f"  leads: {made_leads} ({len(converted_leads)} converted)")

# --- attendance, visits, follow-ups --------------------------------------

visit_count = 0
attendance_count = 0
for day_offset in range(21):
    day = today - timedelta(days=day_offset)
    if day.weekday() == 6:  # Sunday off
        continue
    for rep in active_reps:
        if rng.random() < 0.12:  # the odd absence
            continue
        check_in = timezone.make_aware(
            timezone.datetime.combine(day, timezone.datetime.min.time())
        ) + timedelta(hours=9, minutes=rng.randint(0, 55))
        # Today's shift is still open for some, so "still out" is non-zero.
        check_out = None
        if day_offset > 0 or rng.random() < 0.55:
            check_out = check_in + timedelta(hours=8, minutes=rng.randint(0, 90))
        _, made = Attendance.objects.get_or_create(
            user=rep, date=day,
            defaults=dict(
                check_in_at=check_in, check_out_at=check_out,
                check_in_lat=LAT + rng.uniform(-0.03, 0.03),
                check_in_lng=LNG + rng.uniform(-0.03, 0.03),
            ),
        )
        if made:
            attendance_count += 1

        for _ in range(rng.randint(0, 3)):
            lead = rng.choice(
                Lead.objects.filter(assigned_to=rep)[:20] or [None]
            ) if rng.random() < 0.8 else None
            if lead is None:
                continue
            FieldVisit.objects.create(
                user=rep, lead=lead, date=day,
                visited_at=check_in + timedelta(hours=rng.randint(1, 7)),
                lat=float(lead.lat), lng=float(lead.lng),
                duration_minutes=rng.randint(18, 75),
                notes="Discussed programme scope and timelines.",
            )
            visit_count += 1

print(f"  attendance: {attendance_count} days, visits: {visit_count}")

followup_count = 0
for lead in Lead.objects.filter(status=Lead.Status.NEW)[:26]:
    due = now + timedelta(days=rng.randint(-6, 9))
    FollowUp.objects.create(
        lead=lead, assigned_to=lead.assigned_to, created_by=admin,
        due_at=due,
        status=FollowUp.Status.PENDING if rng.random() < 0.72
        else FollowUp.Status.DONE,
        note="Send revised proposal and pricing sheet.",
    )
    followup_count += 1
print(f"  follow-ups: {followup_count}")

# --- daily reports, so the trend lines have shape ------------------------

report_count = 0
for day_offset in range(20):
    day = today - timedelta(days=day_offset)
    for rep in active_reps:
        att = Attendance.objects.filter(user=rep, date=day).first()
        if att is None:
            continue
        _, made = DailyReport.objects.get_or_create(
            user=rep, date=day,
            defaults=dict(
                checked_in=True,
                check_in_at=att.check_in_at,
                check_out_at=att.check_out_at,
                hours_worked=Decimal(rng.randrange(60, 95)) / Decimal(10),
                visits_count=FieldVisit.objects.filter(user=rep, date=day).count(),
                visit_minutes=rng.randint(40, 210),
                leads_created=rng.randint(0, 3),
                leads_won=1 if rng.random() < 0.18 else 0,
                customers_created=1 if rng.random() < 0.15 else 0,
                followups_completed=rng.randint(0, 4),
                followups_pending=rng.randint(0, 5),
                followups_overdue=rng.randint(0, 2),
            ),
        )
        if made:
            report_count += 1
print(f"  daily reports: {report_count}")

print("\nDone. Totals now:")
print(f"  users     {User.objects.count()}")
print(f"  leads     {Lead.objects.count()}")
print(f"  customers {Customer.objects.count()}")
print(f"  visits    {FieldVisit.objects.count()}")
print(f"  follow-ups{FollowUp.objects.count():>3}")
