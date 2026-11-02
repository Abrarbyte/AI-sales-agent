import 'package:flutter/material.dart';

import '../../core/company_profile.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/people.dart';

/// A lead typed in at the office - an enquiry by phone or from the website
/// - and handed straight to a rep, who gets the assignment notification on
/// the phone exactly as with a reassignment.
///
/// Returns the API body for `POST /api/crm/leads/`, or null on cancel.
class NewLeadDialog extends StatefulWidget {
  const NewLeadDialog({super.key, required this.reps});

  final List<SalesRep> reps;

  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required List<SalesRep> reps,
  }) => showDialog<Map<String, dynamic>>(
    context: context,
    builder: (BuildContext context) => NewLeadDialog(reps: reps),
  );

  @override
  State<NewLeadDialog> createState() => _NewLeadDialogState();
}

class _NewLeadDialogState extends State<NewLeadDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _company = TextEditingController();
  final TextEditingController _contact = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _city = TextEditingController();
  final TextEditingController _designation = TextEditingController();
  final TextEditingController _budget = TextEditingController();
  final TextEditingController _requirement = TextEditingController();
  final TextEditingController _notes = TextEditingController();

  String? _industry;
  String? _projectType;
  String? _platforms;
  String _priority = 'warm';
  String _source = 'phone';
  String? _repId;

  static const Set<String> _appTypes = <String>{
    'android_app',
    'ios_app',
    'web_app',
    'website_and_app',
  };

  @override
  void initState() {
    super.initState();
    if (widget.reps.length == 1) _repId = widget.reps.first.id;
  }

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[
      _company,
      _contact,
      _phone,
      _email,
      _city,
      _designation,
      _budget,
      _requirement,
      _notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_repId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick the rep who will work this lead.')),
      );
      return;
    }
    final String budget = _budget.text.trim();
    Navigator.of(context).pop(<String, dynamic>{
      'name': _contact.text.trim(),
      'company_name': _company.text.trim(),
      'phone': _phone.text.trim(),
      'email': _email.text.trim(),
      'city': _city.text.trim(),
      'designation': _designation.text.trim(),
      'industry': _industry ?? '',
      'project_type': _projectType ?? '',
      'platforms': _appTypes.contains(_projectType) ? (_platforms ?? '') : '',
      'budget': budget.isEmpty ? null : budget,
      'priority': _priority,
      'source': _source,
      'requirement': _requirement.text.trim(),
      'notes': _notes.text.trim(),
      'assigned_to': int.tryParse(_repId!),
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.xl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 760),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('New lead', style: theme.textTheme.titleLarge),
                        const SizedBox(height: 2),
                        Text(
                          'The rep you pick is notified on the phone and '
                          'finds it under New.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
            ),
            Divider(color: theme.dividerColor, height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _FieldRow(
                        children: <Widget>[
                          _Field(
                            label: 'Contact name *',
                            controller: _contact,
                            hint: 'Who you spoke to',
                            validator: (String? v) =>
                                (v == null || v.trim().isEmpty)
                                ? 'Name is required'
                                : null,
                          ),
                          _Field(
                            label: 'Phone *',
                            controller: _phone,
                            hint: '+91 98200 00000',
                            keyboardType: TextInputType.phone,
                            // Same rule as the server: optional +, 8-15
                            // digits, spaces or dashes between groups.
                            validator: (String? v) {
                              final String s = (v ?? '').trim();
                              if (s.isEmpty) return 'Phone is required';
                              return RegExp(r'^\+?(?:[ -]?\d){8,15}$').hasMatch(s)
                                  ? null
                                  : 'Enter a valid phone number (8-15 digits)';
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _FieldRow(
                        children: <Widget>[
                          _Field(
                            label: 'Company',
                            controller: _company,
                            hint: 'Spice Route Cafe',
                          ),
                          _Field(
                            label: 'Designation',
                            controller: _designation,
                            hint: 'Owner, marketing head...',
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _FieldRow(
                        children: <Widget>[
                          _Field(
                            label: 'Email',
                            controller: _email,
                            hint: 'name@company.com',
                            keyboardType: TextInputType.emailAddress,
                            validator: (String? v) {
                              final String s = (v ?? '').trim();
                              if (s.isEmpty) return null;
                              return s.contains('@') && s.contains('.')
                                  ? null
                                  : 'Enter a valid email';
                            },
                          ),
                          _Field(
                            label: 'City',
                            controller: _city,
                            hint: 'Kolhapur',
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _FieldRow(
                        children: <Widget>[
                          _Select<String?>(
                            label: 'Industry',
                            value: _industry,
                            items: <String?>[
                              null,
                              ...CompanyProfile.industryLabels.keys,
                            ],
                            labelOf: (String? k) => k == null
                                ? '-'
                                : CompanyProfile.industryLabels[k]!,
                            onChanged: (String? v) =>
                                setState(() => _industry = v),
                          ),
                          _Select<String?>(
                            label: 'What do they want built?',
                            value: _projectType,
                            items: <String?>[
                              null,
                              ...CompanyProfile.projectTypeLabels.keys,
                            ],
                            labelOf: (String? k) => k == null
                                ? '-'
                                : CompanyProfile.projectTypeLabels[k]!,
                            onChanged: (String? v) =>
                                setState(() => _projectType = v),
                          ),
                        ],
                      ),
                      if (_appTypes.contains(_projectType)) ...<Widget>[
                        const SizedBox(height: AppSpacing.lg),
                        _Select<String?>(
                          label: 'Platforms',
                          value: _platforms,
                          items: const <String?>[null, 'android', 'ios', 'both'],
                          labelOf: (String? k) => switch (k) {
                            'android' => 'Android',
                            'ios' => 'iOS',
                            'both' => 'Android + iOS',
                            _ => '-',
                          },
                          onChanged: (String? v) =>
                              setState(() => _platforms = v),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      _FieldRow(
                        children: <Widget>[
                          _Select<String>(
                            label: 'Source',
                            value: _source,
                            items: CompanyProfile.leadSourceLabels.keys.toList(),
                            labelOf: (String k) =>
                                CompanyProfile.leadSourceLabels[k]!,
                            onChanged: (String? v) =>
                                setState(() => _source = v ?? _source),
                          ),
                          _Select<String>(
                            label: 'Priority',
                            value: _priority,
                            items: const <String>['hot', 'warm', 'cold'],
                            labelOf: (String k) =>
                                '${k[0].toUpperCase()}${k.substring(1)}',
                            onChanged: (String? v) =>
                                setState(() => _priority = v ?? _priority),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _FieldRow(
                        children: <Widget>[
                          _Field(
                            label: 'Their budget (₹)',
                            controller: _budget,
                            hint: 'If they mentioned one',
                            keyboardType: TextInputType.number,
                            validator: (String? v) {
                              final String s = (v ?? '').trim();
                              if (s.isEmpty) return null;
                              return double.tryParse(s) == null
                                  ? 'Numbers only'
                                  : null;
                            },
                          ),
                          _Select<String?>(
                            label: 'Assign to *',
                            value: _repId,
                            items: <String?>[
                              null,
                              for (final SalesRep r in widget.reps) r.id,
                            ],
                            labelOf: (String? id) => id == null
                                ? 'Pick a rep'
                                : widget.reps
                                      .firstWhere((SalesRep r) => r.id == id)
                                      .name,
                            onChanged: (String? v) =>
                                setState(() => _repId = v),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _Field(
                        label: 'Requirement',
                        controller: _requirement,
                        hint: 'Pages, features, what the site/app must do',
                        lines: 2,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _Field(
                        label: 'Notes',
                        controller: _notes,
                        hint: 'Anything the rep should know before calling',
                        lines: 2,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Divider(color: theme.dividerColor, height: 1),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  FilledButton(
                    onPressed: _submit,
                    child: const Text('Create and assign'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        if (c.maxWidth < 460) {
          return Column(
            children: <Widget>[
              children[0],
              const SizedBox(height: AppSpacing.lg),
              children[1],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: children[0]),
            const SizedBox(width: AppSpacing.lg),
            Expanded(child: children[1]),
          ],
        );
      },
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.hint,
    this.validator,
    this.keyboardType,
    this.lines = 1,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final int lines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: AppSpacing.xs),
        TextFormField(
          controller: controller,
          validator: validator,
          keyboardType: keyboardType,
          maxLines: lines,
          decoration: InputDecoration(hintText: hint),
        ),
      ],
    );
  }
}

class _Select<T> extends StatelessWidget {
  const _Select({
    required this.label,
    required this.value,
    required this.items,
    required this.labelOf,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> items;
  final String Function(T) labelOf;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: AppSpacing.xs),
        DropdownButtonFormField<T>(
          initialValue: value,
          isExpanded: true,
          items: <DropdownMenuItem<T>>[
            for (final T i in items)
              DropdownMenuItem<T>(value: i, child: Text(labelOf(i))),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }
}
