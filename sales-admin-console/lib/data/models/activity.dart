import 'package:flutter/foundation.dart';

import '../../core/config.dart';

/// A media URL as the API sent it: absolute when the serializer had a
/// request, otherwise `/media/...`, which is resolved against the API host.
String? mediaUrl(dynamic raw) {
  if (raw == null) return null;
  final String s = raw.toString();
  if (s.isEmpty) return null;
  if (s.startsWith('http://') || s.startsWith('https://')) return s;
  return '${Config.apiBase}${s.startsWith('/') ? '' : '/'}$s';
}

double? _num(dynamic v) => v == null ? null : double.tryParse(v.toString());

DateTime? _date(dynamic v) =>
    v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

/// A field visit logged from the phone: who went where, what came of it,
/// and the photo taken on site.
@immutable
class FieldVisit {
  const FieldVisit({
    required this.id,
    required this.repId,
    required this.repName,
    required this.targetName,
    required this.visitedAt,
    required this.outcome,
    this.leadId,
    this.customerId,
    this.lat,
    this.lng,
    this.photoUrl,
    this.notes = '',
    this.durationMinutes,
  });

  final String id;
  final String repId;
  final String repName;
  final String? leadId;
  final String? customerId;

  /// The lead or customer that was visited, by name.
  final String targetName;
  final DateTime visitedAt;

  /// interested | not_interested | follow_up | order_placed | not_available
  final String outcome;
  final double? lat;
  final double? lng;
  final String? photoUrl;
  final String notes;
  final int? durationMinutes;

  bool get hasLocation => lat != null && lng != null;

  factory FieldVisit.fromJson(Map<String, dynamic> json, {String? repName}) =>
      FieldVisit(
        id: json['id'].toString(),
        repId: json['user']?.toString() ?? '',
        repName: repName ?? json['username']?.toString() ?? '',
        leadId: json['lead']?.toString(),
        customerId: json['customer']?.toString(),
        targetName: json['target_name']?.toString() ?? '',
        visitedAt:
            _date(json['visited_at']) ??
            DateTime.fromMillisecondsSinceEpoch(0),
        outcome: json['outcome']?.toString() ?? '',
        lat: _num(json['lat']),
        lng: _num(json['lng']),
        photoUrl: mediaUrl(json['photo']),
        notes: json['notes']?.toString() ?? '',
        durationMinutes: (json['duration_minutes'] as num?)?.toInt(),
      );
}

/// A GPS site check-in the rep tapped during the day - a breadcrumb, not a
/// visit record.
@immutable
class Checkpoint {
  const Checkpoint({
    required this.id,
    required this.repId,
    required this.repName,
    required this.recordedAt,
    required this.lat,
    required this.lng,
    this.accuracyMetres,
    this.note = '',
    this.photoUrl,
  });

  final String id;
  final String repId;
  final String repName;
  final DateTime recordedAt;
  final double lat;
  final double lng;
  final int? accuracyMetres;
  final String note;
  final String? photoUrl;

  factory Checkpoint.fromJson(Map<String, dynamic> json, {String? repName}) =>
      Checkpoint(
        id: json['id'].toString(),
        repId: json['user']?.toString() ?? '',
        repName: repName ?? json['username']?.toString() ?? '',
        recordedAt:
            _date(json['recorded_at']) ??
            DateTime.fromMillisecondsSinceEpoch(0),
        lat: _num(json['lat']) ?? 0,
        lng: _num(json['lng']) ?? 0,
        accuracyMetres: (json['accuracy_m'] as num?)?.toInt(),
        note: json['note']?.toString() ?? '',
        photoUrl: mediaUrl(json['photo']),
      );
}

/// One rep's working day: when they checked in and out, and from where.
@immutable
class AttendanceDay {
  const AttendanceDay({
    required this.id,
    required this.repId,
    required this.repName,
    required this.date,
    required this.kind,
    required this.checkInAt,
    required this.isOpen,
    this.checkOutAt,
    this.checkInLat,
    this.checkInLng,
    this.checkOutLat,
    this.checkOutLng,
    this.note = '',
    this.hoursWorked = 0,
  });

  final String id;
  final String repId;
  final String repName;
  final DateTime date;

  /// field | office
  final String kind;
  final DateTime checkInAt;
  final DateTime? checkOutAt;
  final double? checkInLat;
  final double? checkInLng;
  final double? checkOutLat;
  final double? checkOutLng;
  final String note;
  final double hoursWorked;

  /// Checked in and not yet out.
  final bool isOpen;

  factory AttendanceDay.fromJson(
    Map<String, dynamic> json, {
    String? repName,
  }) => AttendanceDay(
    id: json['id'].toString(),
    repId: json['user']?.toString() ?? '',
    repName: repName ?? json['username']?.toString() ?? '',
    date:
        DateTime.tryParse(json['date']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
    kind: json['kind']?.toString() ?? 'field',
    checkInAt:
        _date(json['check_in_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    checkOutAt: _date(json['check_out_at']),
    checkInLat: _num(json['check_in_lat']),
    checkInLng: _num(json['check_in_lng']),
    checkOutLat: _num(json['check_out_lat']),
    checkOutLng: _num(json['check_out_lng']),
    note: json['note']?.toString() ?? '',
    hoursWorked: (json['hours_worked'] as num?)?.toDouble() ?? 0,
    isOpen: json['is_open'] as bool? ?? json['check_out_at'] == null,
  );
}

/// A follow-up the rep scheduled against a lead or customer, and how it
/// turned out.
@immutable
class FollowUp {
  const FollowUp({
    required this.id,
    required this.repId,
    required this.repName,
    required this.targetName,
    required this.kind,
    required this.status,
    required this.dueAt,
    required this.isOverdue,
    this.leadId,
    this.customerId,
    this.note = '',
    this.completedAt,
    this.outcomeNote = '',
  });

  final String id;
  final String repId;
  final String repName;
  final String? leadId;
  final String? customerId;
  final String targetName;

  /// call | visit | meeting | email | message
  final String kind;

  /// pending | done | cancelled
  final String status;
  final DateTime dueAt;
  final bool isOverdue;
  final String note;
  final DateTime? completedAt;
  final String outcomeNote;

  bool get isPending => status == 'pending';

  factory FollowUp.fromJson(Map<String, dynamic> json, {String? repName}) =>
      FollowUp(
        id: json['id'].toString(),
        repId: json['assigned_to']?.toString() ?? '',
        repName: repName ?? json['assigned_to_name']?.toString() ?? '',
        leadId: json['lead']?.toString(),
        customerId: json['customer']?.toString(),
        targetName: json['target_name']?.toString() ?? '',
        kind: json['kind']?.toString() ?? 'call',
        status: json['status']?.toString() ?? 'pending',
        dueAt: _date(json['due_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
        isOverdue: json['is_overdue'] as bool? ?? false,
        note: json['note']?.toString() ?? '',
        completedAt: _date(json['completed_at']),
        outcomeNote: json['outcome_note']?.toString() ?? '',
      );
}
