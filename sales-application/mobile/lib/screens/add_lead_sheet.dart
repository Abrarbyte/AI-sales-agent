import 'package:flutter/material.dart';

import '../api.dart';
import '../pipeline_labels.dart';
import '../theme.dart';
import '../widgets/form_sheet.dart';
import 'lead_detail_screen.dart';

/// A port of the Stitch design "Add Lead": a bottom sheet with a drag handle,
/// five fields and a Cancel / Save Lead footer.
///
/// The design marks Name and Phone with an asterisk, which is exactly what the
/// `Lead` model requires — every other contact field is `blank=True`. So the
/// form and the database agree without either being bent to fit.
///
/// The design's Source list (Website Form, Cold Call, Industry Event…) does not
/// match the model's choices, and the model's win: `field_visit` matters for a
/// field-sales product and the design has no equivalent, while "Industry Event"
/// would need a migration to gain nothing.
class AddLeadSheet extends StatefulWidget {
  const AddLeadSheet({super.key});

  @override
  State<AddLeadSheet> createState() => _AddLeadSheetState();
}

class _AddLeadSheetState extends State<AddLeadSheet> {
  static const _sources = PipelineLabels.sources;

  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _company = TextEditingController();
  final _designation = TextEditingController();
  final _city = TextEditingController();
  final _requirement = TextEditingController();
  final _existingUrl = TextEditingController();
  final _budget = TextEditingController();

  String _source = 'field_visit';
  String? _projectType;
  String? _platforms;
  String? _industry;
  String _priority = 'warm';
  bool _saving = false;
  String? _error;

