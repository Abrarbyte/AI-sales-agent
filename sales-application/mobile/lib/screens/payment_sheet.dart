import 'package:flutter/material.dart';

import '../api.dart';
import '../pipeline_labels.dart';
import '../widgets/form_sheet.dart';

/// The ways a payment arrives, as the server names them.
const paymentMethods = <(String, String)>[
  ('upi', 'UPI'),
  ('bank_transfer', 'Bank transfer'),
  ('cash', 'Cash'),
  ('cheque', 'Cheque'),
  ('card', 'Card'),
  ('other', 'Other'),
];

/// Record money received from a customer (#42): how much, how, and the
/// reference that proves it. Dated today. The server refuses more than the
/// balance and says so; that message is shown as-is.
class RecordPaymentSheet extends StatefulWidget {
  const RecordPaymentSheet({
    super.key,
    required this.customerId,
    required this.balance,
  });

  final int customerId;
  final double balance;

  @override
  State<RecordPaymentSheet> createState() => _RecordPaymentSheetState();
}

class _RecordPaymentSheetState extends State<RecordPaymentSheet> {
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _notes = TextEditingController();
  String _method = 'upi';
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _amount.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _notes.dispose();
    super.dispose();
  }

  double get _value => double.tryParse(_amount.text.trim()) ?? 0;

  Future<void> _save() async {
    if (_value > widget.balance) {
      setState(() => _error =
          'That is more than the ₹${PipelineLabels.money(widget.balance)} still due.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await Api.instance.post(
        '/api/crm/customers/${widget.customerId}/payments/',
        {
          'amount': _value.toStringAsFixed(2),
          'method': _method,
          'reference': _reference.text.trim(),
          'notes': _notes.text.trim(),
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FormSheet(
      title: 'Record a payment',
      saveLabel: 'Record',
      saving: _saving,
      error: _error,
      onSave: _value > 0 ? _save : null,
      children: [
        Text('₹${PipelineLabels.money(widget.balance)} still due.'),
        const SizedBox(height: 16),
        LabeledField(
          label: 'Amount received (₹)',
          controller: _amount,
          hint: '0',
          icon: Icons.currency_rupee,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 20),
        ChoiceRow<String>(
          label: 'Paid by',
          options: paymentMethods,
          value: _method,
          onChanged: (v) => setState(() => _method = v),
        ),
        const SizedBox(height: 20),
        LabeledField(
          label: 'Reference',
          controller: _reference,
          hint: 'UTR, cheque number...',
          icon: Icons.tag,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 20),
        LabeledField(
          label: 'Notes',
          controller: _notes,
          hint: '',
          icon: Icons.notes_outlined,
          textInputAction: TextInputAction.done,
        ),
      ],
    );
  }
}
