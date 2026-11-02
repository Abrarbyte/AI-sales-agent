import 'package:flutter/foundation.dart';

import 'common.dart';

/// What an Admin is allowed to do inside their own branch.
///
/// Only a Super Admin can change these. They are sent as a flat object so the
/// Flask side can store them in a single JSONB column.
@immutable
class AdminPermissions {
  const AdminPermissions({
    this.canCreateReps = true,
    this.canReassignLeads = true,
    this.canApproveVisitProof = true,
    this.canEditTargets = false,
    this.canApproveIncentives = false,
    this.canExportData = false,
    this.canOverrideGeofence = false,
  });

  final bool canCreateReps;
  final bool canReassignLeads;
  final bool canApproveVisitProof;
  final bool canEditTargets;
  final bool canApproveIncentives;
  final bool canExportData;
  final bool canOverrideGeofence;

  factory AdminPermissions.fromJson(Map<String, dynamic> json) =>
      AdminPermissions(
        canCreateReps: json['can_create_reps'] as bool? ?? true,
        canReassignLeads: json['can_reassign_leads'] as bool? ?? true,
        canApproveVisitProof: json['can_approve_visit_proof'] as bool? ?? true,
        canEditTargets: json['can_edit_targets'] as bool? ?? false,
        canApproveIncentives: json['can_approve_incentives'] as bool? ?? false,
        canExportData: json['can_export_data'] as bool? ?? false,
        canOverrideGeofence: json['can_override_geofence'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'can_create_reps': canCreateReps,
        'can_reassign_leads': canReassignLeads,
        'can_approve_visit_proof': canApproveVisitProof,
        'can_edit_targets': canEditTargets,
        'can_approve_incentives': canApproveIncentives,
        'can_export_data': canExportData,
        'can_override_geofence': canOverrideGeofence,
      };

  /// Label / value / setter triples, so the edit form can render the toggles
  /// without a hand-maintained list that drifts from the model.
  List<PermissionToggle> get toggles => <PermissionToggle>[
        PermissionToggle(
          key: 'can_create_reps',
          label: 'Create and edit Sales Reps',
          description: 'Add reps to their own team and edit rep profiles.',
          value: canCreateReps,
          apply: (bool v) => copyWith(canCreateReps: v),
        ),
        PermissionToggle(
          key: 'can_reassign_leads',
          label: 'Reassign leads within team',
          description: 'Move a lead between reps they manage.',
          value: canReassignLeads,
          apply: (bool v) => copyWith(canReassignLeads: v),
        ),
        PermissionToggle(
          key: 'can_approve_visit_proof',
          label: 'Approve visit proof',
          description: 'Clear photo/OTP proof for their own team.',
          value: canApproveVisitProof,
          apply: (bool v) => copyWith(canApproveVisitProof: v),
        ),
        PermissionToggle(
          key: 'can_edit_targets',
          label: 'Edit team targets',
          description: 'Adjust per-rep quotas inside the team total you set.',
          value: canEditTargets,
          apply: (bool v) => copyWith(canEditTargets: v),
        ),
        PermissionToggle(
          key: 'can_approve_incentives',
          label: 'Approve incentive payouts',
          description: 'Sign off payouts up to their approval ceiling.',
          value: canApproveIncentives,
          apply: (bool v) => copyWith(canApproveIncentives: v),
        ),
        PermissionToggle(
          key: 'can_export_data',
          label: 'Export team data',
          description: 'Download CSV/PDF for their own branch only.',
          value: canExportData,
          apply: (bool v) => copyWith(canExportData: v),
        ),
        PermissionToggle(
          key: 'can_override_geofence',
          label: 'Override geofence rules',
          description: 'Loosen the global check-in radius for their branch.',
          value: canOverrideGeofence,
          apply: (bool v) => copyWith(canOverrideGeofence: v),
        ),
      ];

  int get grantedCount => toggles.where((PermissionToggle t) => t.value).length;

  AdminPermissions copyWith({
    bool? canCreateReps,
    bool? canReassignLeads,
    bool? canApproveVisitProof,
    bool? canEditTargets,
    bool? canApproveIncentives,
    bool? canExportData,
    bool? canOverrideGeofence,
  }) =>
      AdminPermissions(
        canCreateReps: canCreateReps ?? this.canCreateReps,
        canReassignLeads: canReassignLeads ?? this.canReassignLeads,
        canApproveVisitProof: canApproveVisitProof ?? this.canApproveVisitProof,
        canEditTargets: canEditTargets ?? this.canEditTargets,
        canApproveIncentives: canApproveIncentives ?? this.canApproveIncentives,
        canExportData: canExportData ?? this.canExportData,
        canOverrideGeofence: canOverrideGeofence ?? this.canOverrideGeofence,
      );
}

@immutable
class PermissionToggle {
  const PermissionToggle({
    required this.key,
    required this.label,
    required this.description,
    required this.value,
    required this.apply,
  });

