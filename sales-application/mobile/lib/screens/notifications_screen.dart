import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets/form_sheet.dart';
import '../widgets/motion.dart';
import 'followups_screen.dart';

/// What the bell holds: reminders, assignments, everything the server has
/// told this person. Tap marks it read and, for a follow-up, opens the list.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    const path = '/api/notifications/';
    // First open: the last saved copy straight away, then the server (#90).
    if (_items.isEmpty) {
      final saved = await Api.instance.cached(path);
      if (saved is List && mounted) {
        setState(() => _items = saved.cast<Map<String, dynamic>>());
      }
    }
    if (!mounted) return;
    setState(() {
      _loading = _items.isEmpty;
      _error = null;
    });
    try {
      final data = await Api.instance.get(path);
      setState(() => _items = (data as List).cast<Map<String, dynamic>>());
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Cannot reach the server.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(Map<String, dynamic> n) async {
    if (n['read_at'] == null) {
      try {
        await Api.instance.post('/api/notifications/${n['id']}/read/');
      } catch (_) {}
    }
    final link = n['link']?.toString() ?? '';
    if (link.startsWith('/followups/') && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const FollowUpsScreen()),
      );
    }
    if (mounted) _load();
  }

  Future<void> _readAll() async {
    try {
      await Api.instance.post('/api/notifications/read-all/');
    } catch (_) {}
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final unread = _items.where((n) => n['read_at'] == null).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (unread > 0)
            TextButton(
              onPressed: _readAll,
              child: const Text('Mark all read'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.notifications_none,
                              size: 36, color: scheme.onSurfaceVariant),
                          const SizedBox(height: 10),
                          Text('Nothing yet',
                              style: AppTheme.sans(16, 600, 22,
                                  color: scheme.onSurface)),
                          Text('Reminders land here before a meeting.',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                        itemCount: _items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => Reveal(
                            index: i < 6 ? i : 0, child: _row(scheme, _items[i])),
                      ),
                    ),
    );
  }

  Widget _row(ColorScheme scheme, Map<String, dynamic> n) {
    final unread = n['read_at'] == null;
    final at = DateTime.tryParse(n['created_at']?.toString() ?? '')?.toLocal();
    final kind = n['kind']?.toString() ?? '';
    final (icon, color) = switch (kind) {
      'followup_overdue' => (Icons.alarm_off, AppTheme.rose600),
      'followup_due' => (Icons.alarm, AppTheme.neoTeal),
      'lead_assigned' => (Icons.person_add_alt_1, AppTheme.neoBlue),
      'visit_logged' => (Icons.place_outlined, AppTheme.neoAccent),
      'attendance_missing' => (Icons.event_busy, AppTheme.amber600),
      _ => (Icons.notifications_none, Tw.slate500),
    };
    return SurfaceCard(
      small: true,
      radius: AppTheme.radius,
      padding: const EdgeInsets.all(14),
      onTap: () => _open(n),
      color: unread ? Colors.white : Tw.slate100.withValues(alpha: 0.6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NeoIconWell(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(n['title']?.toString() ?? '',
                    style: AppTheme.sans(14, unread ? 700 : 500, 20,
                        color: scheme.onSurface)),
                if ((n['body']?.toString() ?? '').isNotEmpty)
                  Text(n['body'].toString(),
                      style: TextStyle(fontSize: 13, color: scheme.onSurface),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                if (at != null)
                  Text(
                    '${fmtDate(at)} '
                    '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          if (unread)
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: 6),
              decoration: const BoxDecoration(
                  color: AppTheme.neoCyan, shape: BoxShape.circle),
            ),
        ],
      ),
    );
  }
}
