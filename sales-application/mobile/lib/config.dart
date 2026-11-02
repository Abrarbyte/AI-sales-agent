import 'package:flutter/foundation.dart';

/// Where the Django backend lives.
///
/// The right address depends on where the app is running, and getting this
/// wrong is the usual first-day frustration:
///   * Chrome on this machine  -> localhost
///   * Android emulator        -> 10.0.2.2 (its alias for the host machine)
///   * A real phone on Wi-Fi   -> the laptop's LAN address
///
/// Override at run time without editing code:
///   flutter run --dart-define=API_BASE=http://192.168.1.3:8000
class Config {
  static const String _override = String.fromEnvironment('API_BASE');

  /// This machine's Wi-Fi address, for testing on a real phone.
  static const String lanAddress = 'http://192.168.1.3:8000';

  /// Tests point the client at a local stand-in server.
  static String? _testBase;
  static void debugOverrideBase(String base) => _testBase = base;

  static String get apiBase {
    if (_testBase != null) return _testBase!;
    if (_override.isNotEmpty) return _override;
    if (kIsWeb) return 'http://localhost:8000';
    // Android: the emulator needs 10.0.2.2; a real device needs the LAN IP.
    // Defaulting to the LAN address, since a real phone is the honest test
    // for a field app.
    return lanAddress;
  }

  /// True when the build was given a server explicitly. A release build
  /// without one is pointed at a developer's laptop, which is worth showing
  /// on the Settings screen rather than silently failing in the field.
  static bool get isConfigured => _override.isNotEmpty;

  /// Build for the field:
  ///   flutter build apk --release --dart-define=API_BASE=https://api.example.com
  static bool get isRelease => kReleaseMode;
}
