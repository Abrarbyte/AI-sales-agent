import 'package:flutter/material.dart';

import '../../core/theme/app_palette.dart';
import 'common.dart';

/// Review state of a visit's proof-of-presence.
enum ProofStatus {
  pending('pending', 'Pending review'),
  approved('approved', 'Approved'),
  flagged('flagged', 'Flagged'),
  rejected('rejected', 'Rejected');

  const ProofStatus(this.wire, this.label);

  final String wire;
  final String label;

  static ProofStatus fromWire(String? v) => ProofStatus.values.firstWhere(
        (ProofStatus s) => s.wire == v,
        orElse: () => ProofStatus.pending,
      );

  Color get color {
    switch (this) {
      case ProofStatus.approved:
        return VizPalette.statusGood;
      case ProofStatus.pending:
        return VizPalette.statusWarning;
      case ProofStatus.flagged:
        return VizPalette.statusSerious;
      case ProofStatus.rejected:
        return VizPalette.statusCritical;
    }
  }

  IconData get icon {
    switch (this) {
      case ProofStatus.approved:
        return Icons.verified_outlined;
      case ProofStatus.pending:
        return Icons.hourglass_empty;
      case ProofStatus.flagged:
        return Icons.flag_outlined;
      case ProofStatus.rejected:
        return Icons.cancel_outlined;
    }
  }
}

/// How the rep proved they were on site.
enum ProofKind {
  photo('photo', 'Photo'),
  otp('otp', 'Customer OTP'),
  signature('signature', 'Signature'),
  none('none', 'No proof');

  const ProofKind(this.wire, this.label);

  final String wire;
  final String label;

  static ProofKind fromWire(String? v) => ProofKind.values.firstWhere(
        (ProofKind k) => k.wire == v,
        orElse: () => ProofKind.none,
      );

  IconData get icon {
    switch (this) {
      case ProofKind.photo:
        return Icons.photo_camera_outlined;
      case ProofKind.otp:
        return Icons.pin_outlined;
      case ProofKind.signature:
        return Icons.draw_outlined;
      case ProofKind.none:
        return Icons.block;
    }
  }
}

@immutable
class VisitProof {
  const VisitProof({
    required this.kind,
    required this.status,
    this.photoUrl,
    this.otpVerified,
    this.capturedAt,
    this.reviewerName,
    this.reviewedAt,
    this.reviewNote,
  });

  final ProofKind kind;
  final ProofStatus status;

  /// Signed URL from object storage. Expires - fetch it with the visit, do not
  /// cache it across sessions.
  final String? photoUrl;
  final bool? otpVerified;
  final DateTime? capturedAt;
  final String? reviewerName;
  final DateTime? reviewedAt;
  final String? reviewNote;

  factory VisitProof.fromJson(Map<String, dynamic> json) => VisitProof(
        kind: ProofKind.fromWire(json['kind']?.toString()),
        status: ProofStatus.fromWire(json['status']?.toString()),
        photoUrl: json['photo_url']?.toString(),
        otpVerified: json['otp_verified'] as bool?,
        capturedAt: json['captured_at'] == null
            ? null
            : DateTime.parse(json['captured_at'].toString()),
        reviewerName: json['reviewer_name']?.toString(),
        reviewedAt: json['reviewed_at'] == null
            ? null
            : DateTime.parse(json['reviewed_at'].toString()),
        reviewNote: json['review_note']?.toString(),
      );
}

/// A single field check-in.
@immutable
class Visit {
  const Visit({
    required this.id,
    required this.repId,
    required this.repName,
    required this.adminId,
    required this.teamName,
    required this.leadId,
    required this.leadName,
    required this.checkInAt,
    required this.location,
    required this.proof,
    required this.distanceFromLeadMetres,
    required this.withinGeofence,
    this.checkOutAt,
    this.durationMinutes = 0,
    this.outcome = '',
    this.address = '',
  });

  final String id;
  final String repId;
  final String repName;
  final String adminId;
  final String teamName;
  final String leadId;
  final String leadName;
  final DateTime checkInAt;
  final DateTime? checkOutAt;
  final GeoPoint location;
  final VisitProof proof;

  /// Metres between the check-in point and the lead's registered address.
  final double distanceFromLeadMetres;

  /// Whether that distance was inside the geofence radius in force at the time.
  final bool withinGeofence;

  final int durationMinutes;
  final String outcome;
  final String address;

  /// A visit worth a Super Admin's attention: outside the fence, or no proof
  /// captured at all.
  bool get needsAttention =>
      !withinGeofence || proof.kind == ProofKind.none;

