import 'package:flutter/material.dart';

import '../../core/theme/app_palette.dart';

/// Where a day's review stands. Colour never carries the meaning alone - every
/// use pairs it with the label and an icon, like the rest of the console.
enum ClaimStatus {
  pending('pending', 'Pending', Icons.hourglass_empty),
  approved('approved', 'Approved', Icons.verified_outlined),
  queried('queried', 'Queried', Icons.help_outline),
  rejected('rejected', 'Rejected', Icons.cancel_outlined);

  const ClaimStatus(this.wire, this.label, this.icon);

  final String wire;
  final String label;
  final IconData icon;

  static ClaimStatus fromWire(String? v) => ClaimStatus.values.firstWhere(
        (ClaimStatus s) => s.wire == v,
        orElse: () => ClaimStatus.pending,
      );

  Color get color {
    switch (this) {
      case ClaimStatus.approved:
        return VizPalette.statusGood;
      case ClaimStatus.pending:
        return VizPalette.statusWarning;
      case ClaimStatus.queried:
        return VizPalette.statusSerious;
      case ClaimStatus.rejected:
        return VizPalette.statusCritical;
    }
  }

  /// Decided one way or the other - the compute job no longer refreshes it.
  bool get isSettled =>
      this == ClaimStatus.approved || this == ClaimStatus.rejected;
}

/// The rupees-per-km rate in force, as the backend's AllowanceRate reports it.
@immutable
class AllowanceRate {
  const AllowanceRate({
    required this.ratePerKm,
    required this.effectiveFrom,
    this.updatedByName = '',
    this.note = '',
  });

  final double ratePerKm;
  final DateTime effectiveFrom;
  final String updatedByName;
  final String note;

  factory AllowanceRate.fromJson(Map<String, dynamic> json) => AllowanceRate(
        ratePerKm:
            double.tryParse(json['rate_per_km']?.toString() ?? '') ?? 0,
        effectiveFrom: DateTime.parse(json['effective_from'].toString()),
        updatedByName: json['updated_by_name']?.toString() ?? '',
        note: json['note']?.toString() ?? '',
      );
}

/// One rep's travel for one day, costed and awaiting a decision. The money
/// figures are a frozen snapshot from the backend, never recomputed here.
@immutable
class TravelClaim {
  const TravelClaim({
    required this.id,
    required this.repId,
    required this.repName,
    required this.date,
    required this.distanceKm,
    required this.ratePerKm,
    required this.amount,
    required this.method,
    required this.isEstimate,
    required this.flaggedLegs,
    required this.status,
    this.approvedByName = '',
    this.reviewedAt,
    this.note = '',
  });

  final String id;
  final String repId;
  final String repName;
  final DateTime date;

  final double distanceKm;
  final double ratePerKm;
  final double amount;

  /// 'road' (Routes API) or 'straight' (haversine estimate).
  final String method;

  /// True when the Routes API was unreachable and straight-line stood in, so
  /// the figure is an estimate rather than a measurement.
  final bool isEstimate;

  /// Legs the backend judged too long to be real travel (a GPS jump). Each is
  /// a map with leg/km/from/to; the console only needs the count and the km.
  final List<Map<String, dynamic>> flaggedLegs;

  final ClaimStatus status;
  final String approvedByName;
  final DateTime? reviewedAt;
  final String note;

  /// Worth a reviewer's eye before approval: a fallback estimate, or a flagged
  /// GPS leg behind the distance.
  bool get needsAttention => isEstimate || flaggedLegs.isNotEmpty;

  factory TravelClaim.fromJson(Map<String, dynamic> json) => TravelClaim(
        id: json['id'].toString(),
        repId: json['user'].toString(),
        repName: json['username']?.toString() ?? '',
        date: DateTime.parse(json['date'].toString()),
        distanceKm: double.tryParse(json['distance_km']?.toString() ?? '') ?? 0,
        ratePerKm: double.tryParse(json['rate_per_km']?.toString() ?? '') ?? 0,
        amount: double.tryParse(json['amount']?.toString() ?? '') ?? 0,
        method: json['method']?.toString() ?? 'straight',
        isEstimate: json['is_estimate'] as bool? ?? false,
        flaggedLegs: ((json['flagged_legs'] as List<dynamic>?) ??
                const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .toList(growable: false),
        status: ClaimStatus.fromWire(json['status']?.toString()),
        approvedByName: json['approved_by_name']?.toString() ?? '',
        reviewedAt: json['reviewed_at'] == null
            ? null
            : DateTime.tryParse(json['reviewed_at'].toString()),
        note: json['note']?.toString() ?? '',
      );
}
