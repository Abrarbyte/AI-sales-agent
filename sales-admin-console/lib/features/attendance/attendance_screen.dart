import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/company_profile.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../data/models/activity.dart';
import '../../data/models/common.dart';
import '../../data/models/people.dart';
import '../../data/providers.dart';
import '../../data/repositories/company_repository.dart';
import '../../widgets/async_gate.dart';
import '../../widgets/table_panel.dart';
import '../../widgets/motion.dart';
import '../../widgets/primitives.dart';
import '../dashboard/dashboard_panels.dart';

/// Who is working today and from where, then the day-by-day history:
/// check-in and check-out times, hours, and the note left at check-in.
class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

enum _Range { week, month, quarter }

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  String? _repId;
  _Range _range = _Range.week;

  @override
  Widget build(BuildContext context) {
    return AsyncGate<CompanySnapshot>(
      value: ref.watch(companyProvider),
      onRetry: () => ref.invalidate(companyProvider),
      loadingHeight: 420,
      data: (CompanySnapshot co) => _build(context, co),
    );
  }

  Widget _build(BuildContext context, CompanySnapshot co) {
    final LayoutSize size = Responsive.of(context);
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime since = today.subtract(
      Duration(
        days: switch (_range) {
          _Range.week => 6,
          _Range.month => 29,
          _Range.quarter => 89,
        },
      ),
    );

    final Map<String, AttendanceDay> todayByRep = <String, AttendanceDay>{
      for (final AttendanceDay a in co.attendance)
        if (a.date == today) a.repId: a,
    };
    final List<SalesRep> reps = co.activeReps;
    final int onDuty = todayByRep.values
        .where((AttendanceDay a) => a.isOpen)
        .length;
    final int closed = todayByRep.values
        .where((AttendanceDay a) => !a.isOpen)
        .length;

    final List<AttendanceDay> history =
        co.attendance.where((AttendanceDay a) {
          if (a.date.isBefore(since)) return false;
          if (_repId != null && a.repId != _repId) return false;
          return true;
        }).toList()..sort((AttendanceDay a, AttendanceDay b) {
          final int byDate = b.date.compareTo(a.date);
          return byDate != 0 ? byDate : a.repName.compareTo(b.repName);
        });
    final Map<String, String> repNames = <String, String>{
      for (final SalesRep r in co.reps) r.id: r.name,
    };

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        size.isCompact ? AppSpacing.lg : AppSpacing.xl,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PanelHeader(
            title: 'Attendance',
            subtitle: Text(
              '$onDuty on duty now - $closed finished for the day - '
              '${reps.length - todayByRep.length} not checked in',
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Reveal(
            index: 1,
            child: _TodayBoard(reps: reps, today: todayByRep),
          ),
          const SizedBox(height: AppSpacing.xl),
          DataBlock(children: <Widget>[
          Reveal(
            index: 2,
            child: Panel(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              child: Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  Text('History', style: Theme.of(context).textTheme.titleMedium),
                  PillDropdown<String?>(
                    value: _repId,
                    items: <String?>[null, ...repNames.keys],
                    labelOf: (String? id) =>
                        id == null ? 'Everyone' : repNames[id]!,
                    onChanged: (String? id) => setState(() => _repId = id),
                  ),
                  PillDropdown<_Range>(
                    value: _range,
                    items: _Range.values,
                    labelOf: (_Range r) => switch (r) {
                      _Range.week => 'Last 7 days',
                      _Range.month => 'Last 30 days',
                      _Range.quarter => 'Last 90 days',
                    },
                    onChanged: (_Range r) => setState(() => _range = r),
                  ),
                ],
              ),
            ),
          ),
          if (history.isEmpty)
            Panel(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: EmptyState(
                icon: Icons.schedule_outlined,
                title: 'No attendance in this range',
                message: 'Days appear here as reps check in from the phone.',
              ),
            )
          else
            Reveal(index: 3, child: _HistoryTable(days: history)),
          ]),
        ],
      ),
    );
  }
}

/// One card per active rep: on duty / day closed / not checked in.
class _TodayBoard extends StatelessWidget {
  const _TodayBoard({required this.reps, required this.today});

