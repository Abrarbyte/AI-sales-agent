import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geocoding/geocoding.dart';

/// A readable name for a GPS fix - "Baner, Pune" - so neither the salesman
/// nor his manager has to read coordinates (#91).
///
/// Uses the phone's own geocoder: free, no API key. It needs a connection,
/// so it can fail; that is fine. The coordinates are still sent and stay the
/// record, and this returns null rather than holding up a check-in.
Future<String?> placeName(double lat, double lng) async {
  if (kIsWeb) return null;
  try {
    final marks = await Geocoding()
        .placemarkFromCoordinates(lat, lng)
        .timeout(const Duration(seconds: 5));
    if (marks.isEmpty) return null;
    return placeLabel(marks.first);
  } catch (_) {
    return null;
  }
}

/// The area, then the city: "Baner, Pune". Falls back down each list, since
/// a rural fix often has no sub-locality and a city centre no street.
String? placeLabel(Placemark p) {
  String? first(List<String?> values) {
    for (final v in values) {
      final t = v?.trim() ?? '';
      if (t.isNotEmpty) return t;
    }
    return null;
  }

  final area = first([p.subLocality, p.thoroughfare, p.name]);
  final city =
      first([p.locality, p.subAdministrativeArea, p.administrativeArea]);
  final parts = <String>[
    ?area,
    if (city != null && city != area) city,
  ];
  if (parts.isEmpty) return null;
  final label = parts.join(', ');
  // The server keeps 255 characters.
  return label.length > 255 ? label.substring(0, 255) : label;
}
