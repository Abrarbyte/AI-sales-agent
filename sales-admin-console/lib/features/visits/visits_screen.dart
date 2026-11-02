import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/company_profile.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../data/models/activity.dart';
import '../../data/models/people.dart';
import '../../data/providers.dart';
import '../../data/repositories/company_repository.dart';
import '../../widgets/activity_blocks.dart';
import '../../widgets/table_panel.dart';
import '../../widgets/async_gate.dart';
import '../../widgets/motion.dart';
import '../../widgets/primitives.dart';
import '../dashboard/dashboard_panels.dart';

/// Every field visit and site check-in the team logged: who went where,
/// when, what came of it, the notes, and the photo taken on site.
class VisitsScreen extends ConsumerStatefulWidget {
  const VisitsScreen({super.key});

  @override
  ConsumerState<VisitsScreen> createState() => _VisitsScreenState();
}

enum _View { visits, checkpoints }

enum _Range { today, week, month, all }

class _VisitsScreenState extends ConsumerState<VisitsScreen> {
  final TextEditingController _search = TextEditingController();
  _View _view = _View.visits;
  _Range _range = _Range.week;
  String? _repId;
  String? _outcome;
  String? _expandedId;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  DateTime? get _since {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    return switch (_range) {
      _Range.today => today,
      _Range.week => today.subtract(const Duration(days: 6)),
      _Range.month => today.subtract(const Duration(days: 29)),
      _Range.all => null,
    };
  }

  List<FieldVisit> _visits(CompanySnapshot co) {
    final String q = _search.text.trim().toLowerCase();
    final DateTime? since = _since;
    final List<FieldVisit> out = co.visits.where((FieldVisit v) {
      if (since != null && v.visitedAt.isBefore(since)) return false;
      if (_repId != null && v.repId != _repId) return false;
      if (_outcome != null && v.outcome != _outcome) return false;
      if (q.isEmpty) return true;
      return v.targetName.toLowerCase().contains(q) ||
          v.repName.toLowerCase().contains(q) ||
          v.notes.toLowerCase().contains(q);
    }).toList();
    out.sort(
      (FieldVisit a, FieldVisit b) => b.visitedAt.compareTo(a.visitedAt),
    );
    return out;
  }

  List<Checkpoint> _checkpoints(CompanySnapshot co) {
    final String q = _search.text.trim().toLowerCase();
    final DateTime? since = _since;
    final List<Checkpoint> out = co.checkpoints.where((Checkpoint c) {
      if (since != null && c.recordedAt.isBefore(since)) return false;
      if (_repId != null && c.repId != _repId) return false;
      if (q.isEmpty) return true;
      return c.repName.toLowerCase().contains(q) ||
          c.note.toLowerCase().contains(q);
    }).toList();
    out.sort(
      (Checkpoint a, Checkpoint b) => b.recordedAt.compareTo(a.recordedAt),
    );
    return out;
  }

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
    final List<FieldVisit> visits = _visits(co);
    final List<Checkpoint> checkpoints = _checkpoints(co);
    final DateTime now = DateTime.now();
    final int today = co.visits
        .where(
          (FieldVisit v) =>
              v.visitedAt.year == now.year &&
              v.visitedAt.month == now.month &&
              v.visitedAt.day == now.day,
        )
        .length;
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
            title: 'Visits',
            subtitle: Text(
              '${co.visits.length} visits logged - $today today - '
              '${co.checkpoints.length} site check-ins',
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          DataBlock(children: <Widget>[
          Reveal(
            index: 1,
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
                  PillDropdown<_View>(
                    value: _view,
                    items: _View.values,
                    labelOf: (_View v) => v == _View.visits
                        ? 'Field visits'
                        : 'Site check-ins',
                    onChanged: (_View v) => setState(() => _view = v),
                  ),
                  SizedBox(
                    width: 260,
                    child: TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search, size: 18),
                        hintText: 'Search customer, rep or notes',
                        isDense: true,
                      ),
                    ),
                  ),
                  PillDropdown<String?>(
                    value: _repId,
                    items: <String?>[null, ...repNames.keys],
                    labelOf: (String? id) =>
                        id == null ? 'Any rep' : repNames[id]!,
                    onChanged: (String? id) => setState(() => _repId = id),
                  ),
                  if (_view == _View.visits)
                    PillDropdown<String?>(
                      value: _outcome,
                      items: <String?>[
                        null,
                        ...CompanyProfile.visitOutcomeLabels.keys,
                      ],
                      labelOf: (String? o) => o == null
                          ? 'Any outcome'
                          : CompanyProfile.visitOutcomeLabels[o]!,
                      onChanged: (String? o) => setState(() => _outcome = o),
                    ),
                  PillDropdown<_Range>(
                    value: _range,
                    items: _Range.values,
                    labelOf: (_Range r) => switch (r) {
                      _Range.today => 'Today',
                      _Range.week => 'Last 7 days',
                      _Range.month => 'Last 30 days',
                      _Range.all => 'All time',
                    },
                    onChanged: (_Range r) => setState(() => _range = r),
                  ),
                ],
              ),
            ),
          ),
          if (_view == _View.visits)
            visits.isEmpty
                ? Panel(
                    padding: const EdgeInsets.all(AppSpacing.xxl),
                    child: EmptyState(
                      icon: Icons.route_outlined,
                      title: 'No visits match these filters',
                      message:
                          'Visits are logged from the phone against a lead '
                          'or customer.',
                    ),
                  )
                : Reveal(
                    index: 2,
                    child: _VisitTable(
                      visits: visits,
                      expandedId: _expandedId,
                      onToggle: (String id) => setState(
                        () => _expandedId = _expandedId == id ? null : id,
                      ),
                    ),
                  )
          else
            checkpoints.isEmpty
                ? Panel(
                    padding: const EdgeInsets.all(AppSpacing.xxl),
                    child: EmptyState(
                      icon: Icons.my_location_outlined,
                      title: 'No site check-ins in this range',
                      message:
                          'Reps mark their location from the home screen '
                          'as they move between sites.',
                    ),
                  )
                : Reveal(
                    index: 2,
                    child: _CheckpointTable(checkpoints: checkpoints),
                  ),
          ]),
        ],
      ),
    );
  }
}