  /// The open lead this number is already on, when the server refused a
  /// duplicate and the rep may open it (#30).
  int? _existingLeadId;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _company.dispose();
    _designation.dispose();
    _city.dispose();
    _requirement.dispose();
    _existingUrl.dispose();
    _budget.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _phone.text.trim().isEmpty) {
      setState(() => _error = 'A name and a phone number are required.');
      return;
    }
    // Same rule as the server: optional +, 8-15 digits, spaces/dashes ok.
    if (!RegExp(r'^\+?(?:[ -]?\d){8,15}$').hasMatch(_phone.text.trim())) {
      setState(() => _error = 'Enter a valid phone number (8-15 digits).');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
      _existingLeadId = null;
    });
    try {
      final lead = await Api.instance.post('/api/crm/leads/', {
        'name': _name.text.trim(),
        'phone': _phone.text.trim(),
        'company_name': _company.text.trim(),
        'designation': _designation.text.trim(),
        'city': _city.text.trim(),
        'requirement': _requirement.text.trim(),
        'source': _source,
        'project_type': _projectType ?? '',
        'platforms':
            PipelineLabels.appTypes.contains(_projectType) ? (_platforms ?? '') : '',
        'industry': _industry ?? '',
        'existing_url': _existingUrl.text.trim(),
        'budget': _budget.text.trim().isEmpty ? null : _budget.text.trim(),
        'priority': _priority,
      });
      if (!mounted) return;
      Navigator.of(context).pop(lead);
    } on ApiException catch (e) {
      final duplicate = e.body?['duplicate'];
      setState(() {
        _error = e.message;
        _existingLeadId = duplicate is Map && duplicate['kind'] == 'lead'
            ? int.tryParse('${duplicate['id']}')
            : null;
      });
    } catch (_) {
      setState(() => _error = 'Cannot reach the server.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppTheme.radiusXl)),
      ),
      padding:
          EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _handle(scheme),
            _header(scheme),
            Flexible(child: _form(scheme)),
            _footer(scheme),
          ],
        ),
      ),
    );
  }

  Widget _handle(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Container(
        width: 48, // w-12 h-1.5
        height: 6,
        decoration: BoxDecoration(
          color: scheme.outlineVariant.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }

  Widget _header(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 0, 8, 16),
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.3))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text('Add New Lead',
                style: AppTheme.headlineMd.copyWith(color: scheme.onSurface)),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            color: scheme.onSurfaceVariant,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _form(ColorScheme scheme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _field(scheme,
              label: 'Name *',
              controller: _name,
              hint: 'John Doe',
              icon: Icons.person_outline,
              textInputAction: TextInputAction.next),
          const SizedBox(height: 20),
          _field(scheme,
              label: 'Phone *',
              controller: _phone,
              hint: '(555) 123-4567',
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next),
          const SizedBox(height: 20),
          _field(scheme,
              label: 'Company',
              controller: _company,
              hint: 'Ravi Cafe',
              icon: Icons.domain_outlined,
              textInputAction: TextInputAction.next),
          const SizedBox(height: 20),
          _field(scheme,
              label: 'Designation',
              controller: _designation,
              hint: 'Owner, marketing head...',
              icon: Icons.badge_outlined,
              textInputAction: TextInputAction.next),
          const SizedBox(height: 20),
          _label(scheme, 'Industry'),
          DropdownButtonFormField<String>(
            initialValue: _industry,
            isExpanded: true,
            hint: const Text('What business are they in?'),
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.storefront_outlined, size: 20)),
            items: [
              for (final (value, label) in PipelineLabels.industries)
                DropdownMenuItem(value: value, child: Text(label)),
            ],
            onChanged: (value) => setState(() => _industry = value),
          ),
          const SizedBox(height: 20),
          ChoiceRow<String>(
            label: 'What do they want built?',
            options: PipelineLabels.projectTypes,
            value: _projectType,
            onChanged: (v) => setState(() => _projectType = v),
          ),
          if (PipelineLabels.appTypes.contains(_projectType)) ...[
            const SizedBox(height: 20),
            ChoiceRow<String>(
              label: 'Platforms',
              options: PipelineLabels.platforms,
              value: _platforms,
              onChanged: (v) => setState(() => _platforms = v),
            ),
          ],
          const SizedBox(height: 20),
          _field(scheme,
              label: 'Existing website / app',
              controller: _existingUrl,
              hint: 'https://... (if they have one)',
              icon: Icons.link_outlined,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next),
          const SizedBox(height: 20),
          _field(scheme,
              label: 'Their budget (₹)',
              controller: _budget,
              hint: 'If they mentioned one',
              icon: Icons.currency_rupee,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next),
          const SizedBox(height: 20),
          ChoiceRow<String>(
            label: 'Priority',
            options: PipelineLabels.priorities,
            value: _priority,
            onChanged: (v) => setState(() => _priority = v),
          ),
          const SizedBox(height: 20),
          _field(scheme,
              label: 'City',
              controller: _city,
              hint: 'New York',
              icon: Icons.location_city_outlined,
              textInputAction: TextInputAction.next),
          const SizedBox(height: 20),
          _field(scheme,
              label: 'Requirement / interest',
              controller: _requirement,
              hint: 'Pages, features, what the site/app must do',
              icon: Icons.lightbulb_outline,
              textInputAction: TextInputAction.done),
          const SizedBox(height: 20),
          _label(scheme, 'Source'),
          DropdownButtonFormField<String>(
            initialValue: _source,
            isExpanded: true,
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.campaign_outlined, size: 20)),
            items: [
              for (final (value, label) in _sources)
                DropdownMenuItem(value: value, child: Text(label)),
            ],
            onChanged: (value) => setState(() => _source = value ?? _source),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!,
                style: AppTheme.sans(14, 400, 20, color: scheme.error)),
          ],
          if (_existingLeadId != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Open that lead'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) =>
                        LeadDetailScreen(leadId: _existingLeadId!))),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _label(ColorScheme scheme, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4), // gap-[4px]
      child: Text(text.toUpperCase(),
          style: AppTheme.labelSm.copyWith(color: scheme.onSurfaceVariant)),
    );
  }

  Widget _field(
    ColorScheme scheme, {
    required String label,
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(scheme, label),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, size: 20),
          ),
        ),
      ],
    );
  }

  Widget _footer(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: BoxDecoration(
        border: Border(
            top: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.3))),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.2, color: Colors.white),
                    )
                  : const Text('Save Lead'),
            ),
          ),
        ],
      ),
    );
  }
}
