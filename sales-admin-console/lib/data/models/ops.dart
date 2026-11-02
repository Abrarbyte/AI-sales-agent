import 'package:flutter/material.dart';

import '../../core/theme/app_palette.dart';
import 'lead.dart';

/// Categories the audit log can be filtered by. Kept coarse on purpose - a
/// filter with forty options is not a filter.
enum AuditActionType {
  auth('auth', 'Sign-in / out', Icons.login),
  leadChange('lead_change', 'Lead change', Icons.filter_alt_outlined),
  leadReassign('lead_reassign', 'Lead reassignment', Icons.swap_horiz),
  visitReview('visit_review', 'Visit proof review', Icons.verified_outlined),
  userAdmin('user_admin', 'User administration', Icons.manage_accounts_outlined),
  targetChange('target_change', 'Target change', Icons.flag_outlined),
  payoutDecision('payout_decision', 'Payout decision', Icons.payments_outlined),
  configChange('config_change', 'Configuration change', Icons.tune),
  announcement('announcement', 'Announcement', Icons.campaign_outlined),
  export('export', 'Data export', Icons.download_outlined);

  const AuditActionType(this.wire, this.label, this.icon);

  final String wire;
  final String label;
  final IconData icon;

  static AuditActionType fromWire(String? v) =>
      AuditActionType.values.firstWhere(
        (AuditActionType a) => a.wire == v,
        orElse: () => AuditActionType.leadChange,
      );

  /// Actions that change who can do what, or move money. Rendered with a
  /// stronger weight in the log so they are findable by eye.
  bool get isSensitive =>
      this == AuditActionType.userAdmin ||
      this == AuditActionType.payoutDecision ||
      this == AuditActionType.configChange ||
      this == AuditActionType.export;
}

@immutable
class AuditEvent {
  const AuditEvent({
    required this.id,
    required this.at,
    required this.actorId,
    required this.actorName,
    required this.actorRole,
    required this.type,
    required this.summary,
    this.targetLabel,
    this.detail,
    this.ipAddress,
    this.beforeValue,
    this.afterValue,
  });

  final String id;
  final DateTime at;
  final String actorId;
  final String actorName;

  /// Wire value of the actor's role at the time of the action.
  final String actorRole;
  final AuditActionType type;

  /// One-line description already rendered by the backend, e.g.
  /// "Reassigned 12 leads from Northern to Coastal".
  final String summary;

  /// The record acted on, e.g. "Lead #4821" or "Admin: Priya Nair".
  final String? targetLabel;
  final String? detail;
  final String? ipAddress;

  /// Old/new values for a field-level change, when the backend records them.
  final String? beforeValue;
  final String? afterValue;

  bool get hasDiff => beforeValue != null || afterValue != null;

  factory AuditEvent.fromJson(Map<String, dynamic> json) => AuditEvent(
        id: json['id'].toString(),
        at: DateTime.parse(json['at'].toString()),
        actorId: json['actor_id'].toString(),
        actorName: json['actor_name']?.toString() ?? '',
        actorRole: json['actor_role']?.toString() ?? '',
        type: AuditActionType.fromWire(json['type']?.toString()),
        summary: json['summary']?.toString() ?? '',
        targetLabel: json['target_label']?.toString(),
        detail: json['detail']?.toString(),
        ipAddress: json['ip_address']?.toString(),
        beforeValue: json['before']?.toString(),
        afterValue: json['after']?.toString(),
      );
}

/// Who an announcement reaches.
enum AnnouncementAudience {
  admins('admins', 'All Admins'),
  adminsAndReps('admins_and_reps', 'All Admins + Sales Reps'),
  selectedTeams('selected_teams', 'Selected teams');

  const AnnouncementAudience(this.wire, this.label);

  final String wire;
  final String label;

