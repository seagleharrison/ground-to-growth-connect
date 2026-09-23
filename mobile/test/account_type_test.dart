import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ground_to_growth_connect/app_state.dart';
import 'package:ground_to_growth_connect/models/models.dart';
import 'package:ground_to_growth_connect/views/settings_view.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'support/fake_api.dart';

Future<AppState> _pumpSettings(WidgetTester tester, FakeApi api) async {
  FlutterSecureStorage.setMockInitialValues({'auth_token': 'tok'});
  final state = AppState()
    ..user = User.fromJson(api.user)
    ..isUnlocked = true;
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
        theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange, brightness: Brightness.dark)),
        home: const SettingsView(),
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
  return state;
}

void _withFakeApi(String description, Future<void> Function(WidgetTester tester, FakeApi api) body) {
  testWidgets(description, (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final api = FakeApi();
    await http.runWithClient(() => body(tester, api), () => api.client);
  });
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('account-type-row')));
  await tester.tap(find.byKey(const Key('account-type-row')));
  await tester.pumpAndSettle();
}

void main() {
  _withFakeApi('Settings has an Account type row that opens the chooser with the current type marked', (tester, api) async {
    await _pumpSettings(tester, api);
    await _openSheet(tester);

    expect(find.text('Account type'), findsWidgets);
    for (final t in ['Getting support', 'Volunteer', 'Admin']) {
      expect(find.text(t), findsOneWidget);
    }
    expect(find.text('Current'), findsOneWidget);
  });

  _withFakeApi('Switching to staff asks for the code, refuses a wrong one, and accepts the right one', (tester, api) async {
    final state = await _pumpSettings(tester, api);
    await _openSheet(tester);

    await tester.tap(find.byKey(const Key('type-volunteer')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('staff-code-field')), findsOneWidget, reason: 'staff roles need the invite code');

    await tester.enterText(find.byKey(const Key('staff-code-field')), 'not-the-code');
    await tester.pump();
    await tester.tap(find.byKey(const Key('account-type-save')));
    await tester.pumpAndSettle();
    expect(find.textContaining("staff code doesn't look right"), findsOneWidget, reason: 'a friendly explanation, not a raw error');
    expect(find.byKey(const Key('account-type-error')), findsOneWidget);
    expect(state.user!.personType, 'homeless', reason: 'a refused switch changes nothing');
    expect(api.user['personType'], 'homeless');

    await tester.enterText(find.byKey(const Key('staff-code-field')), FakeApi.staffCode);
    await tester.pump();
    await tester.tap(find.byKey(const Key('account-type-save')));
    await tester.pumpAndSettle();

    expect(state.user!.personType, 'volunteer');
    expect(state.user!.isStaff, isTrue);
    expect(api.user['personType'], 'volunteer');
    expect(find.byKey(const Key('account-type-error')), findsNothing);
    expect(find.text('Getting support'), findsNothing, reason: 'the sheet closes after switching');
  });

  _withFakeApi('A staff member can switch back to getting support without any code', (tester, api) async {
    api.user['personType'] = 'admin';
    api.user['isStaff'] = true;
    final state = await _pumpSettings(tester, api);
    await _openSheet(tester);

    await tester.tap(find.byKey(const Key('type-homeless')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('staff-code-field')), findsNothing);

    await tester.tap(find.byKey(const Key('account-type-save')));
    await tester.pumpAndSettle();

    expect(state.user!.personType, 'homeless');
    expect(state.user!.isStaff, isFalse);
    expect(api.user['personType'], 'homeless');
  });

  _withFakeApi('The switch button stays off until a different type is chosen and the code is typed', (tester, api) async {
    await _pumpSettings(tester, api);
    await _openSheet(tester);

    Future<void> tapSave() async {
      await tester.tap(find.byKey(const Key('account-type-save')));
      await tester.pumpAndSettle();
    }

    await tapSave(); // nothing chosen yet
    expect(api.user['personType'], 'homeless');

    await tester.tap(find.byKey(const Key('type-admin')));
    await tester.pumpAndSettle();
    await tapSave(); // chose staff but typed no code
    expect(api.user['personType'], 'homeless');
    expect(find.byKey(const Key('account-type-error')), findsNothing, reason: 'no request should even be sent');
  });
}
