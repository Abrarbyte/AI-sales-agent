import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/company_profile.dart';
import '../../core/theme/app_palette.dart';
import '../../data/api/api_client.dart';
import '../../data/providers.dart';
import '../../data/repositories/company_repository.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/customer.dart';
import '../../data/models/people.dart';

/// A product from the catalogue, as the dialog needs it.
typedef ProductOption = ({String id, String name});

/// Schedules a handover milestone from the console (#44) - the same request
/// the phone app makes. Returns the POST body, or null if cancelled.
///
/// Opened from the Handovers screen (pick the customer) or from a customer's
/// details (already picked).
class ScheduleMilestoneDialog extends StatefulWidget {
  const ScheduleMilestoneDialog({
    super.key,
    required this.customers,
    required this.reps,
    required this.products,
    this.customerId,
  });

  final List<Customer> customers;
  final List<SalesRep> reps;
  final List<ProductOption> products;
  final String? customerId;

  @override
  State<ScheduleMilestoneDialog> createState() =>
      _ScheduleMilestoneDialogState();
}

class _ScheduleMilestoneDialogState extends State<ScheduleMilestoneDialog> {
  late String? _customerId = widget.customerId;
  String _milestone = 'design_approval';
  late String? _productId = widget.products.length == 1
      ? widget.products.first.id
      : null;
  String? _repId;
  DateTime _on = DateTime.now().add(const Duration(days: 7));
  bool _signOff = true;
  final TextEditingController _notes = TextEditingController();

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final List<Customer> customers =
        widget.customers.where((Customer c) => c.isActive).toList()..sort(
          (Customer a, Customer b) => a.displayName.compareTo(b.displayName),
        );
    final bool ready = _customerId != null && _productId != null;

    return AlertDialog(
      title: const Text('Schedule a milestone'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              DropdownButtonFormField<String>(
                initialValue: _customerId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Customer'),
                items: <DropdownMenuItem<String>>[
                  for (final Customer c in customers)
                    DropdownMenuItem<String>(
                      value: c.id,
                      child: Text(c.displayName),
                    ),
                ],
                onChanged: widget.customerId != null
                    ? null
                    : (String? v) => setState(() => _customerId = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _milestone,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Milestone'),
                items: <DropdownMenuItem<String>>[
                  for (final MapEntry<String, String> m
                      in CompanyProfile.milestoneLabels.entries)
                    DropdownMenuItem<String>(
                      value: m.key,
                      child: Text(m.value),
                    ),
                ],
                onChanged: (String? v) =>
                    setState(() => _milestone = v ?? _milestone),
              ),
              const SizedBox(height: 12),
              if (widget.products.isEmpty)
                const Text(
                  'There are no products yet. Add one in Configuration first.',
                )
              else
                DropdownButtonFormField<String>(
                  initialValue: _productId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Project'),
                  items: <DropdownMenuItem<String>>[
                    for (final ProductOption p in widget.products)
                      DropdownMenuItem<String>(
                        value: p.id,
                        child: Text(p.name),
                      ),
                  ],
                  onChanged: (String? v) => setState(() => _productId = v),
                ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final DateTime? picked = await showDatePicker(
                          context: context,
                          initialDate: _on,
                          firstDate: DateTime.now().subtract(
                            const Duration(days: 1),
                          ),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                        );
                        if (picked != null) setState(() => _on = picked);
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(labelText: 'Date'),
                        child: Text(Fmt.date(_on)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      initialValue: _repId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Owner'),
                      items: <DropdownMenuItem<String?>>[
                        // The server gives it to the customer's rep.
                        const DropdownMenuItem<String?>(
                          child: Text("The customer's rep"),
                        ),
                        for (final SalesRep r in widget.reps)
                          DropdownMenuItem<String?>(
                            value: r.id,
                            child: Text(r.name),
                          ),
                      ],
                      onChanged: (String? v) => setState(() => _repId = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _signOff,
                onChanged: (bool? v) => setState(() => _signOff = v ?? true),
                title: const Text('Needs the client to sign off'),
              ),
              TextField(
                controller: _notes,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  hintText: 'What to bring, who to ask for',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: ready
              ? () => Navigator.of(context).pop(<String, dynamic>{
                  'customer': int.tryParse(_customerId!),
                  'product': int.tryParse(_productId!),
                  'milestone': _milestone,
                  'scheduled_on': _date(_on),
                  'required': _signOff,
                  if (_repId != null) 'assigned_to': int.tryParse(_repId!),
                  'notes': _notes.text.trim(),
                })
              : null,
          child: const Text('Schedule'),
        ),
      ],
    );
  }
}

/// Opens the dialog and schedules what it returns, with a message either
/// way. Shared by the Handovers screen and a customer's details.
Future<void> scheduleMilestone(
  BuildContext context,
  WidgetRef ref,
  CompanySnapshot co, {
  String? customerId,
}) async {
  final List<ProductOption> products;
  try {
    products = await ref.read(deliveryRepositoryProvider).products();
  } on ApiException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: VizPalette.statusCritical,
        ),
      );
    }
    return;
  }
  if (!context.mounted) return;
  final Map<String, dynamic>? body = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (_) => ScheduleMilestoneDialog(
      customers: co.customers,
      reps: co.activeReps,
      products: products,
      customerId: customerId,
    ),
  );
  if (body == null) return;
  try {
    await ref.read(deliveryRepositoryProvider).schedule(body);
  } on ApiException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not schedule it: ${e.message}'),
          backgroundColor: VizPalette.statusCritical,
        ),
      );
    }
    return;
  }
  ref.invalidate(companyProvider);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${CompanyProfile.milestoneLabels[body['milestone']] ?? 'Milestone'} '
          'scheduled for ${Fmt.date(DateTime.parse(body['scheduled_on'] as String))}',
        ),
      ),
    );
  }
}