  static AnnouncementAudience fromWire(String? v) =>
      AnnouncementAudience.values.firstWhere(
        (AnnouncementAudience a) => a.wire == v,
        orElse: () => AnnouncementAudience.admins,
      );
}

enum AnnouncementChannel {
  push('push', 'Push notification', Icons.notifications_active_outlined),
  inApp('in_app', 'In-app banner', Icons.web_asset),
  email('email', 'Email', Icons.mail_outline),
  sms('sms', 'SMS', Icons.sms_outlined);

  const AnnouncementChannel(this.wire, this.label, this.icon);

  final String wire;
  final String label;
  final IconData icon;
}

@immutable
class Announcement {
  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    required this.audience,
    required this.channels,
    required this.sentAt,
    required this.sentByName,
    this.teamIds = const <String>[],
    this.recipientCount = 0,
    this.readCount = 0,
    this.scheduledFor,
    this.pinned = false,
  });

  final String id;
  final String title;
  final String body;
  final AnnouncementAudience audience;
  final List<AnnouncementChannel> channels;

  /// Null while an announcement is still scheduled.
  final DateTime? sentAt;
  final String sentByName;
  final List<String> teamIds;
  final int recipientCount;
  final int readCount;
  final DateTime? scheduledFor;

  /// Keeps the message at the top of the recipients' in-app feed.
  final bool pinned;

  bool get isScheduled => sentAt == null && scheduledFor != null;

  double get readRate => recipientCount == 0 ? 0 : readCount / recipientCount;

  factory Announcement.fromJson(Map<String, dynamic> json) => Announcement(
        id: json['id'].toString(),
        title: json['title']?.toString() ?? '',
        body: json['body']?.toString() ?? '',
        audience: AnnouncementAudience.fromWire(json['audience']?.toString()),
        channels: ((json['channels'] as List<dynamic>?) ?? const <dynamic>[])
            .map((dynamic e) => AnnouncementChannel.values.firstWhere(
                  (AnnouncementChannel c) => c.wire == e.toString(),
                  orElse: () => AnnouncementChannel.inApp,
                ))
            .toList(growable: false),
        sentAt: json['sent_at'] == null
            ? null
            : DateTime.parse(json['sent_at'].toString()),
        sentByName: json['sent_by_name']?.toString() ?? '',
        teamIds: ((json['team_ids'] as List<dynamic>?) ?? const <dynamic>[])
            .map((dynamic e) => e.toString())
            .toList(growable: false),
        recipientCount: (json['recipient_count'] as num?)?.toInt() ?? 0,
        readCount: (json['read_count'] as num?)?.toInt() ?? 0,
        scheduledFor: json['scheduled_for'] == null
            ? null
            : DateTime.parse(json['scheduled_for'].toString()),
        pinned: json['pinned'] as bool? ?? false,
      );
}

// --- Configuration models --------------------------------------------------

/// A configurable pipeline stage. Order is the display order left-to-right in
/// the funnel; [kind] tells the analytics layer how to count it.
@immutable
class PipelineStage {
  const PipelineStage({
    required this.id,
    required this.name,
    required this.order,
    required this.kind,
    this.probability = 0,
    this.leadCount = 0,
  });

  final String id;
  final String name;
  final int order;
  final LeadStageKind kind;

  /// Default close probability, 0..1. Feeds the weighted-pipeline figure.
  final double probability;

  /// Live count, so deleting a stage can warn about what it would strand.
  final int leadCount;

