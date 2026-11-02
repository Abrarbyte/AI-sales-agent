import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_admin_console/core/theme/app_theme.dart';
import 'package:sales_admin_console/features/people/person_form_dialog.dart';

/// Opens the form in a dialog and returns what Save hands back.
Future<PersonFormResult?> _openAndSave(
  WidgetTester tester,
  PersonFormDialog dialog,
) async {
  PersonFormResult? result;
  tester.view.physicalSize = const Size(1400, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    home: Builder(
      builder: (BuildContext context) => Scaffold(
        body: TextButton(
          onPressed: () async =>
              result = await showDialog<PersonFormResult>(
                  context: context, builder: (_) => dialog),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Save changes'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('editing shows the current username and does not ask again',
      (WidgetTester tester) async {
    final PersonFormResult? result = await _openAndSave(
      tester,
      const PersonFormDialog(
        existingId: '7',
        initialUsername: 'aniket11chavan14',
        initialName: 'Aniket Chavan',
        initialEmail: 'aniket@example.com',
      ),
    );
    // Saved without typing a username: no "Username is required".
    expect(find.text('Username is required'), findsNothing);
    expect(result, isNotNull);
    expect(result!.username, 'aniket11chavan14');
  });

  testWidgets('the username cannot be edited on an existing person',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(
        body: PersonFormDialog(
          existingId: '7',
          initialUsername: 'aniket11chavan14',
          initialName: 'Aniket Chavan',
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final TextField field = tester.widget<TextField>(find.ancestor(
      of: find.text('aniket11chavan14'),
      matching: find.byType(TextField),
    ));
    expect(field.readOnly, isTrue);
    expect(find.text('They sign in with this. It cannot be changed.'),
        findsOneWidget);
  });
}
