import 'package:flutter/material.dart';

import '../api.dart';
import '../pipeline_labels.dart';
import '../theme.dart';
import '../widgets/chips.dart';
import '../widgets/form_sheet.dart';
import '../widgets/motion.dart';
import 'delivery_sheets.dart';

/// One delivery, and the two ways it ends. The two big buttons at the top
/// are the whole point of the screen; everything below is the record.
class DeliveryDetailScreen extends StatefulWidget {
  const DeliveryDetailScreen({super.key, required this.deliveryId});

  final int deliveryId;

  @override
  State<DeliveryDetailScreen> createState() => _DeliveryDetailScreenState();
}

class _DeliveryDetailScreenState extends State<DeliveryDetailScreen> {
  Map<String, dynamic>? _d;
  List<dynamic> _attempts = const [];
  bool _loading = true;
  bool _changed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _apply(List<dynamic> results) {
    if (!mounted) return;
    setState(() {
      _d = (results[0] as Map).cast<String, dynamic>();
      _attempts = results[1] as List<dynamic>;
    });
  }

  Future<void> _load() async {
    final paths = [
      '/api/delivery/deliveries/${widget.deliveryId}/',
      '/api/delivery/deliveries/${widget.deliveryId}/attempts/',
    ];
    // First open: the last saved copy straight away, then the server (#90).
    if (_d == null) {
      final saved = await Api.instance.cachedAll(paths);
      if (saved != null) _apply(saved);
    }
    if (!mounted) return;
    setState(() {
      _loading = _d == null;
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

  Future<void> _after(Future<dynamic> sheet) async {
    final result = await sheet;
    if (result != null) {
      _changed = true;
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final d = _d;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(_changed),
        ),
        title: Text(d?['product_name']?.toString() ?? 'Milestone'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                    children: [
                      Reveal(index: 0, child: _header(scheme, d!)),
                      const SizedBox(height: 16),
                      Reveal(index: 1, child: _actions(scheme, d)),
                      const SizedBox(height: 24),
                      Reveal(index: 2, child: _details(scheme, d)),
                      if (d['status'] == 'delivered') ...[
                        const SizedBox(height: 16),
                        Reveal(index: 3, child: _delivered(scheme, d)),
                      ],
                      if (_attempts.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Reveal(index: 4, child: _attemptsCard(scheme)),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _header(ColorScheme scheme, Map<String, dynamic> d) {
    final (label, color) = Statuses.delivery(d['status']?.toString());
    final on = DateTime.tryParse(d['scheduled_on']?.toString() ?? '');
    final overdue = d['is_overdue'] == true;
    return Row(
      children: [
        StatusPill(label: label, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            on == null
                ? ''
                : '${overdue ? 'Was due' : 'Scheduled'} ${fmtDate(on)}',
            style: TextStyle(
              fontSize: 13,
              color: overdue ? scheme.error : scheme.onSurfaceVariant,
              fontWeight: overdue ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }

  Widget _actions(ColorScheme scheme, Map<String, dynamic> d) {
    final status = d['status']?.toString() ?? '';
    if (status == 'delivered' || status == 'cancelled') {
      return SurfaceCard(
        color: scheme.surfaceContainerHigh,
        child: Text(
          status == 'delivered'
              ? 'Done. Nothing more to do.'
              : (d['outcome_notes']?.toString() ?? '').isEmpty
                  ? 'This milestone was cancelled.'
                  : 'This milestone was cancelled: ${d['outcome_notes']}',
          style: AppTheme.bodyMd.copyWith(color: scheme.onSurfaceVariant),
        ),
      );
    }
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: AppTheme.emerald500,
                foregroundColor: Colors.white),
            icon: const Icon(Icons.check_circle_outline, size: 20),
            label: const Text('Done'),
            onPressed: () => _after(showFormSheet(
                context, DeliveredSheet(deliveryId: widget.deliveryId))),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
                foregroundColor: scheme.error,
                side: BorderSide(color: scheme.error.withValues(alpha: 0.5))),
            icon: const Icon(Icons.error_outline, size: 20),
            label: const Text('Blocked'),
            onPressed: () => _after(showFormSheet(
                context, NotDeliveredSheet(deliveryId: widget.deliveryId))),
          ),
        ),
      ],
    );
  }

  Widget _details(ColorScheme scheme, Map<String, dynamic> d) {
    String s(String k) => d[k]?.toString() ?? '';
    return _card(scheme, title: 'Milestone', children: [
      _kv(scheme, 'Step',
          PipelineLabels.label(PipelineLabels.milestones, s('milestone'))),
      _kv(scheme, 'Customer', s('customer_name')),
      _kv(scheme, 'Project', s('product_name')),
      _kv(scheme, 'Where', s('address').isEmpty ? '-' : s('address')),
      _kv(scheme, 'Client sign-off',
          d['required'] == false ? 'Not needed' : 'Needed'),
      _kv(scheme, 'Owner', s('assigned_to_name')),
      if (s('notes').isNotEmpty) _kv(scheme, 'Notes', s('notes')),
    ]);
  }

  Widget _delivered(ColorScheme scheme, Map<String, dynamic> d) {
    final at = DateTime.tryParse(d['delivered_at']?.toString() ?? '');
    final proof = d['proof']?.toString();
    return _card(scheme, title: 'Done', children: [
      _kv(scheme, 'Done on', at == null ? '-' : fmtDate(at)),
      _kv(scheme, 'Signed off by',
          (d['received_by']?.toString() ?? '').isEmpty
              ? '-'
              : d['received_by'].toString()),
      // Written when it was delivered; the scheduling notes stay above (#45).
      if ((d['outcome_notes']?.toString() ?? '').isNotEmpty)
        _kv(scheme, 'Notes when done', d['outcome_notes'].toString()),
      if (proof != null && proof.isNotEmpty) ...[
        Text('PROOF',
            style: AppTheme.labelSm.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radius),
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: Image.network(proof, fit: BoxFit.cover,
                errorBuilder: (_, _, _) => ColoredBox(
                      color: scheme.surfaceContainerHigh,
                      child: Center(
                          child: Icon(Icons.broken_image_outlined,
                              color: scheme.onSurfaceVariant)),
                    )),
          ),
        ),
      ],
    ]);
  }

  Widget _attemptsCard(ColorScheme scheme) {
    return _card(
      scheme,
      title: 'Blocked (${_attempts.length})',
      children: [
        for (final a in _attempts) ...[
          _attempt(scheme, (a as Map).cast<String, dynamic>()),
          if (a != _attempts.last) const Divider(height: 20),
        ],
      ],
    );
  }

  Widget _attempt(ColorScheme scheme, Map<String, dynamic> a) {
    final at = DateTime.tryParse(a['attempted_at']?.toString() ?? '');
    final retry = DateTime.tryParse(a['retry_on']?.toString() ?? '');
    final reason = PipelineLabels.label(PipelineLabels.blockedReasons, a['reason']?.toString());
    final note = a['reason_note']?.toString() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${reason[0].toUpperCase()}${reason.substring(1)}'
          '${note.isEmpty ? '' : ' - $note'}',
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface),
        ),
        const SizedBox(height: 4),
        Text(
          '${at == null ? '' : 'Attempted ${fmtDate(at)}'}'
          '${retry == null ? '' : '  ·  Retry ${fmtDate(retry)}'}'
          '  ·  Customer ${a['customer_contacted'] == true ? 'told' : 'not told'}',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
        if ((a['notes']?.toString() ?? '').isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(a['notes'].toString(),
              style: TextStyle(fontSize: 13, color: scheme.onSurface)),
        ],
      ],
    );
  }

  Widget _card(ColorScheme scheme,
      {required String title, required List<Widget> children}) {
    return SurfaceCard(
      radius: AppTheme.radiusXl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTheme.sans(15, 600, 20, color: scheme.onSurface)),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _kv(ColorScheme scheme, String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k.toUpperCase(),
              style: AppTheme.labelSm.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(v, style: TextStyle(fontSize: 14, color: scheme.onSurface)),
        ],
      ),
    );
  }
}
