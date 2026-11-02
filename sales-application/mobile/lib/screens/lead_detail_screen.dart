import 'package:flutter/material.dart';

import '../api.dart';
import '../pipeline_labels.dart';
import '../theme.dart';
import '../widgets/chips.dart';
import '../widgets/form_sheet.dart';
import '../widgets/motion.dart';
import '../widgets/activity_cards.dart';
import 'convert_sheet.dart';
import 'customer_detail_screen.dart';
import 'followup_sheet.dart';
import 'visit_sheet.dart';
import 'demo_sheet.dart';
import 'negotiation_sheet.dart';

/// One lead: who they are, what they want, where they are in the pipeline,
/// and the next thing to do about it.
///
/// The action row follows the stage. A new lead can be shown a
/// demo; anything open can go to negotiation or straight to conversion; and
/// anything open can be marked lost. The status itself is never edited here -
/// every button creates the record that moves it.
class LeadDetailScreen extends StatefulWidget {
  const LeadDetailScreen({super.key, required this.leadId});

  final int leadId;

  @override
  State<LeadDetailScreen> createState() => _LeadDetailScreenState();
}

class _LeadDetailScreenState extends State<LeadDetailScreen> {
  Map<String, dynamic>? _lead;
  Map<String, dynamic>? _negotiation;
  List<dynamic> _demos = const [];
  List<Map<String, dynamic>> _visits = const [];
  List<Map<String, dynamic>> _followUps = const [];
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
    final negotiations = results[2] as List<dynamic>;
    final visits = (results[3] as List).cast<Map<String, dynamic>>();
    final followUps = (results[4] as List).cast<Map<String, dynamic>>();
    setState(() {
      _lead = (results[0] as Map).cast<String, dynamic>();
      _demos = results[1] as List<dynamic>;
      _negotiation = negotiations.isEmpty
          ? null
          : (negotiations.first as Map).cast<String, dynamic>();
      _visits = visits;
      _followUps = followUps;
    });
  }

  Future<void> _load() async {
    final paths = [
      '/api/crm/leads/${widget.leadId}/',
      '/api/crm/demos/?lead=${widget.leadId}',
      '/api/crm/negotiations/?lead=${widget.leadId}',
      // Only this lead's rows - not every visit, filtered here (#89).
      '/api/visits/?lead=${widget.leadId}',
      '/api/visits/followups/?status=pending&lead=${widget.leadId}',
    ];
    // First open: the last saved copy straight away, then the server (#90).
    if (_lead == null) {
      final saved = await Api.instance.cachedAll(paths);
      if (saved != null && mounted) _apply(saved);
    }
    if (!mounted) return;
    setState(() {
      _loading = _lead == null;
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

  Future<void> _close() async {
    String reason = 'no_response';
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('Mark this lead as lost?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'It stays on record as lost. Knowing why helps the '
                  'team win the next one.'),
              const SizedBox(height: 16),
              ChoiceRow<String>(
                label: 'Why did we lose it?',
                options: PipelineLabels.lostReasons,
                value: reason,
                onChanged: (v) => setDialog(() => reason = v),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Keep open')),
            FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Mark as lost')),
          ],
        ),
      ),
    );
    if (yes != true) return;
    try {
      await Api.instance.patch('/api/crm/leads/${widget.leadId}/',
          {'status': 'closed', 'lost_reason': reason});
      _changed = true;
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
    final lead = _lead;

    return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(_changed),
          ),
          title: Text(lead?['name']?.toString() ?? 'Lead'),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _errorView(scheme)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                      children: [
                        Reveal(index: 0, child: _stageHeader(scheme, lead!)),
                        const SizedBox(height: 16),
                        Reveal(index: 1, child: _actions(scheme, lead)),
                        const SizedBox(height: 24),
                        Reveal(index: 2, child: _contactCard(scheme, lead)),
                        const SizedBox(height: 16),
                        Reveal(index: 3, child: _demoCard(scheme, lead)),
                        const SizedBox(height: 16),
                        Reveal(index: 4, child: _negotiationCard(scheme)),
                        const SizedBox(height: 16),
                        Reveal(
                          index: 5,
                          child: FollowUpsCard(
                            followUps: _followUps,
                            onSchedule: () => _after(showFormSheet(
                                context, FollowUpSheet(leadId: widget.leadId))),
                            onComplete: (f) => _after(showFormSheet(
                                context, CompleteFollowUpSheet(followUp: f))),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Reveal(
                          index: 6,
                          // No button here: Log visit is in the action row
                          // above, the one place to log it (#93).
                          child: VisitsCard(visits: _visits),
                        ),
                      ],
                    ),
                  ),
    );
  }

  // ------------------------------------------------------------ sections

  Widget _stageHeader(ColorScheme scheme, Map<String, dynamic> lead) {
    final next = lead['next_followup'] as Map?;
    final due = next == null
        ? null
        : DateTime.tryParse(next['due_at']?.toString() ?? '');
    final overdue = next?['is_overdue'] == true;
    return Row(
      children: [
        LeadStatusBadge(status: lead['status']?.toString() ?? 'new'),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            due == null
                ? 'No follow-up scheduled'
                : '${overdue ? 'Overdue' : 'Next'}: '
                    '${fmtDate(due)}',
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

  Widget _actions(ColorScheme scheme, Map<String, dynamic> lead) {
    final status = lead['status']?.toString() ?? 'new';
    final open = const {'new', 'demo', 'negotiation', 'proposal'}
        .contains(status);
    if (!open) {
      final customerId = lead['converted_customer'];
      return SurfaceCard(
        color: scheme.surfaceContainerHigh,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              status == 'converted'
                  // The customer holds the contact details now (#52).
                  ? 'This lead is now a customer. Their contact details are '
                      'kept on the customer.'
                  : 'This lead was lost.',
              style: AppTheme.bodyMd.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (status == 'converted' && customerId is int) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.storefront_outlined, size: 18),
                label: const Text('Open customer'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) =>
                        CustomerDetailScreen(customerId: customerId))),
              ),
            ],
          ],
        ),
      );
    }

    final requirement = lead['requirement']?.toString() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (status == 'new' || status == 'demo')
          FilledButton.icon(
            icon: const Icon(Icons.play_circle_outline, size: 20),
            label: Text(_demos.isEmpty ? 'Mark demo given' : 'Log another demo'),
            onPressed: () => _after(showFormSheet(
              context,
              DemoSheet(leadId: widget.leadId, product: requirement),
            )),
          ),
        if (status == 'new' || status == 'demo')
          const SizedBox(height: 10),
        OutlinedButton.icon(
          icon: const Icon(Icons.handshake_outlined, size: 20),
          label: Text(
              _negotiation == null ? 'Open negotiation' : 'Update negotiation'),
          onPressed: () => _after(showFormSheet(
            context,
            NegotiationSheet(
              leadId: widget.leadId,
              existing: _negotiation,
              requirement: requirement,
            ),
          )),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          icon: const Icon(Icons.add_location_alt_outlined, size: 20),
          label: const Text('Log visit'),
          onPressed: () => _after(showFormSheet(
            context,
            VisitSheet(
                leadId: widget.leadId,
                targetName: lead['name']?.toString() ?? ''),
          )),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          icon: const Icon(Icons.verified_outlined, size: 20),
          label: const Text('Convert to customer'),
          onPressed: () => _after(showFormSheet(
            context,
            ConvertSheet(lead: lead),
          )),
        ),
        const SizedBox(height: 10),
        TextButton.icon(
          icon: Icon(Icons.block, size: 18, color: scheme.error),
          label: Text('Mark as lost', style: TextStyle(color: scheme.error)),
          onPressed: _close,
        ),
      ],
    );
  }

  Widget _contactCard(ColorScheme scheme, Map<String, dynamic> lead) {
    String s(String k) {
      final v = lead[k];
      return v == null ? '' : v.toString();
    }
    final company = [s('company_name'), s('designation')]
        .where((x) => x.isNotEmpty)
        .join(' · ');
    final rows = <(IconData, String)>[
      if (company.isNotEmpty) (Icons.domain_outlined, company),
      (Icons.phone_outlined, s('phone')),
      if (s('email').isNotEmpty) (Icons.mail_outline, s('email')),
      if (s('address').isNotEmpty || s('city').isNotEmpty)
        (Icons.place_outlined,
            [s('address'), s('city')].where((x) => x.isNotEmpty).join(', ')),
      if (s('industry').isNotEmpty)
        (Icons.storefront_outlined,
            PipelineLabels.label(PipelineLabels.industries, s('industry'))),
      (Icons.campaign_outlined,
          'Source: ${PipelineLabels.label(PipelineLabels.sources, s('source'))}'),
    ];
    final project = [
      PipelineLabels.label(PipelineLabels.projectTypes, s('project_type')),
      if (s('platforms').isNotEmpty)
        PipelineLabels.label(PipelineLabels.platforms, s('platforms')),
    ].where((x) => x.isNotEmpty).join(' · ');
    final priority = s('priority');
    return _card(
      scheme,
      title: 'Contact',
      trailing: priority.isEmpty
          ? null
          : StatusPill(
              label: PipelineLabels.label(PipelineLabels.priorities, priority),
              color: switch (priority) {
                'hot' => AppTheme.rose500,
                'cold' => AppTheme.blue500,
                _ => AppTheme.amber500,
              }),
      children: [
        for (final (icon, text) in rows) ...[
          _iconRow(scheme, icon, text),
          const SizedBox(height: 8),
        ],
        if (project.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('PROJECT',
              style: AppTheme.labelSm.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text(project,
              style: AppTheme.bodyMd.copyWith(
                  color: scheme.onSurface, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
        ],
        if (s('existing_url').isNotEmpty) ...[
          _iconRow(scheme, Icons.link_outlined, s('existing_url')),
          const SizedBox(height: 8),
        ],
        if (s('budget').isNotEmpty && s('budget') != 'null') ...[
          _iconRow(scheme, Icons.currency_rupee,
              'Their budget: ₹${PipelineLabels.money(lead['budget'])}'),
          const SizedBox(height: 8),
        ],
        if (s('expected_start').isNotEmpty && s('expected_start') != 'null') ...[
          _iconRow(scheme, Icons.event_outlined,
              'Wants to start: ${s('expected_start')}'),
          const SizedBox(height: 8),
        ],
        if (s('lost_reason').isNotEmpty) ...[
          _iconRow(scheme, Icons.cancel_outlined,
              'Lost: ${PipelineLabels.label(PipelineLabels.lostReasons, s('lost_reason'))}'),
          const SizedBox(height: 8),
        ],
        if (s('requirement').isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('REQUIREMENT / INTEREST',
              style: AppTheme.labelSm.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text(s('requirement'),
              style: AppTheme.bodyMd.copyWith(color: scheme.onSurface)),
        ],
        if (s('value').isNotEmpty && s('value') != 'null') ...[
          const SizedBox(height: 12),
          Row(
            children: [
              _money(scheme, 'Value', lead['value']),
              const SizedBox(width: 24),
              _money(scheme, 'Paid', lead['amount_paid']),
            ],
          ),
        ],
      ],
    );
  }

  Widget _demoCard(ColorScheme scheme, Map<String, dynamic> lead) {
    if (_demos.isEmpty) {
      return _card(scheme,
          title: 'Demo',
          children: [
            Text('No demo given yet.',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant))
          ]);
    }
    return _card(
      scheme,
      title: 'Demo${_demos.length > 1 ? ' (${_demos.length})' : ''}',
      children: [
        for (final d in _demos.take(3)) ...[
          _demoRow(scheme, (d as Map).cast<String, dynamic>()),
          if (d != _demos.take(3).last) const Divider(height: 20),
        ],
      ],
    );
  }

  Widget _demoRow(ColorScheme scheme, Map<String, dynamic> d) {
    final held = DateTime.tryParse(d['held_at']?.toString() ?? '');
    final (label, color) = Statuses.demoOutcome(d['outcome']?.toString());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(d['product']?.toString() ?? '',
                  style: AppTheme.bodyMd.copyWith(
                      color: scheme.onSurface, fontWeight: FontWeight.w600)),
            ),
            StatusPill(label: label, color: color),
          ],
        ),
        const SizedBox(height: 4),
        // The outcome says whether they were interested (#49).
        Text(
          held == null ? '' : fmtDate(held),
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
        if ((d['feedback']?.toString() ?? '').isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('"${d['feedback']}"',
              style: TextStyle(
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  color: scheme.onSurface)),
        ],
      ],
    );
  }

  Widget _negotiationCard(ColorScheme scheme) {
    final n = _negotiation;
    if (n == null) {
      return _card(scheme,
          title: 'Negotiation',
          children: [
            Text('Not opened.',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant))
          ]);
    }
    final (label, color) = Statuses.negotiation(n['status']?.toString());
    final close = DateTime.tryParse(n['expected_close_on']?.toString() ?? '');
    final slipping = n['is_slipping'] == true;
    String s(String k) => n[k]?.toString() ?? '';
    return _card(
      scheme,
      title: 'Negotiation',
      trailing: StatusPill(label: label, color: color),
      children: [
        if (s('decision_maker').isNotEmpty)
          _kv(scheme, 'Decision maker', s('decision_maker')),
        if (s('quoted_amount').isNotEmpty && s('quoted_amount') != 'null')
          _kv(
              scheme,
              'Quoted',
              '₹${PipelineLabels.money(n['quoted_amount'])}'
              '${s('discount_pct').isNotEmpty && s('discount_pct') != 'null' ? '  (${s('discount_pct')}% off)' : ''}'),
        if (s('payment_terms').isNotEmpty)
          _kv(scheme, 'Payment',
              PipelineLabels.label(PipelineLabels.paymentTerms, s('payment_terms'))),
        // The one payment note, which now holds the old free-text terms (#48).
        if (s('payment_terms_note').isNotEmpty)
          _kv(scheme, 'Payment details', s('payment_terms_note')),
        if (s('timeline_weeks').isNotEmpty && s('timeline_weeks') != 'null')
          _kv(scheme, 'Timeline', '${s('timeline_weeks')} weeks'),
        if (s('competitor').isNotEmpty)
          _kv(scheme, 'Competing with', s('competitor')),
        _kv(
          scheme,
          'Expected close',
          close == null
              ? '-'
              : '${fmtDate(close)}${slipping ? '  (slipping)' : ''}',
          danger: slipping,
        ),
        if (s('objections').isNotEmpty) _kv(scheme, 'Objections', s('objections')),
      ],
    );
  }

  // -------------------------------------------------------------- pieces

  Widget _card(ColorScheme scheme,
      {required String title,
      required List<Widget> children,
      Widget? trailing}) {
    return SurfaceCard(
      radius: AppTheme.radiusXl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title,
                    style: AppTheme.sans(15, 600, 20, color: scheme.onSurface)),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 12),
          ...children,
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
          child: Text(text,
              style: TextStyle(fontSize: 14, color: scheme.onSurface)),
        ),
      ],
    );
  }

  Widget _kv(ColorScheme scheme, String k, String v, {bool danger = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k.toUpperCase(),
              style: AppTheme.labelSm.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(v,
              style: TextStyle(
                  fontSize: 14,
                  color: danger ? scheme.error : scheme.onSurface)),
        ],
      ),
    );
  }

  Widget _money(ColorScheme scheme, String label, dynamic v) {
    final n = v == null ? 0 : (v is num ? v : double.tryParse('$v') ?? 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(),
            style: AppTheme.labelSm.copyWith(color: scheme.onSurfaceVariant)),
        Text('₹${n.toStringAsFixed(0)}',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
                fontFeatures: const [FontFeature.tabularFigures()])),
      ],
    );
  }

  Widget _errorView(ColorScheme scheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 36, color: scheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(_error!,
                textAlign: TextAlign.center,
                style: AppTheme.bodyMd.copyWith(color: scheme.onSurface)),
            const SizedBox(height: 20),
            OutlinedButton(onPressed: _load, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
