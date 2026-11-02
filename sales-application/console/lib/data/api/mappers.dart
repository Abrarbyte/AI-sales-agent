import '../../core/company_profile.dart';
import '../models/common.dart';
import '../models/lead.dart';
import '../models/ops.dart';
import '../models/people.dart';

/// Translates what Django sends into what the console's models expect.
///
/// The two contracts were designed apart: the console's models were written
/// against a richer API than `backend/` actually serves (branches, targets,
/// incentives, configurable stages). Rather than bend either side, every
/// difference is resolved here, in one file, so a screen never has to know that
/// `SalesRep.branch` is a constant while `SalesRep.wonLeads` is counted from the
/// leads endpoint.
///
/// Where the backend has no equivalent the field is derived if it honestly can
/// be, and left at zero if it cannot. `Mappers.unbackedFields` lists the second
/// group - it is the to-do list for the API.
class Mappers {
  const Mappers._();

  /// Console model fields with no backend source, kept explicit so nobody
  /// mistakes a zero here for a real measurement.
  static const List<String> unbackedFields = <String>[
    'SalesRep.targetThisPeriod - no target/quota model exists',
    'AdminUser.attainment - depends on targets',
    'AdminUser.permissions - derived from role; no per-admin permission store',
    'KpiSnapshot.*Delta - no historical snapshot to compare against',
    'KpiSnapshot.pendingPayoutCount - no incentive model exists',
  ];

  // ---------------------------------------------------------------- people

  /// Django's `is_active` is a boolean; the console has a four-state lifecycle.
  /// Only two of those states are representable, which is the honest mapping -
  /// there is no "suspended" or "invited" in the backend.
  static EntityStatus statusOf(Map<String, dynamic> user) =>
      (user['is_active'] as bool? ?? true)
      ? EntityStatus.active
      : EntityStatus.inactive;

  static String nameOf(Map<String, dynamic> user) {
    final String full = user['full_name']?.toString().trim() ?? '';
    if (full.isNotEmpty) return full;
    return user['username']?.toString() ?? 'Unknown';
  }

  /// Whether this person supervises a team, and so belongs on the Admins
  /// screen rather than the Reps screen.
  ///
  /// Mirrors Django's `User.MANAGER_ROLES` deliberately. A `manager` may have
  /// team members and is `IsManagerOrAbove` on the API, so treating them as a
  /// rep left their reports parented to somebody absent from the Admins list -
  /// those reps' leads then rolled up to nobody, and the team counts
  /// disagreed with the Reps screen.
  static bool isAdminRole(Map<String, dynamic> user) {
    final String role = user['role']?.toString() ?? '';
    return role == 'manager' || role == 'admin' || role == 'super_admin';
  }

  /// A Super Admin may do everything; an Admin gets the day-to-day subset.
  /// The backend stores no per-admin permission flags - `role` is the whole
  /// permission model - so these are derived rather than read.
  static AdminPermissions permissionsFor(Map<String, dynamic> user) {
    final bool isSuper = user['role']?.toString() == 'super_admin';
    return AdminPermissions(
      canCreateReps: true,
      canReassignLeads: true,
      canApproveVisitProof: true,
      canEditTargets: isSuper,
      canApproveIncentives: isSuper,
      canExportData: isSuper,
      canOverrideGeofence: isSuper,
    );
  }

  static DateTime _dateOr(dynamic raw, DateTime fallback) {
    if (raw == null) return fallback;
    return DateTime.tryParse(raw.toString()) ?? fallback;
  }

  static DateTime? _dateOrNull(dynamic raw) =>
      raw == null ? null : DateTime.tryParse(raw.toString());

  /// Builds an [AdminUser] from a Django user plus the roll-ups counted from
  /// the leads endpoint and the team's own membership.
  static AdminUser adminFromUser(
    Map<String, dynamic> user, {
    required int repCount,
    required int activeRepCount,
    required int leadsOwned,
    required double conversionRate,
  }) {
    return AdminUser(
      id: user['id'].toString(),
      name: nameOf(user),
      email: user['email']?.toString() ?? '',
      phone: user['phone']?.toString() ?? '',
      branch: CompanyProfile.branch,
      teamName: CompanyProfile.teamName,
      status: statusOf(user),
      repCount: repCount,
      activeRepCount: activeRepCount,
      permissions: permissionsFor(user),
      createdAt: _dateOr(user['date_joined'], DateTime.now()),
      lastActiveAt: _dateOrNull(user['last_login']),
      leadsOwned: leadsOwned,
      conversionRate: conversionRate,
      // Needs a target model to divide by. See [unbackedFields].
      attainment: 0,
      roleWire: user['role']?.toString() ?? 'admin',
      managerId: user['manager']?.toString(),
      username: user['username']?.toString() ?? '',
    );
  }

