import 'package:flutter_test/flutter_test.dart';
import 'package:sales_admin_console/data/models/activity.dart';

void main() {
  test('a visit shows the place name with its coordinates (#91)', () {
    final FieldVisit v = FieldVisit.fromJson(<String, dynamic>{
      'id': 1, 'user': 2, 'username': 'rep', 'target_name': 'Acme',
      'visited_at': '2026-10-10T10:00:00Z', 'outcome': 'interested',
      'lat': '18.559120', 'lng': '73.784210', 'place': 'Baner, Pune',
    });
    expect(v.where, 'Baner, Pune  (18.55912, 73.78421)');
  });

  test('an older visit with no place name shows coordinates', () {
    final FieldVisit v = FieldVisit.fromJson(<String, dynamic>{
      'id': 1, 'visited_at': '2026-10-10T10:00:00Z', 'outcome': 'interested',
      'lat': '18.559120', 'lng': '73.784210',
    });
    expect(v.where, '18.55912, 73.78421');
  });

  test('attendance reads both place names', () {
    final AttendanceDay d = AttendanceDay.fromJson(<String, dynamic>{
      'id': 1, 'date': '2026-10-10', 'kind': 'field',
      'check_in_at': '2026-10-10T09:00:00Z', 'check_in_lat': '18.5',
      'check_in_lng': '73.8', 'check_in_place': 'Baner, Pune',
      'check_out_at': null, 'check_out_place': '', 'is_open': true,
    });
    expect(d.checkInWhere, 'Baner, Pune');
    expect(d.checkOutWhere, isNull); // not checked out: no fix, no name
  });
}
