import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../data/api/api_client.dart';
import '../../data/api/mappers.dart';
import '../../data/models/customer.dart';
import '../../data/models/lead.dart';
import '../../core/company_profile.dart';
import '../../data/models/ops.dart';
import '../../data/models/people.dart';
import '../../data/providers.dart';
import '../../data/repositories/company_repository.dart';
import '../../widgets/async_gate.dart';
import '../../widgets/table_panel.dart';
import '../../widgets/motion.dart';
import '../../widgets/primitives.dart';
import '../dashboard/dashboard_panels.dart';
import '../../data/models/activity.dart';
import '../../widgets/activity_blocks.dart';
import '../shell/console_shell.dart' show NavSection, openSection;
import 'new_lead_dialog.dart';

/// Lead oversight: every lead, where it sits in the pipeline, and what has
/// happened to it - the demo it was shown and the negotiation it is in.
///
/// The stage strip along the top is the pipeline diagram with live counts:
/// New -> Demo -> Negotiation -> Proposal -> Customer, and Lost as the exit. Tapping
/// a stage filters the table to it.
///
/// The table lists open leads: customers and lost leads are history, and
/// used to fill most of it (#33). The "Show customers & lost" switch, or
/// picking their stage, brings them back.
class LeadsScreen extends ConsumerStatefulWidget {
  const LeadsScreen({super.key});

  @override
  ConsumerState<LeadsScreen> createState() => _LeadsScreenState();
}

class _LeadsScreenState extends ConsumerState<LeadsScreen> {
  final TextEditingController _search = TextEditingController();

  String? _stageId;
  String? _repId;
  String? _source;
  String? _expandedId;
  bool _showClosed = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Lead> _filtered(CompanySnapshot co) {
    final String q = _search.text.trim().toLowerCase();
    final List<Lead> out = co.leads.where((Lead l) {
      if (!_showClosed && _stageId == null && !l.isOpen) return false;
      if (_stageId != null && l.stageId != _stageId) return false;
      if (_repId != null && l.repId != _repId) return false;
      if (_source != null && l.source != _source) return false;
      if (q.isEmpty) return true;
      return l.companyName.toLowerCase().contains(q) ||
          l.contactName.toLowerCase().contains(q) ||
          l.phone.contains(q) ||
          l.requirement.toLowerCase().contains(q);
    }).toList();
    // Newest activity first, which is what oversight is for.
    out.sort((Lead a, Lead b) => b.updatedAt.compareTo(a.updatedAt));
    return out;
  }

