import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../core/company_profile.dart';
import '../../data/api/api_client.dart';
import '../../data/providers.dart';
import '../../data/repositories/company_repository.dart';
import '../../widgets/async_gate.dart';
import '../../data/models/common.dart';
import '../../data/models/people.dart';
import '../../widgets/primitives.dart';
import 'admin_detail_screen.dart';
import '../people/person_form_dialog.dart';

/// Screen 2 - Admin Management.
///
/// ===========================================================================
/// EXPECTED API CONTRACT
/// ===========================================================================
/// GET /super/admins?search=&branch=&status=&page=1&page_size=25
///   200 { "items": [ {
///           "id": "adm_1", "name": "Priya Nair",
///           "email": "priya.nair@...", "phone": "+91 98200 41881",
///           "branch": "Pune HQ", "team_name": "Northern",
///           "status": "active",
///           "rep_count": 7, "active_rep_count": 6,
///           "leads_owned": 138, "conversion_rate": 0.27, "attainment": 0.94,
///           "created_at": "2025-07-21T00:00:00Z",
///           "last_active_at": "2026-08-25T08:52:00Z",
///           "permissions": {
///             "can_create_reps": true, "can_reassign_leads": true,
///             "can_approve_visit_proof": true, "can_edit_targets": true,
///             "can_approve_incentives": true, "can_export_data": true,
///             "can_override_geofence": false
///           }
///        } ], "page": 1, "page_size": 25, "total": 6 }
///
/// POST /super/admins
///   req { "name", "email", "phone", "branch", "team_name",
///         "permissions": { ...same shape... } }
///   201 { ...admin object... }   - status starts as "invited"
///   422 { "error": { "code": "validation_failed",
///                    "message": "...", "fields": { "email": "Already in use" } } }
///
/// PATCH /super/admins/{id}
///   req  any subset of the POST body
///   200  { ...admin object... }
///
/// PATCH /super/admins/{id}/status
///   req  { "status": "active" | "suspended" | "inactive" }
///   200  { ...admin object... }
///   409  when deactivating an Admin who still owns reps and
///        "reassign_to_admin_id" was not supplied.
/// ===========================================================================
class AdminsScreen extends ConsumerStatefulWidget {
  const AdminsScreen({super.key});

  @override
  ConsumerState<AdminsScreen> createState() => _AdminsScreenState();
}

class _AdminsScreenState extends ConsumerState<AdminsScreen> {
  final TextEditingController _search = TextEditingController();

  String _branch = 'All branches';
  EntityStatus? _status;

