import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../api.dart';
import '../config.dart';
import '../theme.dart';
import '../updates.dart';
import '../widgets/motion.dart';
import '../widgets/update_widgets.dart';
import 'login_screen.dart';

/// Who is signed in, where the app is pointed, whether the phone will let it
/// do its job (location, notifications), and sign out.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.me});

  final Map<String, dynamic>? me;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  PackageInfo? _pkg;
  bool _checkingUpdate = false;

  /// Settings' own "Check for updates" (#94): the newest build if there is
  /// one, otherwise a note that this is already it.
  Future<void> _checkForUpdate() async {
    setState(() => _checkingUpdate = true);
    await Updates.check();
    if (!mounted) return;
    setState(() => _checkingUpdate = false);
    final release = Updates.available.value;
    if (release != null) {
      await showUpdateSheet(context, release);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You have the newest version.')));
    }
  }

  LocationPermission? _location;
  bool? _notifications;
  bool _serverOk = false;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    final pkg = await PackageInfo.fromPlatform();
    LocationPermission? loc;
    bool? notif;
    try {
      loc = await Geolocator.checkPermission();
    } catch (_) {}
    try {
      notif = await FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.areNotificationsEnabled();
    } catch (_) {}
    bool ok = false;
    try {
      await Api.instance.get('/api/health/');
      ok = true;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _pkg = pkg;
      _location = loc;
      _notifications = notif;
      _serverOk = ok;
      _checking = false;
    });
  }

  Future<void> _signOut() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('Reminders scheduled on this phone are cleared.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Stay')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Sign out')),
        ],
      ),
    );
    if (yes != true) return;
    await Api.instance.logout();
    try {
      await FlutterLocalNotificationsPlugin().cancelAll();
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final me = widget.me;
    final name = [me?['first_name'], me?['last_name']]
        .where((x) => (x?.toString() ?? '').isNotEmpty)
        .join(' ');

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: RefreshIndicator(
        onRefresh: _check,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Reveal(
              index: 0,
              child: SurfaceCard(
                radius: AppTheme.radiusXl,
                child: Row(
                  children: [
                    const NeoIconWell(Icons.person_outline),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name.isEmpty ? (me?['username']?.toString() ?? '-') : name,
                              style: AppTheme.sans(16, 600, 22,
                                  color: scheme.onSurface)),
                          Text(
                            '@${me?['username'] ?? ''}'
                            '${(me?['role_display'] ?? me?['role']) == null ? '' : ' · ${me?['role_display'] ?? me?['role']}'}',
                            style: TextStyle(
                                fontSize: 12, color: scheme.onSurfaceVariant),
                          ),
                          if ((me?['manager_name']?.toString() ?? '').isNotEmpty)
                            Text('Reports to ${me!['manager_name']}',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Reveal(
              index: 1,
              child: _card(scheme, 'Phone permissions', [
                _row(
                  scheme,
                  Icons.my_location,
                  'Location',
                  _checking
                      ? 'Checking...'
                      : switch (_location) {
                          LocationPermission.always ||
                          LocationPermission.whileInUse =>
                            'Allowed',
                          LocationPermission.deniedForever =>
                            'Blocked - enable in phone settings',
                          _ => 'Not allowed yet',
                        },
                  ok: _location == LocationPermission.always ||
                      _location == LocationPermission.whileInUse,
                  onTap: () async {
                    final p = await Geolocator.requestPermission();
                    if (p == LocationPermission.deniedForever) {
                      await Geolocator.openAppSettings();
                    }
                    _check();
                  },
                ),
                const Divider(height: 20),
                _row(
                  scheme,
                  Icons.notifications_active_outlined,
                  'Meeting reminders',
                  _checking
                      ? 'Checking...'
                      : _notifications == null
                          ? 'Not available on this platform'
                          : (_notifications! ? 'Allowed' : 'Blocked'),
                  ok: _notifications == true,
                  onTap: () async {
                    await FlutterLocalNotificationsPlugin()
                        .resolvePlatformSpecificImplementation<
                            AndroidFlutterLocalNotificationsPlugin>()
                        ?.requestNotificationsPermission();
                    _check();
                  },
                ),
              ]),
            ),
            const SizedBox(height: 16),
            Reveal(
              index: 2,
              child: _card(scheme, 'Server', [
                _row(
                  scheme,
                  Icons.cloud_outlined,
                  Config.apiBase,
                  _checking
                      ? 'Checking...'
                      : _serverOk
                          ? 'Connected'
                          : 'Cannot reach the server',
                  ok: _serverOk,
                  onTap: _check,
                ),
                if (Config.isRelease && !Config.isConfigured) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Tw.rose50,
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      border: Border.all(color: Tw.rose100),
                    ),
                    child: Text(
                      'This build was not given a server address. It is '
                      'pointed at a developer machine. Rebuild with '
                      '--dart-define=API_BASE=...',
                      style: TextStyle(fontSize: 12, color: Tw.rose600),
                    ),
                  ),
                ],
              ]),
            ),
            const SizedBox(height: 16),
            Reveal(
              index: 3,
              child: _card(scheme, 'About', [
                _row(
                  scheme,
                  Icons.info_outline,
                  'SalesHub',
                  _pkg == null
                      ? ''
                      : 'Version ${_pkg!.version} (${_pkg!.buildNumber})',
                ),
                const SizedBox(height: 12),
                _row(
                  scheme,
                  Icons.system_update,
                  'Check for updates',
                  _checkingUpdate ? 'Checking...' : 'Get the newest version',
                  onTap: _checkingUpdate ? null : _checkForUpdate,
                ),
              ]),
            ),
            const SizedBox(height: 24),
            Reveal(
              index: 4,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Tw.rose600,
                  side: BorderSide(color: Tw.rose600.withValues(alpha: 0.4)),
                ),
                onPressed: _signOut,
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('Sign out'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(ColorScheme scheme, String title, List<Widget> children) {
    return SurfaceCard(
      radius: AppTheme.radiusXl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTheme.sans(15, 600, 20, color: scheme.onSurface)),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _row(ColorScheme scheme, IconData icon, String title, String sub,
      {bool? ok, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: Row(
        children: [
          NeoIconWell(icon,
              color: ok == null
                  ? null
                  : (ok ? AppTheme.emerald600 : AppTheme.rose600)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface),
                    overflow: TextOverflow.ellipsis),
                Text(sub,
                    style: TextStyle(
                        fontSize: 12,
                        color: ok == false
                            ? AppTheme.rose600
                            : scheme.onSurfaceVariant)),
              ],
            ),
          ),
          if (onTap != null)
            Icon(Icons.chevron_right, size: 18, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}
