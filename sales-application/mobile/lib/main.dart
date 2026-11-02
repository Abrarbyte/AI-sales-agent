import 'package:flutter/material.dart';

import 'api.dart';
import 'reminders.dart';
import 'screens/followups_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'theme.dart';
import 'widgets/mobile_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Read any saved tokens before the first frame, so a returning user lands
  // on the home screen rather than being bounced through login.
  await Api.instance.loadSavedTokens();
  // Local meeting alarms. Tapping one opens the follow-ups list.
  await Reminders.init();
  Reminders.onOpen = (_) => _navigator.currentState?.push(
        MaterialPageRoute(builder: (_) => const FollowUpsScreen()),
      );
  runApp(const SalesHubApp());
}

final GlobalKey<NavigatorState> _navigator = GlobalKey<NavigatorState>();

class SalesHubApp extends StatelessWidget {
  const SalesHubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigator,
      title: 'SalesHub',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      // The Ambient Neo design is light-only; dark is a derived twin that
      // has never been reviewed. Pinned, so every rep sees the same app.
      themeMode: ThemeMode.light,
      // Wrap every route, so the phone frame persists across navigation
      // instead of only framing the first screen.
      builder: (context, child) => MobileShell(child: child ?? const SizedBox()),
      home: Api.instance.isLoggedIn ? const HomeScreen() : const LoginScreen(),
    );
  }
}
