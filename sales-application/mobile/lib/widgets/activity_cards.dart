import 'package:flutter/material.dart';

import '../theme.dart';
import 'form_sheet.dart';

/// The Visits and Follow-ups cards shared by the lead and customer detail
/// screens. Both take the raw API rows and two callbacks; the screens own
/// the fetching and the sheets.

class VisitsCard extends StatelessWidget {
  const VisitsCard({super.key, required this.visits, this.onLog});

  final List<Map<String, dynamic>> visits;

  /// Shows a "Log visit" button in the header. Null where the page already
  /// has its own Log visit button - the lead page's action row (#93).
  final VoidCallback? onLog;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SurfaceCard(
      radius: AppTheme.radiusXl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                    'Visits${visits.isEmpty ? '' : ' (${visits.length})'}',
                    style: AppTheme.sans(15, 600, 20, color: scheme.onSurface)),
              ),
              if (onLog != null)
                TextButton.icon(
                  onPressed: onLog,
                  icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                  label: const Text('Log visit'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (visits.isEmpty)
            Text('No visits logged yet.',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant))
          else
            for (final v in visits.take(3)) ...[
              _visitRow(scheme, v),
              if (v != visits.take(3).last) const Divider(height: 18),
            ],
        ],
      ),
    );
  }

  Widget _visitRow(ColorScheme scheme, Map<String, dynamic> v) {
    final at = DateTime.tryParse(v['visited_at']?.toString() ?? '');
    final outcome = (v['outcome'] ?? '').toString().replaceAll('_', ' ');
    final mins = v['duration_minutes'];
    final photo = v['photo']?.toString();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (photo != null && photo.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(photo,
                width: 44,
                height: 44,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                      width: 44,
                      height: 44,
                      color: scheme.surfaceContainerHigh,
                      child: Icon(Icons.photo_outlined,
                          size: 18, color: scheme.onSurfaceVariant),
                    )),
          )
        else
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.place_outlined,
                size: 18, color: scheme.onSurfaceVariant),
          ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                outcome.isEmpty
                    ? 'Visit'
                    : '${outcome[0].toUpperCase()}${outcome.substring(1)}',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface),
              ),
              Text(
                '${at == null ? '' : fmtDate(at)}'
                '${mins == null ? '' : ' · $mins min'}',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              if ((v['notes']?.toString() ?? '').isNotEmpty)
                Text(v['notes'].toString(),
                    style: TextStyle(fontSize: 13, color: scheme.onSurface),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }
}

class FollowUpsCard extends StatelessWidget {
  const FollowUpsCard({
    super.key,
    required this.followUps,
    required this.onSchedule,
    required this.onComplete,
  });

  /// Pending follow-ups for this lead or customer, soonest first.
  final List<Map<String, dynamic>> followUps;
  final VoidCallback onSchedule;
  final ValueChanged<Map<String, dynamic>> onComplete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SurfaceCard(
      radius: AppTheme.radiusXl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Follow-ups',
                    style: AppTheme.sans(15, 600, 20, color: scheme.onSurface)),
              ),
              TextButton.icon(
                onPressed: onSchedule,
                icon: const Icon(Icons.add_alarm_outlined, size: 18),
                label: const Text('Schedule'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (followUps.isEmpty)
            Text('Nothing scheduled.',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant))
          else
            for (final f in followUps) ...[
              _row(scheme, f),
              if (f != followUps.last) const Divider(height: 18),
            ],
        ],
      ),
    );
  }

  Widget _row(ColorScheme scheme, Map<String, dynamic> f) {
    final due = DateTime.tryParse(f['due_at']?.toString() ?? '');
    final overdue = f['is_overdue'] == true;
    final kind = (f['kind'] ?? 'call').toString();
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${kind[0].toUpperCase()}${kind.substring(1)}'
                '${(f['note']?.toString() ?? '').isEmpty ? '' : ' · ${f['note']}'}',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                due == null
                    ? ''
                    : '${overdue ? 'Overdue - ' : ''}${fmtDate(due)} '
                        '${due.toLocal().hour.toString().padLeft(2, '0')}:'
                        '${due.toLocal().minute.toString().padLeft(2, '0')}',
                style: TextStyle(
                    fontSize: 12,
                    color: overdue ? scheme.error : scheme.onSurfaceVariant,
                    fontWeight: overdue ? FontWeight.w600 : FontWeight.w400),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 34),
            padding: const EdgeInsets.symmetric(horizontal: 14),
          ),
          onPressed: () => onComplete(f),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
