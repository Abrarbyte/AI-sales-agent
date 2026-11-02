import 'dart:ui' show Size;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_admin_console/data/api/mappers.dart';
import 'package:sales_admin_console/data/models/analytics.dart';
import 'package:sales_admin_console/data/models/common.dart';
import 'package:sales_admin_console/data/models/customer.dart';
import 'package:sales_admin_console/data/models/delivery.dart';
import 'package:sales_admin_console/data/models/lead.dart';
import 'package:sales_admin_console/data/models/people.dart';
import 'package:sales_admin_console/data/providers.dart';
import 'package:sales_admin_console/data/repositories/company_repository.dart';
import 'package:sales_admin_console/features/auth/auth_state.dart';
import 'package:sales_admin_console/main.dart';

/// Two reps under one admin - enough to render every people-facing panel.
CompanySnapshot _snapshot() {
  final DateTime now = DateTime(2026, 9, 1);

  return CompanySnapshot(
    admins: <AdminUser>[
      AdminUser(
        id: '1',
        name: 'Priya Nair',
        email: 'priya@example.com',
        phone: '9000000001',
        branch: 'Pune HQ',
        teamName: 'Demand Generation',
        status: EntityStatus.active,
        repCount: 2,
        activeRepCount: 2,
        permissions: const AdminPermissions(),
        createdAt: now,
        leadsOwned: 12,
        conversionRate: 0.25,
      ),
    ],
    reps: <SalesRep>[
      SalesRep(
        id: '2',
        name: 'Aditi Patil',
        email: 'aditi@example.com',
        phone: '9000000002',
        adminId: '1',
        teamName: 'Demand Generation',
        branch: 'Pune HQ',
        status: EntityStatus.active,
        joinedAt: now,
        assignedLeads: 8,
        openLeads: 5,
        wonLeads: 3,
        revenueThisPeriod: 24000,
      ),
      SalesRep(
        id: '3',
        name: 'Karan Joshi',
        email: 'karan@example.com',
        phone: '9000000003',
        adminId: '1',
        teamName: 'Demand Generation',
        branch: 'Pune HQ',
        status: EntityStatus.active,
        joinedAt: now,
        assignedLeads: 4,
        openLeads: 3,
        wonLeads: 1,
        revenueThisPeriod: 9000,
      ),
    ],
    leads: const <Lead>[],
    customers: const <Customer>[],
    deliveries: const <Delivery>[],
    visitRows: const <Map<String, dynamic>>[],
    loadedAt: now,
  );
}

KpiSnapshot _kpis() => KpiSnapshot(
      totalLeads: 12,
      totalLeadsDelta: 0,
      visitsToday: 3,
      visitsTodayDelta: 0,
      activeAdmins: 1,
      totalAdmins: 1,
      activeReps: 2,
      totalReps: 2,
      conversionRate: 0.33,
      conversionRateDelta: 0,
      pipelineValue: 41000,
      revenueThisPeriod: 33000,
      leadsTrend: const <TrendPoint>[],
      visitsTrend: const <TrendPoint>[],
      conversionTrend: const <TrendPoint>[],
      revenueTrend: const <TrendPoint>[],
      pendingProofCount: 2,
      pendingPayoutCount: 0,
      generatedAt: DateTime(2026, 9, 1),
    );

SignedInUser _signedIn() => const SignedInUser(
      id: '1',
      name: 'Abrar Patel',
      roleLabel: 'Super Admin',
    );

void main() {
  // These render the console itself, so they start signed in; the login
  // screen is what an empty token shows and is not under test here.
  setUp(() => signedIn.value = true);

  testWidgets('dashboard renders once its providers resolve',
      (WidgetTester tester) async {
    // A desktop-sized window, so the sidebar shows its labels rather than
    // collapsing to the icon rail it uses below 900px.
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          companyProvider.overrideWith((Ref ref) async => _snapshot()),
          kpiProvider.overrideWith((Ref ref) async => _kpis()),
          currentUserProvider.overrideWith((Ref ref) async => _signedIn()),
        ],
        child: const SalesAdminConsole(),
      ),
    );
    // Not pumpAndSettle: the hero glow breathes forever by design, so the
    // frame never "settles". Two seconds covers the staggered entrance.
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('Revenue booked'), findsOneWidget);
    expect(find.text('Earning summary'), findsOneWidget);
    expect(find.text('Recent deals'), findsOneWidget);
    // The sidebar lists every section by name.
    expect(find.text('Sales reps'), findsOneWidget);
  });

  testWidgets('a backend that cannot be reached is reported, not a blank page',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          companyProvider.overrideWith(
            (Ref ref) async => throw Exception('Connection refused'),
          ),
          kpiProvider.overrideWith(
            (Ref ref) async => throw Exception('Connection refused'),
          ),
          currentUserProvider.overrideWith(
            (Ref ref) async => throw Exception('Connection refused'),
          ),
        ],
        child: const SalesAdminConsole(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cannot reach the server'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  group('team hierarchy', () {
    Map<String, dynamic> withRole(String role) => <String, dynamic>{
          'id': 1,
          'username': 'someone',
          'role': role,
        };

    // Regression: a `manager` was classified as a rep, so reps reporting to
    // one were parented to somebody missing from the Admins list and their
    // leads rolled up to nobody - the Admins screen read "2/2 reps" beside a
    // three-rep Reps screen.
    test('a manager supervises a team, so counts as an Admin', () {
      expect(Mappers.isAdminRole(withRole('manager')), isTrue);
    });

    test('admins and super admins count as Admins', () {
      expect(Mappers.isAdminRole(withRole('admin')), isTrue);
      expect(Mappers.isAdminRole(withRole('super_admin')), isTrue);
    });

    test('an employee is a rep, not an Admin', () {
      expect(Mappers.isAdminRole(withRole('employee')), isFalse);
    });

    test('an unknown or absent role is never an Admin', () {
      expect(Mappers.isAdminRole(withRole('')), isFalse);
      expect(Mappers.isAdminRole(<String, dynamic>{'id': 1}), isFalse);
    });
  });
}
