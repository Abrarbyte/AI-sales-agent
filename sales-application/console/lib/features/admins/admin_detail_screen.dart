import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../data/api/api_client.dart';
import '../../data/providers.dart';
import '../../data/repositories/company_repository.dart';
import '../../widgets/async_gate.dart';
import '../../data/models/common.dart';
import '../../data/models/people.dart';
import '../../widgets/primitives.dart';

/// Screen 2b - one Admin's team, with cross-team rep reassignment.
///
/// ===========================================================================
/// EXPECTED API CONTRACT
/// ===========================================================================
/// GET /super/admins/{id}
///   200 { ...admin object (see admins_screen.dart)... }
///
/// GET /super/admins/{id}/reps
///   200 { "items": [ {
///           "id": "rep_3", "name": "Karan Joshi",
///           "email": "...", "phone": "...",
///           "admin_id": "adm_1", "team_name": "Northern", "branch": "Pune HQ",
///           "status": "active", "joined_at": "2025-02-11T00:00:00Z",
///           "assigned_leads": 24, "open_leads": 15, "won_leads": 7,
///           "visits_this_month": 31, "visit_compliance_rate": 0.87,
///           "revenue_this_period": 412000.0, "target_this_period": 500000.0
///        } ] }
///
/// POST /super/reps/reassign
///   req  { "rep_ids": ["rep_3","rep_9"], "to_admin_id": "adm_4" }
///   200  { "moved": 2, "reps": [ ...updated rep objects... ] }
///   409  { "error": { "code": "rep_has_open_visits",
///                     "message": "2 reps have visits in progress" } }
///        The backend moves the reps' team/branch denormalisations and
///        re-parents their OPEN leads; closed leads keep their historic owner
///        so past-period reports stay stable.
/// ===========================================================================
class AdminDetailScreen extends ConsumerStatefulWidget {
  const AdminDetailScreen({
    super.key,
    required this.admin,
    required this.onBack,
    required this.onChanged,
  });

  final AdminUser admin;
  final VoidCallback onBack;

  /// Called after a mutation so the list behind can refresh its roll-ups.
  final VoidCallback onChanged;

  @override
  ConsumerState<AdminDetailScreen> createState() => _AdminDetailScreenState();
}

class _AdminDetailScreenState extends ConsumerState<AdminDetailScreen> {
  final Set<String> _selected = <String>{};

  Future<void> _reassignSelected(CompanySnapshot co) async {
    final List<AdminUser> targets = co.admins
        .where((AdminUser a) => a.id != widget.admin.id)
        .toList();

    final String? toId = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => _ReassignDialog(
        count: _selected.length,
        fromTeam: widget.admin.teamName,
        targets: targets,
      ),
    );
    if (toId == null) return;

    // One PATCH per rep: the employees endpoint updates a single person, and
    // there is no bulk-reassign route. Failures are counted rather than
    // aborting the batch, so a partial move still reports honestly.
    final CompanyRepository repo = ref.read(companyRepositoryProvider);
    final List<String> repIds = _selected.toList();
    int moved = 0;
    String? failure;
    for (final String repId in repIds) {
      try {
        await repo.reassignRep(repId, toId);
        moved++;
      } on ApiException catch (e) {
        failure ??= e.message;
      }
    }

    final AdminUser? to = co.adminById(toId);

