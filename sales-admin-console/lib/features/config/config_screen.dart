import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/responsive.dart';
import '../../data/api/api_client.dart';
import '../../data/api/mappers.dart';
import '../../data/models/lead.dart';
import '../../data/models/ops.dart';
import '../../data/providers.dart';
import '../../widgets/motion.dart';
import '../../widgets/primitives.dart';
import '../dashboard/dashboard_panels.dart';

/// Configuration: the product catalogue (what reps sell and deliver) and
/// the pipeline as it is fixed in code. Products are the one thing here a
/// manager edits; stages are shown so nobody goes looking for a setting
/// that does not exist.
class ConfigScreen extends ConsumerStatefulWidget {
  const ConfigScreen({super.key});

  @override
  ConsumerState<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends ConsumerState<ConfigScreen> {
  List<Map<String, dynamic>> _products = const <Map<String, dynamic>>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _products.isEmpty;
      _error = null;
    });
    try {
      final List<Map<String, dynamic>> rows =
          await ref.read(apiClientProvider).getList('/api/crm/products/');
      setState(() => _products = rows);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Cannot reach the server.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit({Map<String, dynamic>? existing}) async {
    final _ProductDraft? draft = await showDialog<_ProductDraft>(
      context: context,
      builder: (_) => _ProductDialog(existing: existing),
    );
    if (draft == null) return;
    final ApiClient api = ref.read(apiClientProvider);
    try {
      if (existing == null) {
        await api.post('/api/crm/products/', <String, dynamic>{
          'name': draft.name,
          'kind': draft.kind,
          'is_active': draft.active,
        });
      } else {
        await api.patch('/api/crm/products/${existing['id']}/', <String, dynamic>{
          'name': draft.name,
          'kind': draft.kind,
          'is_active': draft.active,
        });
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.message),
        backgroundColor: VizPalette.statusCritical,
      ));
      return;
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SingleChildScrollView(
      padding: Responsive.pagePadding(Responsive.of(context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const PageHeader(
              title: 'Configuration',
              subtitle: 'Product catalogue and the pipeline'),
          const SizedBox(height: AppSpacing.lg),
          Reveal(
            index: 0,
            child: Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  PanelHeader(
                    title: 'Products & services',
                    subtitle: const Text(
                        'What reps attach to customers and schedule deliveries for'),
                    trailing: FilledButton.icon(
                      onPressed: () => _edit(),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('New product'),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(AppSpacing.xl),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_error != null)
                    ErrorNotice(message: _error!, onRetry: _load)
                  else if (_products.isEmpty)
                    const EmptyState(
                      icon: Icons.inventory_2_outlined,
                      title: 'No products yet',
                      message:
                          'Add what the company sells. Reps pick from this list.',
                    )
                  else
                    for (final Map<String, dynamic> p in _products)
                      _ProductRow(product: p, onEdit: () => _edit(existing: p)),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Reveal(
            index: 1,
            child: Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const PanelHeader(
                    title: 'Pipeline',
                    subtitle: Text(
                        'Fixed in code. Demo and Negotiation are entered by logging '
                        'a record, never by hand; Converted needs the 30% deposit.'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: <Widget>[
                      for (final PipelineStage s in Mappers.fixedStages)
                        StatusChip(
                          label: '${s.order + 1}. ${s.name}',
                          color: s.kind == LeadStageKind.won
                              ? VizPalette.statusGood
                              : s.kind == LeadStageKind.lost
                                  ? VizPalette.inkMuted
                                  : VizPalette.accent,
                          icon: Icons.circle,
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Leads with no activity for 30 days are closed nightly by '
                    'the scheduler (close_stale_leads).',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: VizPalette.inkMuted),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.product, required this.onEdit});

  final Map<String, dynamic> product;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool active = product['is_active'] as bool? ?? true;
    final String kind = product['kind']?.toString() ?? 'product';
    return HoverRow(
      onTap: onEdit,
      child: Container(
        height: AppSpacing.tableRowHeight,
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: theme.dividerColor)),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              kind == 'service'
                  ? Icons.handyman_outlined
                  : Icons.inventory_2_outlined,
              size: 18,
              color: active ? VizPalette.accent : VizPalette.inkMuted,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                product['name']?.toString() ?? '',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: active ? null : VizPalette.inkMuted,
                  decoration: active ? null : TextDecoration.lineThrough,
                ),
              ),
            ),
            StatusChip(
              label: kind == 'service' ? 'Service' : 'Product',
              color: VizPalette.inkMuted,
              icon: Icons.label_outline,
              dense: true,
            ),
            const SizedBox(width: AppSpacing.md),
            StatusChip(
              label: active ? 'Active' : 'Retired',
              color: active ? VizPalette.statusGood : VizPalette.inkMuted,
              icon: active ? Icons.check_circle_outline : Icons.pause_circle_outline,
              dense: true,
            ),
            const SizedBox(width: AppSpacing.md),
            Icon(Icons.edit_outlined, size: 16, color: VizPalette.inkMuted),
          ],
        ),
      ),
    );
  }
}

class _ProductDraft {
  const _ProductDraft(this.name, this.kind, this.active);
  final String name;
  final String kind;
  final bool active;
}

class _ProductDialog extends StatefulWidget {
  const _ProductDialog({this.existing});

  final Map<String, dynamic>? existing;

  @override
  State<_ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends State<_ProductDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?['name']?.toString() ?? '');
  late String _kind = widget.existing?['kind']?.toString() ?? 'product';
  late bool _active = widget.existing?['is_active'] as bool? ?? true;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool editing = widget.existing != null;
    return AlertDialog(
      title: Text(editing ? 'Edit product' : 'New product'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: AppSpacing.md),
            SegmentedButton<String>(
              segments: const <ButtonSegment<String>>[
                ButtonSegment<String>(value: 'product', label: Text('Product')),
                ButtonSegment<String>(value: 'service', label: Text('Service')),
              ],
              selected: <String>{_kind},
              onSelectionChanged: (Set<String> s) =>
                  setState(() => _kind = s.first),
            ),
            if (editing) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                subtitle: const Text(
                    'Retired products stay on old records but cannot be picked.'),
                value: _active,
                onChanged: (bool v) => setState(() => _active = v),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: _name.text.trim().isEmpty
              ? null
              : () => Navigator.of(context)
                  .pop(_ProductDraft(_name.text.trim(), _kind, _active)),
          child: Text(editing ? 'Save' : 'Add'),
        ),
      ],
    );
  }
}
