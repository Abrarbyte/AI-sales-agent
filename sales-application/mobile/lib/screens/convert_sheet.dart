import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets/form_sheet.dart';

/// Convert a lead into a customer.
///
/// The server refuses without an agreed price, and until the deposit the
/// payment terms ask for has been received (full advance 100%, half-and-half
/// 50%, otherwise 30%). This sheet does the arithmetic up front: it shows
/// what is owed, takes the amount received now, PATCHes it onto the lead,
/// then calls /convert/. If the server still says no, its message is shown
/// as-is.
class ConvertSheet extends StatefulWidget {
  const ConvertSheet({super.key, required this.lead});

  final Map<String, dynamic> lead;

  @override
  State<ConvertSheet> createState() => _ConvertSheetState();
}

class _ConvertSheetState extends State<ConvertSheet> {
  late final _value = TextEditingController(
    text: _num(widget.lead['value']) == 0
        ? ''
        : _num(widget.lead['value']).toStringAsFixed(0),
  );
  final _received = TextEditingController();

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // The Convert button's enabled state depends on both fields, and the
    // sheet as a whole has to rebuild for it - not just the summary card.
    _value.addListener(_recalc);
    _received.addListener(_recalc);
  }

  void _recalc() => setState(() {});

  static double _num(dynamic v) =>
      v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);

  double get _paid => _num(widget.lead['amount_paid']);
  double get _agreed => double.tryParse(_value.text.trim()) ?? 0;
  /// The share of the price due up front, as the server works it out from
  /// the agreed payment terms (#32). 30% from a server too old to say.
  double get _share {
    final share = _num(widget.lead['deposit_share']);
    return share > 0 ? share : 0.30;
  }

  double get _deposit => _agreed * _share;
  double get _now => double.tryParse(_received.text.trim()) ?? 0;
  double get _outstanding =>
      (_deposit - _paid - _now).clamp(0, double.infinity);

  @override
  void dispose() {
    _value.removeListener(_recalc);
    _received.removeListener(_recalc);
    _value.dispose();
    _received.dispose();
    super.dispose();
  }

  Future<void> _convert() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final id = widget.lead['id'];
    try {
      // Record the money first, so a refusal from /convert/ still leaves the
      // payment on the lead.
      await Api.instance.patch('/api/crm/leads/$id/', {
        if (_agreed > 0) 'value': _agreed.toStringAsFixed(2),
        'amount_paid': (_paid + _now).toStringAsFixed(2),
      });
      final customer = await Api.instance.post('/api/crm/leads/$id/convert/');
      if (!mounted) return;
      Navigator.of(context).pop(customer);
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
    final scheme = Theme.of(context).colorScheme;
    // No price, no conversion: the server refuses it (#16).
    final ready = _agreed > 0 && _outstanding == 0;

    return FormSheet(
      title: 'Convert to customer',
      saveLabel: 'Convert',
      saving: _saving,
      error: _error,
      onSave: ready ? _convert : null,
      children: [
        LabeledField(
          label: 'Agreed value (₹)',
          controller: _value,
          hint: '0',
          icon: Icons.currency_rupee,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 20),
        LabeledField(
          label: 'Amount received now (₹)',
          controller: _received,
          hint: '0',
          icon: Icons.payments_outlined,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.done,
        ),
        const SizedBox(height: 20),
        SurfaceCard(
          color: scheme.surfaceContainerHigh,
          child: Column(
            children: [
              _row(scheme, 'Deposit required (${(_share * 100).round()}%)',
                  _deposit),
              const SizedBox(height: 6),
              _row(scheme, 'Already paid', _paid),
              const SizedBox(height: 6),
              _row(scheme, 'Receiving now', _now),
              const Divider(height: 18),
              _row(
                scheme,
                'Still outstanding',
                _outstanding,
                danger: _outstanding > 0,
                bold: true,
              ),
              if (_agreed == 0) ...[
                const SizedBox(height: 10),
                Text(
                  'Enter the agreed price first - a lead needs one to '
                  'become a customer.',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(
    ColorScheme scheme,
    String label,
    double amount, {
    bool danger = false,
    bool bold = false,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
        ),
        Text(
          '₹${amount.toStringAsFixed(0)}',
          style: TextStyle(
            fontSize: bold ? 16 : 14,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            color: danger ? scheme.error : scheme.onSurface,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
