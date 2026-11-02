# Super Admin Console - work remaining

Short notes. What is left to build in `sales_admin_console`, and what the new
requirements add.

**Where it stands today:** the console reads live data over JWT. Five screens
are built (Dashboard, Admins, Admin detail, Reps, Rep detail); six are
placeholders. Everything the backend cannot support has been removed from the
UI rather than shown as a zero.

---

## A. Missing, backend already ready

Build these against endpoints that exist today.

| # | Screen | Endpoint | Why it matters |
|---|--------|----------|----------------|
| A1 | **Login** | `POST /api/auth/login/` | There is none. The console only opens via a dev token shim. `ApiClient.login()` exists and is unused |
| A2 | **Leads** | `GET/PATCH /api/crm/leads/` | Placeholder. Your core CRM data has no screen |
| A3 | **Reports** | `GET /api/analytics/reports/` | Placeholder |
| A4 | **Customers** | `GET /api/crm/customers/` | **No caller anywhere.** Every won deal creates a Customer nobody can see |
| A5 | Sign out | client-side | Removed during cleanup - bring back **with** A1 |
| A6 | Refresh control | - | No auto-refresh; the page must be reloaded to see new data |
| A7 | Account activation | - | New people need a password typed by an admin; there is no invite flow |

A1 is the one to do first: it retires `dev-login.html`, and A5 returns with it.

---

## B. Placeholders that need backend first

No tables exist for any of these. Do not build the screen until the schema is
agreed.

- **Targets & Incentives** - quotas, commission rules, payouts
- **Audit Log** - who changed what
- **Announcements** - broadcast to reps
- **Configuration** - custom fields, templates, working hours, feature toggles

Roughly 96 of the 129 unbacked model fields sit in this group. Most of it is
enterprise surface a single-team operation may not need - **decide build/drop
per capability before writing any migration.**

---

## C. New - Demo stage in the pipeline

Pipeline becomes **Lead -> Demo -> Converted -> Customer**.

- `Mappers.stageKindOf()` maps Django's status to the console's stage kind - add
  `demo` there once the backend has it.
- Funnel and stage counts pick it up automatically; they are derived, not
  stored.
- The Leads screen (A2) should filter and show stage, so build it after the
  backend change lands, not before.

---

## D. New - Meeting alerts

The rep-side alert is app work. The console side is oversight:

- Upcoming meetings across the team, and meetings missed.
- Which alerts were sent and to whom, once a Notification producer exists.
- Nothing creates a `Notification` today - the console cannot report on alerts
  until the backend does.

---

## E. New - Travel distance and allowance

This is the biggest new area for the console, because it is where money is
approved.

- **Travel claims queue** - per rep, per visit, per period, with approve/query
  actions. Needs the reimbursement model and its approval state.
- **Distance review** - the trail behind a claimed distance, so a Super Admin
  can see the route, not just a number. `visits_checkpoint` already holds the
  raw points and nothing reads them.
- **Allowance rate** - editable rate per km. Currently no configuration store
  exists anywhere (see B), so decide where this lives.
- **Cost reporting** - travel spend by rep and by period, alongside revenue.

Note: the console already has `GpsTrail` and `VisitProof` models with
`totalDistanceMetres` and geofence fields, written against a richer API than
exists. Reuse the shapes; do not invent new ones.

---

## F. Known-wrong, deliberately left

- **Revenue trend** chart plots leads won per day, not currency - relabelled,
  because no per-day revenue is stored anywhere.
- **KPI deltas** read `0.0%` - nothing stores a prior window to compare against.
  `DailyReport` already holds per-day counts, so period-over-period is a query
  rather than a migration. Cheapest real win on the dashboard.
- Branch and team are constants in `CompanyProfile` - `User` has a manager chain
  but no branch column.

Full list in `Mappers.unbackedFields`.

---

## G. Architecture, when the data grows

The console downloads every lead, visit and attendance row and computes counts,
rankings and roll-ups in Dart. Correct at 60 leads, collapses at 50,000.

Fix is a console-shaped namespace with the aggregation done in SQL:

```
GET /api/console/dashboard/   -> KPI shape, computed server-side
GET /api/console/reps/        -> rep rows with roll-ups already joined
GET /api/console/admins/      -> admin rows with team counts joined
```

Not urgent at current volume. It is the main architectural debt outstanding.