  final List<SalesRep> reps;
  final Map<String, AttendanceDay> today;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle? muted = theme.textTheme.labelSmall?.copyWith(
      color: VizPalette.inkMuted,
    );
    final List<SalesRep> sorted = List<SalesRep>.of(reps)
      ..sort((SalesRep a, SalesRep b) {
        // On duty first, then finished, then absent; by name within each.
        int rank(SalesRep r) {
          final AttendanceDay? d = today[r.id];
          return d == null ? 2 : (d.isOpen ? 0 : 1);
        }

        final int byRank = rank(a).compareTo(rank(b));
        return byRank != 0 ? byRank : a.name.compareTo(b.name);
      });

    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      children: <Widget>[
        for (final SalesRep r in sorted)
          SizedBox(
            width: 250,
            child: Panel(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Builder(
                builder: (BuildContext context) {
                  final AttendanceDay? d = today[r.id];
                  final (String label, Color color, IconData icon) = d == null
                      ? ('Not checked in', VizPalette.inkMuted, Icons.remove_circle_outline)
                      : d.isOpen
                      ? ('On duty', VizPalette.statusGood, Icons.check_circle_outline)
                      : ('Day closed', VizPalette.statusWarning, Icons.nightlight_outlined);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          InitialsAvatar(name: r.name, size: 28),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              r.name,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      StatusChip(label: label, color: color, icon: icon, dense: true),
                      const SizedBox(height: AppSpacing.sm),
                      if (d == null)
                        Text('No check-in today', style: muted)
                      else ...<Widget>[
                        Text(
                          '${CompanyProfile.labelOf(CompanyProfile.attendanceKindLabels, d.kind)}'
                          ' - in ${Fmt.time(d.checkInAt)}'
                          '${d.checkOutAt == null ? '' : ' - out ${Fmt.time(d.checkOutAt!)}'}',
                          style: muted,
                        ),
                        if (d.checkOutAt != null)
                          Text(
                            '${d.hoursWorked.toStringAsFixed(1)} h worked',
                            style: muted,
                          ),
                        if (d.note.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              d.note,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

const List<double> _cols = <double>[110, 150, 90, 90, 90, 70];

class _HistoryTable extends StatelessWidget {
  const _HistoryTable({required this.days});

  final List<AttendanceDay> days;

  @override
  Widget build(BuildContext context) {
    // The panel's dark theme, not the page's: cells are styled before the
    // TablePanel below wraps them.
    final ThemeData theme = Dt.theme(context);
    final TextStyle? head = Dt.head;
    final TextStyle? muted = theme.textTheme.labelSmall?.copyWith(
      color: VizPalette.inkMuted,
    );

    return TablePanel(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) {
          final double width = c.maxWidth > 820 ? c.maxWidth : 820;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Row(
                      children: <Widget>[
                        SizedBox(width: _cols[0], child: Text('Date', style: head)),
                        SizedBox(width: _cols[1], child: Text('Rep', style: head)),
                        SizedBox(width: _cols[2], child: Text('From', style: head)),
                        SizedBox(width: _cols[3], child: Text('In', style: head)),
                        SizedBox(width: _cols[4], child: Text('Out', style: head)),
                        SizedBox(width: _cols[5], child: Text('Hours', style: head)),
                        Expanded(child: Text('Note', style: head)),
                      ],
                    ),
                  ),
                  for (final AttendanceDay d in days)
                    Container(
                      height: AppSpacing.tableRowHeight,
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: theme.dividerColor),
                        ),
                      ),
                      child: Row(
                        children: <Widget>[
                          SizedBox(
                            width: _cols[0],
                            child: Text(
                              Fmt.dateShort(d.date),
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                          SizedBox(
                            width: _cols[1],
                            child: Text(
                              d.repName,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                          SizedBox(
                            width: _cols[2],
                            child: Text(
                              CompanyProfile.labelOf(
                                CompanyProfile.attendanceKindLabels,
                                d.kind,
                              ),
                              style: muted,
                            ),
                          ),
                          SizedBox(
                            width: _cols[3],
                            child: Text(
                              Fmt.time(d.checkInAt),
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                          SizedBox(
                            width: _cols[4],
                            child: Text(
                              d.checkOutAt == null
                                  ? (d.isOpen ? 'on duty' : '-')
                                  : Fmt.time(d.checkOutAt!),
                              style: d.checkOutAt == null
                                  ? muted?.copyWith(
                                      color: d.isOpen
                                          ? VizPalette.statusGood
                                          : null,
                                    )
                                  : theme.textTheme.bodySmall,
                            ),
                          ),
                          SizedBox(
                            width: _cols[5],
                            child: Text(
                              d.checkOutAt == null
                                  ? '-'
                                  : d.hoursWorked.toStringAsFixed(1),
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              d.note.isEmpty
                                  ? (d.checkInLat == null
                                        ? '-'
                                        : 'at ${GeoPoint(lat: d.checkInLat!, lng: d.checkInLng ?? 0).lat.toStringAsFixed(4)}, '
                                              '${(d.checkInLng ?? 0).toStringAsFixed(4)}')
                                  : d.note,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
