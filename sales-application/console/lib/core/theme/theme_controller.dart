import 'package:flutter/material.dart';

/// App-wide theme selection.
///
/// A plain [ValueNotifier] rather than a state-management package: the whole
/// app needs exactly one value, and [MaterialApp] rebuilds from it directly.
///
/// When a backend is wired up, persist the choice against the user profile
/// (GET/PATCH /me/preferences { "theme": "light" | "dark" | "system" }) so it
/// follows the Super Admin between their tablet and desktop.
final ValueNotifier<ThemeMode> appThemeMode = ValueNotifier<ThemeMode>(
  ThemeMode.light,
);

extension ThemeModeLabel on ThemeMode {
  String get label {
    switch (this) {
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.system:
        return 'Match system';
    }
  }

  IconData get icon {
    switch (this) {
      case ThemeMode.light:
        return Icons.light_mode_outlined;
      case ThemeMode.dark:
        return Icons.dark_mode_outlined;
      case ThemeMode.system:
        return Icons.brightness_auto_outlined;
    }
  }
}