  /// Non-null when drilled into one Admin. Kept here rather than pushing a
  /// route so the sidebar and top bar stay put.
  String? _openAdminId;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<AdminUser> _filtered(CompanySnapshot co) {
    final String q = _search.text.trim().toLowerCase();
    return co.admins.where((AdminUser a) {
      if (_status != null && a.status != _status) return false;
      if (_branch != 'All branches' && a.branch != _branch) return false;
      if (q.isEmpty) return true;
      return a.name.toLowerCase().contains(q) ||
          a.email.toLowerCase().contains(q) ||
          a.teamName.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _openForm({AdminUser? existing, CompanySnapshot? company}) async {
    final PersonFormResult? result = await showDialog<PersonFormResult>(
      context: context,
      builder: (_) => PersonFormDialog(
        existingId: existing?.id,
        initialName: existing?.name ?? '',
        initialEmail: existing?.email ?? '',
        initialPhone: existing?.phone ?? '',
        initialRole:
            existing == null ? PersonRole.admin : PersonRole.fromWire(existing.roleWire),
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

  Future<void> _confirmStatusChange(
    AdminUser admin,
    CompanySnapshot co,
  ) async {
    final bool deactivating = admin.status == EntityStatus.active;
    final int reps = co.repsForAdmin(admin.id).length;

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(deactivating
            ? 'Deactivate ${admin.name}?'
            : 'Reactivate ${admin.name}?'),
        content: Text(
          deactivating
              ? 'They lose access immediately. Their $reps rep'
                  '${reps == 1 ? '' : 's'} stay assigned to ${admin.teamName} '
                  'until you move them.'
              : 'They regain access to the ${admin.teamName} team right away.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: deactivating
                ? FilledButton.styleFrom(
                    backgroundColor: VizPalette.statusCritical)
                : null,
            child: Text(deactivating ? 'Deactivate' : 'Reactivate'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final CompanyRepository repo = ref.read(companyRepositoryProvider);
    try {
      // DELETE deactivates rather than removes, so history survives.
      if (deactivating) {
        await repo.deactivateEmployee(admin.id);
      } else {
        await repo.reactivateEmployee(admin.id);
      }
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
    if (_openAdminId != null) {
      final AdminUser? admin = co.adminById(_openAdminId!);
      if (admin != null) {
        return AdminDetailScreen(
          admin: admin,
          onBack: () => setState(() => _openAdminId = null),
          onChanged: () => ref.invalidate(companyProvider),
        );
      }
    }

    final LayoutSize size = Responsive.of(context);
    final List<AdminUser> admins = _filtered(co);

    return SingleChildScrollView(
      padding: Responsive.pagePadding(size),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PageHeader(
            title: 'Admins',
            subtitle:
                '${co.admins.length} team manager for '
                '${CompanyProfile.teamName}, ${CompanyProfile.branch}',
            actions: <Widget>[
              FilledButton.icon(
                onPressed: () => _openForm(company: co),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New Admin'),
              ),
            ],
          ),
          _FilterBar(
            searchController: _search,
            branch: _branch,
            branches: <String>['All branches', ...CompanyProfile.branches],
            status: _status,
            onSearch: () => setState(() {}),
            onBranch: (String b) => setState(() => _branch = b),
            onStatus: (EntityStatus? s) => setState(() => _status = s),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (admins.isEmpty)
            Card(
              child: EmptyState(
                icon: Icons.manage_accounts_outlined,
                title: 'No Admins match these filters',
                message:
                    'Try clearing the branch or status filter, or search by a '
                    'different name.',
                action: OutlinedButton(
                  onPressed: () => setState(() {
                    _search.clear();
                    _branch = 'All branches';
                    _status = null;
                  }),
                  child: const Text('Clear filters'),
                ),
              ),
            )
          else if (size.isCompact)
            Column(
              children: admins
                  .map((AdminUser a) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: _AdminCard(
                          admin: a,
                          onOpen: () => setState(() => _openAdminId = a.id),
                          onEdit: () => _openForm(existing: a, company: co),
                          onToggleStatus: () => _confirmStatusChange(a, co),
                        ),
                      ))
                  .toList(),
            )
          else
            _AdminTable(
              admins: admins,
              onOpen: (AdminUser a) => setState(() => _openAdminId = a.id),
              onEdit: (AdminUser a) => _openForm(existing: a, company: co),
              onToggleStatus: (AdminUser a) => _confirmStatusChange(a, co),
            ),
        ],
      ),
    );
  }
}

// --- Filters ---------------------------------------------------------------

/// One filter row above everything it scopes - never a filter per card.
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.searchController,
    required this.branch,
    required this.branches,
    required this.status,
    required this.onSearch,
    required this.onBranch,
    required this.onStatus,
  });

  final TextEditingController searchController;
  final String branch;
  final List<String> branches;
  final EntityStatus? status;
  final VoidCallback onSearch;
  final ValueChanged<String> onBranch;
  final ValueChanged<EntityStatus?> onStatus;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            SizedBox(
              width: 280,
              height: 38,
              child: TextField(
                controller: searchController,
                onChanged: (_) => onSearch(),
                decoration: InputDecoration(
                  hintText: 'Search name, email or team',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  prefixIconConstraints:
                      const BoxConstraints(minWidth: 36, minHeight: 36),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  suffixIcon: searchController.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, size: 15),
                          onPressed: () {
                            searchController.clear();
                            onSearch();
                          },
                        ),
                ),
              ),
            ),
            _DropdownFilter<String>(
              icon: Icons.apartment_outlined,
              value: branch,
              items: branches,
              labelOf: (String b) => b,
              onChanged: onBranch,
            ),
            _DropdownFilter<EntityStatus?>(
              icon: Icons.toggle_on_outlined,
              value: status,
              items: <EntityStatus?>[null, ...EntityStatus.values],
              labelOf: (EntityStatus? s) => s?.label ?? 'Any status',
              onChanged: onStatus,
            ),
          ],
        ),
      ),
    );
  }
}

class _DropdownFilter<T> extends StatelessWidget {
  const _DropdownFilter({
    required this.icon,
    required this.value,
    required this.items,
    required this.labelOf,
    required this.onChanged,
  });

  final IconData icon;
  final T value;
  final List<T> items;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16, color: VizPalette.inkMuted),
          const SizedBox(width: AppSpacing.sm),
          DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isDense: true,
              style: Theme.of(context).textTheme.labelMedium,
              borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
              items: items
                  .map((T i) => DropdownMenuItem<T>(
                        value: i,
                        child: Text(labelOf(i)),
                      ))
                  .toList(),
              onChanged: (T? v) {
                if (v != null || null is T) onChanged(v as T);
              },
            ),
          ),
        ],
      ),
    );
  }
}

