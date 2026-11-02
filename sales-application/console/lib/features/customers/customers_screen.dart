import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/company_profile.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../data/models/customer.dart';
import '../../data/models/delivery.dart';
import '../../data/models/lead.dart';
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
import '../../widgets/download.dart';
import '../../data/api/api_client.dart';
import 'payment_dialogs.dart';
import '../deliveries/schedule_dialog.dart';
import '../shell/console_shell.dart' show NavSection, openSection;

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

  void _say(String message, {bool bad = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: bad ? VizPalette.statusCritical : null,
      ),
    );
  }

  Future<void> _setPrice(Customer c) async {
    final double? price = await askForPrice(
      context,
      customerName: c.displayName,
      current: c.price,
      paid: c.amountPaid,
    );
    if (price == null) return;
    try {
      await ref.read(companyRepositoryProvider).setCustomerPrice(c.id, price);
    } on ApiException catch (e) {
      _say('Could not save the price: ${e.message}', bad: true);
      return;
    }
    ref.invalidate(companyProvider);
    _say('${c.displayName}: price set to ${Fmt.money(price)}');
  }

  Future<void> _recordPayment(Customer c) async {
    final Map<String, dynamic>? body = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => RecordPaymentDialog(
        customerName: c.displayName,
        balance: c.balance ?? 0,
      ),
    );
    if (body == null) return;
    try {
      await ref.read(companyRepositoryProvider).recordPayment(c.id, body);
    } on ApiException catch (e) {
      _say('Could not record the payment: ${e.message}', bad: true);
      return;
    }
    ref.invalidate(companyProvider);
    _say(
      '${Fmt.money(double.parse(body['amount'] as String))} recorded '
      'for ${c.displayName}',
    );
  }

  Future<void> _complete(Customer c) async {
    try {
      await ref.read(companyRepositoryProvider).completeProject(c.id);
    } on ApiException catch (e) {
      // The server says what's missing: the handover, or money still due.
      _say(e.message, bad: true);
      return;
    }
    ref.invalidate(companyProvider);
    _say('${c.displayName}: project completed');
  }

  Future<void> _downloadReceipt(Customer c) async {
    try {
      final (List<int> bytes, String name) = await ref
          .read(companyRepositoryProvider)
          .receiptPdf(c.id);
      saveBytes(Uint8List.fromList(bytes), name, mime: 'application/pdf');
    } on ApiException catch (e) {
      _say(e.message, bad: true);
    }
  }

  void _openLead(String leadId) {
    ref.read(leadFocusProvider.notifier).state = leadId;
    openSection.value = NavSection.leads;
  }

  Widget _build(BuildContext context, CompanySnapshot co) {
    // A converted lead's "Open customer" lands here (#37).
    final String? focus = ref.watch(customerFocusProvider);
    if (focus != null) {
      _search.clear();
      _repId = null;
      _delivery = null;
      _support = null;
      _activeOnly = false;
      _expandedId = focus;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(customerFocusProvider.notifier).state = null;
      });
    }
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
          DataBlock(
            children: <Widget>[
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
                  onDelivery: (DeliveryStatus? s) =>
                      setState(() => _delivery = s),
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
                    onOpenLead: _openLead,
                    onSetPrice: _setPrice,
                    onRecordPayment: _recordPayment,
                    onDownloadReceipt: _downloadReceipt,
                    onComplete: _complete,
                    onSchedule: (Customer c) =>
                        scheduleMilestone(context, ref, co, customerId: c.id),
                  ),
                ),
            ],
          ),
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

// Column proportions, not pixels. Each is an Expanded flex, so the row
// fills whatever width the table is given and every column grows by the
// same factor. As fixed widths the data crowded into the left of a wide
// screen and the rest of every row stood empty. The sum still sets the
// minimum width, below which the table scrolls rather than squeezing.
const List<double> _cols = <double>[250, 130, 200, 100, 190, 130, 130, 110];
const double _minTableWidth = 1240;

class _CustomerTable extends StatelessWidget {
  const _CustomerTable({
    required this.customers,
    required this.co,
    required this.expandedId,
    required this.onToggle,
    required this.onOpenLead,
    required this.onSetPrice,
    required this.onRecordPayment,
    required this.onDownloadReceipt,
    required this.onComplete,
    required this.onSchedule,
  });

