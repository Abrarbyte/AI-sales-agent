import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracker_app/screens/add_lead_sheet.dart';
import 'package:sales_tracker_app/screens/convert_sheet.dart';
import 'package:sales_tracker_app/screens/negotiation_sheet.dart';
import 'package:sales_tracker_app/screens/payment_sheet.dart';
import 'package:sales_tracker_app/screens/login_screen.dart';
import 'package:sales_tracker_app/theme.dart';
import 'package:sales_tracker_app/widgets/chips.dart';

void main() {
  group('add lead sheet', () {
    testWidgets('shows every field the design does, and marks the two the '
        'model requires', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: AddLeadSheet()),
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Add New Lead'), findsOneWidget);
      // Name and Phone carry the asterisk; Company, City and Source do not,
      // matching `blank=True` on the model.
      expect(find.text('NAME *'), findsOneWidget);
      expect(find.text('PHONE *'), findsOneWidget);
      expect(find.text('COMPANY'), findsOneWidget);
      expect(find.text('CITY'), findsOneWidget);
      expect(find.text('SOURCE'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Save Lead'), findsOneWidget);
    });

    testWidgets('refuses to save without a name and a phone',
        (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: AddLeadSheet()),
      ));
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Save Lead'));
      await tester.pump();

      // Caught before any request goes out, so an empty lead never reaches
      // the API to be rejected there.
      expect(find.text('A name and a phone number are required.'),
          findsOneWidget);
    });
  });

  Widget wrap(Widget child) =>
      MaterialApp(theme: AppTheme.light, home: child);

  group('login screen', () {
    testWidgets('shows the SalesHub branding and both fields',
        (WidgetTester tester) async {
      await tester.pumpWidget(wrap(const LoginScreen()));

      expect(find.text('SalesHub'), findsOneWidget);
      expect(find.text('Sign in to log your visits and leads.'),
          findsOneWidget);
      // Labels sit above the fields in this design, rather than inside them.
      expect(find.text('Username'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      // The design sets the button in caps.
      expect(find.widgetWithText(FilledButton, 'SIGN IN'), findsOneWidget);
    });

    testWidgets('empty fields show an error instead of calling the API',
        (WidgetTester tester) async {
      await tester.pumpWidget(wrap(const LoginScreen()));

      await tester.tap(find.widgetWithText(FilledButton, 'SIGN IN'));
      await tester.pump();

      expect(find.text('Enter your username and password to continue.'),
          findsOneWidget);
    });

    testWidgets('password is hidden until the reveal button is tapped',
        (WidgetTester tester) async {
      await tester.pumpWidget(wrap(const LoginScreen()));

      TextField passwordField() => tester.widget<TextField>(
          find.byType(TextField).last);

      expect(passwordField().obscureText, isTrue);

      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pump();

      expect(passwordField().obscureText, isFalse);
    });
  });

  group('design components', () {
    testWidgets('lead status badge names and colours by status',
        (WidgetTester tester) async {
      await tester.pumpWidget(wrap(
        const Scaffold(body: LeadStatusBadge(status: 'converted')),
      ));

      // Stored as 'converted', read as Customer (#27).
      final text = tester.widget<Text>(find.text('Customer'));
      expect(text.style?.color, AppTheme.emerald600);
    });

    testWidgets('a lost lead reads as Lost', (WidgetTester tester) async {
      await tester.pumpWidget(wrap(
        const Scaffold(body: LeadStatusBadge(status: 'closed')),
      ));

      expect(find.text('Lost'), findsOneWidget);
    });

    testWidgets('stat tile turns red only when flagged as danger',
        (WidgetTester tester) async {
      await tester.pumpWidget(wrap(const Scaffold(
        body: Row(children: [
          Expanded(child: StatTile(label: 'Overdue', value: '0')),
          Expanded(
              child: StatTile(label: 'Overdue', value: '3', danger: true)),
        ]),
      )));

      final calm = tester.widget<Text>(find.text('0'));
      final alarmed = tester.widget<Text>(find.text('3'));

      expect(calm.style?.color, isNot(AppTheme.light.colorScheme.error));
      expect(alarmed.style?.color, AppTheme.light.colorScheme.error);
    });
  });

  // The shape scale of the dark dashboard design: 12 for tiles and rows,
  // 16 for the larger cards and sheets. Pinned so a stray edit shows up.
  group('shape', () {
    test('radius scale matches the neo design', () {
      expect(AppTheme.radiusMd, 12.0); // rounded-xl
      expect(AppTheme.radius, 16.0); // rounded-2xl
      expect(AppTheme.radiusXl, 24.0); // rounded-3xl (default)
      expect(AppTheme.radius2xl, 28.0); // the config's custom 3xl
      expect(AppTheme.radiusDock, 36.0); // rounded-4xl
    });

    test('the palette is the Ambient Neo design, light-first', () {
      final light = AppTheme.light.colorScheme;
      expect(light.brightness, Brightness.light);
      expect(light.surface, AppTheme.neoBg); // #EEF3F8 ground
      expect(light.surfaceContainerLowest, AppTheme.neoCard); // white cards
      expect(light.primary, AppTheme.neoBlue); // #0A4B6E
      expect(light.secondary, AppTheme.neoTeal); // #088395
      expect(AppTheme.accent, AppTheme.neoCyan); // #22C1C3
      // Dark is a derived twin, never shipped - but must still differ.
      expect(AppTheme.dark.colorScheme.surface, isNot(light.surface));
      expect(AppTheme.dark.colorScheme.brightness, Brightness.dark);
    });

    test('controls clear the minimum touch target', () {
      // Deliberately taller than the design's h-10 / h-9. See AppTheme.
      expect(AppTheme.controlHeight, greaterThanOrEqualTo(48.0));
    });

    test('density is pinned, so controlHeight survives off-mobile', () {
      // `adaptivePlatformDensity` is compact (-2, -2) on web and desktop,
      // which takes 8px off every button — 48 becomes 40, under the minimum.
      // A widget test alone will not catch a regression here, because
      // flutter_test reports Android, where the adaptive default is already
      // standard. Assert the pin directly.
      for (final theme in [AppTheme.light, AppTheme.dark]) {
        expect(theme.visualDensity, VisualDensity.standard);
        expect(theme.visualDensity.vertical, 0.0);
      }
    });

    testWidgets('buttons and fields are actually laid out that tall',
        (WidgetTester tester) async {
      await tester.pumpWidget(wrap(Scaffold(
        body: Column(children: [
          FilledButton(onPressed: () {}, child: const Text('Save')),
          OutlinedButton(onPressed: () {}, child: const Text('Cancel')),
          const TextField(decoration: InputDecoration(hintText: 'Name')),
        ]),
      )));

      final controls = {
        'FilledButton': find.byType(FilledButton),
        'OutlinedButton': find.byType(OutlinedButton),
        'TextField': find.byType(TextField),
      };
      for (final entry in controls.entries) {
        expect(tester.getSize(entry.value).height,
            greaterThanOrEqualTo(AppTheme.controlHeight),
            reason: '${entry.key} is under the touch-target minimum');
      }
    });

    testWidgets('the app renders in Hanken Grotesk, the design typeface',
        (WidgetTester tester) async {
      await tester.pumpWidget(wrap(const Scaffold(body: Text('Sales Portal'))));

      final style = tester.widget<Text>(find.text('Sales Portal')).style;
      final resolved = style?.fontFamily ??
          Theme.of(tester.element(find.text('Sales Portal')))
              .textTheme
              .bodyMedium
              ?.fontFamily;
      expect(resolved, 'HankenGrotesk');
    });

    test('variable fonts carry their weight on the wght axis', () {
      // Both faces ship as one variable file, so a bare `fontWeight` would be
      // synthesised rather than selected. Every style must name the axis too.
      for (final style in [AppTheme.headlineLgMobile, AppTheme.labelSm]) {
        expect(style.fontVariations, isNotNull);
        expect(style.fontVariations!.single.axis, 'wght');
        expect(style.fontVariations!.single.value, style.fontWeight!.value);
      }
      expect(AppTheme.labelSm.fontFamily, 'JetBrainsMono');
    });
  });

  group('convert sheet', () {
    Future<void> open(WidgetTester tester, Map<String, dynamic> lead) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: ConvertSheet(lead: lead)),
      ));
      await tester.pump();
    }

    FilledButton convertButton(WidgetTester tester) =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Convert'));

    testWidgets('asks for the deposit the payment terms set',
        (WidgetTester tester) async {
      // Half-and-half: the server says 0.50, not the old fixed 30% (#32).
      await open(tester, {
        'id': 1, 'value': '100000.00', 'amount_paid': '0.00',
        'deposit_share': '0.50',
      });
      expect(find.text('Deposit required (50%)'), findsOneWidget);
      expect(find.text('₹50000'), findsNWidgets(2)); // required, outstanding
      expect(convertButton(tester).onPressed, isNull);

      // Second field: amount received now.
      await tester.enterText(find.byType(TextField).at(1), '50000');
      await tester.pump();
      expect(convertButton(tester).onPressed, isNotNull);
    });

    testWidgets('will not convert without an agreed price',
        (WidgetTester tester) async {
      await open(tester, {'id': 1, 'value': null, 'amount_paid': '0.00'});
      expect(find.textContaining('Enter the agreed price first'), findsOneWidget);
      expect(convertButton(tester).onPressed, isNull);
    });
  });

  group('record payment sheet', () {
    testWidgets('shows the balance and refuses more than it', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: RecordPaymentSheet(customerId: 1, balance: 70000),
        ),
      ));
      await tester.pump();
      expect(find.text('₹70,000 still due.'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '80000');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Record'));
      await tester.pump();
      // Caught here, before the server has to refuse it.
      expect(find.textContaining('more than the ₹70,000 still due'),
          findsOneWidget);
    });
  });

  group('negotiation sheet', () {
    testWidgets('has one place for what they want and one for payment', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: NegotiationSheet(leadId: 1, requirement: 'Shop website'),
        ),
      ));
      await tester.pump();
      // Strictly one field each (#48): the lead's requirement, edited here.
      // Field labels are shown in capitals.
      expect(find.text('Shop website'), findsOneWidget);
      expect(find.text('WHAT THEY WANT'), findsOneWidget);
      expect(find.textContaining('SCOPE'), findsNothing);
      expect(find.textContaining('PROPOSED SOLUTION'), findsNothing);
      expect(find.textContaining('TERMS / CONDITIONS'), findsNothing);
      expect(find.text('PAYMENT DETAILS'), findsOneWidget);
    });
  });
}
