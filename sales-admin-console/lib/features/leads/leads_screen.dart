import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../data/api/api_client.dart';
import '../../data/api/mappers.dart';
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
import 'new_lead_dialog.dart';

/// Lead oversight: every lead, where it sits in the pipeline, and what has
/// happened to it - the demo it was shown and the negotiation it is in.
///
/// The stage strip along the top is the pipeline diagram with live counts:
/// Lead -> Demo -> Negotiation -> Converted, and Closed as the exit. Tapping
/// a stage filters the table to it.
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

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Lead> _filtered(CompanySnapshot co) {
    final String q = _search.text.trim().toLowerCase();
    final List<Lead> out = co.leads.where((Lead l) {
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
    final String rep = co.activeReps
        .where((SalesRep r) => r.id == '${body['assigned_to']}')
        .map((SalesRep r) => r.name)
        .firstOrNull ?? 'the rep';
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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(globalSearchProvider.notifier).state = '';
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
          DataBlock(children: <Widget>[
          Reveal(
            index: 2,
            child: _LeadFilters(
              controller: _search,
              reps: co.activeReps,
              repId: _repId,
              sources: sources.toList()..sort(),
              source: _source,
              onSearch: () => setState(() {}),
              onRep: (String? id) => setState(() => _repId = id),
              onSource: (String? s) => setState(() => _source = s),
            ),
          ),
          if (leads.isEmpty)
            Panel(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: EmptyState(
                icon: Icons.bolt_outlined,
                title: 'No leads match these filters',
                message: 'Clear a filter, or pick another stage above.',
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
              ),
            ),
          ]),
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
    required this.onSearch,
    required this.onRep,
    required this.onSource,
  });

  final TextEditingController controller;
  final List<SalesRep> reps;
  final String? repId;
  final List<String> sources;
  final String? source;
  final VoidCallback onSearch;
  final ValueChanged<String?> onRep;
  final ValueChanged<String?> onSource;

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
        ],
      ),
    );
  }
}

// --- Table -----------------------------------------------------------------

const List<double> _cols = <double>[260, 120, 140, 130, 110, 96];
const double _minTableWidth = 856;

class _LeadTable extends StatelessWidget {
  const _LeadTable({
    required this.leads,
    required this.expandedId,
    required this.onToggle,
    required this.onReassign,
  });

  final List<Lead> leads;
  final String? expandedId;
  final ValueChanged<Lead> onToggle;
  final ValueChanged<Lead> onReassign;

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
                          child: Text('Lead', style: head),
                        ),
                        SizedBox(
                          width: _cols[1],
                          child: Text('Stage', style: head),
                        ),
                        SizedBox(
                          width: _cols[2],
                          child: Text('Rep', style: head),
                        ),
                        SizedBox(
                          width: _cols[3],
                          child: Text('Next follow-up', style: head),
                        ),
                        SizedBox(
                          width: _cols[4],
                          child: Text('Source', style: head),
                        ),
                        SizedBox(
                          width: _cols[5],
                          child: Text('Value',
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
                      _LeadDetail(lead: l, onReassign: () => onReassign(l)),
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
            SizedBox(
              width: _cols[1],
              child: Align(
                alignment: Alignment.centerLeft,
                child: StatusChip(
                  label: stage.name,
                  color: color,
                  icon: _stageIcon(stage),
                  dense: true,
                ),
              ),
            ),
            SizedBox(
              width: _cols[2],
              child: Text(
                lead.repName,
                overflow: TextOverflow.ellipsis,
                style: muted,
              ),
            ),
            SizedBox(
              width: _cols[3],
              child: Text(
                next == null ? '-' : Fmt.dateShort(next),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: overdue
                      ? VizPalette.statusCritical
                      : VizPalette.inkMuted,
                ),
              ),
            ),
            SizedBox(
              width: _cols[4],
              child: Text(
                lead.source,
                overflow: TextOverflow.ellipsis,
                style: muted,
              ),
            ),
            SizedBox(
              width: _cols[5],
              child: Text(
                lead.value == 0 ? '-' : Fmt.moneyCompact(lead.value),
                textAlign: TextAlign.right,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontFeatures: kTabularFigures,
                ),
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
  'assigned' => Icons.person_outline,
  'demo' => Icons.play_circle_outline,
  'negotiation' => Icons.handshake_outlined,
  'proposal' => Icons.description_outlined,
  'converted' => Icons.check_circle_outline,
  _ => Icons.cancel_outlined,
};

/// The expanded row: the demo and negotiation records behind the stage.
class _LeadDetail extends ConsumerWidget {
  const _LeadDetail({required this.lead, required this.onReassign});

  final Lead lead;
  final VoidCallback onReassign;

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
                title: 'Contact',
                rows: <(String, String)>[
                  (
                    'Name',
                    lead.designation.isEmpty
                        ? lead.contactName
                        : '${lead.contactName} (${lead.designation})',
                  ),
                  ('Phone', lead.phone),
                  ('Email', dash(lead.email)),
                  ('City', dash(lead.city)),
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
                  (
                    'Deal value',
                    lead.value == 0 ? '-' : Fmt.money(lead.value),
                  ),
                ],
              ),
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
                        (
                          'Interested?',
                          demo.interested == null
                              ? 'Unknown'
                              : (demo.interested! ? 'Yes' : 'No'),
                        ),
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
                        ('Requirements', dash(neg.requirements)),
                        ('Scope', dash(neg.scope)),
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
                        ('Proposed', dash(neg.proposedSolution)),
                        ('Terms', dash(neg.terms)),
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
            ],
          ),
          if (lead.isOpen)
            Padding(
              padding: const EdgeInsets.only(top: 18),
              // A Row, so the pill sizes to its label instead of filling the
              // loose width a Wrap hands it.
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  PillButton(
                    label: 'Reassign',
                    filled: false,
                    onTap: onReassign,
                  ),
                ],
              ),
            ),
        ],
      ),
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