  Future<void> _newLead(CompanySnapshot co) async {
    final Map<String, dynamic>? body = await NewLeadDialog.show(
      context,
      reps: co.activeReps,
    );
    if (body == null) return;
    try {
      await ref.read(pipelineRepositoryProvider).createLead(body);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not create the lead: ${e.message}'),
          backgroundColor: VizPalette.statusCritical,
        ),
      );
      return;
    }
    ref.invalidate(companyProvider);
    if (!mounted) return;
    final String rep =
        co.activeReps
            .where((SalesRep r) => r.id == '${body['assigned_to']}')
            .map((SalesRep r) => r.name)
            .firstOrNull ??
        'the rep';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${body['name']} added and handed to $rep')),
    );
  }

  Future<void> _reassign(Lead lead, CompanySnapshot co) async {
    final SalesRep? rep = await showDialog<SalesRep>(
      context: context,
      builder: (BuildContext ctx) => SimpleDialog(
        title: Text('Reassign ${lead.companyName}'),
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
    try {
      await ref.read(pipelineRepositoryProvider).reassignLead(lead.id, rep.id);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not reassign: ${e.message}'),
          backgroundColor: VizPalette.statusCritical,
        ),
      );
      return;
    }
    ref.invalidate(companyProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${lead.companyName} handed to ${rep.name}')),
    );
  }

  /// The stages a lost lead can be reopened at: New, and each later one its
  /// own records back - a demo given, a negotiation opened, a proposal sent.
  /// The server refuses the rest, so they aren't offered. Furthest last.
  static List<PipelineStage> _reopenStages(Lead lead) {
    final NegotiationSummary? neg = lead.negotiation;
    final Set<String> backed = <String>{
      'new',
      if (lead.demoCount > 0) 'demo',
      if (neg != null) 'negotiation',
      if (neg?.status == 'proposal_sent') 'proposal',
    };
    return Mappers.fixedStages
        .where((PipelineStage s) => backed.contains(s.id))
        .toList();
  }

  Future<void> _reopen(Lead lead) async {
    final List<PipelineStage> open = _reopenStages(lead);
    // Where it had got to, by default.
    String stageId = open.last.id;
    final TextEditingController reason = TextEditingController();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setDialog) => AlertDialog(
          title: Text('Reopen ${lead.companyName}?'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'It goes back into the pipeline. The reason is kept on '
                  "the lead's history.",
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: stageId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Back to'),
                  items: <DropdownMenuItem<String>>[
                    for (final PipelineStage s in open)
                      DropdownMenuItem<String>(
                        value: s.id,
                        child: Text(s.name),
                      ),
                  ],
                  onChanged: (String? v) =>
                      setDialog(() => stageId = v ?? stageId),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reason,
                  autofocus: true,
                  maxLines: 2,
                  onChanged: (_) => setDialog(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Why?',
                    hintText: 'e.g. They called back with a new budget',
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: reason.text.trim().isEmpty
                  ? null
                  : () => Navigator.of(ctx).pop(true),
              child: const Text('Reopen'),
            ),
          ],
        ),
      ),
    );
    final String why = reason.text.trim();
    reason.dispose();
    if (ok != true) return;
    try {
      await ref
          .read(pipelineRepositoryProvider)
          .reopenLead(lead.id, stageId: stageId, reason: why);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not reopen: ${e.message}'),
          backgroundColor: VizPalette.statusCritical,
        ),
      );
      return;
    }
    ref.invalidate(companyProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${lead.companyName} reopened at '
          '${Mappers.stageFor(stageId).name}',
        ),
      ),
    );
  }

  void _openCustomer(String customerId) {
    ref.read(customerFocusProvider.notifier).state = customerId;
    openSection.value = NavSection.customers;
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
    // A term typed into the top bar lands here once, then is cleared.
    final String jump = ref.watch(globalSearchProvider);
    if (jump.isNotEmpty) {
      _search.text = jump;
      _stageId = null;
      // Jumping to a name should find it, customer or lost lead included.
      _showClosed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(globalSearchProvider.notifier).state = '';
      });
    }
    // A link from elsewhere (a customer's "came from" lead) opens that lead.
    final String? focus = ref.watch(leadFocusProvider);
    if (focus != null) {
      _search.clear();
      _stageId = null;
      _repId = null;
      _source = null;
      _showClosed = true;
      _expandedId = focus;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(leadFocusProvider.notifier).state = null;
      });
    }
    final LayoutSize size = Responsive.of(context);
    final List<Lead> leads = _filtered(co);
    final Set<String> sources = <String>{
      for (final Lead l in co.leads)
        if (l.source.isNotEmpty) l.source,
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
            title: 'Lead oversight',
            subtitle: Text(
              '${co.leads.length} leads - '
              '${co.leads.where((Lead l) => l.isOpen).length} open',
            ),
            trailing: FilledButton.icon(
              onPressed: () => _newLead(co),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New lead'),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Reveal(
            index: 1,
            child: _StageStrip(
              leads: co.leads,
              selected: _stageId,
              onSelect: (String? id) => setState(() => _stageId = id),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          DataBlock(
            children: <Widget>[
              Reveal(
                index: 2,
                child: _LeadFilters(
                  controller: _search,
                  reps: co.activeReps,
                  repId: _repId,
                  sources: sources.toList()..sort(),
                  source: _source,
                  showClosed: _showClosed,
                  onSearch: () => setState(() {}),
                  onRep: (String? id) => setState(() => _repId = id),
                  onSource: (String? s) => setState(() => _source = s),
                  onShowClosed: (bool v) => setState(() => _showClosed = v),
                ),
              ),
              if (leads.isEmpty)
                Panel(
                  padding: const EdgeInsets.all(AppSpacing.xxl),
                  child: EmptyState(
                    icon: Icons.bolt_outlined,
                    title: 'No leads match these filters',
                    message: _showClosed
                        ? 'Clear a filter, or pick another stage above.'
                        : 'Clear a filter, pick another stage above, or '
                              'show customers & lost leads.',
                  ),
                )
              else
                Reveal(
                  index: 3,
                  child: _LeadTable(
                    leads: leads,
                    expandedId: _expandedId,
                    onToggle: (Lead l) => setState(
                      () => _expandedId = _expandedId == l.id ? null : l.id,
                    ),
                    onReassign: (Lead l) => _reassign(l, co),
                    onReopen: _reopen,
                    onOpenCustomer: _openCustomer,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// --- Stage strip -----------------------------------------------------------

class _StageStrip extends StatelessWidget {
  const _StageStrip({
    required this.leads,
    required this.selected,
    required this.onSelect,
  });

  final List<Lead> leads;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ChartTheme chart = context.chart;
    final List<PipelineStage> stages = Mappers.fixedStages;

    return Panel(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            for (int i = 0; i < stages.length; i++) ...<Widget>[
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    stages[i].kind == LeadStageKind.lost
                        ? Icons.subdirectory_arrow_right
                        : Icons.chevron_right,
                    size: 16,
                    color: VizPalette.inkMuted,
                  ),
                ),
              _StageTile(
                stage: stages[i],
                count: leads
                    .where((Lead l) => l.stageId == stages[i].id)
                    .length,
                color: stageColor(stages[i], chart),
                selected: selected == stages[i].id,
                onTap: () =>
                    onSelect(selected == stages[i].id ? null : stages[i].id),
                theme: theme,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StageTile extends StatelessWidget {
  const _StageTile({
    required this.stage,
    required this.count,
    required this.color,
    required this.selected,
    required this.onTap,
    required this.theme,
  });

  final PipelineStage stage;
  final int count;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 128,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: selected ? 0.22 : 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: color.withValues(alpha: selected ? 0.8 : 0.25),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              stage.name.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              Fmt.count(count),
              style: theme.textTheme.titleLarge?.copyWith(
                fontFeatures: kTabularFigures,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One hue light-to-dark for the ordered open stages; good/muted for the
/// two terminal ones, so won and lost never read as "further along".
Color stageColor(PipelineStage stage, ChartTheme chart) => Dt.stage(stage.id);

// --- Filters ---------------------------------------------------------------

class _LeadFilters extends StatelessWidget {
  const _LeadFilters({
    required this.controller,
    required this.reps,
    required this.repId,
    required this.sources,
    required this.source,
    required this.showClosed,
    required this.onSearch,
    required this.onRep,
    required this.onSource,
    required this.onShowClosed,
  });

  final TextEditingController controller;
  final List<SalesRep> reps;
  final String? repId;
  final List<String> sources;
  final String? source;
  final bool showClosed;
  final VoidCallback onSearch;
  final ValueChanged<String?> onRep;
  final ValueChanged<String?> onSource;
  final ValueChanged<bool> onShowClosed;

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
                      hintText: 'Search company, contact, phone, requirement',
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
          PillDropdown<String?>(
            value: repId,
            items: <String?>[null, ...repNames.keys],
            labelOf: (String? id) => id == null ? 'Any rep' : repNames[id]!,
            onChanged: onRep,
          ),
          PillDropdown<String?>(
            value: source,
            items: <String?>[null, ...sources],
            labelOf: (String? s) => s ?? 'Any source',
            onChanged: onSource,
          ),
          FilterChip(
            label: const Text('Show customers & lost'),
            selected: showClosed,
            onSelected: onShowClosed,
          ),
        ],
      ),
    );
  }
}

// --- Table -----------------------------------------------------------------

// Column proportions, not pixels. Each is an Expanded flex, so the row
// fills whatever width the table is given and every column grows by the
// same factor. As fixed widths the data crowded into the left of a wide
// screen and the rest of every row stood empty. The sum still sets the
// minimum width, below which the table scrolls rather than squeezing.
const List<double> _cols = <double>[260, 120, 140, 130, 110, 96];
const double _minTableWidth = 856;

class _LeadTable extends StatelessWidget {
  const _LeadTable({
    required this.leads,
    required this.expandedId,
    required this.onToggle,
    required this.onReassign,
    required this.onReopen,
    required this.onOpenCustomer,
  });

  final List<Lead> leads;
  final String? expandedId;
  final ValueChanged<Lead> onToggle;
  final ValueChanged<Lead> onReassign;
  final ValueChanged<Lead> onReopen;
  final ValueChanged<String> onOpenCustomer;

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
                        Expanded(
                          flex: _cols[0].round(),
                          child: Text('Lead', style: head),
                        ),
                        Expanded(
                          flex: _cols[1].round(),
                          child: Text('Stage', style: head),
                        ),
                        Expanded(
                          flex: _cols[2].round(),
                          child: Text('Rep', style: head),
                        ),
                        Expanded(
                          flex: _cols[3].round(),
                          child: Text('Next follow-up', style: head),
                        ),
                        Expanded(
                          flex: _cols[4].round(),
                          child: Text('Source', style: head),
                        ),
                        Expanded(
                          flex: _cols[5].round(),
                          child: Text(
                            'Value',
                            style: head,
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                  ),
                  for (final Lead l in leads) ...<Widget>[
                    _LeadRow(
                      lead: l,
                      expanded: expandedId == l.id,
                      onTap: () => onToggle(l),
                    ),
                    if (expandedId == l.id)
                      _LeadDetail(
                        lead: l,
                        onReassign: () => onReassign(l),
                        onReopen: () => onReopen(l),
                        onOpenCustomer: l.customerId == null
                            ? null
                            : () => onOpenCustomer(l.customerId!),
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

class _LeadRow extends StatelessWidget {
  const _LeadRow({
    required this.lead,
    required this.expanded,
    required this.onTap,
  });

  final Lead lead;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ChartTheme chart = context.chart;
    final PipelineStage stage = Mappers.stageFor(lead.stageId);
    final Color color = stageColor(stage, chart);
    final TextStyle? muted = theme.textTheme.labelSmall?.copyWith(
      color: VizPalette.inkMuted,
    );
    final DateTime? next = lead.nextActionAt;
    final bool overdue =
        next != null && lead.isOpen && next.isBefore(DateTime.now());

    return HoverRow(
      onTap: onTap,
      child: Container(
        height: AppSpacing.tableRowHeight,
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: theme.dividerColor)),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              flex: _cols[0].round(),
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
                          lead.companyName,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                        Text(
                          lead.requirement.isEmpty
                              ? '${lead.contactName} - ${lead.city}'
                              : '${lead.contactName} - ${lead.requirement}',
                          overflow: TextOverflow.ellipsis,
                          style: muted,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: _cols[1].round(),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  StatusChip(
                    label: stage.name,
                    color: color,
                    icon: _stageIcon(stage),
                    dense: true,
                  ),
                  // Why it was lost, where the list can be scanned for it (#36).
                  if (lead.stageKind == LeadStageKind.lost &&
                      lead.lostReason.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        CompanyProfile.labelOf(
                          CompanyProfile.lostReasonLabels,
                          lead.lostReason,
                        ),
                        overflow: TextOverflow.ellipsis,
                        style: muted,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              flex: _cols[2].round(),
              child: Text(
                lead.repName,
                overflow: TextOverflow.ellipsis,
                style: muted,
              ),
            ),
            Expanded(
              flex: _cols[3].round(),
              child: Text(
                next == null ? '-' : Fmt.dateShort(next),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: overdue
                      ? VizPalette.statusCritical
                      : VizPalette.inkMuted,
                ),
              ),
            ),
            Expanded(
              flex: _cols[4].round(),
              child: Text(
                lead.source,
                overflow: TextOverflow.ellipsis,
                style: muted,
              ),
            ),
            Expanded(
              flex: _cols[5].round(),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    lead.value == 0 ? '-' : Fmt.moneyCompact(lead.value),
                    textAlign: TextAlign.right,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontFeatures: kTabularFigures,
                    ),
                  ),
                  // Money received was sent to the console but never shown
                  // (#34). Red when it is more than the price.
                  if (lead.amountPaid > 0)
                    Text(
                      'paid ${Fmt.moneyCompact(lead.amountPaid)}',
                      textAlign: TextAlign.right,
                      style: muted?.copyWith(
                        fontFeatures: kTabularFigures,
                        color: lead.value > 0 && lead.amountPaid > lead.value
                            ? VizPalette.statusCritical
                            : null,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _stageIcon(PipelineStage stage) => switch (stage.id) {
  'new' => Icons.fiber_new_outlined,
  'demo' => Icons.play_circle_outline,
  'negotiation' => Icons.handshake_outlined,
  'proposal' => Icons.description_outlined,
  'converted' => Icons.check_circle_outline,
  _ => Icons.cancel_outlined,
};

/// The expanded row: the demo and negotiation records behind the stage,
/// the money, and any steps back.
class _LeadDetail extends ConsumerWidget {
  const _LeadDetail({
    required this.lead,
    required this.onReassign,
    required this.onReopen,
    this.onOpenCustomer,
  });

  final Lead lead;
  final VoidCallback onReassign;
  final VoidCallback onReopen;

  /// Opens the customer this lead became; null unless it converted.
  final VoidCallback? onOpenCustomer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final CompanySnapshot? co = ref.watch(companyProvider).valueOrNull;
    final DemoSummary? demo = lead.latestDemo;
    final NegotiationSummary? neg = lead.negotiation;
    final List<FieldVisit> visits =
        co?.visitsForLead(lead.id) ?? const <FieldVisit>[];
    final List<FollowUp> followUps =
        co?.followUpsForLead(lead.id) ?? const <FollowUp>[];
    String dash(String v) => v.isEmpty ? '-' : v;
    final Customer? customer = lead.customerId == null
        ? null
        : co?.customers
              .where((Customer c) => c.id == lead.customerId)
              .firstOrNull;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: AppSpacing.xl,
            runSpacing: AppSpacing.lg,
            crossAxisAlignment: WrapCrossAlignment.start,
            children: <Widget>[
              _DetailBlock(
                // A customer's lead: the customer holds the contact details,
                // so they're shown from there, current (#52).
                title: customer == null ? 'Contact' : 'Contact (on the customer)',
                rows: <(String, String)>[
                  (
                    'Name',
                    customer != null
                        ? customer.name
                        : lead.designation.isEmpty
                        ? lead.contactName
                        : '${lead.contactName} (${lead.designation})',
                  ),
                  ('Phone', customer?.phone ?? lead.phone),
                  ('Email', dash(customer?.email ?? lead.email)),
                  ('City', dash(customer?.city ?? lead.city)),
                  (
                    'Industry',
                    lead.industry.isEmpty
                        ? '-'
                        : CompanyProfile.labelOf(
                            CompanyProfile.industryLabels,
                            lead.industry,
                          ),
                  ),
                  ('Source', lead.source),
                  ('Rep', lead.repName),
                  ('Added', Fmt.date(lead.createdAt)),
                  if (lead.lostReason.isNotEmpty)
                    (
                      'Lost because',
                      CompanyProfile.labelOf(
                        CompanyProfile.lostReasonLabels,
                        lead.lostReason,
                      ),
                    ),
                  ('Notes', dash(lead.notes)),
                ],
              ),
              _DetailBlock(
                title: 'Project',
                rows: <(String, String)>[
                  (
                    'Wants',
                    lead.projectType.isEmpty
                        ? '-'
                        : '${CompanyProfile.labelOf(CompanyProfile.projectTypeLabels, lead.projectType)}'
                              '${lead.platforms.isEmpty ? '' : ' (${lead.platforms == 'both' ? 'Android + iOS' : lead.platforms})'}',
                  ),
                  ('Requirement', dash(lead.requirement)),
                  ('Existing site/app', dash(lead.existingUrl)),
                  (
                    'Their budget',
                    lead.budget == null ? '-' : Fmt.money(lead.budget!),
                  ),
                  (
                    'Wants to start',
                    lead.expectedStart == null
                        ? '-'
                        : Fmt.date(lead.expectedStart!),
                  ),
                  ('Priority', lead.priority),
                ],
              ),
              _MoneyBlock(lead: lead),
              _DetailBlock(
                title: demo == null
                    ? 'Presentation'
                    : 'Presentation (${lead.demoCount} given)',
                rows: demo == null
                    ? const <(String, String)>[('Status', 'None given yet')]
                    : <(String, String)>[
                        ('Date', Fmt.dateTime(demo.heldAt)),
                        ('Presented', dash(demo.product)),
                        (
                          'Shown as',
                          dash(
                            CompanyProfile.labelOf(
                              CompanyProfile.demoShownLabels,
                              demo.shown,
                            ),
                          ),
                        ),
                        (
                          'Where',
                          dash(
                            CompanyProfile.labelOf(
                              CompanyProfile.demoModeLabels,
                              demo.mode,
                            ),
                          ),
                        ),
                        ('Attended', dash(demo.attendees)),
                        ('Given by', dash(demo.givenBy)),
                        ('Outcome', demo.outcome),
                        ('Feedback', dash(demo.feedback)),
                        ('Notes', dash(demo.notes)),
                      ],
              ),
              _DetailBlock(
                title: 'Negotiation',
                rows: neg == null
                    ? const <(String, String)>[('Status', 'Not opened')]
                    : <(String, String)>[
                        ('Status', neg.statusLabel),
                        (
                          'Started',
                          neg.startedAt == null
                              ? '-'
                              : Fmt.date(neg.startedAt!),
                        ),
                        ('Decision maker', dash(neg.decisionMaker)),
                        (
                          'Quoted',
                          neg.quotedAmount == null
                              ? '-'
                              : '${Fmt.money(neg.quotedAmount!)}'
                                    '${neg.discountPct == null ? '' : '  (${neg.discountPct}% off)'}',
                        ),
                        (
                          'Payment',
                          neg.paymentTerms.isEmpty
                              ? '-'
                              : '${CompanyProfile.labelOf(CompanyProfile.paymentTermsLabels, neg.paymentTerms)}'
                                    '${neg.paymentTermsNote.isEmpty ? '' : ' - ${neg.paymentTermsNote}'}',
                        ),
                        (
                          'Timeline',
                          neg.timelineWeeks == null
                              ? '-'
                              : '${neg.timelineWeeks} weeks',
                        ),
                        ('Competing with', dash(neg.competitor)),
                        ('Objections', dash(neg.objections)),
                        (
                          'Expected close',
                          neg.expectedCloseOn == null
                              ? '-'
                              : '${Fmt.date(neg.expectedCloseOn!)}'
                                    '${neg.isSlipping ? '  (slipping)' : ''}',
                        ),
                        (
                          'Proposal file',
                          neg.proposalUrl == null ? 'None' : 'Attached',
                        ),
                        ('Notes', dash(neg.notes)),
                      ],
                warn: neg?.isSlipping ?? false,
              ),
              VisitsBlock(visits: visits),
              FollowUpsBlock(followUps: followUps),
              if (lead.stageChanges.isNotEmpty)
                _DetailBlock(
                  title: 'Steps back',
                  rows: <(String, String)>[
                    for (final StageChange c in lead.stageChanges)
                      (
                        Fmt.dateShort(c.at),
                        '${c.fromStage} -> ${c.toStage}, by ${c.by}: '
                            '${c.reason}',
                      ),
                  ],
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 18),
            // A Row, so the pills size to their labels instead of filling
            // the loose width a Wrap hands them.
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (lead.isOpen)
                  PillButton(
                    label: 'Reassign',
                    filled: false,
                    onTap: onReassign,
                  ),
                // Managers and admins only, which is everyone signed in to
                // the console; the server asks the same (#59).
                if (lead.stageKind == LeadStageKind.lost)
                  PillButton(label: 'Reopen', filled: false, onTap: onReopen),
                // Which customer it became (#37).
                if (onOpenCustomer != null)
                  PillButton(
                    label: 'Open customer',
                    filled: false,
                    onTap: onOpenCustomer!,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Price, what has been paid, and what is still needed before the lead can
/// become a customer (#34). For a customer, the balance left on the price.
class _MoneyBlock extends StatelessWidget {
  const _MoneyBlock({required this.lead});

  final Lead lead;

  @override
  Widget build(BuildContext context) {
    final bool priced = lead.value > 0;
    final bool overpaid = priced && lead.amountPaid > lead.value;
    final String share = '${(lead.depositShare * 100).round()}%';
    return _DetailBlock(
      title: 'Money',
      warn: overpaid,
      rows: <(String, String)>[
        ('Price', priced ? Fmt.money(lead.value) : 'Not agreed yet'),
        ('Paid', Fmt.money(lead.amountPaid)),
        if (overpaid) ('Check', 'Paid more than the price'),
        if (lead.isOpen && priced) ...<(String, String)>[
          ('Deposit', '$share = ${Fmt.money(lead.depositRequired)}'),
          (
            'Still to pay',
            lead.depositOutstanding == 0
                ? 'Nothing - ready to convert'
                : '${Fmt.money(lead.depositOutstanding)} before converting',
          ),
        ],
        if (lead.stageKind == LeadStageKind.won && priced)
          (
            'Balance',
            lead.amountPaid >= lead.value
                ? 'Paid in full'
                : Fmt.money(lead.value - lead.amountPaid),
          ),
      ],
    );
  }
}

class _DetailBlock extends StatelessWidget {
  const _DetailBlock({
    required this.title,
    required this.rows,
    this.warn = false,
  });

  final String title;
  final List<(String, String)> rows;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SizedBox(
      width: 240,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            title.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: warn ? VizPalette.statusCritical : VizPalette.inkMuted,
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
                  SizedBox(
                    width: 96,
                    child: Text(
                      k,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: VizPalette.inkMuted,
                      ),
                    ),
                  ),
                  Expanded(child: Text(v, style: theme.textTheme.bodySmall)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