  final List<Customer> customers;
  final CompanySnapshot co;
  final String? expandedId;
  final ValueChanged<Customer> onToggle;
  final ValueChanged<String> onOpenLead;
  final ValueChanged<Customer> onSetPrice;
  final ValueChanged<Customer> onRecordPayment;
  final ValueChanged<Customer> onDownloadReceipt;
  final ValueChanged<Customer> onComplete;
  final ValueChanged<Customer> onSchedule;

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
                          child: Text('Customer', style: head),
                        ),
                        Expanded(
                          flex: _cols[1].round(),
                          child: Text('Rep', style: head),
                        ),
                        Expanded(
                          flex: _cols[2].round(),
                          child: Text('Products', style: head),
                        ),
                        Expanded(
                          flex: _cols[3].round(),
                          child: Text('Since', style: head),
                        ),
                        Expanded(
                          flex: _cols[4].round(),
                          child: Text('Project', style: head),
                        ),
                        Expanded(
                          flex: _cols[5].round(),
                          child: Text('Last milestone', style: head),
                        ),
                        Expanded(
                          flex: _cols[6].round(),
                          child: Text('Support', style: head),
                        ),
                        Expanded(
                          flex: _cols[7].round(),
                          child: Text(
                            'Balance',
                            style: head,
                            textAlign: TextAlign.right,
                          ),
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
                      _CustomerDetail(
                        customer: c,
                        co: co,
                        onOpenLead: onOpenLead,
                        onSetPrice: () => onSetPrice(c),
                        onRecordPayment: () => onRecordPayment(c),
                        onDownloadReceipt: () => onDownloadReceipt(c),
                        onComplete: () => onComplete(c),
                        onSchedule: () => onSchedule(c),
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
            Expanded(
              flex: _cols[0].round(),
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
            Expanded(
              flex: _cols[1].round(),
              child: Text(
                customer.repName,
                overflow: TextOverflow.ellipsis,
                style: muted,
              ),
            ),
            Expanded(
              flex: _cols[2].round(),
              child: Padding(
                padding: const EdgeInsets.only(right: AppSpacing.md),
                child: Text(
                  customer.products.isEmpty
                      ? '-'
                      : customer.products.join(', '),
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
            Expanded(
              flex: _cols[3].round(),
              child: Text(Fmt.dateShort(customer.customerSince), style: muted),
            ),
            Expanded(
              flex: _cols[4].round(),
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
                      color:
                          customer.projectStatus == 'live' ||
                              customer.projectStatus == 'completed'
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
            Expanded(
              flex: _cols[5].round(),
              child: Align(
                alignment: Alignment.centerLeft,
                child: customer.deliveryStatus == null
                    ? Text('-', style: muted)
                    : DeliveryStatusChip(
                        status: DeliveryStatus.fromWire(
                          customer.deliveryStatus,
                        ),
                        dense: true,
                      ),
              ),
            ),
            Expanded(
              flex: _cols[6].round(),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SupportStatusChip(status: customer.supportStatus),
              ),
            ),
            // Who still owes money, at a glance (#42).
            Expanded(
              flex: _cols[7].round(),
              child: Text(
                _balanceLabel(customer),
                textAlign: TextAlign.right,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontFeatures: kTabularFigures,
                  color: _balanceColor(customer),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _balanceLabel(Customer c) {
  final double? b = c.balance;
  if (b == null) return 'No price';
  if (b < 0) return 'Over ${Fmt.moneyCompact(-b)}';
  if (b == 0) return 'Paid';
  return '${Fmt.moneyCompact(b)} due';
}

Color? _balanceColor(Customer c) {
  final double? b = c.balance;
  if (b == null) return VizPalette.inkMuted;
  if (b < 0) return VizPalette.statusCritical;
  if (b == 0) return VizPalette.statusGood;
  return null;
}

/// The expanded row: everything the phone has recorded about this customer
/// - contact and notes, the project, every visit with its photo, the
/// follow-ups, and the handover milestones.
class _CustomerDetail extends StatelessWidget {
  const _CustomerDetail({
    required this.customer,
    required this.co,
    required this.onOpenLead,
    required this.onSetPrice,
    required this.onRecordPayment,
    required this.onDownloadReceipt,
    required this.onComplete,
    required this.onSchedule,
  });

  final Customer customer;
  final CompanySnapshot co;
  final ValueChanged<String> onOpenLead;
  final VoidCallback onSetPrice;
  final VoidCallback onRecordPayment;
  final VoidCallback onDownloadReceipt;
  final VoidCallback onComplete;
  final VoidCallback onSchedule;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Customer c = customer;
    String dash(String v) => v.isEmpty ? '-' : v;
    // The leads that became this customer - more than one for a returning
    // client's next project (#37).
    final List<Lead> cameFrom =
        co.leads.where((Lead l) => l.customerId == c.id).toList()
          ..sort((Lead a, Lead b) => a.createdAt.compareTo(b.createdAt));

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
                      <String>[
                        c.address,
                        c.city,
                      ].where((String x) => x.isNotEmpty).join(', '),
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
                    CompanyProfile.labelOf(
                      CompanyProfile.hostingLabels,
                      c.hosting,
                    ),
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
              KeyValueBlock(
                title: 'Money',
                warn: (c.balance ?? 0) < 0,
                rows: <(String, String)>[
                  (
                    'Price',
                    c.price == null ? 'Not agreed yet' : Fmt.money(c.price!),
                  ),
                  ('Paid', Fmt.money(c.amountPaid)),
                  (
                    'Balance',
                    c.balance == null
                        ? '-'
                        : c.balance! < 0
                        ? 'Paid ${Fmt.money(-c.balance!)} more than the price'
                        : c.balance == 0
                        ? 'Paid in full'
                        : '${Fmt.money(c.balance!)} due',
                  ),
                ],
              ),
              KeyValueBlock(
                title: 'Payments (${c.payments.length})',
                width: 300,
                rows: c.payments.isEmpty
                    ? const <(String, String)>[('', 'None recorded yet')]
                    : <(String, String)>[
                        for (final CustomerPayment p in c.payments)
                          (
                            Fmt.dateShort(p.receivedOn),
                            '${Fmt.money(p.amount)} - '
                                '${paymentMethodLabels[p.method] ?? p.method}'
                                '${p.reference.isEmpty ? '' : ' (${p.reference})'}',
                          ),
                      ],
              ),
              KeyValueBlock(
                title: 'Came from',
                rows: cameFrom.isEmpty
                    ? const <(String, String)>[('Lead', 'Added as a customer')]
                    : <(String, String)>[
                        for (final Lead l in cameFrom)
                          (
                            l.convertedAt == null
                                ? 'Lead'
                                : Fmt.dateShort(l.convertedAt!),
                            '${l.companyName}'
                                '${l.value > 0 ? ' - ${Fmt.money(l.value)}' : ''}',
                          ),
                      ],
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                // Money first: what the admin most often opens this for.
                IntrinsicWidth(
                  child: PillButton(
                    label: c.price == null ? 'Set price' : 'Change price',
                    filled: false,
                    onTap: onSetPrice,
                  ),
                ),
                if ((c.balance ?? 0) > 0)
                  IntrinsicWidth(
                    child: PillButton(
                      label: 'Record payment',
                      filled: false,
                      onTap: onRecordPayment,
                    ),
                  ),
                IntrinsicWidth(
                  child: PillButton(
                    label: 'Schedule milestone',
                    filled: false,
                    onTap: onSchedule,
                  ),
                ),
                // Live is as far as milestones go; Completed is marked here
                // once handed over and paid (#43).
                if (c.projectStatus == 'live')
                  IntrinsicWidth(
                    child: PillButton(
                      label: 'Mark completed',
                      filled: false,
                      onTap: onComplete,
                    ),
                  ),
                if (c.balance == 0 && c.price != null && c.price! > 0)
                  IntrinsicWidth(
                    child: PillButton(
                      label: 'Download receipt',
                      filled: false,
                      onTap: onDownloadReceipt,
                    ),
                  ),
                // IntrinsicWidth: a pill fills the loose width a Wrap
                // hands it otherwise.
                for (final Lead l in cameFrom)
                  IntrinsicWidth(
                    child: PillButton(
                      label: cameFrom.length == 1
                          ? 'Open the lead'
                          : 'Open lead: ${l.companyName}',
                      filled: false,
                      onTap: () => onOpenLead(l.id),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
