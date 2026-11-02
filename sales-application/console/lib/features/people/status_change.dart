import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../../data/api/api_client.dart';
import '../../data/models/common.dart';
import '../../data/models/people.dart';
import '../../data/providers.dart';
import '../../data/repositories/company_repository.dart';

/// Deactivate or reactivate someone - an admin, a manager or a rep.
///
/// Deactivating asks who takes over their open leads, booked follow-ups,
/// customers and handovers (#24). If they have some and nobody is chosen,
/// the server refuses and says what's still open; that message is shown.
/// Shared by the Admins and Sales reps screens, so both ask the same (#40).
///
/// [note] is a line about what else happens, e.g. an admin's reps staying on
/// their team. Returns whether anything changed.
Future<bool> changePersonStatus(
  BuildContext context,
  WidgetRef ref, {
  required String id,
  required String name,
  required bool isActive,
  required CompanySnapshot co,
  String? note,
}) async {
  final bool deactivating = isActive;
  // Who can take over their open work: every other active person.
  final List<(String, String)> successors = <(String, String)>[
    for (final AdminUser a in co.admins)
      if (a.id != id && a.status == EntityStatus.active) (a.id, a.name),
    for (final SalesRep r in co.activeReps)
      if (r.id != id) (r.id, r.name),
  ];
  String? transferTo;

  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => StatefulBuilder(
      builder: (BuildContext context, StateSetter setDialog) => AlertDialog(
        title: Text(deactivating ? 'Deactivate $name?' : 'Reactivate $name?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              deactivating
                  ? 'They lose access immediately.${note == null ? '' : ' $note'}'
                  : 'They can sign in again right away.${note == null ? '' : ' $note'}',
            ),
            if (deactivating) ...<Widget>[
              const SizedBox(height: 16),
              const Text(
                'Any open leads, booked follow-ups, customers and '
                'handovers they own go to:',
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                initialValue: transferTo,
                isExpanded: true,
                items: <DropdownMenuItem<String?>>[
                  const DropdownMenuItem<String?>(
                    child: Text('Nobody - they have no open work'),
                  ),
                  for (final (String sid, String sname) in successors)
                    DropdownMenuItem<String?>(value: sid, child: Text(sname)),
                ],
                onChanged: (String? v) => setDialog(() => transferTo = v),
              ),
            ],
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: deactivating
                ? FilledButton.styleFrom(
                    backgroundColor: VizPalette.statusCritical,
                  )
                : null,
            child: Text(deactivating ? 'Deactivate' : 'Reactivate'),
          ),
        ],
      ),
    ),
  );

  if (ok != true) return false;

  final CompanyRepository repo = ref.read(companyRepositoryProvider);
  try {
    // DELETE deactivates rather than removes, so history survives.
    if (deactivating) {
      await repo.deactivateEmployee(id, transferTo: transferTo);
    } else {
      await repo.reactivateEmployee(id);
    }
  } on ApiException catch (e) {
    if (!context.mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(e.message),
        backgroundColor: VizPalette.statusCritical,
      ),
    );
    return false;
  }
  ref.invalidate(companyProvider);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(deactivating ? '$name deactivated' : '$name reactivated'),
      ),
    );
  }
  return true;
}
