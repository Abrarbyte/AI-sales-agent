import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_admin_console/core/theme/app_theme.dart';
import 'package:sales_admin_console/data/models/customer.dart';
import 'package:sales_admin_console/data/models/people.dart';
import 'package:sales_admin_console/features/deliveries/schedule_dialog.dart';

Customer _customer() => Customer.fromJson(<String, dynamic>{
  'id': 5,
  'name': 'Neeta Rane',
  'company_name': 'FreshBox Groceries',
  'phone': '9810000219',
  'is_active': true,
});

void main() {
  testWidgets('scheduling from a customer sends the milestone the server needs',
      (WidgetTester tester) async {
    Map<String, dynamic>? sent;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  sent = await showDialog<Map<String, dynamic>>(
                    context: context,
                    builder: (_) => ScheduleMilestoneDialog(
                      customers: <Customer>[_customer()],
                      reps: const <SalesRep>[],
                      products: const <ProductOption>[(id: '3', name: 'Website (CMS)')],
                      customerId: '5',
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // Handovers could only be scheduled from the phone before (#44).
    expect(find.text('Schedule a milestone'), findsOneWidget);
    expect(find.text('FreshBox Groceries'), findsOneWidget);

    await tester.tap(find.text('Schedule'));
    await tester.pumpAndSettle();
    expect(sent, isNotNull);
    expect(sent!['customer'], 5);
    expect(sent!['product'], 3);
    expect(sent!['milestone'], 'design_approval');
    expect(sent!['required'], isTrue);
    expect(sent!.containsKey('assigned_to'), isFalse);
  });
}