// --- Table -----------------------------------------------------------------

class _AdminTable extends StatelessWidget {
  const _AdminTable({
    required this.admins,
    required this.onOpen,
    required this.onEdit,
    required this.onToggleStatus,
  });

  final List<AdminUser> admins;
  final ValueChanged<AdminUser> onOpen;
  final ValueChanged<AdminUser> onEdit;
  final ValueChanged<AdminUser> onToggleStatus;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 980),
          child: DataTable(
            showCheckboxColumn: false,
            columns: const <DataColumn>[
              DataColumn(label: Text('ADMIN')),
              DataColumn(label: Text('TEAM / BRANCH')),
              DataColumn(label: Text('REPS'), numeric: true),
              DataColumn(label: Text('LEADS'), numeric: true),
              DataColumn(label: Text('CONVERSION'), numeric: true),
              DataColumn(label: Text('STATUS')),
              DataColumn(label: Text('')),
            ],
            rows: admins.map((AdminUser a) {
              return DataRow(
                onSelectChanged: (_) => onOpen(a),
                cells: <DataCell>[
                  DataCell(Row(
                    children: <Widget>[
                      InitialsAvatar(
                        name: a.name,
                        entityIndex: 0,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(a.name, style: theme.textTheme.bodyMedium),
                          Text(a.email, style: theme.textTheme.labelSmall),
                        ],
                      ),
                    ],
                  )),
                  DataCell(Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(a.teamName, style: theme.textTheme.bodyMedium),
                      Text(a.branch, style: theme.textTheme.labelSmall),
                    ],
                  )),
                  DataCell(Text(
                    '${a.activeRepCount}/${a.repCount}',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontFeatures: kTabularFigures),
                  )),
                  DataCell(Text(
                    Fmt.count(a.leadsOwned),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontFeatures: kTabularFigures),
                  )),
                  DataCell(Text(
                    Fmt.percent(a.conversionRate),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontFeatures: kTabularFigures),
                  )),
                  DataCell(StatusChip(
                    label: a.status.label,
                    color: a.status.color,
                    icon: a.status.icon,
                    dense: true,
                  )),
                  DataCell(_RowActions(
                    onEdit: () => onEdit(a),
                    onToggleStatus: () => onToggleStatus(a),
                    isActive: a.status == EntityStatus.active,
                  )),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _RowActions extends StatelessWidget {
  const _RowActions({
    required this.onEdit,
    required this.onToggleStatus,
    required this.isActive,
  });

  final VoidCallback onEdit;
  final VoidCallback onToggleStatus;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Actions',
      icon: const Icon(Icons.more_horiz, size: 18),
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      onSelected: (String v) {
        if (v == 'edit') onEdit();
        if (v == 'status') onToggleStatus();
      },
      itemBuilder: (_) => <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(value: 'edit', child: Text('Edit details')),
        PopupMenuItem<String>(
          value: 'status',
          child: Text(isActive ? 'Deactivate' : 'Reactivate'),
        ),
      ],
    );
  }
}

// --- Compact card (phone) --------------------------------------------------

class _AdminCard extends StatelessWidget {
  const _AdminCard({
    required this.admin,
    required this.onOpen,
    required this.onEdit,
    required this.onToggleStatus,
  });

  final AdminUser admin;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onToggleStatus;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  InitialsAvatar(
                    name: admin.name,
                    entityIndex:
                        0,
                    size: 34,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(admin.name, style: theme.textTheme.titleSmall),
                        Text('${admin.teamName} - ${admin.branch}',
                            style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  StatusChip(
                    label: admin.status.label,
                    color: admin.status.color,
                    icon: admin.status.icon,
                    dense: true,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: <Widget>[
                  _MiniStat(
                    label: 'Reps',
                    value: '${admin.activeRepCount}/${admin.repCount}',
                  ),
                  _MiniStat(
                    label: 'Leads',
                    value: Fmt.count(admin.leadsOwned),
                  ),
                  _MiniStat(
                    label: 'Conversion',
                    value: Fmt.percent(admin.conversionRate),
                  ),
                  _MiniStat(
                    label: 'Conversion',
                    value: Fmt.percent(admin.conversionRate),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(onPressed: onEdit, child: const Text('Edit')),
                  TextButton(
                    onPressed: onToggleStatus,
                    child: Text(
                      admin.status == EntityStatus.active
                          ? 'Deactivate'
                          : 'Reactivate',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall
                ?.copyWith(color: VizPalette.inkMuted),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontFeatures: kTabularFigures),
          ),
        ],
      ),
    );
  }
}
