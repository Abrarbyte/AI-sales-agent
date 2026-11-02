import 'package:flutter/foundation.dart';

/// Where the Django backend lives.
///
/// Deployed, the console is served by the same nginx that proxies `/api/`,
/// so the right server is simply the address the page was loaded from -
/// `http://localhost` on the office PC, `https://saleshub.<tailnet>.ts.net`
/// from outside, the PC's IP on the office network. Reading it from the page
/// means one build works at all of them. It used to be compiled in, which
/// broke the console the moment it was opened at any address other than the
/// one it was built for: the phone called its own `localhost` and reported
/// that it could not reach the server.
///
/// In development `flutter run -d chrome` serves the page on one port and
/// Django listens on another, so a debug build still defaults to :8000.
///
/// Override at run time without editing code:
///   flutter run -d chrome --dart-define=API_BASE=http://192.168.1.3:8000
class Config {
  static const String _override = String.fromEnvironment('API_BASE');

  /// The office LAN address, for a console pointed at a shared backend.
  static const String lanAddress = 'http://192.168.1.3:8000';

  static String get apiBase {
    if (_override.isNotEmpty) return _override;
    if (kIsWeb && kReleaseMode) return Uri.base.origin;
    // A debug web run, or a Windows build on the admin's own machine.
    return 'http://localhost:8000';
  }
}
