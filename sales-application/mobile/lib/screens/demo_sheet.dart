import 'package:flutter/material.dart';

import '../api.dart';
import '../pipeline_labels.dart';
import '../widgets/form_sheet.dart';

/// "Mark demo given": what was shown, how it went, whether they want it.
///
/// POSTs to /api/crm/demos/, which moves the lead to the `demo` stage on
/// the server - the app never sets that status itself.
class DemoSheet extends StatefulWidget {
  const DemoSheet({super.key, required this.leadId, this.product = ''});

  final int leadId;

  /// Prefilled from the lead's requirement, since that is usually what
  /// gets shown.
  final String product;

  @override
  State<DemoSheet> createState() => _DemoSheetState();
}

class _DemoSheetState extends State<DemoSheet> {
  static const _outcomes = [
    ('successful', 'Successful'),
    ('partial', 'Partial'),
    ('unsuccessful', 'Unsuccessful'),
    ('rescheduled', 'Rescheduled'),
  ];

  late final _product = TextEditingController(text: widget.product);
  final _feedback = TextEditingController();
  final _notes = TextEditingController();
  final _attendees = TextEditingController();
  String? _mode;
  String? _shown = 'portfolio';

  DateTime _heldAt = DateTime.now();
  String _outcome = 'successful';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _product.dispose();
    _feedback.dispose();
    _notes.dispose();
    _attendees.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_product.text.trim().isEmpty) {
      setState(() => _error = 'Say what was shown.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final demo = await Api.instance.post('/api/crm/demos/', {
        'lead': widget.leadId,
        'held_at': _heldAt.toIso8601String(),
        'product': _product.text.trim(),
        'mode': _mode ?? '',
        'shown': _shown ?? '',
        'attendees': _attendees.text.trim(),
        'outcome': _outcome,
        'feedback': _feedback.text.trim(),
        'notes': _notes.text.trim(),
      });
      if (!mounted) return;
      Navigator.of(context).pop(demo);
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
      title: 'Log presentation',
      saveLabel: 'Save',
      saving: _saving,
      error: _error,
      onSave: _save,
      children: [
        DateField(
          label: 'Presentation date',
          value: _heldAt,
          onChanged: (d) => setState(() => _heldAt = d ?? _heldAt),
        ),
        const SizedBox(height: 20),
        LabeledField(
          label: 'What was presented *',
          controller: _product,
          hint: 'Restaurant website with online ordering',
          icon: Icons.inventory_2_outlined,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 20),
        ChoiceRow<String>(
          label: 'Shown as',
          options: PipelineLabels.demoShown,
          value: _shown,
          onChanged: (v) => setState(() => _shown = v),
        ),
        const SizedBox(height: 20),
        ChoiceRow<String>(
          label: 'Where',
          options: PipelineLabels.demoModes,
          value: _mode,
          onChanged: (v) => setState(() => _mode = v),
        ),
        const SizedBox(height: 20),
        LabeledField(
          label: 'Who attended (client side)',
          controller: _attendees,
          hint: 'Owner, manager...',
          icon: Icons.groups_outlined,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 20),
        ChoiceRow<String>(
          label: 'Outcome',
          options: _outcomes,
          value: _outcome,
          onChanged: (v) => setState(() => _outcome = v),
        ),
        const SizedBox(height: 20),
        LabeledField(
          label: 'Customer feedback',
          controller: _feedback,
          hint: 'What they said',
          lines: 3,
        ),
        const SizedBox(height: 20),
        LabeledField(
          label: 'Notes',
          controller: _notes,
          hint: 'Anything for next time',
          lines: 2,
        ),
      ],
    );
  }
}
