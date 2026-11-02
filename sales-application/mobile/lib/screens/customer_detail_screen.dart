import 'package:flutter/material.dart';

import '../api.dart';
import '../pipeline_labels.dart';
import '../theme.dart';
import '../widgets/chips.dart';
import '../widgets/form_sheet.dart';
import '../widgets/motion.dart';
import '../widgets/activity_cards.dart';
import 'delivery_detail_screen.dart';
import 'followup_sheet.dart';
import 'visit_sheet.dart';
import 'delivery_sheets.dart';
import 'payment_sheet.dart';

/// One customer: contact, what they bought, support, and their deliveries.
class CustomerDetailScreen extends StatefulWidget {
  const CustomerDetailScreen({super.key, required this.customerId});

  final int customerId;

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  Map<String, dynamic>? _c;
  List<dynamic> _deliveries = const [];
  List<Map<String, dynamic>> _visits = const [];
  List<Map<String, dynamic>> _followUps = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _apply(List<dynamic> results) {
    if (!mounted) return;
    final visits = (results[2] as List).cast<Map<String, dynamic>>();
    final followUps = (results[3] as List).cast<Map<String, dynamic>>();
    setState(() {
      _c = (results[0] as Map).cast<String, dynamic>();
      _deliveries = results[1] as List<dynamic>;
      _visits = visits;
      _followUps = followUps;
    });
  }