    setState(_selected.clear);
    ref.invalidate(companyProvider);
    widget.onChanged();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failure == null
              ? 'Moved $moved rep${moved == 1 ? '' : 's'} to '
                  '${to?.teamName ?? 'team'}'
              : 'Moved $moved of ${repIds.length}. $failure',
        ),
        backgroundColor:
            failure == null ? null : VizPalette.statusCritical,
      ),
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
    // Re-read so roll-ups reflect any reassignment made on this screen.
    final AdminUser admin = co.adminById(widget.admin.id) ?? widget.admin;
    final List<SalesRep> team = co.repsForAdmin(admin.id);

    return SingleChildScrollView(
      padding: Responsive.pagePadding(size),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _Breadcrumb(name: admin.name, onBack: widget.onBack),
          const SizedBox(height: AppSpacing.md),
          _AdminSummaryCard(admin: admin),
          const SizedBox(height: AppSpacing.lg),
          const SizedBox(height: AppSpacing.lg),
          SectionCard(
            title: 'Team: ${admin.teamName}',
            subtitle: _selected.isEmpty
                ? '${team.length} reps report to ${admin.name}'
                : '${_selected.length} selected',
            padding: EdgeInsets.zero,
            actions: <Widget>[
              if (_selected.isNotEmpty)
                FilledButton.icon(
                  onPressed: () => _reassignSelected(co),
                  icon: const Icon(Icons.swap_horiz, size: 16),
                  label: const Text('Reassign'),
                ),
              if (_selected.isNotEmpty) const SizedBox(width: AppSpacing.sm),
            ],
            child: team.isEmpty
                ? const EmptyState(
                    icon: Icons.badge_outlined,
                    title: 'No reps on this team',
                    message:
                        'Reassign reps here from another Admin, or invite new '
                        'ones from the Sales Rep directory.',
                  )
                : _TeamTable(
                    reps: team,
                    selected: _selected,
                    onToggle: (String id, bool on) => setState(() {
                      if (on) {
                        _selected.add(id);
                      } else {
                        _selected.remove(id);
                      }
                    }),
                    onToggleAll: (bool on) => setState(() {
                      _selected.clear();
                      if (on) {
                        _selected.addAll(team.map((SalesRep r) => r.id));
                      }
                    }),
                  ),
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
        IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back, size: 18),
          tooltip: 'Back to Admins',
          visualDensity: VisualDensity.compact,
        ),
        const SizedBox(width: AppSpacing.xs),
        InkWell(
          onTap: onBack,
          child: Text(
            'Admins',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.primary),
          ),
        ),
        Text('  /  ', style: theme.textTheme.bodySmall),
        Text(name, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _AdminSummaryCard extends StatelessWidget {
  const _AdminSummaryCard({required this.admin});

  final AdminUser admin;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Wrap(
          spacing: AppSpacing.xl,
          runSpacing: AppSpacing.lg,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            SizedBox(
              width: 300,
              child: Row(
                children: <Widget>[
                  InitialsAvatar(
                    name: admin.name,
                    size: 46,
                    entityIndex:
                        0,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(admin.name, style: theme.textTheme.titleLarge),
                        if (admin.username.isNotEmpty)
                          Text(
                            'Signs in as ${admin.username}',
                            style: theme.textTheme.bodySmall,
                          ),
                        Text(admin.email, style: theme.textTheme.bodySmall),
                        Text(admin.phone, style: theme.textTheme.bodySmall),
                        const SizedBox(height: AppSpacing.sm),
                        StatusChip(
                          label: admin.status.label,
                          color: admin.status.color,
                          icon: admin.status.icon,
                          dense: true,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _DetailStat(
              label: 'Team',
              value: admin.teamName,
              sub: admin.branch,
            ),
            _DetailStat(
              label: 'Reps',
              value: '${admin.activeRepCount}/${admin.repCount}',
              sub: 'active / total',
            ),
            _DetailStat(
              label: 'Leads owned',
              value: Fmt.count(admin.leadsOwned),
              sub: '${Fmt.percent(admin.conversionRate)} conversion',
            ),
            _DetailStat(
              label: 'Conversion',
              value: Fmt.percent(admin.conversionRate),
              sub: 'this period',
            ),
            _DetailStat(
              label: 'Last active',
              value: admin.lastActiveAt == null
                  ? 'Never'
                  : Fmt.relative(admin.lastActiveAt!),
              sub: 'joined ${Fmt.date(admin.createdAt)}',
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailStat extends StatelessWidget {
  const _DetailStat({
    required this.label,
    required this.value,
    required this.sub,
  });

  final String label;
  final String value;
  final String sub;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall
              ?.copyWith(color: VizPalette.inkMuted),
        ),
        const SizedBox(height: 3),
        Text(value, style: theme.textTheme.titleMedium),
        Text(sub, style: theme.textTheme.labelSmall),
      ],
    );
  }
}

// _PermissionsCard was removed. The seven toggles it showed are derived from
// `role` in Mappers.permissionsFor - the backend stores no per-admin
// permission flags - so the panel presented invented policy as configuration,
// and its "edit from the Admins list" hint pointed at a form that no longer
// carries them. Restore it if a permission store is ever added.
class _TeamTable extends StatelessWidget {
  const _TeamTable({
    required this.reps,
    required this.selected,
    required this.onToggle,
    required this.onToggleAll,
  });

  final List<SalesRep> reps;
  final Set<String> selected;
  final void Function(String id, bool on) onToggle;
  final ValueChanged<bool> onToggleAll;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool allOn = selected.length == reps.length && reps.isNotEmpty;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 860),
        child: DataTable(
          onSelectAll: (bool? v) => onToggleAll(v ?? false),
          columns: const <DataColumn>[
            DataColumn(label: Text('REP')),
            DataColumn(label: Text('STATUS')),
            DataColumn(label: Text('LEADS'), numeric: true),
            DataColumn(label: Text('VISITS'), numeric: true),
            DataColumn(label: Text('PROOF OK'), numeric: true),
            DataColumn(label: Text('LAST CHECK-IN')),
          ],
          rows: reps.map((SalesRep r) {
            final bool on = selected.contains(r.id);
            return DataRow(
              selected: on,
              onSelectChanged: (bool? v) => onToggle(r.id, v ?? false),
              cells: <DataCell>[
                DataCell(Row(
                  children: <Widget>[
                    InitialsAvatar(name: r.name, size: 28),
                    const SizedBox(width: AppSpacing.md),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(r.name, style: theme.textTheme.bodyMedium),
                        Text(
                          <String>[
                            if (r.username.isNotEmpty) r.username,
                            if (r.email.isNotEmpty) r.email,
                          ].join(' - '),
                          style: theme.textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ],
                )),
                DataCell(StatusChip(
                  label: r.status.label,
                  color: r.status.color,
                  icon: r.status.icon,
                  dense: true,
                )),
                DataCell(Text(
                  '${r.assignedLeads}',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontFeatures: kTabularFigures),
                )),
                DataCell(Text(
                  '${r.visitsThisMonth}',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontFeatures: kTabularFigures),
                )),
                DataCell(Text(
                  Fmt.percent(r.visitComplianceRate, decimals: 0),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontFeatures: kTabularFigures),
                )),
                DataCell(Text(
                  r.lastCheckInAt == null
                      ? '-'
                      : Fmt.relative(r.lastCheckInAt!),
                  style: theme.textTheme.bodySmall,
                )),
              ],
            );
          }).toList(),
          showCheckboxColumn: true,
          headingRowColor: WidgetStatePropertyAll<Color>(
            allOn
                ? theme.colorScheme.primary.withValues(alpha: 0.06)
                : Colors.transparent,
          ),
        ),
      ),
    );
  }
}

