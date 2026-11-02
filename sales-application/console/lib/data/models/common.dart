import 'package:flutter/material.dart';

import '../../core/theme/app_palette.dart';

/// Lifecycle state shared by Admins, Reps and most other records.
///
/// Wire values match the Flask `status` column exactly.
enum EntityStatus {
  active('active', 'Active'),
  inactive('inactive', 'Inactive'),
  suspended('suspended', 'Suspended'),
  invited('invited', 'Invited');

  const EntityStatus(this.wire, this.label);

  final String wire;
  final String label;

  static EntityStatus fromWire(String? v) => EntityStatus.values.firstWhere(
        (EntityStatus s) => s.wire == v,
        orElse: () => EntityStatus.inactive,
      );

  /// Status colours are reserved tokens - they always travel with a label, so
  /// colour never carries the meaning on its own.
  Color get color {
    switch (this) {
      case EntityStatus.active:
        return VizPalette.statusGood;
      case EntityStatus.invited:
        return VizPalette.statusWarning;
      case EntityStatus.suspended:
        return VizPalette.statusCritical;
      case EntityStatus.inactive:
        return VizPalette.inkMuted;
    }
  }

  IconData get icon {
    switch (this) {
      case EntityStatus.active:
        return Icons.check_circle_outline;
      case EntityStatus.invited:
        return Icons.mail_outline;
      case EntityStatus.suspended:
        return Icons.block;
      case EntityStatus.inactive:
        return Icons.pause_circle_outline;
    }
  }
}

/// A WGS-84 coordinate as recorded by the rep's device.
@immutable
class GeoPoint {
  const GeoPoint({
    required this.lat,
    required this.lng,
    this.accuracyMetres,
    this.recordedAt,
  });

  final double lat;
  final double lng;

  /// Device-reported horizontal accuracy. A large value is why an otherwise
  /// in-radius check-in can still be worth flagging.
  final double? accuracyMetres;
  final DateTime? recordedAt;

  factory GeoPoint.fromJson(Map<String, dynamic> json) => GeoPoint(
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        accuracyMetres: (json['accuracy_m'] as num?)?.toDouble(),
        recordedAt: json['recorded_at'] == null
            ? null
            : DateTime.parse(json['recorded_at'].toString()),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'lat': lat,
        'lng': lng,
        if (accuracyMetres != null) 'accuracy_m': accuracyMetres,
        if (recordedAt != null) 'recorded_at': recordedAt!.toIso8601String(),
      };
}

/// Inclusive date window used by every filter bar and report request.
@immutable
class DateRange {
  const DateRange({required this.start, required this.end, this.label});

  final DateTime start;
  final DateTime end;

  /// Preset name ("Last 30 days") when the range came from a preset row.
  final String? label;

  static DateRange lastDays(int days, {String? label}) {
    final DateTime now = DateTime.now();
    return DateRange(
      start: DateTime(now.year, now.month, now.day - (days - 1)),
      end: DateTime(now.year, now.month, now.day, 23, 59, 59),
      label: label ?? 'Last $days days',
    );
  }

  static DateRange get today {
    final DateTime now = DateTime.now();
    return DateRange(
      start: DateTime(now.year, now.month, now.day),
      end: DateTime(now.year, now.month, now.day, 23, 59, 59),
      label: 'Today',
    );
  }

  static DateRange get monthToDate {
    final DateTime now = DateTime.now();
    return DateRange(
      start: DateTime(now.year, now.month),
      end: now,
      label: 'Month to date',
    );
  }

  static List<DateRange> get presets => <DateRange>[
        today,
        lastDays(7),
        lastDays(30),
        lastDays(90),
        monthToDate,
      ];

  bool contains(DateTime d) =>
      !d.isBefore(start) && !d.isAfter(end);

  int get days => end.difference(start).inDays + 1;

  @override
  bool operator ==(Object other) =>
      other is DateRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// One page of a server-paginated collection.
@immutable
class Paged<T> {
  const Paged({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.total,
  });

  final List<T> items;
  final int page;
  final int pageSize;
  final int total;

  bool get hasMore => page * pageSize < total;

  int get pageCount => pageSize == 0 ? 1 : (total / pageSize).ceil();

  static Paged<T> single<T>(List<T> items) =>
      Paged<T>(items: items, page: 1, pageSize: items.length, total: items.length);

  Paged<R> map<R>(R Function(T) f) => Paged<R>(
        items: items.map(f).toList(growable: false),
        page: page,
        pageSize: pageSize,
        total: total,
      );
}

/// One (x, y) sample in a time series.
@immutable
class TrendPoint {
  const TrendPoint({required this.date, required this.value});

  final DateTime date;
  final double value;

  factory TrendPoint.fromJson(Map<String, dynamic> json) => TrendPoint(
        date: DateTime.parse(json['date'].toString()),
        value: (json['value'] as num).toDouble(),
      );
}
