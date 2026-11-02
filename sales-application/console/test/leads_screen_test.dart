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
import 'package:sales_admin_console/features/leads/leads_screen.dart';

/// A lead row as the API sends it, with only what a test cares about set.
Map<String, dynamic> _row(
  int id,
  String name,
  String status, {
  String value = '100000.00',
  String paid = '0.00',
  String required = '30000.00',
  String? share = '0.30',
  int? customer,
  String lostReason = '',
  List<Map<String, dynamic>> stageChanges = const <Map<String, dynamic>>[],
}) => <String, dynamic>{
  'id': id,
  'name': name,
  'company_name': name,
  'phone': '90000000$id',
  'status': status,
  'source': 'referral',
  'value': value,
  'amount_paid': paid,
  'deposit_required': required,
  'deposit_share': ?share,
  'converted_customer': customer,
  'lost_reason': lostReason,
  'stage_changes': stageChanges,
  'created_at': '2026-09-20T10:00:00Z',
  'updated_at': '2026-09-2${id}T10:00:00Z',
};

void main() {
  group('a lead row from the API', () {
    test('carries the money, the customer it became, and its steps back', () {
      final Lead lead = Mappers.leadFrom(
        _row(
          1,
          'Om Gym',
          'converted',
          paid: '40000.00',
          customer: 7,
          stageChanges: <Map<String, dynamic>>[
            <String, dynamic>{
              'from_status': 'closed',
              'to_status': 'demo',
              'changed_by_name': 'priya',
              'reason': 'They called back',
              'changed_at': '2026-09-25T09:00:00Z',
            },
          ],
        ),
      );
      expect(lead.amountPaid, 40000);
      expect(lead.depositRequired, 30000);
      expect(lead.customerId, '7');
      expect(lead.stageChanges.single.fromStage, 'Lost');
      expect(lead.stageChanges.single.toStage, 'Demo');
      expect(lead.stageChanges.single.reason, 'They called back');
    });

    test('works out what is still to pay before converting', () {
      final Lead lead = Mappers.leadFrom(
        _row(2, 'Vertex', 'proposal', paid: '10000.00', share: '0.50',
            required: '50000.00'),
      );
      expect(lead.depositShare, 0.5);
      expect(lead.depositOutstanding, 40000);
    });

    test('an older server with no deposit share means 30%', () {
      final Lead lead = Mappers.leadFrom(_row(3, 'Old', 'new', share: null));
      expect(lead.depositShare, 0.30);
    });
  });

  group('the Leads screen', () {
    Future<void> show(
      WidgetTester tester, {
      List<Customer> customers = const <Customer>[],
    }) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final CompanySnapshot co = CompanySnapshot(
        admins: const <AdminUser>[],
        reps: const <SalesRep>[],
        leads: <Lead>[
          Mappers.leadFrom(_row(1, 'Open Deal', 'proposal', paid: '10000.00')),
          Mappers.leadFrom(_row(2, 'Became Customer', 'converted', customer: 9)),
          Mappers.leadFrom(
            _row(3, 'Went Elsewhere', 'closed', lostReason: 'other_agency'),
          ),
        ],
        customers: customers,
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
            home: const Scaffold(body: LeadsScreen()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
    }

    testWidgets('lists open leads only, until customers & lost are shown', (
      WidgetTester tester,
    ) async {
      await show(tester);
      expect(find.text('Open Deal'), findsOneWidget);
      expect(find.text('Became Customer'), findsNothing);
      expect(find.text('Went Elsewhere'), findsNothing);

      await tester.tap(find.text('Show customers & lost'));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Became Customer'), findsOneWidget);
      expect(find.text('Went Elsewhere'), findsOneWidget);
      // Why it was lost, in the list itself (#36).
      expect(find.text('Went with another agency'), findsOneWidget);
    });

    testWidgets('a lead shows what was paid and what is still needed', (
      WidgetTester tester,
    ) async {
      await show(tester);
      expect(find.text('paid ₹10K'), findsOneWidget);

      await tester.tap(find.text('Open Deal'));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('MONEY'), findsOneWidget);
      expect(find.textContaining('before converting'), findsOneWidget);
    });

    testWidgets('a lost lead offers Reopen; a customer links to itself', (
      WidgetTester tester,
    ) async {
      await show(tester);
      await tester.tap(find.text('Show customers & lost'));
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.text('Went Elsewhere'));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Reopen'), findsOneWidget);
      expect(find.text('Open customer'), findsNothing);

      await tester.tap(find.text('Became Customer'));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Open customer'), findsOneWidget);
      expect(find.text('Reopen'), findsNothing);
    });

    testWidgets("a customer's lead shows the customer's current contact", (
      WidgetTester tester,
    ) async {
      // Edited on the customer after the sale; the lead's copy is old (#52).
      final Customer now = Customer.fromJson(<String, dynamic>{
        'id': 9,
        'name': 'New Contact',
        'company_name': 'Became Customer',
        'phone': '9999999999',
        'is_active': true,
      });
      await show(tester, customers: <Customer>[now]);
      await tester.tap(find.text('Show customers & lost'));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Became Customer'));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('CONTACT (ON THE CUSTOMER)'), findsOneWidget);
      expect(find.text('9999999999'), findsOneWidget);
    });
  });
}
