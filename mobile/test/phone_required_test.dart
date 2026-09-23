import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ground_to_growth_connect/app_state.dart';
import 'package:ground_to_growth_connect/models/models.dart';
import 'package:ground_to_growth_connect/views/edit_profile_view.dart';
import 'package:ground_to_growth_connect/views/register_view.dart';
import 'package:ground_to_growth_connect/widgets/ui.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'support/fake_api.dart';

void main() {
  group('sign-up', () {
    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ChangeNotifierProvider(
        create: (_) => AppState(),
        child: const MaterialApp(home: RegisterView()),
      ));
      await tester.pump();
    }

    testWidgets('the phone field is a plain, always-visible field, not tucked behind a tap-to-reveal section', (tester) async {
      await pump(tester);
      expect(find.widgetWithText(TextField, 'Phone'), findsOneWidget);
      expect(find.text('Add contact details'), findsNothing, reason: 'phone must not be hidden in a collapsed section');
    });

    testWidgets('Create my account stays off until both name and phone are filled in', (tester) async {
      await pump(tester);
      Finder button() => find.byType(GradientButton);
      bool enabled() => tester.widget<GradientButton>(button()).onPressed != null;

      expect(find.text('Create my account'), findsOneWidget);
      expect(enabled(), isFalse);

      await tester.enterText(find.widgetWithText(TextField, 'Full name'), 'Jane Doe');
      await tester.pump();
      expect(enabled(), isFalse, reason: 'name alone is not enough');

      await tester.enterText(find.widgetWithText(TextField, 'Phone'), '912-555-0100');
      await tester.pump();
      expect(enabled(), isTrue);

      await tester.enterText(find.widgetWithText(TextField, 'Phone'), '   ');
      await tester.pump();
      expect(enabled(), isFalse, reason: 'a blank phone (just spaces) must not count');
    });
  });

  group('edit profile', () {
    Future<AppState> pump(WidgetTester tester, FakeApi api) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      FlutterSecureStorage.setMockInitialValues({'auth_token': 'tok'});
      final state = AppState()
        ..user = User.fromJson(api.user)
        ..isUnlocked = true;
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange, brightness: Brightness.dark)),
          home: const EditProfileView(),
        ),
      ));
      await tester.pump();
      return state;
    }

    testWidgets('clearing the phone number disables Save and shows an error, refilling it re-enables Save', (tester) async {
      final api = FakeApi();
      await http.runWithClient(() async {
        await pump(tester, api);
        Finder saveButton() => find.widgetWithText(FilledButton, 'Save changes');
        bool saveEnabled() => tester.widget<FilledButton>(saveButton()).onPressed != null;

        await tester.enterText(find.widgetWithText(TextField, 'Phone'), '');
        await tester.pump();
        expect(find.text("Phone can't be blank"), findsOneWidget);
        expect(saveEnabled(), isFalse);

        await tester.enterText(find.widgetWithText(TextField, 'Phone'), '912-555-0199');
        await tester.pump();
        expect(find.text("Phone can't be blank"), findsNothing);
        expect(saveEnabled(), isTrue);
      }, () => api.client);
    });
  });
}