  Future<void> _load() async {
    final paths = [
      '/api/crm/customers/${widget.customerId}/',
      '/api/delivery/deliveries/?customer=${widget.customerId}',
      // Only this customer's rows - not every visit, filtered here (#89).
      '/api/visits/?customer=${widget.customerId}',
      '/api/visits/followups/?status=pending&customer=${widget.customerId}',
    ];
    // First open: the last saved copy straight away, then the server (#90).
    if (_c == null) {
      final saved = await Api.instance.cachedAll(paths);
      if (saved != null && mounted) _apply(saved);
    }
    if (!mounted) return;
    setState(() {
      _loading = _c == null;
      _error = null;
    });
    try {
      _apply(await Future.wait(paths.map(Api.instance.get)));
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Cannot reach the server.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshAfter(Future<dynamic> sheet) async {
    if (await sheet != null) _load();
  }

  Future<void> _schedule() async {
    final c = _c!;
    final address = [c['address'], c['city']]
        .where((x) => (x?.toString() ?? '').isNotEmpty)
        .join(', ');
    final result = await showFormSheet(
      context,
      ScheduleDeliverySheet(customerId: widget.customerId, address: address),
    );
    if (result != null) _load();
  }

  Future<void> _openDelivery(Map<String, dynamic> d) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
          builder: (_) => DeliveryDetailScreen(deliveryId: d['id'] as int)),
    );
    if (mounted) _load();
  }

  /// Live, handed over and paid: mark it finished (#43). The server checks
  /// both and says what's missing if it isn't ready.
  Future<void> _complete() async {
    try {
      await Api.instance
          .post('/api/crm/customers/${widget.customerId}/complete/');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Project completed')));
      _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _setSupport(String status) async {
    try {
      await Api.instance.patch(
          '/api/crm/customers/${widget.customerId}/', {'support_status': status});
      _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = _c;

    return Scaffold(
      appBar: AppBar(
        title: Text(c == null
            ? 'Customer'
            : (c['company_name']?.toString().isNotEmpty == true
                ? c['company_name'].toString()
                : c['name'].toString())),
      ),
      floatingActionButton: c == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _schedule,
              icon: const Icon(Icons.flag_outlined),
              label: const Text('Schedule handover'),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
                    children: [
                      Reveal(index: 0, child: _contact(scheme, c!)),
                      const SizedBox(height: 16),
                      Reveal(index: 1, child: _project(scheme, c)),
                      const SizedBox(height: 16),
                      Reveal(index: 1, child: _money(scheme, c)),
                      const SizedBox(height: 16),
                      Reveal(index: 1, child: _support(scheme, c)),
                      const SizedBox(height: 24),
                      Reveal(
                        index: 2,
                        child: FollowUpsCard(
                          followUps: _followUps,
                          onSchedule: () => _refreshAfter(showFormSheet(
                              context,
                              FollowUpSheet(customerId: widget.customerId))),
                          onComplete: (f) => _refreshAfter(showFormSheet(
                              context, CompleteFollowUpSheet(followUp: f))),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Reveal(
                        index: 3,
                        child: VisitsCard(
                          visits: _visits,
                          onLog: () => _refreshAfter(showFormSheet(
                              context,
                              VisitSheet(
                                  customerId: widget.customerId,
                                  targetName: c['name']?.toString() ?? ''))),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Reveal(index: 4, child: _deliveriesSection(scheme)),
                    ],
                  ),
                ),
    );
  }

  Widget _contact(ColorScheme scheme, Map<String, dynamic> c) {
    String s(String k) => c[k]?.toString() ?? '';
    final since = DateTime.tryParse(s('customer_since'));
    final products = (c['product_names'] as List<dynamic>? ?? const []);
    return SurfaceCard(
      radius: AppTheme.radiusXl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s('name'),
              style: AppTheme.sans(16, 600, 22, color: scheme.onSurface)),
          const SizedBox(height: 10),
          _iconRow(scheme, Icons.phone_outlined, s('phone')),
          if (s('email').isNotEmpty) ...[
            const SizedBox(height: 8),
            _iconRow(scheme, Icons.mail_outline, s('email')),
          ],
          if (s('address').isNotEmpty || s('city').isNotEmpty) ...[
            const SizedBox(height: 8),
            _iconRow(scheme, Icons.place_outlined,
                [s('address'), s('city')].where((x) => x.isNotEmpty).join(', ')),
          ],
          if (since != null) ...[
            const SizedBox(height: 8),
            _iconRow(scheme, Icons.verified_outlined,
                'Customer since ${fmtDate(since)}'),
          ],
          if (products.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('PRODUCTS / SERVICES',
                style: AppTheme.labelSm.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final p in products)
                  StatusPill(label: p.toString(), color: AppTheme.blue500),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _patch(Map<String, dynamic> body) async {
    try {
      await Api.instance.patch('/api/crm/customers/${widget.customerId}/', body);
      _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _editText(String title, String key, String current,
      {TextInputType? keyboard}) async {
    final controller = TextEditingController(text: current);
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
            controller: controller, autofocus: true, keyboardType: keyboard),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (value != null) await _patch({key: value});
  }

  /// Where the build stands, and the things that outlive it: the domain,
  /// who hosts it, and whether they pay for maintenance.
  Widget _project(ColorScheme scheme, Map<String, dynamic> c) {
    String s(String k) => c[k] == null ? '' : c[k].toString();
    final status = s('project_status');
    final goLive = DateTime.tryParse(s('go_live_on'));
    final renews = DateTime.tryParse(s('maintenance_renews_on'));
    final (statusLabel, statusColor) = switch (status) {
      'completed' => ('Completed', AppTheme.emerald600),
      'live' => ('Live', AppTheme.emerald500),
      'uat' => ('Client testing', AppTheme.violet500),
      'development' => ('In development', AppTheme.blue500),
      'design' => ('In design', AppTheme.amber500),
      _ => ('Not started', const Color(0xFF8A8A93)),
    };
    Widget row(IconData icon, String text, {VoidCallback? onTap}) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              Icon(icon, size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(text,
                      style: TextStyle(fontSize: 13, color: scheme.onSurface))),
              if (onTap != null)
                Icon(Icons.edit_outlined, size: 14, color: scheme.outline),
            ]),
          ),
        );
    return SurfaceCard(
      radius: AppTheme.radiusXl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
                child: Text('Project',
                    style: AppTheme.sans(15, 600, 20, color: scheme.onSurface))),
            StatusPill(label: statusLabel, color: statusColor),
          ]),
          const SizedBox(height: 10),
          row(Icons.event_available_outlined,
              goLive == null ? 'Go-live: not yet' : 'Went live ${fmtDate(goLive)}'),
          const SizedBox(height: 6),
          row(Icons.language_outlined,
              s('domain').isEmpty ? 'Domain: add' : s('domain'),
              onTap: () => _editText('Domain', 'domain', s('domain'),
                  keyboard: TextInputType.url)),
          const SizedBox(height: 10),
          Text('HOSTING',
              style: AppTheme.labelSm.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            for (final (value, label) in PipelineLabels.hosting)
              ChoiceChip(
                label: Text(label),
                selected: s('hosting') == value,
                onSelected: (_) => _patch({'hosting': value}),
              ),
          ]),
          const SizedBox(height: 10),
          Text('MAINTENANCE',
              style: AppTheme.labelSm.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            for (final (value, label) in PipelineLabels.maintenancePlans)
              ChoiceChip(
                label: Text(label),
                selected: s('maintenance_plan') == value,
                onSelected: (_) => _patch({'maintenance_plan': value}),
              ),
          ]),
          if (s('maintenance_plan').isNotEmpty && s('maintenance_plan') != 'none') ...[
            const SizedBox(height: 8),
            row(Icons.autorenew_outlined,
                renews == null ? 'Renewal date: set' : 'Renews ${fmtDate(renews)}',
                onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: renews ?? DateTime.now().add(const Duration(days: 365)),
                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
              );
              if (picked != null) {
                await _patch({'maintenance_renews_on': apiDate(picked)});
              }
            }),
          ],
          if (status == 'live') ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.task_alt, size: 18),
              label: const Text('Mark project completed'),
              onPressed: _complete,
            ),
          ],
        ],
      ),
    );
  }

  /// The agreed price, what's been paid, and each payment (#41, #42). A rep
  /// records a payment here; the receipt is downloaded from the console.
  Widget _money(ColorScheme scheme, Map<String, dynamic> c) {
    double n(String k) => double.tryParse(c[k]?.toString() ?? '') ?? 0;
    final hasPrice = c['price'] != null;
    final balance = n('balance');
    final payments = (c['payments'] as List?) ?? const [];
    String rs(dynamic v) => '₹${PipelineLabels.money(v)}';
    Widget line(String k, String v, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(
                child: Text(k,
                    style: TextStyle(
                        fontSize: 13, color: scheme.onSurfaceVariant))),
            Text(v,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: color ?? scheme.onSurface)),
          ]),
        );
    return SurfaceCard(
      radius: AppTheme.radiusXl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Money', style: AppTheme.sans(15, 600, 20, color: scheme.onSurface)),
          const SizedBox(height: 10),
          line('Agreed price', hasPrice ? rs(c['price']) : 'Not agreed yet'),
          line('Paid', rs(c['amount_paid'])),
          if (hasPrice)
            line(
              'Balance',
              balance < 0
                  ? 'Paid ${rs(-balance)} more than the price'
                  : balance == 0
                      ? 'Paid in full'
                      : '${rs(balance)} due',
              color: balance < 0
                  ? scheme.error
                  : balance == 0
                      ? AppTheme.emerald600
                      : null,
            ),
          if (payments.isNotEmpty) ...[
            const Divider(height: 20),
            for (final p in payments)
              if (p is Map)
                line(
                  '${fmtDate(DateTime.tryParse(p['received_on']?.toString() ?? '') ?? DateTime.now())}'
                  ' - ${PipelineLabels.label(paymentMethods, p['method']?.toString())}',
                  rs(p['amount']),
                ),
          ],
          if (hasPrice && balance > 0) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.payments_outlined, size: 18),
              label: const Text('Record a payment'),
              onPressed: () => _refreshAfter(showFormSheet(
                  context,
                  RecordPaymentSheet(
                      customerId: widget.customerId, balance: balance))),
            ),
          ],
          if (!hasPrice) ...[
            const SizedBox(height: 8),
            Text('Ask an admin to set the agreed price in the console.',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }

  Widget _support(ColorScheme scheme, Map<String, dynamic> c) {
    final current = c['support_status']?.toString() ?? 'none';
    return SurfaceCard(
      radius: AppTheme.radiusXl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Support status',
              style: AppTheme.sans(15, 600, 20, color: scheme.onSurface)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              for (final (value, label) in const [
                ('none', 'No issues'),
                ('open', 'Issue open'),
                ('resolved', 'Resolved'),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: current == value,
                  onSelected: (_) => _setSupport(value),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _deliveriesSection(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Handover milestones',
            style: AppTheme.headlineMd.copyWith(color: scheme.tertiary)),
        const SizedBox(height: 12),
        if (_deliveries.isEmpty)
          SurfaceCard(
            child: Text('Nothing scheduled yet.',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
          )
        else
          for (final d in _deliveries) ...[
            _deliveryCard(scheme, (d as Map).cast<String, dynamic>()),
            const SizedBox(height: 12),
          ],
      ],
    );
  }

  Widget _deliveryCard(ColorScheme scheme, Map<String, dynamic> d) {
    final (label, color) = Statuses.delivery(d['status']?.toString());
    final on = DateTime.tryParse(d['scheduled_on']?.toString() ?? '');
    final overdue = d['is_overdue'] == true;
    final attempts = (d['attempt_count'] as num?)?.toInt() ?? 0;
    final last = d['last_attempt'] as Map?;
    return SurfaceCard(
      onTap: () => _openDelivery(d),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    '${PipelineLabels.label(PipelineLabels.milestones, d['milestone']?.toString())}'
                    ' · ${d['product_name'] ?? ''}',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface)),
                const SizedBox(height: 4),
                Text(
                  on == null ? '' : '${overdue ? 'Was due' : 'Due'} ${fmtDate(on)}',
                  style: TextStyle(
                      fontSize: 12,
                      color: overdue ? scheme.error : scheme.onSurfaceVariant),
                ),
                if (last != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '$attempts attempt${attempts == 1 ? '' : 's'} - '
                    '${PipelineLabels.label(PipelineLabels.blockedReasons, last['reason']?.toString())}',
                    style: TextStyle(fontSize: 12, color: scheme.error),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          StatusPill(label: label, color: color),
        ],
      ),
    );
  }

  Widget _iconRow(ColorScheme scheme, IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 14, color: scheme.onSurface)),
        ),
      ],
    );
  }
}