  /// Builds a [SalesRep] from a Django user plus roll-ups counted elsewhere.
  static SalesRep repFromUser(
    Map<String, dynamic> user, {
    required String adminId,
    required int assignedLeads,
    required int openLeads,
    required int wonLeads,
    required int visitsThisMonth,
    required double visitComplianceRate,
    required double revenueThisPeriod,
    DateTime? lastCheckInAt,
    GeoPoint? lastKnownLocation,
  }) {
    return SalesRep(
      id: user['id'].toString(),
      name: nameOf(user),
      email: user['email']?.toString() ?? '',
      phone: user['phone']?.toString() ?? '',
      adminId: adminId,
      teamName: CompanyProfile.teamName,
      branch: CompanyProfile.branch,
      status: statusOf(user),
      joinedAt: _dateOr(user['date_joined'], DateTime.now()),
      lastCheckInAt: lastCheckInAt,
      lastKnownLocation: lastKnownLocation,
      assignedLeads: assignedLeads,
      openLeads: openLeads,
      wonLeads: wonLeads,
      visitsThisMonth: visitsThisMonth,
      visitComplianceRate: visitComplianceRate,
      revenueThisPeriod: revenueThisPeriod,
      // Needs a target model. See [unbackedFields].
      targetThisPeriod: 0,
      managerId: user['manager']?.toString(),
      username: user['username']?.toString() ?? '',
    );
  }

  /// The write body `POST/PATCH /api/auth/employees/` expects.
  ///
  /// The console edits a single `name`; Django stores first and last
  /// separately, so it is split on the first space. Branch, team and
  /// permissions are console-side concepts and are deliberately not sent.
  static Map<String, dynamic> employeeWriteJson({
    required String name,
    required String email,
    required String phone,
    required String role,
    String? username,
    String? managerId,
    String? password,
    bool? isActive,
  }) {
    final String trimmed = name.trim();
    final int cut = trimmed.indexOf(' ');
    final String first = cut < 0 ? trimmed : trimmed.substring(0, cut);
    final String last = cut < 0 ? '' : trimmed.substring(cut + 1).trim();

    return <String, dynamic>{
      if (username != null) 'username': username,
      'first_name': first,
      'last_name': last,
      'email': email,
      'phone': phone,
      'role': role,
      if (managerId != null) 'manager': int.tryParse(managerId),
      if (password != null && password.isNotEmpty) 'password': password,
      if (isActive != null) 'is_active': isActive,
    };
  }

  // ----------------------------------------------------------------- leads

  /// The backend's four lead states, as the console's three-way stage kind.
  static LeadStageKind stageKindOf(String? status) {
    switch (status) {
      case 'converted':
        return LeadStageKind.won;
      case 'closed':
        return LeadStageKind.lost;
      default:
        return LeadStageKind.open;
    }
  }

  /// `Lead.Status` doubles as the pipeline stage: the backend has no
  /// configurable stage table, so its statuses *are* the pipeline.
  ///
  /// New -> Demo -> Negotiation -> Proposal -> Customer, with Lost as the
  /// exit from any open stage (#27). Demo and negotiation are entered by
  /// logging a record, never by hand, so a lead sitting there always has
  /// something behind it. The server still stores 'converted' and 'closed';
  /// only the names shown change.
  static const List<PipelineStage> fixedStages = <PipelineStage>[
    PipelineStage(
      id: 'new',
      name: 'New',
      order: 0,
      kind: LeadStageKind.open,
      probability: 0.1,
    ),
    PipelineStage(
      id: 'demo',
      name: 'Demo',
      order: 1,
      kind: LeadStageKind.open,
      probability: 0.5,
    ),
    PipelineStage(
      id: 'negotiation',
      name: 'Negotiation',
      order: 2,
      kind: LeadStageKind.open,
      probability: 0.75,
    ),
    PipelineStage(
      id: 'proposal',
      name: 'Proposal sent',
      order: 3,
      kind: LeadStageKind.open,
      probability: 0.85,
    ),
    PipelineStage(
      id: 'converted',
      name: 'Customer',
      order: 4,
      kind: LeadStageKind.won,
      probability: 1,
    ),
    PipelineStage(
      id: 'closed',
      // Shown as Lost (#22); the stored value is still 'closed'.
      name: 'Lost',
      order: 5,
      kind: LeadStageKind.lost,
      probability: 0,
    ),
  ];

