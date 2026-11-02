import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Meeting alerts, scheduled on the phone.
///
/// Every time the app loads the rep's pending follow-ups it hands them here,
/// and this replaces the whole set of local alarms: two per follow-up, 30 and
/// 10 minutes before `due_at`. Scheduled locally so they fire with the app
/// closed and with no signal; the server writes matching Notification rows
/// for the bell and the console, so nothing depends on this alone.
///
/// The web build has no alarms; every call is a no-op there.
class Reminders {
  Reminders._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  /// Called from a notification tap with the follow-up id, so the app can
  /// open the right screen. Set by main.
  static void Function(int followUpId)? onOpen;

  static const _channel = AndroidNotificationChannel(
    'followups',
    'Follow-up reminders',
    description: 'Before a scheduled call, visit or meeting.',
    importance: Importance.high,
  );

  static Future<void> init() async {
    if (kIsWeb || _ready) return;
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      // Unknown zone name: fall back to UTC offsets via the default location.
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (response) {
        final id = int.tryParse(response.payload ?? '');
        if (id != null) onOpen?.call(id);
      },
    );
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(_channel);
    await android?.requestNotificationsPermission();
    await android?.requestExactAlarmsPermission();
    _ready = true;
  }

  /// Replace every scheduled alarm with the set for these pending follow-ups.
  static Future<void> sync(List<Map<String, dynamic>> pending) async {
    if (kIsWeb) return;
    await init();
    await _plugin.cancelAll();

    final now = DateTime.now();
    for (final f in pending) {
      final id = f['id'] as int?;
      final due = DateTime.tryParse(f['due_at']?.toString() ?? '')?.toLocal();
      if (id == null || due == null) continue;
      final kind = (f['kind'] ?? 'follow-up').toString();
      final who = f['target_name']?.toString() ?? '';
      final label = '${kind[0].toUpperCase()}${kind.substring(1)}';

      for (final minutes in const [30, 10]) {
        final at = due.subtract(Duration(minutes: minutes));
        if (!at.isAfter(now)) continue;
        await _plugin.zonedSchedule(
          // One id per (follow-up, offset): id*10 + 3 or +1.
          id: id * 10 + (minutes == 30 ? 3 : 1),
          title: '$label in $minutes min - $who',
          body: (f['note']?.toString() ?? '').isEmpty
              ? 'Due at ${_hm(due)}'
              : f['note'].toString(),
          scheduledDate: tz.TZDateTime.from(at, tz.local),
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              _channel.id,
              _channel.name,
              channelDescription: _channel.description,
              importance: Importance.high,
              priority: Priority.high,
              category: AndroidNotificationCategory.reminder,
            ),
            iOS: const DarwinNotificationDetails(),
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          payload: '$id',
        );
      }
    }
  }

  static String _hm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
