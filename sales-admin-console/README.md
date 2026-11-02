# sales_admin_console

Super Admin console for the Sales Application. A Flutter desktop/web client that
reads live data from the Django backend in `../Sales-Application/backend`.

## Running it

Start the backend first:

```
cd ../Sales-Application/backend
venv/Scripts/python manage.py runserver
```

Then the console:

```
flutter run -d chrome
```

It defaults to `http://localhost:8000`. Point it somewhere else with:

```
flutter run -d chrome --dart-define=API_BASE=http://192.168.1.3:8000
```

Sign-in uses the same JWT pair as the mobile app (`/api/auth/login/`), so the
account needs the Admin or Super Admin role - `EmployeeListView` refuses anyone
below Manager, and the write endpoints refuse anyone below Admin.

## How data flows

```
features/*        screens, via AsyncGate for load/error states
data/providers    Riverpod providers - companyProvider is the root
data/repositories company / metrics / pipeline - fetch and assemble
data/api/mappers  DRF JSON -> the console's models
data/api          ApiClient: JWT, refresh-and-retry, pagination
```

`companyProvider` loads the roster and its roll-ups; everything else derives
from it. After a write, call `ref.invalidate(companyProvider)` and dependent
views reload with it.

## Known gaps

The console's models were written against a richer API than the backend serves.
Where a field has no source it reads zero rather than being invented, and every
such field is listed in `Mappers.unbackedFields`. The larger ones:

- **Targets and incentives.** No model exists, so attainment, target attainment
  and payout counts are zero, and the Targets screen has nothing to write to.
- **Period-over-period deltas.** Nothing stores a prior window, so the KPI tiles
  show no movement arrows.
- **Audit log.** No table records reassignments or config edits; the activity
  feed shows recent CRM movement instead.
- **Branches and teams.** `User` has a manager chain but no branch column, so
  both come from the constants in `core/company_profile.dart`.
- **Pipeline stages.** `Lead.Status` is the pipeline and its four values are
  fixed in code, so the Configuration screen can show stages but not edit them.
