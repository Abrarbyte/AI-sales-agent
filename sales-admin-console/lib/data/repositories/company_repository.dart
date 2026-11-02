import '../api/api_client.dart';
import '../api/mappers.dart';
import '../models/common.dart';
import '../models/customer.dart';
import '../models/delivery.dart';
import '../models/lead.dart';
import '../models/people.dart';
import '../models/activity.dart';

/// Who is signed in, for the top bar.
class SignedInUser {
  const SignedInUser({
    required this.id,
    required this.name,
    required this.roleLabel,
    this.username = '',
  });

  final String id;
  final String name;
  final String roleLabel;
  final String username;
}

/// Everything the people-facing screens need, loaded together.
///
/// The console's Admin and Rep rows carry roll-ups (leads owned, visits this
/// month, conversion) that the backend does not attach to a user - they live in
/// the CRM and visits tables. Fetching them per row would be one request per
/// person; instead the four collections are read once and joined here, which is
/// four requests for the whole screen no matter how many people are in it.
class CompanySnapshot {
  const CompanySnapshot({
    required this.admins,
    required this.reps,
    required this.leads,
    required this.customers,
    required this.deliveries,
    required this.visitRows,
    required this.loadedAt,
    this.visits = const <FieldVisit>[],
    this.checkpoints = const <Checkpoint>[],
    this.attendance = const <AttendanceDay>[],
    this.followUps = const <FollowUp>[],
  });

  final List<AdminUser> admins;
  final List<SalesRep> reps;

  /// Every lead the signed-in account may see, already joined to its rep.
  final List<Lead> leads;

  /// Everyone who has bought, and what is on its way to them.
  final List<Customer> customers;
  final List<Delivery> deliveries;

  /// The raw `/api/visits/` rows this load already fetched.
  ///
  /// Carried rather than dropped so [PipelineRepository] can build activity
  /// timelines from them instead of downloading the same table again - the
  /// pipeline runs after this load, and visits is the largest table in the app.
  final List<Map<String, dynamic>> visitRows;

  /// What the reps did: every visit, site check-in, working day and
  /// follow-up the signed-in account may see, joined to display names.
  final List<FieldVisit> visits;
  final List<Checkpoint> checkpoints;
  final List<AttendanceDay> attendance;
  final List<FollowUp> followUps;

  final DateTime loadedAt;

  AdminUser? adminById(String id) {
    for (final AdminUser a in admins) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// The account the console treats as the owning Admin when a rep has no
  /// manager set. Falls back to the first admin so a screen always has one.
  AdminUser? get primaryAdmin => admins.isEmpty ? null : admins.first;

  SalesRep? repById(String id) {
    for (final SalesRep r in reps) {
      if (r.id == id) return r;
    }
    return null;
  }

  List<SalesRep> repsForAdmin(String adminId) =>
      reps.where((SalesRep r) => r.adminId == adminId).toList(growable: false);

  List<SalesRep> get activeReps => reps
      .where((SalesRep r) => r.status == EntityStatus.active)
      .toList(growable: false);

  /// A rep's stable slot in the roster, used to colour charts consistently as
  /// rows re-order. Ranking must never change a rep's colour.
  int entityIndexOfRep(String repId) {
    final int i = reps.indexWhere((SalesRep r) => r.id == repId);
    return i < 0 ? 0 : i;
  }

  List<FieldVisit> visitsForLead(String leadId) => visits
      .where((FieldVisit v) => v.leadId == leadId)
      .toList(growable: false);

  List<FieldVisit> visitsForCustomer(String customerId) => visits
      .where((FieldVisit v) => v.customerId == customerId)
      .toList(growable: false);

  List<FollowUp> followUpsForLead(String leadId) => followUps
      .where((FollowUp f) => f.leadId == leadId)
      .toList(growable: false);

  List<FollowUp> followUpsForCustomer(String customerId) => followUps
      .where((FollowUp f) => f.customerId == customerId)
      .toList(growable: false);

  List<Delivery> deliveriesForCustomer(String customerId) => deliveries
      .where((Delivery d) => d.customerId == customerId)
      .toList(growable: false);
}

/// Reads people, leads, customers, deliveries, visits and attendance, and
/// assembles them into the shapes the console screens were built against.
class CompanyRepository {
  CompanyRepository(this._api);

