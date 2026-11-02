import 'package:flutter/material.dart';

import '../api.dart';
import '../widgets/offline_banner.dart';
import '../reminders.dart';
import '../theme.dart';
import '../widgets/form_sheet.dart';
import '../widgets/motion.dart';
import 'followup_sheet.dart';

/// Everything still owed: overdue first, then today, then what is coming.
/// Each row has one button - Done - because that is what the list is for.
class FollowUpsScreen extends StatefulWidget {
  const FollowUpsScreen({super.key, this.kinds});

  /// Narrow to these kinds, e.g. ['meeting', 'visit'] for today's agenda.
  final List<String>? kinds;

  @override
  State<FollowUpsScreen> createState() => _FollowUpsScreenState();
}

class _FollowUpsScreenState extends State<FollowUpsScreen> {
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  bool _changed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  static const _path = '/api/visits/followups/?status=pending';

  void _show(List<Map<String, dynamic>> all) {
    if (!mounted) return;
    final kinds = widget.kinds;
    setState(() => _items = kinds == null
        ? all
        : all.where((f) => kinds.contains(f['kind'])).toList());
  }

  Future<void> _load() async {
    // First open: the last saved copy straight away, then the server (#90).
    if (_items.isEmpty) {
      final saved = await Api.instance.cached(_path);
      if (saved is List) _show(saved.cast<Map<String, dynamic>>());
    }
    if (!mounted) return;
    setState(() {
      _loading = _items.isEmpty;
      _error = null;
    });
    try {
      final all =
          (await Api.instance.get(_path) as List).cast<Map<String, dynamic>>();
      // Every pending follow-up gets its two alarms, whatever this screen
      // is filtered to.
      Reminders.sync(all);
      _show(all);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Cannot reach the server.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _complete(Map<String, dynamic> f) async {
    final result =
        await showFormSheet(context, CompleteFollowUpSheet(followUp: f));
    if (result != null) {
      _changed = true;
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    DateTime due(Map<String, dynamic> f) =>
        DateTime.tryParse(f['due_at']?.toString() ?? '') ?? now;
    final sorted = [..._items]..sort((a, b) => due(a).compareTo(due(b)));
    final overdue = sorted.where((f) => due(f).isBefore(now)).toList();
    final dueToday = sorted
        .where((f) => !due(f).isBefore(now) && due(f).isBefore(tomorrow))
        .toList();
    final upcoming = sorted.where((f) => !due(f).isBefore(tomorrow)).toList();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(_changed),
        ),
        title: Text(widget.kinds == null ? 'Follow-ups' : 'Meetings'),
      ),
      body: OfflineAware(child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.task_alt,
                              size: 36, color: AppTheme.emerald500),
                          const SizedBox(height: 10),
                          Text('All clear',
                              style: AppTheme.sans(16, 600, 22,
                                  color: scheme.onSurface)),
                          Text('Nothing pending.',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                        children: [
                          if (overdue.isNotEmpty)
                            _section(scheme, 'Overdue', overdue, AppTheme.rose600, 0),
                          if (dueToday.isNotEmpty)
                            _section(scheme, 'Today', dueToday, AppTheme.neoBlue, 1),
                          if (upcoming.isNotEmpty)
                            _section(scheme, 'Upcoming', upcoming, Tw.slate500, 2),
                        ],
                      ),
                    ),
      ),
    );
  }

  Widget _section(ColorScheme scheme, String title,
      List<Map<String, dynamic>> items, Color color, int index) {
    return Reveal(
      index: index,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 12, 2, 10),
            child: Row(
              children: [
                Text(title.toUpperCase(),
                    style: AppTheme.labelSm.copyWith(color: color)),
                const SizedBox(width: 8),
                Text('${items.length}',
                    style: AppTheme.labelSm.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          for (final f in items) ...[
            _row(scheme, f, color),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _row(ColorScheme scheme, Map<String, dynamic> f, Color color) {
    final due = DateTime.tryParse(f['due_at']?.toString() ?? '')?.toLocal();
    final kind = (f['kind'] ?? 'call').toString();
    final icon = switch (kind) {
      'visit' => Icons.place_outlined,
      'meeting' => Icons.handshake_outlined,
      'email' => Icons.mail_outline,
      'message' => Icons.chat_bubble_outline,
      _ => Icons.call_outlined,
    };
    return SurfaceCard(
      small: true,
      radius: AppTheme.radius,
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Row(
        children: [
          NeoIconWell(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(f['target_name']?.toString() ?? '',
                    style: AppTheme.sans(14, 600, 20, color: scheme.onSurface),
                    overflow: TextOverflow.ellipsis),
                Text(
                  '${kind[0].toUpperCase()}${kind.substring(1)}'
                  '${due == null ? '' : ' · ${fmtDate(due)} '
                      '${due.hour.toString().padLeft(2, '0')}:${due.minute.toString().padLeft(2, '0')}'}',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
                if ((f['note']?.toString() ?? '').isNotEmpty)
                  Text(f['note'].toString(),
                      style: TextStyle(fontSize: 12, color: scheme.onSurface),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            onPressed: () => _complete(f),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}
