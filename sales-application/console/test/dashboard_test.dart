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
import 'package:sales_admin_console/features/dashboard/dashboard_screen.dart';

/// A lead that became a customer [daysAgo] days ago for [value].
Lead _won(int id, int daysAgo, String value) {
  final String at = DateTime.now()
      .subtract(Duration(days: daysAgo))
      .toIso8601String();
  return Mappers.leadFrom(<String, dynamic>{
    'id': id,
    'name': 'Client $id',
    'phone': '900000000$id',
    'status': 'converted',
    'converted_customer': id,
    'value': value,
    'converted_at': at,
    'created_at': at,
    'updated_at': at,
  });
}

/// The dashboard, as [role] (Django's code) would see it.
Future<void> _pumpAs(WidgetTester tester, String role, CompanySnapshot co) async {
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        companyProvider.overrideWith((Ref ref) async => co),
        currentUserProvider.overrideWith(
          (Ref ref) async => SignedInUser(id: '1', name: 'Test', roleLabel: role, role: role),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: DashboardScreen()),
      ),
    ),
  );
  // Two gates now (who is signed in, then the data), each a frame to resolve,
  // then the cards' staggered entrance.
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(seconds: 2));
  await tester.pump(const Duration(seconds: 2));
}

CompanySnapshot _snapshot() => CompanySnapshot(
      admins: const <AdminUser>[],
      reps: const <SalesRep>[],
      leads: <Lead>[
        _won(1, 1, '500000.00'), // this period
        _won(2, 20, '250000.00'), // the period before
      ],
      customers: const <Customer>[],
      deliveries: const <Delivery>[],
      visitRows: const <Map<String, dynamic>>[],
      loadedAt: DateTime.now(),
    );

void main() {
  testWidgets('revenue doubling reads +100%, not +10000%', (
    WidgetTester tester,
  ) async {
    // The dashboard looks back 14 days, and compares with the 14 before.
    await _pumpAs(tester, 'admin', _snapshot());

    // Revenue booked and average deal size both doubled. They were shown a
    // hundred times too big: the change was a percentage, then formatted by
    // a helper that multiplies by 100 again (#80).
    expect(find.text('+100.0%'), findsNWidgets(2));
    expect(find.text('+10000.0%'), findsNothing);
  });

  group('each role has its own dashboard', () {
    testWidgets('the Super Admin sees the whole company, team by team', (
      WidgetTester tester,
    ) async {
      await _pumpAs(tester, 'super_admin', _snapshot());
      expect(find.text('Company overview'), findsOneWidget);
      expect(find.text('Teams'), findsOneWidget);
      expect(find.text('Top reps'), findsNothing);
    });

    testWidgets('an Admin sees the branch: reps and the field today', (
      WidgetTester tester,
    ) async {
      await _pumpAs(tester, 'admin', _snapshot());
      expect(find.text('Branch overview'), findsOneWidget);
      expect(find.text('Top reps'), findsOneWidget);
      expect(find.text('Today in the field'), findsOneWidget);
      expect(find.text('Teams'), findsNothing);
    });

    testWidgets('a Manager sees their team and its follow-ups, not the company', (
      WidgetTester tester,
    ) async {
      await _pumpAs(tester, 'manager', _snapshot());
      expect(find.text('My team'), findsOneWidget);
      expect(find.text('Team revenue'), findsOneWidget);
      expect(find.text('Follow-ups due'), findsOneWidget);
      expect(find.text('Teams'), findsNothing);
      expect(find.text('Earning summary'), findsNothing);
    });
  });
}