  final ApiClient _api;

  Future<CompanySnapshot> load() async {
    // Independent reads - issued together rather than in sequence, so the
    // dashboard costs one round trip's latency instead of six.
    final List<List<Map<String, dynamic>>> results = await Future.wait(
      <Future<List<Map<String, dynamic>>>>[
        _api.getList('/api/auth/employees/'),
        _api.getList('/api/crm/leads/'),
        _api.getList('/api/visits/'),
        _api.getList('/api/attendance/'),
        _api.getList('/api/crm/customers/'),
        _api.getList('/api/delivery/deliveries/'),
        _api.getList('/api/visits/checkpoints/'),
        _api.getList('/api/visits/followups/'),
      ],
    );

    final List<Map<String, dynamic>> users = results[0];
    final List<Map<String, dynamic>> leadRows = results[1];
    final List<Map<String, dynamic>> visitRows = results[2];
    final List<Map<String, dynamic>> attendanceRows = results[3];
    final List<Map<String, dynamic>> customerRows = results[4];
    final List<Map<String, dynamic>> deliveryRows = results[5];
    final List<Map<String, dynamic>> checkpointRows = results[6];
    final List<Map<String, dynamic>> followUpRows = results[7];

    // ---- index the people, so the joins below are lookups, not scans
    final Map<String, Map<String, dynamic>> userById =
        <String, Map<String, dynamic>>{
          for (final Map<String, dynamic> u in users) u['id'].toString(): u,
        };

    final List<Map<String, dynamic>> adminRows = users
        .where(Mappers.isAdminRole)
        .toList(growable: false);
    final List<Map<String, dynamic>> repRows = users
        .where((Map<String, dynamic> u) => !Mappers.isAdminRole(u))
        .toList(growable: false);

    final String? fallbackAdminId = adminRows.isEmpty
        ? null
        : adminRows.first['id'].toString();

    final Set<String> adminIds = <String>{
      for (final Map<String, dynamic> a in adminRows) a['id'].toString(),
    };

    /// The Admin a rep belongs to on the team screens.
    ///
    /// Django's `manager` is an arbitrary chain - a rep may report to someone
    /// who is themselves a rep - while the console shows exactly two levels.
    /// So walk up until an Admin is reached rather than trusting the first
    /// hop, or a rep parented to a non-Admin would roll up to nobody and their
    /// leads would vanish from every team total.
    ///
    /// Falls back to the first Admin: Django allows a null manager, and an
    /// unparented rep must still appear somewhere.
    String adminIdFor(Map<String, dynamic> user) {
      final Set<String> seen = <String>{user['id'].toString()};
      String? cursor = user['manager']?.toString();

      while (cursor != null && cursor.isNotEmpty && seen.add(cursor)) {
        if (adminIds.contains(cursor)) return cursor;
        // Not an Admin - keep climbing. `seen` stops a manager cycle, which
        // the model's clean() blocks on save but a bulk update can still make.
        cursor = userById[cursor]?['manager']?.toString();
      }
      return fallbackAdminId ?? '';
    }

    // ---- roll up leads per rep
    final Map<String, _LeadRollup> leadsByRep = <String, _LeadRollup>{};
    for (final Map<String, dynamic> row in leadRows) {
      final String repId = row['assigned_to']?.toString() ?? '';
      if (repId.isEmpty) continue;
      (leadsByRep[repId] ??= _LeadRollup()).add(row);
    }

    // ---- roll up visits per rep, this calendar month
    final DateTime now = DateTime.now();
    final Map<String, int> visitsThisMonth = <String, int>{};
    for (final Map<String, dynamic> row in visitRows) {
      final DateTime? date = DateTime.tryParse(row['date']?.toString() ?? '');
      if (date == null || date.year != now.year || date.month != now.month) {
        continue;
      }
      final String repId = row['user']?.toString() ?? '';
      if (repId.isEmpty) continue;
      visitsThisMonth[repId] = (visitsThisMonth[repId] ?? 0) + 1;
    }

    // ---- most recent check-in per rep, and where it happened
    final Map<String, Map<String, dynamic>> latestAttendance =
        <String, Map<String, dynamic>>{};
    for (final Map<String, dynamic> row in attendanceRows) {
      final String repId = row['user']?.toString() ?? '';
      if (repId.isEmpty) continue;
      final Map<String, dynamic>? held = latestAttendance[repId];
      if (held == null ||
          (row['date']?.toString() ?? '').compareTo(
                held['date']?.toString() ?? '',
              ) >
              0) {
        latestAttendance[repId] = row;
      }
    }

    // ---- build the reps
    final List<SalesRep> reps = repRows
        .map((Map<String, dynamic> u) {
          final String id = u['id'].toString();
          final _LeadRollup rollup = leadsByRep[id] ?? _LeadRollup();
          final Map<String, dynamic>? attendance = latestAttendance[id];

          return Mappers.repFromUser(
            u,
            adminId: adminIdFor(u),
            assignedLeads: rollup.total,
            openLeads: rollup.open,
            wonLeads: rollup.won,
            visitsThisMonth: visitsThisMonth[id] ?? 0,
            // No visit-proof approval exists in the backend, so compliance cannot
            // be measured. Reported as zero rather than invented.
            visitComplianceRate: 0,
            revenueThisPeriod: rollup.wonValue,
            lastCheckInAt: attendance == null
                ? null
                : DateTime.tryParse(
                    attendance['check_in_at']?.toString() ?? '',
                  ),
            lastKnownLocation: attendance == null
                ? null
                : Mappers.geoFrom(
                    attendance['check_in_lat'],
                    attendance['check_in_lng'],
                  ),
          );
        })
        .toList(growable: false);

    // ---- build the admins, counting their own team
    final List<AdminUser> admins = adminRows
        .map((Map<String, dynamic> u) {
          final String id = u['id'].toString();
          final List<SalesRep> team = reps
              .where((SalesRep r) => r.adminId == id)
              .toList(growable: false);
          final int owned = team.fold(
            0,
            (int s, SalesRep r) => s + r.assignedLeads,
          );
          final int won = team.fold(0, (int s, SalesRep r) => s + r.wonLeads);

          return Mappers.adminFromUser(
            u,
            repCount: team.length,
            activeRepCount: team
                .where((SalesRep r) => r.status == EntityStatus.active)
                .length,
            leadsOwned: owned,
            conversionRate: owned == 0 ? 0 : won / owned,
          );
        })
        .toList(growable: false);

    // ---- leads, joined to the rep's display name and owning admin
    final Map<String, SalesRep> repIndex = <String, SalesRep>{
      for (final SalesRep r in reps) r.id: r,
    };
    final List<Lead> leads = leadRows
        .map((Map<String, dynamic> row) {
          final SalesRep? rep = repIndex[row['assigned_to']?.toString() ?? ''];
          return Mappers.leadFrom(
            row,
            repName: rep?.name,
            adminId: rep?.adminId,
          );
        })
        .toList(growable: false);

    final List<Customer> customers = customerRows
        .map(
          (Map<String, dynamic> row) => Customer.fromJson(
            row,
            repName: repIndex[row['assigned_to']?.toString() ?? '']?.name,
          ),
        )
        .toList(growable: false);
    final List<Delivery> deliveries = deliveryRows
        .map(
          (Map<String, dynamic> row) => Delivery.fromJson(
            row,
            repName: repIndex[row['assigned_to']?.toString() ?? '']?.name,
          ),
        )
        .toList(growable: false);

    // Display names for anyone who logged activity - reps and admins alike.
    String? displayName(dynamic userId) {
      final Map<String, dynamic>? u = userById[userId?.toString() ?? ''];
      return u == null ? null : Mappers.nameOf(u);
    }

    return CompanySnapshot(
      admins: admins,
      reps: reps,
      leads: leads,
      customers: customers,
      deliveries: deliveries,
      visitRows: visitRows,
      visits: visitRows
          .map(
            (Map<String, dynamic> r) =>
                FieldVisit.fromJson(r, repName: displayName(r['user'])),
          )
          .toList(growable: false),
      checkpoints: checkpointRows
          .map(
            (Map<String, dynamic> r) =>
                Checkpoint.fromJson(r, repName: displayName(r['user'])),
          )
          .toList(growable: false),
      attendance: attendanceRows
          .map(
            (Map<String, dynamic> r) =>
                AttendanceDay.fromJson(r, repName: displayName(r['user'])),
          )
          .toList(growable: false),
      followUps: followUpRows
          .map(
            (Map<String, dynamic> r) => FollowUp.fromJson(
              r,
              repName: displayName(r['assigned_to']),
            ),
          )
          .toList(growable: false),
      loadedAt: DateTime.now(),
    );
  }

