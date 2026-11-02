import 'package:flutter/material.dart';

import '../api.dart';
import '../pipeline_labels.dart';
import '../widgets/offline_banner.dart';
import '../theme.dart';
import '../widgets/chips.dart';
import '../widgets/motion.dart';
import 'add_lead_sheet.dart';
import 'lead_detail_screen.dart';

/// The lead list, following the FieldOps leads-page design: a back header,
/// a scrolling row of filter pills, cards, and a round add button.
class LeadsScreen extends StatefulWidget {
  const LeadsScreen({super.key, this.initialFilter = 'all'});

  /// Which pill starts selected - the home screen's strip opens the list
  /// already narrowed.
  final String initialFilter;

  @override
  State<LeadsScreen> createState() => _LeadsScreenState();
}

class _LeadsScreenState extends State<LeadsScreen> {
  static const _filters = [
    'all', 'new', 'demo', 'negotiation', 'proposal', 'converted',
    'closed',
  ];

  List<dynamic> _leads = [];
  bool _loading = true;
  String? _error;
  late String _filter = widget.initialFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final path = _filter == 'all'
        ? '/api/crm/leads/'
        : '/api/crm/leads/?status=$_filter';
    // This filter's last saved list straight away, then the server (#90).
    final saved = await Api.instance.cached(path);
    if (!mounted) return;
    setState(() {
      if (saved is List) _leads = saved;
      _loading = saved is! List;
      _error = null;
    });
    try {
      final data = await Api.instance.get(path);
      setState(() => _leads = data as List<dynamic>);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Cannot reach the server.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openAddSheet() async {
    // The shared sheet, so adding a lead looks and behaves the same whether it
    // is reached from here or from the home screen.
    final lead = await showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AddLeadSheet(),
    );
    if (lead != null) _load();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _header(scheme),
                _filterRow(scheme),
                const OfflineBanner(),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? Center(
                              child: Text(_error!,
                                  style: TextStyle(color: scheme.onSurface)))
                          : _leads.isEmpty
                              ? _emptyState(scheme)
                              : RefreshIndicator(
                                  onRefresh: _load,
                                  child: ListView.separated(
                                    padding: const EdgeInsets.fromLTRB(
                                        20, 16, 20, 96),
                                    itemCount: _leads.length,
                                    separatorBuilder: (_, _) =>
                                        const SizedBox(height: 12),
                                    // Stagger only the first screenful;
                                    // rows further down arrive as scrolled.
                                    itemBuilder: (_, i) => Reveal(
                                        index: i < 6 ? i : 0,
                                        child: _leadCard(scheme, _leads[i])),
                                  ),
                                ),
                ),
              ],
            ),
            Positioned(
              right: 20,
              bottom: 20,
              child: SizedBox(
                width: 56,
                height: 56,
                child: FloatingActionButton(
                  onPressed: _openAddSheet,
                  backgroundColor: scheme.primary,
                  foregroundColor: scheme.onPrimary,
                  shape: const CircleBorder(),
                  tooltip: 'Add lead',
                  child: const Icon(Icons.add, size: 24),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 20, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          IconButton(
            iconSize: 18,
            color: scheme.onSurfaceVariant,
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Back',
          ),
          Text('Leads',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface)),
        ],
      ),
    );
  }

  Widget _filterRow(ColorScheme scheme) {
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            for (final filter in _filters) ...[
              _filterPill(scheme, filter),
              if (filter != _filters.last) const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }

  Widget _filterPill(ColorScheme scheme, String filter) {
    final active = _filter == filter;
    return GestureDetector(
      onTap: () {
        setState(() => _filter = filter);
        _load();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? scheme.primary : scheme.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
              color: active ? scheme.primary : scheme.outlineVariant),
        ),
        child: Text(
          PipelineLabels.label(PipelineLabels.stages, filter),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: active ? scheme.onPrimary : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _emptyState(ColorScheme scheme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off, size: 32, color: scheme.onSurfaceVariant),
          const SizedBox(height: 8),
          Text('No leads found',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: scheme.onSurface)),
          const SizedBox(height: 4),
          Text('Try a different filter or add a new lead.',
              style:
                  TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Future<void> _openLead(Map<String, dynamic> lead) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
          builder: (_) => LeadDetailScreen(leadId: lead['id'] as int)),
    );
    // Always reload: the detail screen reports changes through its own back
    // button, but the Android back gesture pops with nothing, and a
    // converted lead must not still read "New" here.
    if (mounted) _load();
  }

  Widget _leadCard(ColorScheme scheme, Map<String, dynamic> lead) {
    final company = (lead['company_name'] as String?) ?? '';
    final requirement = (lead['requirement'] as String?) ?? '';
    final next = lead['next_followup'] as Map?;
    final due = next == null
        ? null
        : DateTime.tryParse(next['due_at']?.toString() ?? '');
    final overdue = next?['is_overdue'] == true;
    return SurfaceCard(
      onTap: () => _openLead(lead),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(lead['name'] as String? ?? '—',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface)),
                if (company.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _detailRow(scheme, Icons.business_outlined, company),
                ],
                const SizedBox(height: 6),
                _detailRow(scheme, Icons.phone_outlined,
                    lead['phone'] as String? ?? ''),
                if (requirement.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _detailRow(scheme, Icons.lightbulb_outline, requirement),
                ],
                if (due != null) ...[
                  const SizedBox(height: 6),
                  _detailRow(
                      scheme,
                      Icons.event_outlined,
                      '${overdue ? 'Overdue' : 'Follow-up'} '
                      '${due.day}/${due.month}',
                      danger: overdue),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              LeadStatusBadge(status: lead['status'] as String? ?? 'new'),
              const SizedBox(height: 8),
              Icon(Icons.chevron_right,
                  size: 18, color: scheme.onSurfaceVariant),
            ],
          ),
        ],
      ),
    );
  }

  Widget _detailRow(ColorScheme scheme, IconData icon, String text,
      {bool danger = false}) {
    final color = danger ? scheme.error : scheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: danger ? FontWeight.w600 : FontWeight.w400)),
        ),
      ],
    );
  }
}
