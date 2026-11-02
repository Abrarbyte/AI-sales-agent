import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_admin_console/core/theme/app_theme.dart';
import 'package:sales_admin_console/data/api/mappers.dart';
import 'package:sales_admin_console/data/models/customer.dart';
import 'package:sales_admin_console/data/models/delivery.dart';
import 'package:sales_admin_console/data/models/lead.dart';
import 'package:sales_admin_console/data/models/people.dart';
import 'package:sales_admin_console/data/providers.dart';
import 'package:sales_admin_console/data/repositories/company_repository.dart';
import 'package:sales_admin_console/features/reps/reps_screen.dart';

SalesRep _rep(String id, String username, {bool active = true}) =>
    Mappers.repFromUser(
      <String, dynamic>{
        'id': id,
        'username': username,
        'full_name': 'Ravi Kale',
        'email': 'ravi@example.com',
        'is_active': active,
        'role': 'employee',
        'date_joined': '2026-09-01T00:00:00Z',
      },
      adminId: '1',
      assignedLeads: 0,
      openLeads: 0,
      wonLeads: 0,
      visitsThisMonth: 0,
      visitComplianceRate: 0,
      revenueThisPeriod: 0,
    );

void main() {
  test('a person keeps their username, through a copy too', () {
    final SalesRep rep = _rep('7', 'ravi.kale');
    expect(rep.username, 'ravi.kale');
    expect(rep.copyWith(branch: 'Pune').username, 'ravi.kale');
    expect(
      rep.withLeadCounters(assigned: 1, open: 1, won: 0).username,
      'ravi.kale',
    );
  });

  testWidgets('the reps list shows usernames and offers Deactivate', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final CompanySnapshot co = CompanySnapshot(
      admins: const <AdminUser>[],
      reps: <SalesRep>[_rep('7', 'ravi.kale')],
      leads: const <Lead>[],
      customers: const <Customer>[],
      deliveries: const <Delivery>[],
      visitRows: const <Map<String, dynamic>>[],
      loadedAt: DateTime(2026, 9, 29),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          companyProvider.overrideWith((Ref ref) async => co),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: RepsScreen()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    // Shown nowhere before (#39).
    expect(find.text('ravi.kale - ravi@example.com'), findsOneWidget);

    // Reps had no Deactivate in the console (#40).
    await tester.tap(find.byTooltip('Actions'));
    // The menu animates open, then takes taps.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Deactivate'), findsOneWidget);

    await tester.tap(find.text('Deactivate'));
    // The menu closes, then the dialog opens: a frame for each.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Deactivate Ravi Kale?'), findsOneWidget);
    expect(find.text('Nobody - they have no open work'), findsOneWidget);
  });
}