  final String key;
  final String label;
  final String description;
  final bool value;

  /// Returns a new permission set with this toggle flipped to [v].
  final AdminPermissions Function(bool v) apply;
}

/// A branch / team manager.
@immutable
class AdminUser {
  const AdminUser({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.branch,
    required this.teamName,
    required this.status,
    required this.repCount,
    required this.activeRepCount,
    required this.permissions,
    required this.createdAt,
    this.lastActiveAt,
    this.leadsOwned = 0,
    this.conversionRate = 0,
    this.attainment = 0,
    this.roleWire = 'admin',
    this.managerId,
  });

  final String id;
  final String name;
  final String email;
  final String phone;

  /// Django's own role code - `manager`, `admin` or `super_admin`. Kept so an
  /// edit can send back the role this person actually holds rather than
  /// flattening every supervisor to `admin`.
  final String roleWire;

  /// Who this person reports to, straight from Django's `manager` column.
  /// Distinct from a rep's `adminId`, which is the nearest *Admin* ancestor
  /// after the chain is walked; this is the raw single hop, so an edit can
  /// round-trip it untouched.
  final String? managerId;

  /// Physical branch/office the team reports to.
  final String branch;

  /// The team this Admin runs. One Admin owns exactly one team.
  final String teamName;
  final EntityStatus status;
  final int repCount;
  final int activeRepCount;
  final AdminPermissions permissions;
  final DateTime createdAt;
  final DateTime? lastActiveAt;

  /// Roll-ups the list view shows without a second request.
  final int leadsOwned;

  /// 0..1
  final double conversionRate;

  /// Attainment against the current period's target, 0..1+ (1.0 == on target).
  final double attainment;

  factory AdminUser.fromJson(Map<String, dynamic> json) => AdminUser(
        id: json['id'].toString(),
        name: json['name'].toString(),
        email: json['email'].toString(),
        phone: json['phone']?.toString() ?? '',
        branch: json['branch']?.toString() ?? '',
        teamName: json['team_name']?.toString() ?? '',
        status: EntityStatus.fromWire(json['status']?.toString()),
        repCount: (json['rep_count'] as num?)?.toInt() ?? 0,
        activeRepCount: (json['active_rep_count'] as num?)?.toInt() ?? 0,
        permissions: AdminPermissions.fromJson(
          (json['permissions'] as Map<String, dynamic>?) ??
              const <String, dynamic>{},
        ),
        createdAt: DateTime.parse(json['created_at'].toString()),
        lastActiveAt: json['last_active_at'] == null
            ? null
            : DateTime.parse(json['last_active_at'].toString()),
        leadsOwned: (json['leads_owned'] as num?)?.toInt() ?? 0,
        conversionRate: (json['conversion_rate'] as num?)?.toDouble() ?? 0,
        attainment: (json['attainment'] as num?)?.toDouble() ?? 0,
        roleWire: json['role']?.toString() ?? 'admin',
        managerId: json['manager']?.toString(),
      );

  /// Body for create/update. Roll-ups are server-computed and never sent.
  Map<String, dynamic> toWriteJson() => <String, dynamic>{
        'name': name,
        'email': email,
        'phone': phone,
        'branch': branch,
        'team_name': teamName,
        'status': status.wire,
        'permissions': permissions.toJson(),
      };

  AdminUser copyWith({
    String? name,
    String? email,
    String? phone,
    String? branch,
    String? teamName,
    EntityStatus? status,
    AdminPermissions? permissions,
    int? repCount,
    int? activeRepCount,
    String? roleWire,
    String? managerId,
  }) =>
      AdminUser(
        id: id,
        name: name ?? this.name,
        email: email ?? this.email,
        phone: phone ?? this.phone,
        branch: branch ?? this.branch,
        teamName: teamName ?? this.teamName,
        status: status ?? this.status,
        repCount: repCount ?? this.repCount,
        activeRepCount: activeRepCount ?? this.activeRepCount,
        permissions: permissions ?? this.permissions,
        createdAt: createdAt,
        lastActiveAt: lastActiveAt,
        leadsOwned: leadsOwned,
        conversionRate: conversionRate,
        attainment: attainment,
        roleWire: roleWire ?? this.roleWire,
        managerId: managerId ?? this.managerId,
      );
}

/// A field sales rep. Always belongs to exactly one Admin.
@immutable
class SalesRep {
  const SalesRep({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.adminId,
    required this.teamName,
    required this.branch,
    required this.status,
    required this.joinedAt,
    this.lastCheckInAt,
    this.lastKnownLocation,
    this.assignedLeads = 0,
    this.openLeads = 0,
    this.wonLeads = 0,
    this.visitsThisMonth = 0,
    this.visitComplianceRate = 0,
    this.revenueThisPeriod = 0,
    this.targetThisPeriod = 0,
    this.managerId,
  });

