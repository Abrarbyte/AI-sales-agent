import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../core/company_profile.dart';
import '../../data/providers.dart';
import '../../data/repositories/company_repository.dart';
import '../../widgets/async_gate.dart';
import '../../widgets/table_panel.dart';
import '../../widgets/motion.dart';
import '../../data/models/common.dart';
import '../../data/models/people.dart';
import '../../data/api/api_client.dart';
import '../dashboard/dashboard_panels.dart';
import '../people/person_form_dialog.dart';
import 'rep_detail_screen.dart';

/// Screen 3 - Sales Rep Directory.
///
/// ===========================================================================
/// EXPECTED API CONTRACT
/// ===========================================================================
/// GET /super/reps?search=&status=&admin_id=&sort=revenue&order=desc
///                &page=1&page_size=25
///   200 { "items": [ {
///           "id": "rep_2", "name": "Aditi Patil",
///           "email": "aditi.patil@aarmarksmedia.com",
///           "phone": "+91 97xxxxxxx",
///           "admin_id": "adm_1", "team_name": "Demand Generation",
///           "branch": "Pune HQ", "status": "active",
///           "joined_at": "2025-02-11T00:00:00Z",
///           "last_check_in_at": "2026-08-26T08:40:00Z",
///           "assigned_leads": 34, "open_leads": 21, "won_leads": 9,
///           "visits_this_month": 27, "visit_compliance_rate": 0.87,
///           "revenue_this_period": 61400.0, "target_this_period": 54000.0
///        } ], "page": 1, "page_size": 25, "total": 10 }
///
///   `admin_id` is accepted but currently redundant - there is one team. It
///   stays in the contract so adding a second team needs no client change.
///
/// PATCH /super/reps/{id}/status
///   req  { "status": "active" | "inactive" | "suspended" }
///   200  { ...rep object... }
///   409  { "error": { "code": "rep_has_open_leads",
///                     "message": "Reassign 12 open leads first" } }
/// ===========================================================================
class RepsScreen extends ConsumerStatefulWidget {
  const RepsScreen({super.key});

  @override
  ConsumerState<RepsScreen> createState() => _RepsScreenState();
}

enum _RepSort {
  revenue('Revenue'),
  name('Name'),
  leads('Leads assigned'),
  conversion('Conversion');

  const _RepSort(this.label);

  final String label;
}

class _RepsScreenState extends ConsumerState<RepsScreen> {
  final TextEditingController _search = TextEditingController();

  EntityStatus? _status;
  _RepSort _sort = _RepSort.revenue;
  String? _openRepId;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<SalesRep> _filtered(CompanySnapshot co) {
    final String q = _search.text.trim().toLowerCase();
    final List<SalesRep> out = co.reps.where((SalesRep r) {
      if (_status != null && r.status != _status) return false;
      if (q.isEmpty) return true;
      return r.name.toLowerCase().contains(q) ||
          r.email.toLowerCase().contains(q) ||
          r.phone.contains(q);
    }).toList();

    out.sort((SalesRep a, SalesRep b) {
      switch (_sort) {
        case _RepSort.revenue:
          return b.revenueThisPeriod.compareTo(a.revenueThisPeriod);
        case _RepSort.name:
          return a.name.compareTo(b.name);
        case _RepSort.leads:
          return b.assignedLeads.compareTo(a.assignedLeads);
        case _RepSort.conversion:
          return b.conversionRate.compareTo(a.conversionRate);
      }
    });
    return out;
  }