  static PipelineStage stageFor(String? status) => fixedStages.firstWhere(
    (PipelineStage s) => s.id == status,
    orElse: () => fixedStages.first,
  );

  /// Builds a console [Lead] from a DRF lead row.
  ///
  /// `assigned_to_name` is the *username*, not a display name, so when the rep
  /// is known from the employees list that name is preferred.
  static Lead leadFrom(
    Map<String, dynamic> json, {
    String? repName,
    String? adminId,
  }) {
    final PipelineStage stage = stageFor(json['status']?.toString());
    final DateTime created = _dateOr(
      json['created_at'],
      DateTime.fromMillisecondsSinceEpoch(0),
    );

    return Lead(
      id: json['id'].toString(),
      companyName: json['company_name']?.toString().isNotEmpty == true
          ? json['company_name'].toString()
          : json['name']?.toString() ?? '',
      // The backend's `name` is the contact person on the account.
      contactName: json['name']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      stageId: stage.id,
      stageName: stage.name,
      stageKind: stage.kind,
      stageOrder: stage.order,
      source: CompanyProfile.leadSourceLabel(json['source']?.toString()),
      value: _decimal(json['value']),
      repId: json['assigned_to']?.toString() ?? '',
      repName: repName ?? json['assigned_to_name']?.toString() ?? 'Unassigned',
      adminId: adminId ?? '',
      teamName: CompanyProfile.teamName,
      createdAt: created,
      updatedAt: _dateOr(json['updated_at'], created),
      lastVisitAt: null,
      // The soonest pending follow-up, embedded by the leads endpoint.
      nextActionAt: _dateOrNull(
        (json['next_followup'] as Map<String, dynamic>?)?['due_at'],
      ),
      convertedAt: _dateOrNull(json['converted_at']),
      city: json['city']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
      requirement: json['requirement']?.toString() ?? '',
      designation: json['designation']?.toString() ?? '',
      industry: json['industry']?.toString() ?? '',
      projectType: json['project_type']?.toString() ?? '',
      platforms: json['platforms']?.toString() ?? '',
      existingUrl: json['existing_url']?.toString() ?? '',
      priority: json['priority']?.toString() ?? 'warm',
      budget: json['budget'] == null ? null : _decimal(json['budget']),
      expectedStart: _dateOrNull(json['expected_start']),
      lostReason: json['lost_reason']?.toString() ?? '',
      demoCount: (json['demo_count'] as num?)?.toInt() ?? 0,
      latestDemo: json['latest_demo'] == null
          ? null
          : DemoSummary.fromJson(
              (json['latest_demo'] as Map).cast<String, dynamic>(),
            ),
      negotiation: json['negotiation'] == null
          ? null
          : NegotiationSummary.fromJson(
              (json['negotiation'] as Map).cast<String, dynamic>(),
            ),
      amountPaid: _decimal(json['amount_paid']),
      depositRequired: _decimal(json['deposit_required']),
      // Absent from a server older than #32, which always asked for 30%.
      depositShare: json['deposit_share'] == null
          ? 0.30
          : _decimal(json['deposit_share']),
      customerId: json['converted_customer']?.toString(),
      stageChanges: <StageChange>[
        for (final dynamic raw
            in json['stage_changes'] as List<dynamic>? ?? const <dynamic>[])
          if (raw is Map)
            StageChange(
              fromStage: stageFor(raw['from_status']?.toString()).name,
              toStage: stageFor(raw['to_status']?.toString()).name,
              by: raw['changed_by_name']?.toString() ?? 'Someone',
              reason: raw['reason']?.toString() ?? '',
              at: _dateOr(
                raw['changed_at'],
                DateTime.fromMillisecondsSinceEpoch(0),
              ),
            ),
      ],
    );
  }

  /// DRF serialises `DecimalField` as a string ("1250.00") unless
  /// COERCE_DECIMAL_TO_STRING is off, so both shapes are accepted.
  static double _decimal(dynamic raw) {
    if (raw == null) return 0;
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw.toString()) ?? 0;
  }

  static GeoPoint? geoFrom(dynamic lat, dynamic lng) {
    final double? a = lat == null ? null : _decimal(lat);
    final double? b = lng == null ? null : _decimal(lng);
    if (a == null || b == null) return null;
    if (a == 0 && b == 0) return null;
    return GeoPoint(lat: a, lng: b);
  }
}
