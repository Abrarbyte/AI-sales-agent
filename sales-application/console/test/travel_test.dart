import 'package:flutter_test/flutter_test.dart';
import 'package:sales_admin_console/data/models/allowance.dart';

/// The backend sends the money figures as strings (DRF DecimalField) and the
/// status as a wire word. These tests pin the parsing and the derived flags the
/// claims table reads, so a shape change on the server is caught here rather
/// than as a blank cell in the console.
Map<String, dynamic> _claim(Map<String, dynamic> overrides) =>
    <String, dynamic>{
      'id': 7,
      'user': 12,
      'username': 'walk_rep',
      'date': '2026-09-23',
      'distance_km': '7.00',
      'rate_per_km': '2.50',
      'amount': '17.50',
      'method': 'straight',
      'is_estimate': false,
      'flagged_legs': <dynamic>[],
      'status': 'pending',
      ...overrides,
    };

void main() {
  group('TravelClaim.fromJson', () {
    test('parses the money figures from their string form', () {
      final TravelClaim c = TravelClaim.fromJson(_claim(<String, dynamic>{}));
      expect(c.repName, 'walk_rep');
      expect(c.distanceKm, 7.0);
      expect(c.ratePerKm, 2.5);
      expect(c.amount, 17.5);
      expect(c.status, ClaimStatus.pending);
      expect(c.needsAttention, isFalse);
    });

    test('a fallback estimate needs attention', () {
      final TravelClaim c = TravelClaim.fromJson(
          _claim(<String, dynamic>{'is_estimate': true}));
      expect(c.isEstimate, isTrue);
      expect(c.needsAttention, isTrue);
    });

    test('a flagged GPS leg needs attention', () {
      final TravelClaim c = TravelClaim.fromJson(_claim(<String, dynamic>{
        'flagged_legs': <dynamic>[
          <String, dynamic>{'leg': 1, 'km': 412.3},
        ],
      }));
      expect(c.flaggedLegs, hasLength(1));
      expect(c.needsAttention, isTrue);
    });

    test('an approved claim is settled and carries the reviewer', () {
      final TravelClaim c = TravelClaim.fromJson(_claim(<String, dynamic>{
        'status': 'approved',
        'approved_by_name': 't_admin',
      }));
      expect(c.status, ClaimStatus.approved);
      expect(c.status.isSettled, isTrue);
      expect(c.approvedByName, 't_admin');
    });

    test('an unknown status falls back to pending, never crashes', () {
      final TravelClaim c = TravelClaim.fromJson(
          _claim(<String, dynamic>{'status': 'something_new'}));
      expect(c.status, ClaimStatus.pending);
    });
  });

  group('ClaimStatus', () {
    test('pending and queried are not settled; approved and rejected are', () {
      expect(ClaimStatus.pending.isSettled, isFalse);
      expect(ClaimStatus.queried.isSettled, isFalse);
      expect(ClaimStatus.approved.isSettled, isTrue);
      expect(ClaimStatus.rejected.isSettled, isTrue);
    });
  });

  group('AllowanceRate.fromJson', () {
    test('parses the rate and effective date', () {
      final AllowanceRate r = AllowanceRate.fromJson(<String, dynamic>{
        'rate_per_km': '2.50',
        'effective_from': '2026-09-23',
        'updated_by_name': 't_admin',
        'note': 'Launch rate',
      });
      expect(r.ratePerKm, 2.5);
      expect(r.effectiveFrom, DateTime(2026, 9, 23));
      expect(r.updatedByName, 't_admin');
    });
  });
}