  /// Who this rep reports to, straight from Django's `manager` column. Unlike
  /// [adminId], which is the nearest Admin after the chain is walked, this is
  /// the raw single hop - so an edit sends back exactly what was stored.
  final String? managerId;

  final String id;
  final String name;
  final String email;
  final String phone;

  /// Owning Admin. Changing this is the "reassign rep" operation.
  final String adminId;
  final String teamName;
  final String branch;
  final EntityStatus status;
  final DateTime joinedAt;
  final DateTime? lastCheckInAt;
  final GeoPoint? lastKnownLocation;

  final int assignedLeads;
  final int openLeads;
  final int wonLeads;
  final int visitsThisMonth;

  /// Share of visits that satisfied the proof rules, 0..1.
  final double visitComplianceRate;
  final double revenueThisPeriod;
  final double targetThisPeriod;

  double get attainment =>
      targetThisPeriod == 0 ? 0 : revenueThisPeriod / targetThisPeriod;

  double get conversionRate =>
      assignedLeads == 0 ? 0 : wonLeads / assignedLeads;

  factory SalesRep.fromJson(Map<String, dynamic> json) => SalesRep(
        id: json['id'].toString(),
        name: json['name'].toString(),
        email: json['email']?.toString() ?? '',
        phone: json['phone']?.toString() ?? '',
        adminId: json['admin_id'].toString(),
        teamName: json['team_name']?.toString() ?? '',
        branch: json['branch']?.toString() ?? '',
        status: EntityStatus.fromWire(json['status']?.toString()),
        joinedAt: DateTime.parse(json['joined_at'].toString()),
        lastCheckInAt: json['last_check_in_at'] == null
            ? null
            : DateTime.parse(json['last_check_in_at'].toString()),
        lastKnownLocation: json['last_known_location'] == null
            ? null
            : GeoPoint.fromJson(
                json['last_known_location'] as Map<String, dynamic>),
        assignedLeads: (json['assigned_leads'] as num?)?.toInt() ?? 0,
        openLeads: (json['open_leads'] as num?)?.toInt() ?? 0,
        wonLeads: (json['won_leads'] as num?)?.toInt() ?? 0,
        visitsThisMonth: (json['visits_this_month'] as num?)?.toInt() ?? 0,
        visitComplianceRate:
            (json['visit_compliance_rate'] as num?)?.toDouble() ?? 0,
        revenueThisPeriod:
            (json['revenue_this_period'] as num?)?.toDouble() ?? 0,
        targetThisPeriod: (json['target_this_period'] as num?)?.toDouble() ?? 0,
        managerId: json['manager']?.toString(),
      );

  /// Replaces the denormalised lead counters and rescales revenue to match.
  ///
  /// Used by the mock layer to reconcile a rep against the accounts actually
  /// assigned to them; the real backend computes these in SQL and this method
  /// is never called in production.
  SalesRep withLeadCounters({
    required int assigned,
    required int open,
    required int won,
  }) =>
      SalesRep(
        id: id,
        name: name,
        email: email,
        phone: phone,
        adminId: adminId,
        teamName: teamName,
        branch: branch,
        status: status,
        joinedAt: joinedAt,
        lastCheckInAt: lastCheckInAt,
        lastKnownLocation: lastKnownLocation,
        assignedLeads: assigned,
        openLeads: open,
        wonLeads: won,
        visitsThisMonth: visitsThisMonth,
        visitComplianceRate: visitComplianceRate,
        revenueThisPeriod: revenueThisPeriod,
        targetThisPeriod: targetThisPeriod,
      );

  SalesRep copyWith({String? adminId, String? teamName, String? branch,
      EntityStatus? status, String? managerId}) =>
      SalesRep(
        id: id,
        name: name,
        email: email,
        phone: phone,
        adminId: adminId ?? this.adminId,
        teamName: teamName ?? this.teamName,
        branch: branch ?? this.branch,
        status: status ?? this.status,
        joinedAt: joinedAt,
        lastCheckInAt: lastCheckInAt,
        lastKnownLocation: lastKnownLocation,
        assignedLeads: assignedLeads,
        openLeads: openLeads,
        wonLeads: wonLeads,
        visitsThisMonth: visitsThisMonth,
        visitComplianceRate: visitComplianceRate,
        revenueThisPeriod: revenueThisPeriod,
        targetThisPeriod: targetThisPeriod,
        managerId: managerId ?? this.managerId,
      );
}
