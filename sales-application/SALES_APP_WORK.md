# Sales App - work remaining

Short notes. The rep app (`mobile/`) plus the backend endpoints it needs.

**Where it stands (16 Sep 2026):** sections A, B and E are done, plus a
Negotiation stage, Customers with Products, and Deliveries with delivered /
not-delivered attempts - all three clients (backend, console, phone). The
phone app now writes attendance, visits, follow-ups, demos, negotiations,
conversions and deliveries. Production packaging is in place (DEPLOY.md: Docker Compose, scheduler,
health check, hardened settings, signed APK). What remains is D (travel
allowance), waiting on the decisions listed under it, and FCM push as an
add-on to C.

---

## A. Screens missing against endpoints that already exist - DONE

All five shipped in the phone app (attendance sheet, visit sheet, convert
sheet, follow-up sheets, lead detail).

| # | Screen | Endpoint | Unblocks in the console |
|---|--------|----------|--------------------------|
| A1 | Check in / check out | `POST /api/attendance/check-in/` `check-out/` | Attendance rate, last check-in, hours worked |
| A2 | Log a field visit (+ photo) | `POST /api/visits/` | Visits this month, activity timelines |
| A3 | Record payment, convert lead | `PATCH /api/crm/leads/{id}/` then `POST .../convert/` | **Revenue.** The whole sale flow |
| A4 | Complete a follow-up | `POST /api/visits/followups/{id}/complete/` | Follow-up counters stop only growing |
| A5 | Edit / reassign a lead | `PATCH /api/crm/leads/{id}/` | Reps can update a lead after creating it |

A3 note: conversion is refused until 30% of `value` is in `amount_paid`. The
screen must collect the payment first, then convert - the error message is
already returned by the API.

---

## B. New - Demo stage in the pipeline - DONE (plus Negotiation)

Pipeline becomes: **Lead -> Demo -> Converted -> Customer**

Backend (`crm/models.py`):
- Add `DEMO = "demo"` to `Lead.Status`.
- Allowed moves: `new -> assigned -> demo -> converted | closed`. A lead may
  also be closed from any state.
- `close_stale_leads.py` counts 30 days of no activity - decide whether a lead
  sitting in `demo` is exempt.

App:
- "Mark demo given" action on the lead detail, with date and outcome note.
- Demo filter in the leads list (the filter row already exists).

---

## C. New - Meeting alerts - DONE

Decided: reuse `FollowUp` (new kind `meeting`), local alarms on the phone,
server `Notification` rows for the bell and history. FCM push is a later add.

- `manage.py send_reminders` - run every minute (cron `* * * * *`). Sends the
  30-min, 10-min and overdue alerts once each (`FollowUpReminder` records
  what went out).
- Phone schedules two local alarms per pending follow-up whenever it loads
  them; tapping one opens the Follow-ups screen. Bell opens Notifications.
- "Meetings" pill on Home = today's agenda (meetings + visits).

Original notes kept below for the FCM step.

A rep must be warned before a scheduled meeting with a lead or a customer.

Backend:
- `FollowUp.due_at` already stores the appointment time. Either reuse it or add
  a `Meeting` model if meetings need to be distinct from follow-ups. **Decide
  this first** - it changes everything downstream.
- **Nothing currently creates a `Notification`.** The model and endpoints exist,
  the app already polls `unread-count`, and the producer was never written.
- Add a scheduled job that creates a Notification at a lead time (say 30 and 10
  minutes before `due_at`). Runs as a management command under cron/Celery beat,
  the same way `generate_reports` does.

App:
- Local notification scheduling so the alert fires without the app open. Server
  push (FCM) if alerts must survive reinstall or arrive on a cold device.
- Meeting list / today's agenda screen.

---

## D. New - Travel distance and allowance - DEFERRED until after deployment

Decided 23 Sep 2026, to be built once the app is hosted on a real domain.

Settled:
- **Rate: Rs 2.50 per km.** One rate; no vehicle split for now.
- **Distance source: Google Routes API** (`computeRoutes`), road distance, not
  straight line and not a sum of GPS points. One request per rep per day with
  the day's stops as intermediate waypoints - about 220 requests a month for ten
  reps, inside the 10,000/month free tier for Routes Essentials. Billing must
  still be enabled on the Cloud project, and the key restricted to the server IP.
- **Cycle: weekly.** Routes are computed per day (a day is one journey), but the
  job runs once a week and the console shows and approves a week at a time.
- **Week runs Monday to Sunday.** Reps do go out on a Sunday when a client
  calls, so no day is excluded.
- Straight-line distance is the fallback when the Routes API is unreachable,
  and the row is flagged as an estimate rather than silently wrong.

Still open when we pick this up:
- Where a day's journey starts and ends: the office, the rep's home, or simply
  their first and last check-in of the day.
- Whether a manager must approve a week before it is payable (assumed yes).
- Daily or weekly cap, if any.

A rep may travel to a visit **direct from home**, and the company reimburses
travel per visit. This needs a defensible distance, not an estimate.

Backend - new:
- Record a journey per visit: start point, end point, and the path between.
  `visits_checkpoint` already stores `lat`, `lng`, `accuracy_m`, `recorded_at` -
  it is the natural raw material, but nothing reads it today.
- Store `distance_km` on the visit (or a `Trip` model) computed from the
  checkpoint trail, so the figure is fixed at the time of travel and does not
  drift if the rule changes later.
- Allowance rate per km - configurable, not hardcoded.
- Reimbursement record with an approval state, so a Super Admin can approve or
  query a claim.

Decisions needed before building:
- **Distance source.** Sum of GPS points is honest but noisy - poor accuracy
  readings inflate it. A road-distance API is accurate but external and paid.
  Straight-line is cheap and always understates.
- **Home as a start point.** Does home count as the journey origin every day, or
  only when the rep goes direct to a customer? Store the home location on the
  user, or capture "start journey" explicitly in the app.
- **Anti-abuse.** Distance drives money. Decide the accuracy floor, what happens
  when GPS drops mid-journey, and whether a manager must approve.

App:
- "Start journey" / "End journey" around a visit, with background location
  sampling while travelling.
- Show the rep their own distance and claim per visit and per day.
- Battery and permission handling - background location is the heaviest thing
  this app will do.

---

## E. Housekeeping - DONE

- `/api/crm/customers/` has **no caller in either client**. Every converted lead
  creates a Customer that nobody can see. The app needs a customer list, since
  meetings and repeat visits are against customers, not leads.
- The notification bell polls `unread-count` and will always read zero until C
  is done.