  /// Create or edit a rep. Defaults the role to Sales Rep but leaves the
  /// picker in place, so promoting someone to Manager does not mean going to
  /// another screen.
  Future<void> _openForm({SalesRep? existing, CompanySnapshot? company}) async {
    final PersonFormResult? result = await showDialog<PersonFormResult>(
      context: context,
      builder: (_) => PersonFormDialog(
        existingId: existing?.id,
        initialName: existing?.name ?? '',
        initialEmail: existing?.email ?? '',
        initialPhone: existing?.phone ?? '',
        initialRole: PersonRole.employee,
        initialManagerId: existing?.managerId,
        managers: company == null
            ? const <ManagerOption>[]
            : managerOptionsFrom(company),
      ),
    );
    if (result == null) return;

    final CompanyRepository repo = ref.read(companyRepositoryProvider);
    try {
      if (existing == null) {
        await repo.createEmployee(
          username: result.username,
          name: result.name,
          email: result.email,
          phone: result.phone,
          role: result.role.wire,
          managerId: result.managerId,
          password: result.password,
        );
      } else {
        await repo.updateEmployee(
          existing.id,
          name: result.name,
          email: result.email,
          phone: result.phone,
          role: result.role.wire,
          managerId: result.managerId,
          password: result.password,
        );
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save ${result.name}: ${e.message}'),
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
          existing == null
              ? '${result.name} created - they can sign in as '
                    '${result.username}'
              : '${result.name} updated',
        ),
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
    if (_openRepId != null) {
      final SalesRep? rep = co.repById(_openRepId!);
      if (rep != null) {
        return RepDetailScreen(
          rep: rep,
          onBack: () => setState(() => _openRepId = null),
          onChanged: () => ref.invalidate(companyProvider),
        );
      }
    }

    final LayoutSize size = Responsive.of(context);
    final List<SalesRep> reps = _filtered(co);

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
            title: 'Sales Reps',
            subtitle: Text(
              '${co.reps.length} reps in ${CompanyProfile.teamName} - '
              '${co.activeReps.length} active',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                PillDropdown<_RepSort>(
                  value: _sort,
                  items: _RepSort.values,
                  labelOf: (_RepSort s) => 'Sort: ${s.label}',
                  onChanged: (_RepSort s) => setState(() => _sort = s),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton.icon(
                  onPressed: () => _openForm(company: co),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('New Rep'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          DataBlock(children: <Widget>[
          _RepFilters(
            controller: _search,
            status: _status,
            onSearch: () => setState(() {}),
            onStatus: (EntityStatus? s) => setState(() => _status = s),
          ),
          if (reps.isEmpty)
            Panel(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: Column(
                children: <Widget>[
                  Icon(
                    Icons.people_outline,
                    size: 28,
                    color: VizPalette.inkMuted,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'No reps match these filters',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  PillButton(
                    label: 'Clear filters',
                    filled: false,
                    onTap: () => setState(() {
                      _search.clear();
                      _status = null;
                    }),
                  ),
                ],
              ),
            )
          else
            _RepTable(
              reps: reps,
              onOpen: (SalesRep r) => setState(() => _openRepId = r.id),
            ),
          ]),
        ],
      ),
    );
  }
}

class _RepFilters extends StatelessWidget {
  const _RepFilters({
    required this.controller,
    required this.status,
    required this.onSearch,
    required this.onStatus,
  });

  final TextEditingController controller;
  final EntityStatus? status;
  final VoidCallback onSearch;
  final ValueChanged<EntityStatus?> onStatus;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

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
                      hintText: 'Search name, email or phone',
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
          PillDropdown<EntityStatus?>(
            value: status,
            items: <EntityStatus?>[null, ...EntityStatus.values],
            labelOf: (EntityStatus? s) => s?.label ?? 'Any status',
            onChanged: onStatus,
          ),
        ],
      ),
    );
  }
}

// Attainment was removed - no target model exists, so the column was a 0%
// bar for every rep, with thresholds that could never change colour. Restore
// it with SalesRep.targetThisPeriod.
const List<double> _cols = <double>[240, 120, 118, 128, 140];

/// Sum of [_cols] - the table never compresses below this; it stretches
/// to fill anything wider and scrolls horizontally below it.
const double _minTableWidth = 834;

class _RepTable extends StatelessWidget {
  const _RepTable({required this.reps, required this.onOpen});

  final List<SalesRep> reps;
  final ValueChanged<SalesRep> onOpen;

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
                          child: Text('Rep', style: head),
                        ),
                        SizedBox(
                          width: _cols[1],
                          child: Text('Status', style: head),
                        ),
                        SizedBox(
                          width: _cols[2],
                          child: Text('Leads', style: head),
                        ),
                        SizedBox(
                          width: _cols[3],
                          child: Text('Conversion', style: head),
                        ),
                        SizedBox(
                          width: _cols[4],
                          child: Text('Revenue', style: head),
                        ),
                      ],
                    ),
                  ),
                  for (final SalesRep r in reps)
                    _RepRow(rep: r, onOpen: () => onOpen(r)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RepRow extends ConsumerWidget {
  const _RepRow({required this.rep, required this.onOpen});

  final SalesRep rep;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ChartTheme chart = context.chart;
    // The rep's stable colour slot, so re-sorting the table never repaints it.
    final Color color = chart.seriesFor(
      ref.watch(companyProvider).valueOrNull?.entityIndexOfRep(rep.id) ?? 0,
    );

    return HoverRow(
      onTap: onOpen,
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
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                      border: Border.all(color: color.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      Fmt.initials(rep.name),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: color,
                        fontSize: 10,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          rep.name,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                        Text(
                          rep.email,
                          overflow: TextOverflow.ellipsis,
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
            SizedBox(
              width: _cols[1],
              child: Align(
                alignment: Alignment.centerLeft,
                child: _StatusPill(status: rep.status),
              ),
            ),
            SizedBox(
              width: _cols[2],
              child: Text(
                '${rep.wonLeads} / ${rep.assignedLeads}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFeatures: kTabularFigures,
                ),
              ),
            ),
            SizedBox(
              width: _cols[3],
              child: Text(
                Fmt.percent(rep.conversionRate),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFeatures: kTabularFigures,
                ),
              ),
            ),
            SizedBox(
              width: _cols[4],
              child: Text(
                Fmt.moneyCompact(rep.revenueThisPeriod),
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

/// Status colour always travels with its icon and label.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final EntityStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: status.color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(status.icon, size: 11, color: status.color),
          const SizedBox(width: 4),
          Text(
            status.label,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: status.color),
          ),
        ],
      ),
    );
  }
}

/// Shared by the directory and the rep detail header.
