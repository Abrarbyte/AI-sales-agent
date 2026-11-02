import 'package:flutter/material.dart';

import '../theme.dart';

/// The bottom-sheet form every action in the app uses: drag handle, a title
/// row with a close button, a scrolling body, and a Cancel / Save footer.
///
/// One widget, so "Mark demo given", "Open negotiation", "Schedule delivery"
/// and the rest look and behave identically - the screens only describe
/// their fields and what to send.
class FormSheet extends StatelessWidget {
  const FormSheet({
    super.key,
    required this.title,
    required this.children,
    required this.onSave,
    this.saveLabel = 'Save',
    this.saving = false,
    this.error,
    this.destructive = false,
  });

  final String title;
  final List<Widget> children;
  final VoidCallback? onSave;
  final String saveLabel;
  final bool saving;
  final String? error;

  /// A red save button, for "Close lead" and the like.
  final bool destructive;

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
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 8),
              child: Container(
                width: 48,
                height: 6,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 0, 8, 16),
              decoration: BoxDecoration(
                border: Border(
                    bottom: BorderSide(
                        color: scheme.outlineVariant.withValues(alpha: 0.3))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(title,
                        style: AppTheme.headlineMd
                            .copyWith(color: scheme.onSurface)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    color: scheme.onSurfaceVariant,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...children,
                    if (error != null) ...[
                      const SizedBox(height: 16),
                      Text(error!,
                          style: AppTheme.sans(14, 400, 20,
                              color: scheme.error)),
                    ],
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            Container(
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
                      onPressed:
                          saving ? null : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: saving ? null : onSave,
                      style: destructive
                          ? FilledButton.styleFrom(
                              backgroundColor: scheme.error,
                              foregroundColor: scheme.onError)
                          : null,
                      child: saving
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: destructive
                                      ? scheme.onError
                                      : scheme.onPrimary),
                            )
                          : Text(saveLabel),
                    ),
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

/// Opens a [FormSheet]-based widget the standard way and returns its result.
Future<T?> showFormSheet<T>(BuildContext context, Widget sheet) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => sheet,
    );

/// The small tracked-out label above a field.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(text.toUpperCase(),
          style: AppTheme.labelSm.copyWith(color: scheme.onSurfaceVariant)),
    );
  }
}

/// Label + text field.
class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.label,
    required this.controller,
    this.hint = '',
    this.icon,
    this.lines = 1,
    this.keyboardType,
    this.textInputAction,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final IconData? icon;
  final int lines;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(label),
        TextField(
          controller: controller,
          maxLines: lines,
          keyboardType: keyboardType ??
              (lines > 1 ? TextInputType.multiline : null),
          textInputAction: textInputAction,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: icon == null ? null : Icon(icon, size: 20),
            alignLabelWithHint: lines > 1,
          ),
        ),
      ],
    );
  }
}

/// Label + a row of choice pills. One value at a time.
class ChoiceRow<T> extends StatelessWidget {
  const ChoiceRow({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final String label;

  /// (value, label) pairs, in display order.
  final List<(T, String)> options;
  final T? value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(label),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (v, text) in options)
              GestureDetector(
                onTap: () => onChanged(v),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: v == value
                        ? scheme.primary
                        : scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                        color: v == value
                            ? scheme.primary
                            : scheme.outlineVariant),
                  ),
                  child: Text(text,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: v == value
                            ? scheme.onPrimary
                            : scheme.onSurface,
                      )),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Label + a tappable date row that opens the picker.
class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.allowClear = false,
    this.firstDate,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final bool allowClear;
  final DateTime? firstDate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(label),
        InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          onTap: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: value ?? now,
              firstDate: firstDate ?? DateTime(now.year - 1),
              lastDate: DateTime(now.year + 2),
            );
            if (picked != null) onChanged(picked);
          },
          child: InputDecorator(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.event_outlined, size: 20),
              suffixIcon: allowClear && value != null
                  ? IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => onChanged(null))
                  : null,
            ),
            child: Text(
              value == null ? 'Not set' : fmtDate(value!),
              style: TextStyle(
                  fontSize: 15,
                  color: value == null
                      ? scheme.onSurfaceVariant
                      : scheme.onSurface),
            ),
          ),
        ),
      ],
    );
  }

}

/// "15 Sep 2026" - the short date used across the detail screens.
String fmtDate(DateTime d) =>
    '${d.day} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]} ${d.year}';

/// YYYY-MM-DD, what the API wants for a DateField.
String apiDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Label + switch on one row.
class ToggleRow extends StatelessWidget {
  const ToggleRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: AppTheme.bodyMd.copyWith(color: scheme.onSurface)),
              if (hint != null)
                Text(hint!,
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}
