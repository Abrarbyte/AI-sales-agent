import 'package:intl/intl.dart';

/// Display formatting used across every screen so numbers read the same way in
/// a table cell, a KPI tile and a chart tooltip.
class Fmt {
  const Fmt._();

  static final NumberFormat _int = NumberFormat.decimalPattern();
  static final NumberFormat _compact = NumberFormat.compact();
  // Rupees, with Indian digit grouping - 12,34,567 rather than 1,234,567.
  static final NumberFormat _currency =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
  static final NumberFormat _currencyCompact =
      NumberFormat.compactCurrency(
          locale: 'en_IN', symbol: '₹', decimalDigits: 1);
  static final DateFormat _date = DateFormat('d MMM yyyy');
  static final DateFormat _dateShort = DateFormat('d MMM');
  static final DateFormat _time = DateFormat('HH:mm');
  static final DateFormat _dateTime = DateFormat('d MMM, HH:mm');
  static final DateFormat _monthLabel = DateFormat('MMM');

  static String count(num v) => _int.format(v);

  static String compact(num v) => _compact.format(v);

  static String money(num v) => _currency.format(v);

  static String moneyCompact(num v) => _currencyCompact.format(v);

  /// A ratio already expressed 0..1.
  static String percent(double v, {int decimals = 1}) =>
      '${(v * 100).toStringAsFixed(decimals)}%';

  /// A value already expressed 0..100.
  static String pct(num v, {int decimals = 0}) =>
      '${v.toStringAsFixed(decimals)}%';

  /// Signed delta for a KPI tile: "+12.4%" / "-3.0%".
  static String signedPercent(double v, {int decimals = 1}) {
    final String sign = v > 0 ? '+' : '';
    return '$sign${(v * 100).toStringAsFixed(decimals)}%';
  }

  static String date(DateTime d) => _date.format(d);

  static String dateShort(DateTime d) => _dateShort.format(d);

  static String time(DateTime d) => _time.format(d);

  static String dateTime(DateTime d) => _dateTime.format(d);

  static String month(DateTime d) => _monthLabel.format(d);

  /// ISO-8601 date only, the shape the Flask API expects for range filters.
  static String apiDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// "3m ago" / "2h ago" / "5d ago" for the activity feed and audit log.
  static String relative(DateTime d, {DateTime? now}) {
    final Duration diff = (now ?? DateTime.now()).difference(d);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return _dateShort.format(d);
  }

  /// Distance in metres, switching to km past 1000.
  static String distance(double metres) => metres < 1000
      ? '${metres.round()} m'
      : '${(metres / 1000).toStringAsFixed(1)} km';

  static String duration(Duration d) {
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    final int h = d.inHours;
    final int m = d.inMinutes.remainder(60);
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  static String initials(String name) {
    final List<String> parts =
        name.trim().split(RegExp(r'\s+')).where((String p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}
