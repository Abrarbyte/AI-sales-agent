# Development log

Why the project is built the way it is. Written as decisions rather than a
diary, so it stays useful after the details are forgotten.

Covers 20–27 Aug 2026: Phase 1 backend, the Flutter app, and the move to one
repository.

---

## Decisions

### One company, not many — *resolved 24 Aug*

The original brief listed multi-tenancy as "module 47, future". That is not a
decision that can wait: supporting several client companies needs a `company`
column on nearly every table and a filter on every query, and retrofitting it
after go-live is a rewrite, not an addition.

**Decided: single company.** No tenant column anywhere; role-based visibility
is the only scoping rule. `crm/models.py` carries a note on what would change
if this is ever revisited.

### Manager and Team Leader are one role

Scoped as five roles; built with four. At ten people the two titles do the same
job.

Reporting lines are stored as a **link to a person** (`User.manager`), not as a
job title. Adding a separate team-leader tier later is one new choice in an
enum plus a migration — the hierarchy itself does not change shape.

### Visibility is defined once

`common/scoping.py` holds the rule every module reuses:

- Admin / Super Admin — everything
- Manager — their own records plus their team's
- Employee — their own only

Records match on **who owns the work and who created it**. Owner alone is not
enough: a lead an employee brought in and later handed to another team would
vanish from their manager's report. That case was caught by inspection, not by
tests, and is now the reason the rule is two-sided.

Writing it once matters more than it looks. Attendance, leads, customers,
visits, and follow-ups all call the same function, so a change to the policy
lands everywhere at once instead of in five places that can drift.

### The client never sends identity or time

The app sends coordinates. Everything else the server decides:

- **who** comes from the auth token
- **when** comes from the server clock

So attendance cannot be filed for someone else or backdated, which is the whole
point of GPS attendance in the first place.

### Deactivate, never delete

`DELETE` on a user or customer sets `is_active = False`. Attendance rows, visit
history, and future orders all point at those records; removing the row would
orphan months of history to tidy up one person who left.

### Token auth, not sessions

A mobile app cannot use browser session cookies, and one token system serves
both the app and the future web dashboard.

Two tokens, with different jobs: the **access token** travels with every
request and is therefore the most exposed, so it is short-lived (8 hours ≈ one
working day). The **refresh token** travels rarely, lasts 30 days, and can be
revoked centrally if a phone is lost. The library's 5-minute default is built
for banking and would interrupt a salesperson mid-form, outdoors, on a weak
signal.

### Flutter, not React Native

React Native looked right at first — the web dashboard is React, so it would
share a language. It stopped being right on learning the developer already
knows Flutter: the "extra language to learn" cost was the whole argument, and
Flutter renders more smoothly, which matters for Phase 3 map and tracking work.

### One repository

Backend, mobile app, and design reference live together. A change that spans
the API and the app is **one change to the product** and belongs in one commit
— with split repos it becomes two commits in two places that can be deployed
out of order, which is how an app ends up asking for a field the backend does
not have yet.

One repo does not mean one commit: history is per-area (`backend: …`,
`mobile: …`), and a cross-cutting change simply stages both paths.

---

## Bugs worth remembering

These were all found by testing behaviour, not by reading code.

**Anonymous requests returned 500 instead of 401.** The permission class read
`request.user.role` directly. An unauthenticated request carries an
`AnonymousUser`, which has no `role` attribute, so the check crashed before it
could deny anything. Fixed by testing `is_authenticated` first — Python
short-circuits `and`, so `.role` is never reached.

**Django model validation does not apply to API requests.** `Lead.clean()`
blocks marking a lead "won" without a converted customer. DRF never calls
`clean()`, so the rule held in the admin panel and silently did not hold in the
API. The rule is now stated in both places — correct, but duplicated, and worth
unifying.

**A user could be their own manager.** The admin dropdown offered the user
being edited. Now blocked in `clean()`, and the dropdown only offers people who
actually hold a manager-or-above role.

**The design port had the wrong corner radii.** They were read off Tailwind's
documented defaults instead of the project's `tailwind.config.js`, which
overrides them and derives every step from `--radius: 0.625rem`. The real scale
is 8/10/14/18, not 8/12/16.

**Flutter's default density shrinks buttons off-mobile.**
`adaptivePlatformDensity` is compact on web and desktop and removes 8px from
every control — quietly turning a deliberate 48px touch target into 40px, below
Android's minimum, in exactly the web build a phone loads. Density is now
pinned to standard, and asserted in a test, because a widget test alone reports
Android and would not catch a regression.

---

## Environment notes

**Secrets** live in `backend/.env`, which is git-ignored; `.env.example` lists
the keys with empty values. Before this, the database password was typed into
each terminal by hand and lost whenever a new one opened.

**Android without Android Studio.** JDK 21 plus the command-line tools is about
2GB rather than 10GB, and a real phone over USB beats an emulator for a GPS app
— emulator location is a number you type in. The SDK lives at `C:\Android\Sdk`;
it was originally in a folder containing a space, which breaks Gradle.

**The LAN address is looked up at startup, not hardcoded.** The router
reassigns it, and a stale value in `ALLOWED_HOSTS` breaks phone testing in a way
that looks like a firewall problem. It had already drifted once.

**Testing on a phone over Wi-Fi needs three separate things** to be right: the
network profile set to Private, firewall rules scoped to Private (Windows'
existing Python/Dart rules were Public-only, so switching profiles silently
orphaned them), and the current IP. Any one wrong looks identical to the others.

**Browser geolocation only works on HTTPS or localhost.** The web build loaded
on a phone can show the app but cannot test check-in. Real GPS needs the native
app, ideally with `adb reverse tcp:8000 tcp:8000` so the phone reaches the
backend over USB with no network involved.

---

## Open items

- **Android licences** not yet accepted — blocks running on a real phone.
- **`DEBUG = False`** and the real domain in `ALLOWED_HOSTS` before deployment.
- **Redis** on the server for the daily-report queue. Until then:
  `python manage.py generate_reports`.
- **The lead-status rule is stated twice** (model and serializer). Correct, but
  the two can drift.
- **Design and app are kept in step by hand.** `design/` is a React prototype
  with mock data; `mobile/` is the real app styled to match. Editing one does
  not change the other.
