import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';

/// The ways a payment arrives, as the server names them.
const Map<String, String> paymentMethodLabels = <String, String>{
  'upi': 'UPI',
  'bank_transfer': 'Bank transfer',
  'cash': 'Cash',
  'cheque': 'Cheque',
  'card': 'Card',
  'other': 'Other',
};

/// Asks for one payment: how much, when, how, and the reference that proves
/// it (a UTR or cheque number). Returns the POST body, or null if cancelled.
/// The server checks it against the balance too; this only stops the obvious.
class RecordPaymentDialog extends StatefulWidget {
  const RecordPaymentDialog({
    super.key,
    required this.customerName,
    required this.balance,
  });

  final String customerName;
  final double balance;

  @override
  State<RecordPaymentDialog> createState() => _RecordPaymentDialogState();
}

class _RecordPaymentDialogState extends State<RecordPaymentDialog> {
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _reference = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  String _method = 'upi';
  DateTime _on = DateTime.now();

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _notes.dispose();
    super.dispose();
  }

  double? get _value => double.tryParse(_amount.text.trim());

  String? get _problem {
    final double? v = _value;
    if (v == null || v <= 0) return null;
    if (v > widget.balance) {
      return 'More than the ${Fmt.money(widget.balance)} still due.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final double? v = _value;
    final bool ok = v != null && v > 0 && _problem == null;
    return AlertDialog(
      title: Text('Record a payment from ${widget.customerName}'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('${Fmt.money(widget.balance)} still due.'),
            const SizedBox(height: 16),
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Amount (₹)',
                errorText: _problem,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _method,
                    decoration: const InputDecoration(labelText: 'Paid by'),
                    items: <DropdownMenuItem<String>>[
                      for (final MapEntry<String, String> m
                          in paymentMethodLabels.entries)
                        DropdownMenuItem<String>(
                          value: m.key,
                          child: Text(m.value),
                        ),
                    ],
                    onChanged: (String? m) =>
                        setState(() => _method = m ?? _method),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: _on,
                        firstDate: DateTime(2020),
                        // Not in the future: the server refuses that too.
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) setState(() => _on = picked);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Received on',
                      ),
                      child: Text(Fmt.date(_on)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reference,
              decoration: const InputDecoration(
                labelText: 'Reference',
                hintText: 'UTR, cheque number...',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: ok
              ? () => Navigator.of(context).pop(<String, dynamic>{
                  'amount': v.toStringAsFixed(2),
                  'method': _method,
                  'received_on':
                      '${_on.year.toString().padLeft(4, '0')}-'
                      '${_on.month.toString().padLeft(2, '0')}-'
                      '${_on.day.toString().padLeft(2, '0')}',
                  'reference': _reference.text.trim(),
                  'notes': _notes.text.trim(),
                })
              : null,
          child: const Text('Record payment'),
        ),
      ],
    );
  }
}

/// Asks for a customer's agreed price. Returns it, or null if cancelled.
Future<double?> askForPrice(
  BuildContext context, {
  required String customerName,
  double? current,
  double paid = 0,
}) async {
  final TextEditingController price = TextEditingController(
    text: current == null ? '' : current.toStringAsFixed(0),
  );
  final double? result = await showDialog<double>(
    context: context,
    builder: (BuildContext ctx) => StatefulBuilder(
      builder: (BuildContext ctx, StateSetter setDialog) {
        final double? v = double.tryParse(price.text.trim());
        final String? problem = v != null && v < paid
            ? "Can't be less than the ${Fmt.money(paid)} already paid."
            : null;
        return AlertDialog(
          title: Text('Agreed price for $customerName'),
          content: SizedBox(
            width: 380,
            child: TextField(
              controller: price,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setDialog(() {}),
              decoration: InputDecoration(
                labelText: 'Price (₹)',
                errorText: problem,
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: v == null || v < 0 || problem != null
                  ? null
                  : () => Navigator.of(ctx).pop(v),
              child: const Text('Save'),
            ),
          ],
        );
      },
    ),
  );
  price.dispose();
  return result;
}
