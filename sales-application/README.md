# SalesHub

Field work tracking for a field-sales team. A salesperson marks where he is
with one tap, adds leads on the spot, and the company sees the day as a list of
times, places and photographs.

One repository, two parts:

| Folder | What it is | Stack |
|---|---|---|
| [`backend/`](backend) | REST API and admin panel | Django 6.1, DRF, PostgreSQL 16 |
| [`mobile/`](mobile) | Field app for salespeople | Flutter 3.47 |

They live together because a change often spans both sides — adding a field to
the API and showing it in the app is one change to the product, and belongs in
one commit.

The visual design comes from Stitch and lives there rather than in this
repository. An earlier React reference for the superseded FieldOps design was
removed once the app had moved past it; it is still in the history if the
reasoning behind an old screen is ever needed.

---

## Running the backend

Needs PostgreSQL 16 running and a database called `sales_tracker`.

```bash
cd backend
python -m venv venv
venv\Scripts\activate           # Windows
pip install -r requirements.txt

cp .env.example .env             # then fill in the two values
python manage.py migrate
python manage.py createsuperuser
python manage.py runserver 0.0.0.0:8000
```

`0.0.0.0` rather than the default makes the server reachable from a phone on
the same Wi-Fi. Admin panel: http://127.0.0.1:8000/admin

### Secrets

`backend/.env` is git-ignored and holds two values:

```
DB_PASSWORD=      # your PostgreSQL password
SECRET_KEY=       # signs login tokens — treat as a password
```

`.env.example` lists the keys with empty values, so a new machine knows what
to fill in without ever seeing the real ones.

---

## Running the mobile app

```bash
cd mobile
flutter pub get

# In a browser — quickest, but browser location is approximate
flutter run -d chrome --web-port=5000 --dart-define=API_BASE=http://localhost:8000

# On a real phone — the honest test, since checkpoints depend on real GPS
flutter run --dart-define=API_BASE=http://192.168.1.3:8000
```

`API_BASE` points the app at the backend. The right address depends on where
the app runs: `localhost` in a browser on the same machine, `10.0.2.2` from an
Android emulator, and the laptop's Wi-Fi address from a real phone.

---

## How permissions work

One rule, defined once in [`backend/common/scoping.py`](backend/common/scoping.py)
and reused by every module:

- **Admin / Super Admin** — every record
- **Manager** — their own, plus their team's
- **Employee** — their own only

Records match on who owns the work *and* who created it, so a lead a team
member brought in stays visible to their manager even after it is reassigned.

The client never sends who it is or what time it is: the user comes from the
auth token and the timestamp from the server, so a checkpoint cannot be filed
for someone else or backdated. That is what makes it evidence of where
somebody was rather than a claim about it.

---

## Project status

The first version is built and covered by tests — 71 on the backend, 14 on the
app. What a salesperson can do: sign in, mark where he is with one tap
(optionally with a note and a photograph), add leads, and see his own list.
The company reads the day in the Django admin, where each checkpoint links
out to a map.

GPS attendance, field visits against a lead, follow-ups and the daily report
all exist in the API and are tested, but nothing in the app renders them:
they were built before the requirement settled on plain checkpoints. Turning
any of them back on is a screen, not a rebuild.

Phase 2 covers products, quotations, orders, targets, performance, expenses,
leave, and tasks. Phase 3 adds live tracking, geofencing, routes, and chat —
checkpoints are a diary of where he went, not a live trail.

## Deploying

See [DEPLOY.md](DEPLOY.md): Docker Compose for the API + console, a signed APK for the phones, TLS, backups, and the first-run checklist.
