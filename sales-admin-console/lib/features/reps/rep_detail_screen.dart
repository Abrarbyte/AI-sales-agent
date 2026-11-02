import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../data/providers.dart';
import '../../data/api/api_client.dart';
import '../../data/repositories/company_repository.dart';
import '../../data/repositories/pipeline_repository.dart';
import '../../widgets/async_gate.dart';
import '../../data/models/lead.dart';
import '../../data/models/people.dart';
import '../dashboard/dashboard_panels.dart';
import '../people/person_form_dialog.dart';

/// Screen 3b - one rep: performance, assigned accounts, recent activity.
///
/// ===========================================================================
/// EXPECTED API CONTRACT
/// ===========================================================================
/// GET /super/reps/{id}
///   200 { ...rep object (see reps_screen.dart)... }
///
/// GET /super/reps/{id}/leads?status=open|won|lost&page=1
///   200 { "items": [ { "id": "lead_3", "company_name": "Halcyon DataWorks",
///                      "contact_name": "Priyanka Shah",
///                      "stage_id": "stg_3", "stage_name": "Proposal Sent",
///                      "stage_kind": "open", "stage_order": 2,
///                      "source": "Content Syndication", "value": 14500.0,
///                      "rep_id": "rep_3", "rep_name": "Karan Joshi",
///                      "admin_id": "adm_1", "team_name": "Demand Generation",
///                      "created_at": "...", "updated_at": "...",
///                      "city": "San Jose, CA" } ] }
///
/// GET /super/reps/{id}/activity?limit=20
///   200 { "items": [ { "id": "...", "lead_id": "lead_3", "kind": "call",
///                      "summary": "Discovery call with the marketing lead",
///                      "actor_name": "Karan Joshi", "actor_role": "sales_rep",
///                      "at": "2026-08-24T11:20:00Z" } ] }
/// ===========================================================================
class RepDetailScreen extends ConsumerWidget {
  const RepDetailScreen({
    super.key,
    required this.rep,
    required this.onBack,
    required this.onChanged,
  });

  final SalesRep rep;
  final VoidCallback onBack;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncGate<PipelineSnapshot>(
      value: ref.watch(pipelineProvider),
      onRetry: () => ref.invalidate(companyProvider),
      loadingHeight: 420,
      data: (PipelineSnapshot pipeline) => _build(context, pipeline),
    );
  }

  Widget _build(BuildContext context, PipelineSnapshot pipeline) {
    final LayoutSize size = Responsive.of(context);
    final List<Lead> leads = pipeline.leadsForRep(rep.id);

    // The rep's timeline is their accounts' activity, newest first.
    final List<LeadActivity> activity = <LeadActivity>[
      for (final Lead l in leads) ...pipeline.activityFor(l.id),
    ]..sort((LeadActivity a, LeadActivity b) => b.at.compareTo(a.at));

    final Widget leftCol = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _ProfilePanel(rep: rep),
        const SizedBox(height: AppSpacing.lg),
        _PerformancePanel(rep: rep, leads: leads),
      ],
    );

    final Widget rightCol = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _AccountsPanel(leads: leads),
        const SizedBox(height: AppSpacing.lg),
        _ActivityPanel(items: activity.take(12).toList()),
      ],
    );

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
          _Breadcrumb(name: rep.name, onBack: onBack),
          const SizedBox(height: AppSpacing.md),
          if (size.isExpanded)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(width: 372, child: leftCol),
                const SizedBox(width: AppSpacing.lg),
                Expanded(child: rightCol),
              ],
            )
          else
            Column(
              children: <Widget>[
                leftCol,
                const SizedBox(height: AppSpacing.lg),
                rightCol,
              ],
            ),
        ],
      ),
    );
  }
}

