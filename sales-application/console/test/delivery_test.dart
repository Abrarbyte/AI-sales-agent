import 'package:flutter_test/flutter_test.dart';
import 'package:sales_admin_console/data/models/delivery.dart';

void main() {
  test('a delivered milestone keeps both its scheduling and delivery notes',
      () {
    // Delivering used to overwrite the scheduling notes (#45).
    final Delivery d = Delivery.fromJson(<String, dynamic>{
      'id': 1,
      'customer': 2,
      'milestone': 'design_approval',
      'status': 'delivered',
      'scheduled_on': '2026-09-29',
      'notes': 'Bring the signed design brief',
      'outcome_notes': 'Signed off',
    });
    expect(d.notes, 'Bring the signed design brief');
    expect(d.outcomeNotes, 'Signed off');
  });
}
