import 'package:flutter/foundation.dart';

/// Where the Django backend lives.
///
/// The console is a desktop/web client, so unlike the phone app the default is
/// this machine — an admin runs it in Chrome or as a Windows build against a
/// backend on the same host or the office LAN.
///
/// Override at run time without editing code:
///   flutter run -d chrome --dart-define=API_BASE=http://192.168.1.3:8000
class Config {
  static const String _override = String.fromEnvironment('API_BASE');

  /// The office LAN address, for a console pointed at a shared backend.
  static const String lanAddress = 'http://192.168.1.3:8000';

  static String get apiBase {
    if (_override.isNotEmpty) return _override;
    if (kIsWeb) return 'http://localhost:8000';
    // A Windows build on the admin's own machine talks to localhost too; a
    // console run against the shared backend passes --dart-define.
    return 'http://localhost:8000';
  }
}
