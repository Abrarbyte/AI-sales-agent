import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets/form_sheet.dart';

/// Schedule a follow-up against a lead or a customer: what kind, when, why.
class FollowUpSheet extends StatefulWidget {
  const FollowUpSheet({super.key, this.leadId, this.customerId})
      : assert((leadId == null) != (customerId == null));

  final int? leadId;
  final int? customerId;

  @override
  State<FollowUpSheet> createState() => _FollowUpSheetState();
}

class _FollowUpSheetState extends State<FollowUpSheet> {
  static const _kinds = [
    ('call', 'Call'),
    ('visit', 'Visit'),
    ('meeting', 'Meeting'),
    ('email', 'Email'),
    ('message', 'Message'),
  ];

  final _note = TextEditingController();
  String _kind = 'call';
  DateTime _dueDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _dueTime = const TimeOfDay(hour: 10, minute: 0);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  DateTime get _dueAt => DateTime(_dueDate.year, _dueDate.month, _dueDate.day,
      _dueTime.hour, _dueTime.minute);

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: _dueTime);
    if (t != null) setState(() => _dueTime = t);
  }

  Future<void> _save() async {
    if (_dueAt.isBefore(DateTime.now())) {
      setState(() => _error = 'Pick a time in the future.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await Api.instance.post('/api/visits/followups/', {
        if (widget.leadId != null) 'lead': widget.leadId,
        if (widget.customerId != null) 'customer': widget.customerId,
        'kind': _kind,
        'due_at': _dueAt.toIso8601String(),
        'note': _note.text.trim(),
      });
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
    final scheme = Theme.of(context).colorScheme;
    return FormSheet(
      title: 'Schedule follow-up',
      saveLabel: 'Schedule',
      saving: _saving,
      error: _error,
      onSave: _save,
      children: [
        ChoiceRow<String>(
          label: 'Kind',
          options: _kinds,
          value: _kind,
          onChanged: (v) => setState(() => _kind = v),
        ),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: DateField(
                label: 'Date',
                value: _dueDate,
                firstDate: DateTime.now(),
                onChanged: (d) => setState(() => _dueDate = d ?? _dueDate),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const FieldLabel('Time'),
                  InkWell(
                    onTap: _pickTime,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.schedule, size: 20)),
                      child: Text(_dueTime.format(context),
                          style: TextStyle(
                              fontSize: 15, color: scheme.onSurface)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        LabeledField(
          label: 'Note',
          controller: _note,
          hint: 'What this follow-up is for',
          lines: 2,
        ),
      ],
    );
  }
}

/// Mark a follow-up done, with a line on how it went.
class CompleteFollowUpSheet extends StatefulWidget {
  const CompleteFollowUpSheet({super.key, required this.followUp});

  final Map<String, dynamic> followUp;

  @override
  State<CompleteFollowUpSheet> createState() => _CompleteFollowUpSheetState();
}

class _CompleteFollowUpSheetState extends State<CompleteFollowUpSheet> {
  final _outcome = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _outcome.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await Api.instance.post(
        '/api/visits/followups/${widget.followUp['id']}/complete/',
        {'outcome_note': _outcome.text.trim()},
      );
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
    final scheme = Theme.of(context).colorScheme;
    final f = widget.followUp;
    final due = DateTime.tryParse(f['due_at']?.toString() ?? '')?.toLocal();
    return FormSheet(
      title: 'Complete follow-up',
      saveLabel: 'Mark done',
      saving: _saving,
      error: _error,
      onSave: _save,
      children: [
        SurfaceCard(
          color: scheme.surfaceContainerHigh,
          small: true,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${(f['kind'] ?? '').toString().toUpperCase()} · ${f['target_name'] ?? ''}',
                style: AppTheme.labelSm.copyWith(color: scheme.onSurfaceVariant),
              ),
              if ((f['note']?.toString() ?? '').isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(f['note'].toString(),
                    style: AppTheme.bodyMd.copyWith(color: scheme.onSurface)),
              ],
              if (due != null) ...[
                const SizedBox(height: 4),
                Text('Due ${fmtDate(due)}',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        LabeledField(
          label: 'Outcome',
          controller: _outcome,
          hint: 'What happened (optional)',
          lines: 3,
        ),
      ],
    );
  }
}
