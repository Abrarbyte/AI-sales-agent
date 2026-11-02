import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'data/api/api_client.dart';
import 'features/auth/auth_state.dart';
import 'features/auth/login_screen.dart';
import 'features/shell/console_shell.dart';
import 'widgets/auto_refresh.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Restores the JWT pair from the last session before the first frame, so a
  // reload lands back on the dashboard rather than the login screen.
  await ApiClient.instance.loadSavedTokens();
  signedIn.value = ApiClient.instance.isLoggedIn;
  // A fresh ProviderScope every time someone signs in or out. One scope for
  // the app's whole life kept the last account's `me` and data cached, so
  // signing out of an Admin and in as the Super Admin still showed the
  // Admin's name, role and dashboard until a reload.
  runApp(ValueListenableBuilder<bool>(
    valueListenable: signedIn,
    builder: (BuildContext context, bool ok, _) =>
        ProviderScope(key: ValueKey<bool>(ok), child: const SalesAdminConsole()),
  ));
}

/// Super Admin console for a single-company sales operation.
///
/// Reads live data from the Django backend in `Sales-Application/backend`;
/// `Config.apiBase` says where that is, and `--dart-define=API_BASE=...`
/// overrides it. Every screen loads through a provider in `data/providers.dart`.
class SalesAdminConsole extends StatelessWidget {
  const SalesAdminConsole({super.key});

  @override
  Widget build(BuildContext context) {
    // Rebuilds the whole app when the light/dark selection changes.
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: appThemeMode,
      builder: (BuildContext context, ThemeMode mode, _) {
        return MaterialApp(
          title: 'AarMarks Media - Super Admin',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: mode,
          // No token, or one the server no longer accepts: the login screen.
          home: ValueListenableBuilder<bool>(
            valueListenable: signedIn,
            builder: (BuildContext context, bool ok, _) =>
                ok ? const AutoRefresh(child: ConsoleShell()) : const LoginScreen(),
          ),
        );
      },
    );
  }
}
