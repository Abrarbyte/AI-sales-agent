import 'package:flutter/foundation.dart';
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'api.dart';
import 'config.dart';

/// The newest phone app build an admin has uploaded (#94).
@immutable
class AppRelease {
  const AppRelease({
    required this.version,
    required this.build,
    required this.url,
    this.notes = '',
    this.minBuild = 0,
    this.sizeMb,
  });

  final String version;
  final int build;

  /// A path on the server, e.g. /media/app/....apk.
  final String url;
  final String notes;

  /// Builds below this must update before carrying on.
  final int minBuild;
  final double? sizeMb;

  factory AppRelease.fromJson(Map<String, dynamic> json) => AppRelease(
        version: json['version']?.toString() ?? '',
        build: (json['build'] as num?)?.toInt() ?? 0,
        url: json['url']?.toString() ?? '',
        notes: json['notes']?.toString() ?? '',
        minBuild: (json['min_build'] as num?)?.toInt() ?? 0,
        sizeMb: (json['size_mb'] as num?)?.toDouble(),
      );
}

enum UpdateNeed { none, optional, required }

/// What this phone should do about [release], given its own build number.
UpdateNeed updateNeed(int currentBuild, AppRelease? release) {
  if (release == null || release.build <= currentBuild) return UpdateNeed.none;
  return currentBuild < release.minBuild
      ? UpdateNeed.required
      : UpdateNeed.optional;
}

/// Checks the server once per app start and remembers the answer, so Home,
/// Settings and the banner all agree without asking twice.
class Updates {
  Updates._();

  /// The release on offer, or null when this build is the newest.
  static final ValueNotifier<AppRelease?> available = ValueNotifier(null);
  static final ValueNotifier<UpdateNeed> need = ValueNotifier(UpdateNeed.none);

  /// "Later" on the banner: hidden until the app is started again.
  static bool dismissed = false;

  static int? _currentBuild;

  static Future<int> currentBuild() async {
    if (_currentBuild != null) return _currentBuild!;
    final info = await PackageInfo.fromPlatform();
    return _currentBuild = int.tryParse(info.buildNumber) ?? 0;
  }

  /// Never throws: a failed check just means no banner this time.
  static Future<UpdateNeed> check() async {
    if (kIsWeb) return UpdateNeed.none;
    try {
      final json = await Api.instance.get('/api/app/latest/');
      final release = AppRelease.fromJson((json as Map).cast());
      final result = updateNeed(await currentBuild(), release);
      available.value = result == UpdateNeed.none ? null : release;
      need.value = result;
      return result;
    } catch (_) {
      // No release uploaded yet (404), offline, or an old server.
      return need.value;
    }
  }

  /// Downloads the release and opens Android's installer. The events report
  /// download progress; the person still taps Install.
  static Stream<OtaEvent> install(AppRelease release) =>
      OtaUpdate().execute(
        '${Config.apiBase}${release.url}',
        destinationFilename: 'saleshub-${release.version}.apk',
      );
}
