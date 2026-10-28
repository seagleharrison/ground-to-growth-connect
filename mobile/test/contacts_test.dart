import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ground_to_growth_connect/app_state.dart';
import 'package:ground_to_growth_connect/data/calendar_content.dart';
import 'package:ground_to_growth_connect/models/models.dart';
import 'package:ground_to_growth_connect/nav.dart';
import 'package:ground_to_growth_connect/theme/app_theme.dart';
import 'package:ground_to_growth_connect/util/launch.dart';
import 'package:ground_to_growth_connect/views/main_tab_view.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'support/fake_api.dart';

Future<AppState> _pump(WidgetTester tester, FakeApi api, {String personType = 'admin'}) async {
  tester.view.physicalSize = const Size(1200, 3600);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  FlutterSecureStorage.setMockInitialValues({'auth_token': 'tok'});
  api.user['personType'] = personType;
  api.user['isStaff'] = personType != 'homeless';
  api.user['name'] = 'Ada Admin';
  final state = AppState()
    ..user = User.fromJson(api.user)
    ..isUnlocked = true;
  state.calendar.debugPreloadEvents(const CalendarEventsContent(updatedAt: '2026-01-01', events: []));
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: state),
      ChangeNotifierProvider(create: (_) => TabNav(current: AppTab.me)),
    ],
    child: MaterialApp(theme: buildAppTheme(), darkTheme: buildAppTheme(), themeMode: ThemeMode.dark, home: const MainTabView()),
  ));
  await _settle(tester);
  return state;
}

Future<void> _settle(WidgetTester tester, {int times = 6}) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void _withApi(String description, Future<void> Function(WidgetTester tester, FakeApi api) body) {
  testWidgets(description, (tester) async {
    final api = FakeApi();
    await http.runWithClient(() => body(tester, api), () => api.client);
  });
}

Future<void> _openContacts(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('open-contacts')));
  await tester.tap(find.byKey(const Key('open-contacts')));
  await _settle(tester);
}

void main() {
  _withApi('only admins get a Contacts row under Me', (tester, api) async {
    await _pump(tester, api, personType: 'volunteer');
    expect(find.byKey(const Key('open-contacts')), findsNothing);
  });

  _withApi('an admin adds a contact with name, phone, email and notes, and sees it listed', (tester, api) async {
    await _pump(tester, api);
    await _openContacts(tester);
    expect(find.byKey(const Key('contacts-empty')), findsOneWidget);

    await tester.tap(find.byKey(const Key('add-contact')));
    await _settle(tester);
    await tester.enterText(find.byKey(const Key('contact-name')), 'Union Mission');
    await tester.enterText(find.byKey(const Key('contact-phone')), '912-355-1234');
    await tester.enterText(find.byKey(const Key('contact-email')), 'intake@example.org');
    await tester.enterText(find.byKey(const Key('contact-notes')), 'Meals at 5. Ask for Denise.');
    await tester.ensureVisible(find.byKey(const Key('save-contact')));
    await tester.tap(find.byKey(const Key('save-contact')));
    await _settle(tester);

    expect(api.contacts.single['name'], 'Union Mission');
    expect(api.contacts.single['phone'], '912-355-1234');
    expect(api.contacts.single['email'], 'intake@example.org');
    expect(api.contacts.single['notes'], 'Meals at 5. Ask for Denise.');
    expect(find.text('Union Mission'), findsOneWidget);
    expect(find.textContaining('912-355-1234'), findsOneWidget);
    expect(find.byKey(const Key('contacts-empty')), findsNothing);
  });

  _withApi('a contact cannot be saved without a name', (tester, api) async {
    await _pump(tester, api);
    await _openContacts(tester);
    await tester.tap(find.byKey(const Key('add-contact')));
    await _settle(tester);
    await tester.enterText(find.byKey(const Key('contact-phone')), '912-355-1234');
    await tester.ensureVisible(find.byKey(const Key('save-contact')));
    await tester.tap(find.byKey(const Key('save-contact')));
    await _settle(tester);
    expect(find.byKey(const Key('contact-error')), findsOneWidget);
    expect(api.contacts, isEmpty);
  });

  _withApi('tapping a contact opens it for changes, and Call dials the number', (tester, api) async {
    api.contacts.add({'id': 'c9', 'name': 'Dr. Lee Clinic', 'phone': '912-555-0150', 'email': null, 'notes': 'Walk-ins Tue'});
    final opened = <Uri>[];
    Launch.debugOverride = (uri) async {
      opened.add(uri);
      return true;
    };
    addTearDown(() => Launch.debugOverride = null);
    await _pump(tester, api);
    await _openContacts(tester);

    await tester.tap(find.byKey(const Key('contact-c9')));
    await _settle(tester);
    expect(find.text('Walk-ins Tue'), findsOneWidget);
    await tester.tap(find.byKey(const Key('contact-call')));
    await _settle(tester, times: 2);
    expect(opened.single.scheme, 'tel');

    await tester.enterText(find.byKey(const Key('contact-notes')), 'Walk-ins Tue and Thu');
    await tester.ensureVisible(find.byKey(const Key('save-contact')));
    await tester.tap(find.byKey(const Key('save-contact')));
    await _settle(tester);
    expect(api.contacts.single['notes'], 'Walk-ins Tue and Thu');
    expect(api.contacts.single['phone'], '912-555-0150', reason: 'untouched fields stay');
  });

  _withApi('deleting asks first, then removes the contact', (tester, api) async {
    api.contacts.add({'id': 'c9', 'name': 'Dr. Lee Clinic', 'phone': null, 'email': null, 'notes': null});
    await _pump(tester, api);
    await _openContacts(tester);
    await tester.tap(find.byKey(const Key('contact-c9')));
    await _settle(tester);
    await tester.ensureVisible(find.byKey(const Key('delete-contact')));
    await tester.tap(find.byKey(const Key('delete-contact')));
    await _settle(tester);
    expect(api.contacts, hasLength(1), reason: 'nothing happens until they confirm');
    await tester.tap(find.byKey(const Key('confirm-delete-contact')));
    await _settle(tester);
    expect(api.contacts, isEmpty);
    expect(find.text('Dr. Lee Clinic'), findsNothing);
  });

  _withApi('previewing as someone else changes nothing', (tester, api) async {
    final state = await _pump(tester, api);
    state.viewAs(AppView.participant);
    await tester.pump(const Duration(milliseconds: 300));
    expect(await state.contacts.save(name: 'Sneaky'), isNotNull);
    expect(api.contacts, isEmpty);
  });
}
