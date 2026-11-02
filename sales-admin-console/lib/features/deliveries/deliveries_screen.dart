import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../data/api/api_client.dart';
import '../../data/models/delivery.dart';
import '../../core/company_profile.dart';
import '../../data/models/people.dart';
import '../../data/providers.dart';
import '../../data/repositories/company_repository.dart';
import '../../widgets/async_gate.dart';
import '../../widgets/table_panel.dart';
import '../../widgets/kpi_card.dart';
import '../../widgets/motion.dart';
import '../../widgets/primitives.dart';
import '../dashboard/dashboard_panels.dart';
import 'delivery_chips.dart';

/// Every delivery, and the two ways it ends: delivered, or not delivered
/// with the reason and the retry date.
///
/// The console reschedules, reassigns and cancels. Marking one delivered or
/// logging a failed attempt is the driver's job, from the field app, because
/// both need someone at the door.
class DeliveriesScreen extends ConsumerStatefulWidget {
  const DeliveriesScreen({super.key});

  @override
  ConsumerState<DeliveriesScreen> createState() => _DeliveriesScreenState();
}

class _DeliveriesScreenState extends ConsumerState<DeliveriesScreen> {
  final TextEditingController _search = TextEditingController();

  DeliveryStatus? _status;
  String? _repId;
  bool _overdueOnly = false;
  String? _expandedId;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Delivery> _filtered(CompanySnapshot co) {
    final String q = _search.text.trim().toLowerCase();
    final List<Delivery> out = co.deliveries.where((Delivery d) {
      if (_status != null && d.status != _status) return false;
      if (_repId != null && d.repId != _repId) return false;
      if (_overdueOnly && !d.isOverdue) return false;
      if (q.isEmpty) return true;
      return d.customerName.toLowerCase().contains(q) ||
          d.productName.toLowerCase().contains(q) ||
          d.address.toLowerCase().contains(q) ||
          d.receivedBy.toLowerCase().contains(q);
    }).toList();
    // Open ones first, soonest first; finished ones after, newest first.
    out.sort((Delivery a, Delivery b) {
      if (a.status.isFinal != b.status.isFinal) {
        return a.status.isFinal ? 1 : -1;
      }
      return a.status.isFinal
          ? b.scheduledOn.compareTo(a.scheduledOn)
          : a.scheduledOn.compareTo(b.scheduledOn);
    });
    return out;
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    try {
      await action();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: VizPalette.statusCritical,
        ),
      );
      return;
    }
    ref.invalidate(companyProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
  }

  Future<void> _reassign(Delivery d, CompanySnapshot co) async {
    final SalesRep? rep = await showDialog<SalesRep>(
      context: context,
      builder: (BuildContext ctx) => SimpleDialog(
        title: Text('Who takes ${d.customerName}?'),
        children: <Widget>[
          for (final SalesRep r in co.activeReps)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(r),
              child: Text(r.name),
            ),
        ],
      ),
    );
    if (rep == null) return;
    await _run(
      () => ref.read(deliveryRepositoryProvider).reassign(d.id, rep.id),
      'Milestone handed to ${rep.name}',
    );
  }

  Future<void> _reschedule(Delivery d) async {
    final DateTime? on = await showDatePicker(
      context: context,
      initialDate: d.scheduledOn.isBefore(DateTime.now())
          ? DateTime.now()
          : d.scheduledOn,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (on == null) return;
    await _run(
      () => ref.read(deliveryRepositoryProvider).reschedule(d.id, on),
      'Rescheduled to ${Fmt.date(on)}',
    );
  }

  Future<void> _cancel(Delivery d) async {
    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Cancel this milestone?'),
        content: Text('${d.productName} for ${d.customerName} will be dropped.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Cancel milestone'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await _run(
      () => ref.read(deliveryRepositoryProvider).cancel(d.id),
      'Milestone cancelled',
    );
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
    final List<Delivery> all = co.deliveries;
    final List<Delivery> rows = _filtered(co);

    int count(DeliveryStatus s) =>
        all.where((Delivery d) => d.status == s).length;
    final int overdue = all.where((Delivery d) => d.isOverdue).length;

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
            title: 'Handovers',
            subtitle: Text(
              '${all.length} scheduled'
              '${overdue > 0 ? ' - $overdue past their date' : ''}',
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.lg,
            children: <Widget>[
              for (final DeliveryStatus s in <DeliveryStatus>[
                DeliveryStatus.pending,
                DeliveryStatus.outForDelivery,
                DeliveryStatus.delivered,
                DeliveryStatus.notDelivered,
              ])
                SizedBox(
                  width: 200,
                  child: KpiCard(
                    label: s.label,
                    value: Fmt.count(count(s)),
                    icon: deliveryStatusIcon(s),
                    accent: deliveryStatusColor(s),
                    onTap: () =>
                        setState(() => _status = _status == s ? null : s),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          DataBlock(children: <Widget>[
          Reveal(
            index: 1,
            child: _DeliveryFilters(
              controller: _search,
              reps: co.activeReps,
              repId: _repId,
              status: _status,
              overdueOnly: _overdueOnly,
              onSearch: () => setState(() {}),
              onRep: (String? id) => setState(() => _repId = id),
              onStatus: (DeliveryStatus? s) => setState(() => _status = s),
              onOverdue: (bool v) => setState(() => _overdueOnly = v),
            ),
          ),
          if (rows.isEmpty)
            Panel(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: EmptyState(
                icon: Icons.local_shipping_outlined,
                title: 'No milestones match these filters',
                message:
                    'Handover milestones are scheduled against a customer '
                    'from the field app.',
              ),
            )
          else
            Reveal(
              index: 2,
              child: _DeliveryTable(
                rows: rows,
                expandedId: _expandedId,
                onToggle: (Delivery d) => setState(
                  () => _expandedId = _expandedId == d.id ? null : d.id,
                ),
                onReassign: (Delivery d) => _reassign(d, co),
                onReschedule: _reschedule,
                onCancel: _cancel,
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

class _DeliveryFilters extends StatelessWidget {
  const _DeliveryFilters({
    required this.controller,
    required this.reps,
    required this.repId,
    required this.status,
    required this.overdueOnly,
    required this.onSearch,
    required this.onRep,
    required this.onStatus,
    required this.onOverdue,
  });

  final TextEditingController controller;
  final List<SalesRep> reps;
  final String? repId;
  final DeliveryStatus? status;
  final bool overdueOnly;
  final VoidCallback onSearch;
  final ValueChanged<String?> onRep;
  final ValueChanged<DeliveryStatus?> onStatus;
  final ValueChanged<bool> onOverdue;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Map<String, String> repNames = <String, String>{
      for (final SalesRep r in reps) r.id: r.name,
    };

    return Panel(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.md,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          Container(
            width: 300,
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: BoxDecoration(
              color: theme.brightness == Brightness.dark
                  ? VizPalette.raisedDark
                  : VizPalette.raisedLight,
              borderRadius: BorderRadius.circular(19),
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.search, size: 16, color: VizPalette.inkMuted),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextField(
                    controller: controller,
                    onChanged: (_) => onSearch(),
                    decoration: const InputDecoration(
                      hintText: 'Search customer, product or address',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
          PillDropdown<DeliveryStatus?>(
            value: status,
            items: <DeliveryStatus?>[null, ...DeliveryStatus.values],
            labelOf: (DeliveryStatus? s) => s?.label ?? 'Any status',
            onChanged: onStatus,
          ),
          PillDropdown<String?>(
            value: repId,
            items: <String?>[null, ...repNames.keys],
            labelOf: (String? id) => id == null ? 'Any owner' : repNames[id]!,
            onChanged: onRep,
          ),
          PillDropdown<bool>(
            value: overdueOnly,
            items: const <bool>[false, true],
            labelOf: (bool v) => v ? 'Past due only' : 'Any date',
            onChanged: onOverdue,
          ),
        ],
      ),
    );
  }
}

const List<double> _cols = <double>[240, 110, 130, 150, 90, 180];
const double _minTableWidth = 900;

class _DeliveryTable extends StatelessWidget {
  const _DeliveryTable({
    required this.rows,
    required this.expandedId,
    required this.onToggle,
    required this.onReassign,
    required this.onReschedule,
    required this.onCancel,
  });

  final List<Delivery> rows;
  final String? expandedId;
  final ValueChanged<Delivery> onToggle;
  final ValueChanged<Delivery> onReassign;
  final ValueChanged<Delivery> onReschedule;
  final ValueChanged<Delivery> onCancel;

  @override
  Widget build(BuildContext context) {
    final TextStyle? head = Dt.head;

    return TablePanel(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double tableWidth = constraints.maxWidth > _minTableWidth
              ? constraints.maxWidth
              : _minTableWidth;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: tableWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Row(
                      children: <Widget>[
                        SizedBox(
                          width: _cols[0],
                          child: Text('Customer / product', style: head),
                        ),
                        SizedBox(
                          width: _cols[1],
                          child: Text('Scheduled', style: head),
                        ),
                        SizedBox(
                          width: _cols[2],
                          child: Text('Owner', style: head),
                        ),
                        SizedBox(
                          width: _cols[3],
                          child: Text('Status', style: head),
                        ),
                        SizedBox(
                          width: _cols[4],
                          child: Text('Attempts', style: head),
                        ),
                        SizedBox(
                          width: _cols[5],
                          child: Text('Outcome', style: head),
                        ),
                      ],
                    ),
                  ),
                  for (final Delivery d in rows) ...<Widget>[
                    _DeliveryRow(
                      delivery: d,
                      expanded: expandedId == d.id,
                      onTap: () => onToggle(d),
                    ),
                    if (expandedId == d.id)
                      _DeliveryDetail(
                        delivery: d,
                        onReassign: () => onReassign(d),
                        onReschedule: () => onReschedule(d),
                        onCancel: () => onCancel(d),
                      ),
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

class _DeliveryRow extends StatelessWidget {
  const _DeliveryRow({
    required this.delivery,
    required this.expanded,
    required this.onTap,
  });

  final Delivery delivery;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle? muted = theme.textTheme.labelSmall?.copyWith(
      color: VizPalette.inkMuted,
    );
    final Delivery d = delivery;

    final String outcome = switch (d.status) {
      DeliveryStatus.delivered =>
        d.receivedBy.isEmpty
            ? 'Done ${d.deliveredAt == null ? '' : Fmt.dateShort(d.deliveredAt!)}'
            : 'Signed off by ${d.receivedBy}',
      DeliveryStatus.notDelivered =>
        d.lastAttempt == null
            ? 'Blocked'
            : '${d.lastAttempt!.reason.label}'
                  '${d.lastAttempt!.retryOn == null ? '' : ' - retry ${Fmt.dateShort(d.lastAttempt!.retryOn!)}'}',
      DeliveryStatus.cancelled => 'Cancelled',
      _ => d.required ? '' : 'No client sign-off needed',
    };

    return HoverRow(
      onTap: onTap,
      child: Container(
        height: AppSpacing.tableRowHeight,
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: theme.dividerColor)),
        ),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: _cols[0],
              child: Row(
                children: <Widget>[
                  Icon(
                    expanded ? Icons.expand_more : Icons.chevron_right,
                    size: 16,
                    color: VizPalette.inkMuted,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          d.customerName,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                        Text(
                          '${CompanyProfile.labelOf(CompanyProfile.milestoneLabels, d.milestone)}'
                          ' - ${d.productName}',
                          overflow: TextOverflow.ellipsis,
                          style: muted,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: _cols[1],
              child: Text(
                Fmt.dateShort(d.scheduledOn),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: d.isOverdue
                      ? VizPalette.statusCritical
                      : VizPalette.inkMuted,
                ),
              ),
            ),
            SizedBox(
              width: _cols[2],
              child: Text(
                d.repName,
                overflow: TextOverflow.ellipsis,
                style: muted,
              ),
            ),
            SizedBox(
              width: _cols[3],
              child: Align(
                alignment: Alignment.centerLeft,
                child: DeliveryStatusChip(status: d.status, dense: true),
              ),
            ),
            SizedBox(
              width: _cols[4],
              child: Text(
                d.attemptCount == 0 ? '-' : Fmt.count(d.attemptCount),
                style: theme.textTheme.labelMedium?.copyWith(
                  fontFeatures: kTabularFigures,
                  color: d.attemptCount > 1 ? VizPalette.statusSerious : null,
                ),
              ),
            ),
            SizedBox(
              width: _cols[5],
              child: Text(
                outcome,
                overflow: TextOverflow.ellipsis,
                style: muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeliveryDetail extends StatelessWidget {
  const _DeliveryDetail({
    required this.delivery,
    required this.onReassign,
    required this.onReschedule,
    required this.onCancel,
  });

  final Delivery delivery;
  final VoidCallback onReassign;
  final VoidCallback onReschedule;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Delivery d = delivery;
    final DeliveryAttempt? a = d.lastAttempt;
    final TextStyle? key = theme.textTheme.labelSmall?.copyWith(
      color: VizPalette.inkMuted,
    );

    Widget block(String title, List<(String, String)> rows, {Color? accent}) =>
        SizedBox(
          width: 260,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                title.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: accent ?? VizPalette.inkMuted,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final (String k, String v) in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SizedBox(width: 100, child: Text(k, style: key)),
                      Expanded(
                        child: Text(v, style: theme.textTheme.bodySmall),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );

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
      ),
      child: Wrap(
        spacing: AppSpacing.xl,
        runSpacing: AppSpacing.lg,
        children: <Widget>[
          block('Milestone', <(String, String)>[
            (
              'Step',
              CompanyProfile.labelOf(
                CompanyProfile.milestoneLabels,
                d.milestone,
              ),
            ),
            ('Where', d.address.isEmpty ? '-' : d.address),
            ('Client sign-off', d.required ? 'Needed' : 'Not needed'),
            ('Target date', Fmt.date(d.scheduledOn)),
            ('Owner', d.repName),
            if (d.notes.isNotEmpty) ('Notes', d.notes),
          ]),
          if (d.status == DeliveryStatus.delivered)
            block('Done', <(String, String)>[
              (
                'When',
                d.deliveredAt == null ? '-' : Fmt.dateTime(d.deliveredAt!),
              ),
              ('Signed off by', d.receivedBy.isEmpty ? '-' : d.receivedBy),
              ('Document', d.proofUrl == null ? 'None attached' : 'Attached'),
            ], accent: VizPalette.statusGood),
          if (a != null)
            block('Blocked', <(String, String)>[
              (
                'Reason',
                '${a.reason.label}${a.reasonNote.isEmpty ? '' : ' - ${a.reasonNote}'}',
              ),
              ('Attempted', Fmt.dateTime(a.attemptedAt)),
              ('Next date', a.retryOn == null ? '-' : Fmt.date(a.retryOn!)),
              ('Client told', a.customerContacted ? 'Yes' : 'No'),
              ('Attempts', Fmt.count(d.attemptCount)),
            ], accent: VizPalette.statusCritical),
          if (!d.status.isFinal)
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  PillButton(
                    label: 'Reschedule',
                    filled: false,
                    onTap: onReschedule,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  PillButton(
                    label: 'Reassign',
                    filled: false,
                    onTap: onReassign,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  PillButton(label: 'Cancel', filled: false, onTap: onCancel),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