const List<double> _vcols = <double>[150, 130, 220, 150, 70, 64];
const double _vMinWidth = 1000;

class _VisitTable extends StatelessWidget {
  const _VisitTable({
    required this.visits,
    required this.expandedId,
    required this.onToggle,
  });

  final List<FieldVisit> visits;
  final String? expandedId;
  final ValueChanged<String> onToggle;

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
          final double width = c.maxWidth > _vMinWidth
              ? c.maxWidth
              : _vMinWidth;
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
                        SizedBox(width: _vcols[0], child: Text('When', style: head)),
                        SizedBox(width: _vcols[1], child: Text('Rep', style: head)),
                        SizedBox(width: _vcols[2], child: Text('Visited', style: head)),
                        SizedBox(width: _vcols[3], child: Text('Outcome', style: head)),
                        SizedBox(width: _vcols[4], child: Text('Min', style: head)),
                        SizedBox(width: _vcols[5], child: Text('Photo', style: head)),
                        Expanded(child: Text('Notes', style: head)),
                      ],
                    ),
                  ),
                  for (final FieldVisit v in visits) ...<Widget>[
                    HoverRow(
                      onTap: () => onToggle(v.id),
                      child: Container(
                        height: AppSpacing.tableRowHeight,
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(color: theme.dividerColor),
                          ),
                        ),
                        child: Row(
                          children: <Widget>[
                            SizedBox(
                              width: _vcols[0],
                              child: Row(
                                children: <Widget>[
                                  Icon(
                                    expandedId == v.id
                                        ? Icons.expand_more
                                        : Icons.chevron_right,
                                    size: 16,
                                    color: VizPalette.inkMuted,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      Fmt.dateTime(v.visitedAt),
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: _vcols[1],
                              child: Text(
                                v.repName,
                                overflow: TextOverflow.ellipsis,
                                style: muted,
                              ),
                            ),
                            SizedBox(
                              width: _vcols[2],
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    v.targetName,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                  Text(
                                    v.customerId != null ? 'Customer' : 'Lead',
                                    style: muted,
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: _vcols[3],
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: StatusChip(
                                  label: CompanyProfile.labelOf(
                                    CompanyProfile.visitOutcomeLabels,
                                    v.outcome,
                                  ),
                                  color: _outcomeColor(v.outcome),
                                  icon: _outcomeIcon(v.outcome),
                                  dense: true,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: _vcols[4],
                              child: Text(
                                v.durationMinutes?.toString() ?? '-',
                                style: muted,
                              ),
                            ),
                            SizedBox(
                              width: _vcols[5],
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: PhotoThumb(url: v.photoUrl, size: 36),
                              ),
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  right: AppSpacing.md,
                                ),
                                child: Text(
                                  v.notes.isEmpty ? '-' : v.notes,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (expandedId == v.id) _VisitDetail(visit: v),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _VisitDetail extends StatelessWidget {
  const _VisitDetail({required this.visit});

  final FieldVisit visit;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final FieldVisit v = visit;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? VizPalette.raisedDark
            : VizPalette.raisedLight,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Wrap(
        spacing: AppSpacing.xl,
        runSpacing: AppSpacing.lg,
        crossAxisAlignment: WrapCrossAlignment.start,
        children: <Widget>[
          KeyValueBlock(
            title: 'Visit',
            rows: <(String, String)>[
              ('Rep', v.repName),
              ('Visited', v.targetName),
              ('When', Fmt.dateTime(v.visitedAt)),
              (
                'Duration',
                v.durationMinutes == null ? '-' : '${v.durationMinutes} min',
              ),
              (
                'Outcome',
                CompanyProfile.labelOf(
                  CompanyProfile.visitOutcomeLabels,
                  v.outcome,
                ),
              ),
              (
                'Location',
                v.hasLocation
                    ? '${v.lat!.toStringAsFixed(5)}, ${v.lng!.toStringAsFixed(5)}'
                    : 'Not recorded',
              ),
            ],
          ),
          SizedBox(
            width: 360,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const BlockTitle('Notes'),
                Text(
                  v.notes.isEmpty ? 'No notes.' : v.notes,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (v.photoUrl != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const BlockTitle('Photo'),
                PhotoThumb(url: v.photoUrl, size: 120),
              ],
            ),
        ],
      ),
    );
  }
}

Color _outcomeColor(String outcome) => switch (outcome) {
  'interested' => VizPalette.statusGood,
  'order_placed' => VizPalette.statusGood,
  'follow_up' => VizPalette.statusWarning,
  'not_available' => VizPalette.inkMuted,
  'not_interested' => VizPalette.statusCritical,
  _ => VizPalette.inkMuted,
};

IconData _outcomeIcon(String outcome) => switch (outcome) {
  'interested' => Icons.thumb_up_outlined,
  'order_placed' => Icons.check_circle_outline,
  'follow_up' => Icons.update,
  'not_available' => Icons.person_off_outlined,
  'not_interested' => Icons.thumb_down_outlined,
  _ => Icons.circle_outlined,
};

const List<double> _ccols = <double>[150, 130, 220, 64];

class _CheckpointTable extends StatelessWidget {
  const _CheckpointTable({required this.checkpoints});

  final List<Checkpoint> checkpoints;

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
          final double width = c.maxWidth > 760 ? c.maxWidth : 760;
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
                        SizedBox(width: _ccols[0], child: Text('When', style: head)),
                        SizedBox(width: _ccols[1], child: Text('Rep', style: head)),
                        SizedBox(width: _ccols[2], child: Text('Location', style: head)),
                        SizedBox(width: _ccols[3], child: Text('Photo', style: head)),
                        Expanded(child: Text('Note', style: head)),
                      ],
                    ),
                  ),
                  for (final Checkpoint p in checkpoints)
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
                            width: _ccols[0],
                            child: Text(
                              Fmt.dateTime(p.recordedAt),
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                          SizedBox(
                            width: _ccols[1],
                            child: Text(
                              p.repName,
                              overflow: TextOverflow.ellipsis,
                              style: muted,
                            ),
                          ),
                          SizedBox(
                            width: _ccols[2],
                            child: SelectableText(
                              '${p.lat.toStringAsFixed(5)}, ${p.lng.toStringAsFixed(5)}'
                              '${p.accuracyMetres == null ? '' : '  ±${p.accuracyMetres} m'}',
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                          SizedBox(
                            width: _ccols[3],
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: PhotoThumb(url: p.photoUrl, size: 36),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              p.note.isEmpty ? '-' : p.note,
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