class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({required this.name, required this.onBack});

  final String name;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      children: <Widget>[
        InkWell(
          onTap: onBack,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.arrow_back, size: 16),
                const SizedBox(width: 6),
                Text(
                  'Sales Reps',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
        Text('  /  ', style: theme.textTheme.bodySmall),
        Text(name, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _ProfilePanel extends ConsumerWidget {
  const _ProfilePanel({required this.rep});

  final SalesRep rep;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final Color color = context.chart.seriesFor(
      ref.watch(companyProvider).valueOrNull?.entityIndexOfRep(rep.id) ?? 0,
    );

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                  border: Border.all(color: color.withValues(alpha: 0.45)),
                ),
                child: Text(
                  Fmt.initials(rep.name),
                  style: theme.textTheme.titleMedium?.copyWith(color: color),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(rep.name, style: theme.textTheme.titleLarge),
                    Text(
                      '${rep.teamName} - ${rep.branch}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _InfoRow(icon: Icons.mail_outline, value: rep.email),
          _InfoRow(icon: Icons.phone_outlined, value: rep.phone),
          _InfoRow(
            icon: Icons.event_outlined,
            value: 'Joined ${Fmt.date(rep.joinedAt)}',
          ),
          _InfoRow(
            icon: Icons.schedule,
            value: rep.lastCheckInAt == null
                ? 'No recent activity'
                : 'Last active ${Fmt.relative(rep.lastCheckInAt!)}',
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: rep.status.color.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: rep.status.color.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(rep.status.icon, size: 13, color: rep.status.color),
                    const SizedBox(width: 5),
                    Text(
                      rep.status.label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: rep.status.color,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              PillButton(
                label: 'Edit',
                filled: false,
                onTap: () => _editRep(context, ref, rep),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Opens the shared person form for this rep and saves the result.
///
/// Role and manager are read back from the rep rather than assumed, so editing
/// a phone number cannot silently change either.
Future<void> _editRep(BuildContext context, WidgetRef ref, SalesRep rep) async {
  final CompanySnapshot? company = ref.read(companyProvider).valueOrNull;

  final PersonFormResult? result = await showDialog<PersonFormResult>(
    context: context,
    builder: (_) => PersonFormDialog(
      existingId: rep.id,
      initialName: rep.name,
      initialEmail: rep.email,
      initialPhone: rep.phone,
      initialRole: PersonRole.employee,
      initialManagerId: rep.managerId,
      managers: company == null
          ? const <ManagerOption>[]
          : managerOptionsFrom(company),
    ),
  );
  if (result == null) return;

  try {
    await ref
        .read(companyRepositoryProvider)
        .updateEmployee(
          rep.id,
          name: result.name,
          email: result.email,
          phone: result.phone,
          role: result.role.wire,
          managerId: result.managerId,
          password: result.password,
        );
  } on ApiException catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Could not save ${result.name}: ${e.message}'),
        backgroundColor: VizPalette.statusCritical,
      ),
    );
    return;
  }

  ref.invalidate(companyProvider);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text('${result.name} updated')));
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 15, color: VizPalette.inkMuted),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _PerformancePanel extends StatelessWidget {
  const _PerformancePanel({required this.rep, required this.leads});

  final SalesRep rep;
  final List<Lead> leads;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double openValue = leads
        .where((Lead l) => l.isOpen)
        .fold(0, (double s, Lead l) => s + l.value);

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('Performance', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.lg),
          // The attainment meter and its "target" line were removed: no target
          // model exists, so the ratio was always 0% against a target of zero.
          // Revenue booked stands on its own until targets are stored.
          Text(
            Fmt.money(rep.revenueThisPeriod),
            style: theme.textTheme.displaySmall?.copyWith(
              fontFeatures: kTabularFigures,
            ),
          ),
          Text('booked this period', style: theme.textTheme.bodySmall),
          const SizedBox(height: AppSpacing.lg),
          Divider(color: theme.dividerColor, height: 1),
          const SizedBox(height: AppSpacing.md),
          _StatLine(label: 'Accounts assigned', value: '${rep.assignedLeads}'),
          _StatLine(label: 'Won this period', value: '${rep.wonLeads}'),
          _StatLine(
            label: 'Conversion',
            value: Fmt.percent(rep.conversionRate),
          ),
          _StatLine(label: 'Open pipeline', value: Fmt.moneyCompact(openValue)),
          _StatLine(
            label: 'Touchpoints this month',
            value: '${rep.visitsThisMonth}',
          ),
        ],
      ),
    );
  }
}