  factory Visit.fromJson(Map<String, dynamic> json) => Visit(
        id: json['id'].toString(),
        repId: json['rep_id'].toString(),
        repName: json['rep_name']?.toString() ?? '',
        adminId: json['admin_id'].toString(),
        teamName: json['team_name']?.toString() ?? '',
        leadId: json['lead_id']?.toString() ?? '',
        leadName: json['lead_name']?.toString() ?? '',
        checkInAt: DateTime.parse(json['check_in_at'].toString()),
        checkOutAt: json['check_out_at'] == null
            ? null
            : DateTime.parse(json['check_out_at'].toString()),
        location: GeoPoint.fromJson(json['location'] as Map<String, dynamic>),
        proof: VisitProof.fromJson(
          (json['proof'] as Map<String, dynamic>?) ?? const <String, dynamic>{},
        ),
        distanceFromLeadMetres:
            (json['distance_from_lead_m'] as num?)?.toDouble() ?? 0,
        withinGeofence: json['within_geofence'] as bool? ?? true,
        durationMinutes: (json['duration_minutes'] as num?)?.toInt() ?? 0,
        outcome: json['outcome']?.toString() ?? '',
        address: json['address']?.toString() ?? '',
      );
}

/// One rep's ordered GPS breadcrumbs for a day.
@immutable
class GpsTrail {
  const GpsTrail({
    required this.repId,
    required this.date,
    required this.points,
    this.totalDistanceMetres = 0,
  });

  final String repId;
  final DateTime date;

  /// Ordered oldest to newest.
  final List<GeoPoint> points;
  final double totalDistanceMetres;

  factory GpsTrail.fromJson(Map<String, dynamic> json) => GpsTrail(
        repId: json['rep_id'].toString(),
        date: DateTime.parse(json['date'].toString()),
        points: ((json['points'] as List<dynamic>?) ?? const <dynamic>[])
            .map((dynamic e) => GeoPoint.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        totalDistanceMetres:
            (json['total_distance_m'] as num?)?.toDouble() ?? 0,
      );
}

/// Global proof-of-visit policy, optionally overridden per Admin.
@immutable
class GeofenceRules {
  const GeofenceRules({
    required this.radiusMetres,
    required this.requirePhoto,
    required this.requireOtp,
    required this.allowManualAddress,
    required this.maxAccuracyMetres,
    required this.autoFlagOutsideRadius,
    this.adminId,
    this.adminName,
  });

  /// How far from the lead's registered address a check-in may be.
  final int radiusMetres;
  final bool requirePhoto;
  final bool requireOtp;

  /// Whether a rep may type an address when GPS is unavailable.
  final bool allowManualAddress;

  /// Reject a fix whose device accuracy is worse than this.
  final int maxAccuracyMetres;

  /// Send out-of-radius check-ins straight to the review queue.
  final bool autoFlagOutsideRadius;

  /// Null for the company-wide default; set on a per-Admin override.
  final String? adminId;
  final String? adminName;

  bool get isOverride => adminId != null;

  factory GeofenceRules.fromJson(Map<String, dynamic> json) => GeofenceRules(
        radiusMetres: (json['radius_m'] as num?)?.toInt() ?? 200,
        requirePhoto: json['require_photo'] as bool? ?? true,
        requireOtp: json['require_otp'] as bool? ?? false,
        allowManualAddress: json['allow_manual_address'] as bool? ?? false,
        maxAccuracyMetres: (json['max_accuracy_m'] as num?)?.toInt() ?? 50,
        autoFlagOutsideRadius:
            json['auto_flag_outside_radius'] as bool? ?? true,
        adminId: json['admin_id']?.toString(),
        adminName: json['admin_name']?.toString(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'radius_m': radiusMetres,
        'require_photo': requirePhoto,
        'require_otp': requireOtp,
        'allow_manual_address': allowManualAddress,
        'max_accuracy_m': maxAccuracyMetres,
        'auto_flag_outside_radius': autoFlagOutsideRadius,
        if (adminId != null) 'admin_id': adminId,
      };

  GeofenceRules copyWith({
    int? radiusMetres,
    bool? requirePhoto,
    bool? requireOtp,
    bool? allowManualAddress,
    int? maxAccuracyMetres,
    bool? autoFlagOutsideRadius,
  }) =>
      GeofenceRules(
        radiusMetres: radiusMetres ?? this.radiusMetres,
        requirePhoto: requirePhoto ?? this.requirePhoto,
        requireOtp: requireOtp ?? this.requireOtp,
        allowManualAddress: allowManualAddress ?? this.allowManualAddress,
        maxAccuracyMetres: maxAccuracyMetres ?? this.maxAccuracyMetres,
        autoFlagOutsideRadius:
            autoFlagOutsideRadius ?? this.autoFlagOutsideRadius,
        adminId: adminId,
        adminName: adminName,
      );
}