  /// The signed-in account. Used by the top bar, which otherwise had no way
  /// to know who is looking at it.
  Future<SignedInUser> me() async {
    final dynamic raw = await _api.get('/api/auth/me/');
    final Map<String, dynamic> json = (raw as Map).cast<String, dynamic>();
    return SignedInUser(
      id: json['id'].toString(),
      name: Mappers.nameOf(json),
      roleLabel:
          json['role_display']?.toString() ?? json['role']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
    );
  }

  // -------------------------------------------------------------- mutations

  Future<void> createEmployee({
    required String username,
    required String name,
    required String email,
    required String phone,
    required String role,
    String? managerId,
    String? password,
  }) async {
    await _api.post(
      '/api/auth/employees/',
      Mappers.employeeWriteJson(
        username: username,
        name: name,
        email: email,
        phone: phone,
        role: role,
        managerId: managerId,
        password: password,
      ),
    );
  }

  Future<void> updateEmployee(
    String id, {
    required String name,
    required String email,
    required String phone,
    required String role,
    String? managerId,
    String? password,
    bool? isActive,
  }) async {
    await _api.patch(
      '/api/auth/employees/$id/',
      Mappers.employeeWriteJson(
        name: name,
        email: email,
        phone: phone,
        role: role,
        managerId: managerId,
        // Omitted when blank, so an edit that does not touch the password
        // field leaves the existing one alone rather than clearing it.
        password: password,
        isActive: isActive,
      ),
    );
  }