class _StatLine extends StatelessWidget {
  const _StatLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: <Widget>[
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: VizPalette.inkMuted,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: theme.textTheme.labelMedium?.copyWith(
              fontFeatures: kTabularFigures,
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountsPanel extends StatelessWidget {
  const _AccountsPanel({required this.leads});

  final List<Lead> leads;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Panel(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PanelHeader(
            title: 'Assigned accounts',
            subtitle: Text('${leads.length} client accounts'),
          ),
          const SizedBox(height: AppSpacing.md),
          if (leads.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Text(
                'No accounts assigned yet.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            )
          else
            for (final Lead l in leads) _AccountRow(lead: l),
        ],
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.lead});

  final Lead lead;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ChartTheme chart = context.chart;

    // Stage colour comes from the ordinal ramp: the stages are an ORDERED
    // scale, so one hue light-to-dark, never a categorical rainbow.
    final Color stageColor = lead.stageKind == LeadStageKind.won
        ? VizPalette.statusGood
        : lead.stageKind == LeadStageKind.lost
        ? VizPalette.inkMuted
        : chart.ordinalFor(lead.stageOrder, 5);

    return Container(
      height: 54,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  lead.companyName,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                Text(
                  lead.requirement.isEmpty
                      ? '${lead.contactName} - ${lead.city}'
                      : '${lead.contactName} - ${lead.city} - ${lead.requirement}',
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: VizPalette.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: stageColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  lead.stageName,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: stageColor,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              lead.source,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: VizPalette.inkMuted,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              lead.nextActionAt == null
                  ? '-'
                  : Fmt.dateShort(lead.nextActionAt!),
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                // Overdue follow-ups are the thing a manager is here to catch.
                // Evaluated for every row, including the ones with nothing
                // scheduled - so no `!` here, or one such lead paints the
                // whole list grey in a release build.
                color:
                    lead.isOpen &&
                        (lead.nextActionAt?.isBefore(DateTime.now()) ?? false)
                    ? VizPalette.statusCritical
                    : VizPalette.inkMuted,
              ),
            ),
          ),
          SizedBox(
            width: 96,
            child: Text(
              Fmt.moneyCompact(lead.value),
              textAlign: TextAlign.right,
              style: theme.textTheme.labelMedium?.copyWith(
                fontFeatures: kTabularFigures,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityPanel extends StatelessWidget {
  const _ActivityPanel({required this.items});

  final List<LeadActivity> items;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('Recent activity', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          for (int i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: VizPalette.inkMuted.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _iconFor(items[i].kind),
                      size: 13,
                      color: VizPalette.inkMuted,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          items[i].summary,
                          style: theme.textTheme.bodySmall,
                        ),
                        Text(
                          Fmt.relative(items[i].at),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: VizPalette.inkMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  IconData _iconFor(LeadActivityKind kind) {
    switch (kind) {
      case LeadActivityKind.call:
        return Icons.phone_outlined;
      case LeadActivityKind.note:
        return Icons.sticky_note_2_outlined;
      case LeadActivityKind.stageChange:
        return Icons.trending_up;
      case LeadActivityKind.created:
        return Icons.add_circle_outline;
      case LeadActivityKind.reassigned:
        return Icons.swap_horiz;
      case LeadActivityKind.merged:
        return Icons.merge;
      case LeadActivityKind.visit:
        return Icons.place_outlined;
      case LeadActivityKind.valueChange:
        return Icons.attach_money;
    }
  }
}
