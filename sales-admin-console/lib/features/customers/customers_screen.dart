import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/company_profile.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../data/models/customer.dart';
import '../../data/models/delivery.dart';
import '../../data/models/people.dart';
import '../../data/providers.dart';
import '../../data/repositories/company_repository.dart';
import '../../widgets/async_gate.dart';
import '../../widgets/table_panel.dart';
import '../../widgets/motion.dart';
import '../../widgets/primitives.dart';
import '../dashboard/dashboard_panels.dart';
import '../deliveries/delivery_chips.dart';
import '../../widgets/activity_blocks.dart';

/// Everyone who has bought: who looks after them, what they bought, whether
/// it has arrived, and whether anything is open with support.
class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  final TextEditingController _search = TextEditingController();

  String? _repId;
  DeliveryStatus? _delivery;
  SupportStatus? _support;
  bool _activeOnly = true;
  String? _expandedId;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Customer> _filtered(CompanySnapshot co) {
    final String q = _search.text.trim().toLowerCase();
    final List<Customer> out = co.customers.where((Customer c) {
      if (_activeOnly && !c.isActive) return false;
      if (_repId != null && c.repId != _repId) return false;
      if (_delivery != null && c.deliveryStatus != _delivery!.wire) {
        return false;
      }
      if (_support != null && c.supportStatus != _support) return false;
      if (q.isEmpty) return true;
      return c.displayName.toLowerCase().contains(q) ||
          c.name.toLowerCase().contains(q) ||
          c.phone.contains(q) ||
          c.products.any((String p) => p.toLowerCase().contains(q));
    }).toList();
    out.sort(
      (Customer a, Customer b) => b.customerSince.compareTo(a.customerSince),
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
    final List<Customer> customers = _filtered(co);
    final int openSupport = co.customers
        .where((Customer c) => c.supportStatus == SupportStatus.open)
        .length;

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
            title: 'Customers',
            subtitle: Text(
              '${co.customers.where((Customer c) => c.isActive).length} active'
              '${openSupport > 0 ? ' - $openSupport with a support issue open' : ''}',
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          DataBlock(children: <Widget>[
          Reveal(
            index: 1,
            child: _CustomerFilters(
              controller: _search,
              reps: co.activeReps,
              repId: _repId,
              delivery: _delivery,
              support: _support,
              activeOnly: _activeOnly,
              onSearch: () => setState(() {}),
              onRep: (String? id) => setState(() => _repId = id),
              onDelivery: (DeliveryStatus? s) => setState(() => _delivery = s),
              onSupport: (SupportStatus? s) => setState(() => _support = s),
              onActiveOnly: (bool v) => setState(() => _activeOnly = v),
            ),
          ),
          if (customers.isEmpty)
            Panel(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: EmptyState(
                icon: Icons.storefront_outlined,
                title: 'No customers match these filters',
                message: 'Customers appear here once a lead converts.',
              ),
            )
          else
            Reveal(
              index: 2,
              child: _CustomerTable(
                customers: customers,
                co: co,
                expandedId: _expandedId,
                onToggle: (Customer c) => setState(
                  () => _expandedId = _expandedId == c.id ? null : c.id,
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

class _CustomerFilters extends StatelessWidget {
  const _CustomerFilters({
    required this.controller,
    required this.reps,
    required this.repId,
    required this.delivery,
    required this.support,
    required this.activeOnly,
    required this.onSearch,
    required this.onRep,
    required this.onDelivery,
    required this.onSupport,
    required this.onActiveOnly,
  });

  final TextEditingController controller;
  final List<SalesRep> reps;
  final String? repId;
  final DeliveryStatus? delivery;
  final SupportStatus? support;
  final bool activeOnly;
  final VoidCallback onSearch;
  final ValueChanged<String?> onRep;
  final ValueChanged<DeliveryStatus?> onDelivery;
  final ValueChanged<SupportStatus?> onSupport;
  final ValueChanged<bool> onActiveOnly;

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
                      hintText: 'Search customer, phone or product',
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
          PillDropdown<DeliveryStatus?>(
            value: delivery,
            items: <DeliveryStatus?>[null, ...DeliveryStatus.values],
            labelOf: (DeliveryStatus? s) => s?.label ?? 'Any milestone status',
            onChanged: onDelivery,
          ),
          PillDropdown<SupportStatus?>(
            value: support,
            items: <SupportStatus?>[null, ...SupportStatus.values],
            labelOf: (SupportStatus? s) => s?.label ?? 'Any support status',
            onChanged: onSupport,
          ),
          PillDropdown<bool>(
            value: activeOnly,
            items: const <bool>[true, false],
            labelOf: (bool v) => v ? 'Active only' : 'Include inactive',
            onChanged: onActiveOnly,
          ),
        ],
      ),
    );
  }
}

const List<double> _cols = <double>[250, 130, 200, 100, 190, 130, 130];
const double _minTableWidth = 1130;

class _CustomerTable extends StatelessWidget {
  const _CustomerTable({
    required this.customers,
    required this.co,
    required this.expandedId,
    required this.onToggle,
  });

  final List<Customer> customers;
  final CompanySnapshot co;
  final String? expandedId;
  final ValueChanged<Customer> onToggle;

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
                          child: Text('Customer', style: head),
                        ),
                        SizedBox(
                          width: _cols[1],
                          child: Text('Rep', style: head),
                        ),
                        SizedBox(
                          width: _cols[2],
                          child: Text('Products', style: head),
                        ),
                        SizedBox(
                          width: _cols[3],
                          child: Text('Since', style: head),
                        ),
                        SizedBox(
                          width: _cols[4],
                          child: Text('Project', style: head),
                        ),
                        SizedBox(
                          width: _cols[5],
                          child: Text('Last milestone', style: head),
                        ),
                        SizedBox(
                          width: _cols[6],
                          child: Text('Support', style: head),
                        ),
                      ],
                    ),
                  ),
                  for (final Customer c in customers) ...<Widget>[
                    _CustomerRow(
                      customer: c,
                      expanded: expandedId == c.id,
                      onTap: () => onToggle(c),
                    ),
                    if (expandedId == c.id)
                      _CustomerDetail(customer: c, co: co),
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

class _CustomerRow extends StatelessWidget {
  const _CustomerRow({
    required this.customer,
    required this.expanded,
    required this.onTap,
  });

  final Customer customer;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle? muted = theme.textTheme.labelSmall?.copyWith(
      color: VizPalette.inkMuted,
    );

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
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          customer.displayName,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: customer.isActive
                                ? null
                                : VizPalette.inkMuted,
                          ),
                        ),
                        Text(
                          '${customer.name} - ${customer.phone}'
                          '${customer.city.isEmpty ? '' : ' - ${customer.city}'}',
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
                customer.repName,
                overflow: TextOverflow.ellipsis,
                style: muted,
              ),
            ),
            SizedBox(
              width: _cols[2],
              child: Padding(
                padding: const EdgeInsets.only(right: AppSpacing.md),
                child: Text(
                  customer.products.isEmpty ? '-' : customer.products.join(', '),
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
            SizedBox(
              width: _cols[3],
              child: Text(Fmt.dateShort(customer.customerSince), style: muted),
            ),
            SizedBox(
              width: _cols[4],
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    CompanyProfile.labelOf(
                      CompanyProfile.projectStatusLabels,
                      customer.projectStatus,
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: customer.projectStatus == 'live'
                          ? VizPalette.statusGood
                          : null,
                    ),
                  ),
                  Text(
                    customer.goLiveOn != null
                        ? 'Live ${Fmt.dateShort(customer.goLiveOn!)}'
                        : customer.onMaintenance
                        ? '${customer.maintenancePlan} maintenance'
                        : (customer.domain.isEmpty ? '-' : customer.domain),
                    overflow: TextOverflow.ellipsis,
                    style: muted,
                  ),
                ],
              ),
            ),
            SizedBox(
              width: _cols[5],
              child: Align(
                alignment: Alignment.centerLeft,
                child: customer.deliveryStatus == null
                    ? Text('-', style: muted)
                    : DeliveryStatusChip(
                        status: DeliveryStatus.fromWire(customer.deliveryStatus),
                        dense: true,
                      ),
              ),
            ),
            SizedBox(
              width: _cols[6],
              child: Align(
                alignment: Alignment.centerLeft,
                child: SupportStatusChip(status: customer.supportStatus),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The expanded row: everything the phone has recorded about this customer
/// - contact and notes, the project, every visit with its photo, the
/// follow-ups, and the handover milestones.
class _CustomerDetail extends StatelessWidget {
  const _CustomerDetail({required this.customer, required this.co});

  final Customer customer;
  final CompanySnapshot co;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Customer c = customer;
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
      child: Wrap(
        spacing: AppSpacing.xl,
        runSpacing: AppSpacing.lg,
        crossAxisAlignment: WrapCrossAlignment.start,
        children: <Widget>[
          KeyValueBlock(
            title: 'Contact',
            rows: <(String, String)>[
              ('Company', dash(c.companyName)),
              ('Contact', c.name),
              ('Phone', c.phone),
              ('Email', dash(c.email)),
              (
                'Address',
                dash(
                  <String>[c.address, c.city]
                      .where((String x) => x.isNotEmpty)
                      .join(', '),
                ),
              ),
              ('Rep', c.repName),
              ('Customer since', Fmt.date(c.customerSince)),
              ('Support', c.supportStatus.label),
              ('Notes', dash(c.notes)),
            ],
          ),
          KeyValueBlock(
            title: 'Project',
            rows: <(String, String)>[
              (
                'Status',
                CompanyProfile.labelOf(
                  CompanyProfile.projectStatusLabels,
                  c.projectStatus,
                ),
              ),
              (
                'Go-live',
                c.goLiveOn == null ? 'Not yet' : Fmt.date(c.goLiveOn!),
              ),
              ('Domain', dash(c.domain)),
              (
                'Hosting',
                CompanyProfile.labelOf(CompanyProfile.hostingLabels, c.hosting),
              ),
              (
                'Maintenance',
                CompanyProfile.labelOf(
                  CompanyProfile.maintenanceLabels,
                  c.maintenancePlan,
                ),
              ),
              (
                'Renews',
                c.maintenanceRenewsOn == null
                    ? '-'
                    : Fmt.date(c.maintenanceRenewsOn!),
              ),
              ('Bought', c.products.isEmpty ? '-' : c.products.join(', ')),
            ],
          ),
          VisitsBlock(visits: co.visitsForCustomer(c.id)),
          FollowUpsBlock(followUps: co.followUpsForCustomer(c.id)),
          HandoversBlock(deliveries: co.deliveriesForCustomer(c.id)),
        ],
      ),
    );
  }
}