  /// DELETE on the employee endpoint deactivates rather than removes, so
  /// attendance and visit history survives. See `EmployeeDetailView`.
  Future<void> deactivateEmployee(String id) =>
      _api.delete('/api/auth/employees/$id/');

  Future<void> reactivateEmployee(String id) => _api.patch(
    '/api/auth/employees/$id/',
    <String, dynamic>{'is_active': true},
  );

  /// Moves a rep to a different Admin - the "reassign rep" operation.
  Future<void> reassignRep(String repId, String toAdminId) => _api.patch(
    '/api/auth/employees/$repId/',
    <String, dynamic>{'manager': int.tryParse(toAdminId)},
  );
}

/// Running counts for one rep's leads.
class _LeadRollup {
  int total = 0;
  int open = 0;
  int won = 0;
  double wonValue = 0;

  void add(Map<String, dynamic> row) {
    total++;
    final LeadStageKind kind = Mappers.stageKindOf(row['status']?.toString());
    switch (kind) {
      case LeadStageKind.open:
        open++;
      case LeadStageKind.won:
        won++;
        final dynamic raw = row['value'];
        wonValue += raw is num
            ? raw.toDouble()
            : double.tryParse(raw?.toString() ?? '') ?? 0;
      case LeadStageKind.lost:
        break;
    }
  }
}