class _ReassignDialog extends StatefulWidget {
  const _ReassignDialog({
    required this.count,
    required this.fromTeam,
    required this.targets,
  });

  final int count;
  final String fromTeam;
  final List<AdminUser> targets;

  @override
  State<_ReassignDialog> createState() => _ReassignDialogState();
}

class _ReassignDialogState extends State<_ReassignDialog> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return AlertDialog(
      title: Text(
        'Reassign ${widget.count} rep${widget.count == 1 ? '' : 's'}',
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Moving out of ${widget.fromTeam}. Their open leads follow them; '
              'closed leads keep the original owner so past reports do not shift.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.lg),
            ...widget.targets.map((AdminUser a) {
              final bool on = _selected == a.id;
              return InkWell(
                onTap: () => setState(() => _selected = a.id),
                borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.sm,
                    horizontal: AppSpacing.xs,
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        on
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 18,
                        color: on
                            ? theme.colorScheme.primary
                            : VizPalette.inkMuted,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(a.teamName,
                                style: theme.textTheme.bodyMedium),
                            Text(
                              '${a.name} - ${a.branch} - ${a.repCount} reps',
                              style: theme.textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                      if (a.status != EntityStatus.active)
                        Tooltip(
                          message:
                              'This Admin is ${a.status.label.toLowerCase()}',
                          child: const Icon(
                            Icons.warning_amber_rounded,
                            size: 18,
                            color: VizPalette.statusWarning,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _selected == null
              ? null
              : () => Navigator.of(context).pop(_selected),
          child: const Text('Move reps'),
        ),
      ],
    );
  }
}