  factory PipelineStage.fromJson(Map<String, dynamic> json) => PipelineStage(
        id: json['id'].toString(),
        name: json['name']?.toString() ?? '',
        order: (json['order'] as num?)?.toInt() ?? 0,
        kind: LeadStageKind.fromWire(json['kind']?.toString()),
        probability: (json['probability'] as num?)?.toDouble() ?? 0,
        leadCount: (json['lead_count'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toWriteJson() => <String, dynamic>{
        'name': name,
        'order': order,
        'kind': kind.wire,
        'probability': probability,
      };

  PipelineStage copyWith({String? name, int? order, double? probability}) =>
      PipelineStage(
        id: id,
        name: name ?? this.name,
        order: order ?? this.order,
        kind: kind,
        probability: probability ?? this.probability,
        leadCount: leadCount,
      );
}

@immutable
class LeadSourceDef {
  const LeadSourceDef({
    required this.id,
    required this.name,
    required this.active,
    this.leadCount = 0,
  });

  final String id;
  final String name;
  final bool active;
  final int leadCount;

  factory LeadSourceDef.fromJson(Map<String, dynamic> json) => LeadSourceDef(
        id: json['id'].toString(),
        name: json['name']?.toString() ?? '',
        active: json['active'] as bool? ?? true,
        leadCount: (json['lead_count'] as num?)?.toInt() ?? 0,
      );
}

enum CustomFieldType {
  text('text', 'Text'),
  number('number', 'Number'),
  date('date', 'Date'),
  dropdown('dropdown', 'Dropdown'),
  checkbox('checkbox', 'Checkbox');

  const CustomFieldType(this.wire, this.label);

  final String wire;
  final String label;

  static CustomFieldType fromWire(String? v) =>
      CustomFieldType.values.firstWhere(
        (CustomFieldType t) => t.wire == v,
        orElse: () => CustomFieldType.text,
      );
}

@immutable
class CustomFieldDef {
  const CustomFieldDef({
    required this.id,
    required this.label,
    required this.type,
    required this.entity,
    required this.required_,
    this.options = const <String>[],
  });

  final String id;
  final String label;
  final CustomFieldType type;

  /// Which record the field hangs off: "lead" | "visit" | "rep".
  final String entity;

  /// Trailing underscore: `required` is a reserved word in Dart.
  final bool required_;
  final List<String> options;

  factory CustomFieldDef.fromJson(Map<String, dynamic> json) => CustomFieldDef(
        id: json['id'].toString(),
        label: json['label']?.toString() ?? '',
        type: CustomFieldType.fromWire(json['type']?.toString()),
        entity: json['entity']?.toString() ?? 'lead',
        required_: json['required'] as bool? ?? false,
        options: ((json['options'] as List<dynamic>?) ?? const <dynamic>[])
            .map((dynamic e) => e.toString())
            .toList(growable: false),
      );
}

@immutable
class NotificationTemplate {
  const NotificationTemplate({
    required this.id,
    required this.key,
    required this.name,
    required this.subject,
    required this.body,
    required this.channels,
    required this.enabled,
  });

  final String id;

  /// Stable trigger key, e.g. `visit_proof_rejected`.
  final String key;
  final String name;
  final String subject;

  /// Supports `{{placeholders}}` resolved server-side at send time.
  final String body;
  final List<AnnouncementChannel> channels;
  final bool enabled;

  factory NotificationTemplate.fromJson(Map<String, dynamic> json) =>
      NotificationTemplate(
        id: json['id'].toString(),
        key: json['key']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        subject: json['subject']?.toString() ?? '',
        body: json['body']?.toString() ?? '',
        channels: ((json['channels'] as List<dynamic>?) ?? const <dynamic>[])
            .map((dynamic e) => AnnouncementChannel.values.firstWhere(
                  (AnnouncementChannel c) => c.wire == e.toString(),
                  orElse: () => AnnouncementChannel.inApp,
                ))
            .toList(growable: false),
        enabled: json['enabled'] as bool? ?? true,
      );

  NotificationTemplate copyWith({
    String? subject,
    String? body,
    bool? enabled,
  }) =>
      NotificationTemplate(
        id: id,
        key: key,
        name: name,
        subject: subject ?? this.subject,
        body: body ?? this.body,
        channels: channels,
        enabled: enabled ?? this.enabled,
      );
}

/// Attendance policy applied to every rep unless a branch overrides it.
@immutable
class WorkingHoursRule {
  const WorkingHoursRule({
    required this.startMinutes,
    required this.endMinutes,
    required this.workingDays,
    required this.requireCheckIn,
    required this.graceMinutes,
    required this.autoCheckoutMinutes,
  });

  /// Minutes from midnight, so a TimeOfDay round-trips without a timezone.
  final int startMinutes;
  final int endMinutes;

  /// 1 = Monday .. 7 = Sunday, matching DateTime.weekday.
  final Set<int> workingDays;
  final bool requireCheckIn;

  /// How late a rep may check in before it counts against attendance.
  final int graceMinutes;

  /// Close an open visit automatically after this long.
  final int autoCheckoutMinutes;

  TimeOfDay get start =>
      TimeOfDay(hour: startMinutes ~/ 60, minute: startMinutes % 60);

  TimeOfDay get end =>
      TimeOfDay(hour: endMinutes ~/ 60, minute: endMinutes % 60);

  factory WorkingHoursRule.fromJson(Map<String, dynamic> json) =>
      WorkingHoursRule(
        startMinutes: (json['start_minutes'] as num?)?.toInt() ?? 540,
        endMinutes: (json['end_minutes'] as num?)?.toInt() ?? 1080,
        workingDays: ((json['working_days'] as List<dynamic>?) ??
                const <dynamic>[1, 2, 3, 4, 5, 6])
            .map((dynamic e) => (e as num).toInt())
            .toSet(),
        requireCheckIn: json['require_check_in'] as bool? ?? true,
        graceMinutes: (json['grace_minutes'] as num?)?.toInt() ?? 15,
        autoCheckoutMinutes:
            (json['auto_checkout_minutes'] as num?)?.toInt() ?? 240,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'start_minutes': startMinutes,
        'end_minutes': endMinutes,
        'working_days': workingDays.toList()..sort(),
        'require_check_in': requireCheckIn,
        'grace_minutes': graceMinutes,
        'auto_checkout_minutes': autoCheckoutMinutes,
      };

  WorkingHoursRule copyWith({
    int? startMinutes,
    int? endMinutes,
    Set<int>? workingDays,
    bool? requireCheckIn,
    int? graceMinutes,
    int? autoCheckoutMinutes,
  }) =>
      WorkingHoursRule(
        startMinutes: startMinutes ?? this.startMinutes,
        endMinutes: endMinutes ?? this.endMinutes,
        workingDays: workingDays ?? this.workingDays,
        requireCheckIn: requireCheckIn ?? this.requireCheckIn,
        graceMinutes: graceMinutes ?? this.graceMinutes,
        autoCheckoutMinutes: autoCheckoutMinutes ?? this.autoCheckoutMinutes,
      );
}

@immutable
class FeatureToggle {
  const FeatureToggle({
    required this.key,
    required this.name,
    required this.description,
    required this.enabled,
    this.risky = false,
  });

  final String key;
  final String name;
  final String description;
  final bool enabled;

  /// Toggles that change field behaviour for everyone get a confirm step.
  final bool risky;

  factory FeatureToggle.fromJson(Map<String, dynamic> json) => FeatureToggle(
        key: json['key'].toString(),
        name: json['name']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
        enabled: json['enabled'] as bool? ?? false,
        risky: json['risky'] as bool? ?? false,
      );

  FeatureToggle copyWith({bool? enabled}) => FeatureToggle(
        key: key,
        name: name,
        description: description,
        enabled: enabled ?? this.enabled,
        risky: risky,
      );
}

/// Colour helper shared by the ops screens for a read-rate / compliance meter.
Color complianceColor(double ratio) {
  if (ratio >= 0.9) return VizPalette.statusGood;
  if (ratio >= 0.75) return VizPalette.statusWarning;
  if (ratio >= 0.5) return VizPalette.statusSerious;
  return VizPalette.statusCritical;
}
