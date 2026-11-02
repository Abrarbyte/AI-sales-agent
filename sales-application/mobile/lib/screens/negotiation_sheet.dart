import 'package:flutter/material.dart';

import '../api.dart';
import '../pipeline_labels.dart';
import '../widgets/form_sheet.dart';

/// Open a negotiation, or update the one the lead already has.
///
/// One record per lead: the first save POSTs, every save after that PATCHes
/// the same row. The outcome isn't recorded here (#28): a won deal is
/// converted, a lost one is marked lost, both on the lead.
class NegotiationSheet extends StatefulWidget {
  const NegotiationSheet({
    super.key,
    required this.leadId,
    this.existing,
    this.requirement = '',
  });

  final int leadId;

  /// The negotiation row from GET /api/crm/negotiations/?lead=, if any.
  final Map<String, dynamic>? existing;

  /// Seed for Requirements when opening fresh.
  final String requirement;

  @override
  State<NegotiationSheet> createState() => _NegotiationSheetState();
}

class _NegotiationSheetState extends State<NegotiationSheet> {
  static const _statuses = [
    ('in_progress', 'In progress'),
    ('proposal_sent', 'Proposal sent'),
    ('on_hold', 'On hold'),
  ];

  late final Map<String, dynamic> _e = widget.existing ?? const {};
  late final _decisionMaker =
      TextEditingController(text: _e['decision_maker']?.toString() ?? '');
  // What they want is the lead's requirement - the one place for it (#48).
  // Edited here, saved back to the lead.
  late final _requirements = TextEditingController(text: widget.requirement);
  late final _objections =
      TextEditingController(text: _e['objections']?.toString() ?? '');
  late final _notes = TextEditingController(text: _e['notes']?.toString() ?? '');
  late final _quoted = TextEditingController(text: _num(_e['quoted_amount']));
  late final _discount = TextEditingController(text: _num(_e['discount_pct']));
  late final _timeline = TextEditingController(text: _num(_e['timeline_weeks']));
  late final _competitor =
      TextEditingController(text: _e['competitor']?.toString() ?? '');
  late final _paymentNote =
      TextEditingController(text: _e['payment_terms_note']?.toString() ?? '');
  late String? _paymentTerms = (_e['payment_terms']?.toString() ?? '').isEmpty
      ? null
      : _e['payment_terms'].toString();

  static String _num(dynamic v) => v == null ? '' : v.toString();

  late DateTime _startedAt =
      DateTime.tryParse(_e['started_at']?.toString() ?? '') ?? DateTime.now();
  late DateTime? _expectedClose =
      DateTime.tryParse(_e['expected_close_on']?.toString() ?? '');
  late String _status = _statuses.any((s) => s.$1 == _e['status'])
      ? _e['status'] as String
      : 'in_progress';
  bool _saving = false;
  String? _error;

  bool get _isNew => widget.existing == null;

  @override
  void dispose() {
    for (final c in [
      _decisionMaker,
      _requirements,
      _objections,
      _notes,
      _quoted,
      _discount,
      _timeline,
      _competitor,
      _paymentNote,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final body = {
      'lead': widget.leadId,
      'started_at': apiDate(_startedAt),
      'decision_maker': _decisionMaker.text.trim(),
      'objections': _objections.text.trim(),
      'quoted_amount': _quoted.text.trim().isEmpty ? null : _quoted.text.trim(),
      'discount_pct':
          _discount.text.trim().isEmpty ? null : _discount.text.trim(),
      'payment_terms': _paymentTerms ?? '',
      'payment_terms_note': _paymentNote.text.trim(),
      'timeline_weeks':
          _timeline.text.trim().isEmpty ? null : int.tryParse(_timeline.text.trim()),
      'competitor': _competitor.text.trim(),
      'expected_close_on':
          _expectedClose == null ? null : apiDate(_expectedClose!),
      'status': _status,
      'notes': _notes.text.trim(),
    };
    try {
      final result = _isNew
          ? await Api.instance.post('/api/crm/negotiations/', body)
          : await Api.instance
              .patch('/api/crm/negotiations/${_e['id']}/', body);
      if (_requirements.text.trim() != widget.requirement.trim()) {
        await Api.instance.patch('/api/crm/leads/${widget.leadId}/',
            {'requirement': _requirements.text.trim()});
      }
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Cannot reach the server.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FormSheet(
      title: _isNew ? 'Open negotiation' : 'Update negotiation',
      saveLabel: _isNew ? 'Open' : 'Save',
      saving: _saving,
      error: _error,
      onSave: _save,
      children: [
        DateField(
          label: 'Started',
          value: _startedAt,
          onChanged: (d) => setState(() => _startedAt = d ?? _startedAt),
        ),
        const SizedBox(height: 20),
        LabeledField(
          label: 'Decision maker',
          controller: _decisionMaker,
          hint: 'Who signs off',
          icon: Icons.person_outline,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 20),
        LabeledField(
          label: 'What they want',
          controller: _requirements,
          hint: '5 pages, online ordering, admin panel...',
          lines: 3,
        ),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: LabeledField(
                label: 'Quoted (₹)',
                controller: _quoted,
                hint: '1,20,000',
                icon: Icons.currency_rupee,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: LabeledField(
                label: 'Discount %',
                controller: _discount,
                hint: '0',
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        ChoiceRow<String>(
          label: 'Payment terms',
          options: PipelineLabels.paymentTerms,
          value: _paymentTerms,
          onChanged: (v) => setState(() => _paymentTerms = v),
        ),
        // The one note for payment, whatever the terms (#48).
        const SizedBox(height: 12),
        LabeledField(
          label: 'Payment details',
          controller: _paymentNote,
          hint: '40% design, 40% development, 20% go-live',
          lines: 2,
        ),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: LabeledField(
                label: 'Timeline (weeks)',
                controller: _timeline,
                hint: '6',
                icon: Icons.schedule_outlined,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: LabeledField(
                label: 'Other agency quoted?',
                controller: _competitor,
                hint: 'Name / amount',
                textInputAction: TextInputAction.next,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        LabeledField(
          label: 'Customer objections',
          controller: _objections,
          hint: 'Price, timing, a competitor...',
          lines: 2,
        ),

        const SizedBox(height: 20),
        DateField(
          label: 'Expected closing date',
          value: _expectedClose,
          allowClear: true,
          onChanged: (d) => setState(() => _expectedClose = d),
        ),
        const SizedBox(height: 20),
        ChoiceRow<String>(
          label: 'Negotiation status',
          options: _statuses,
          value: _status,
          onChanged: (v) => setState(() => _status = v),
        ),
        const SizedBox(height: 20),
        LabeledField(
          label: 'Notes',
          controller: _notes,
          hint: '',
          lines: 2,
        ),
      ],
    );
  }
}
