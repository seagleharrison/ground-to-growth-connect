import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ground_to_growth_connect/app_state.dart';
import 'package:ground_to_growth_connect/models/models.dart';
import 'package:ground_to_growth_connect/nav.dart';
import 'package:ground_to_growth_connect/theme/app_theme.dart';
import 'package:ground_to_growth_connect/views/main_tab_view.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'support/fake_api.dart';

Future<void> _settle(WidgetTester tester, {int times = 6}) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void _withApi(String description, Future<void> Function(WidgetTester tester, FakeApi api) body) {
  testWidgets(description, (tester) async {
    final api = FakeApi();
    api.people.addAll([
      {'userId': 'p1', 'name': 'Jane Doe', 'role': 'participant', 'joinedAt': '2026-10-01T12:00:00.000Z', 'sharing': true},
      {'userId': 'p2', 'name': 'Bob Smith', 'role': 'participant', 'joinedAt': '2026-09-20T12:00:00.000Z', 'sharing': false},
      {'userId': 'v1', 'name': 'Sam Helper', 'role': 'volunteer', 'joinedAt': '2026-09-25T12:00:00.000Z', 'approved': true, 'paused': false, 'thumbsUp': 4, 'thumbsDown': 1},
      {'userId': 'v2', 'name': 'Pat New', 'role': 'volunteer', 'joinedAt': '2026-10-05T12:00:00.000Z', 'approved': false, 'paused': false},
      {'userId': 'a1', 'name': 'Ada Admin', 'role': 'admin', 'joinedAt': '2026-09-01T12:00:00.000Z', 'approved': true},
    ]);
    api.personExtras['p1'] = {
      'email': 'jane@example.com',
      'phone': '(912) 555-0101',
      'gender': 'female',
      'lastCheckIn': DateTime.now().toUtc().subtract(const Duration(minutes: 12)).toIso8601String(),
      'documentStorage': true,
      'documentsOnFile': 2,
      'helpRequests': 3,
      'helpRequestsDone': 2,
    };
    api.personExtras['v1'] = {'email': 'sam@example.com', 'phone': '(912) 555-0102', 'helped': 6};
    await http.runWithClient(() => body(tester, api), () => api.client);
  });
}

Future<void> _openAnalytics(WidgetTester tester, FakeApi api, {String personType = 'admin'}) async {
  tester.view.physicalSize = const Size(1200, 4200);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  FlutterSecureStorage.setMockInitialValues({'auth_token': 'tok'});
  api.user['personType'] = personType;
  api.user['isStaff'] = true;
  final state = AppState()
    ..user = User.fromJson(api.user)
    ..isUnlocked = true;
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: state),
      ChangeNotifierProvider(create: (_) => TabNav(current: AppTab.analytics)),
    ],
    child: MaterialApp(theme: buildAppTheme(), darkTheme: buildAppTheme(), themeMode: ThemeMode.dark, home: const MainTabView()),
  ));
  await _settle(tester);
}

void main() {
  _withApi('tapping People we serve lists everyone registered, newest first', (tester, api) async {
    await _openAnalytics(tester, api);
    await tester.tap(find.byKey(const Key('stat-participants')));
    await _settle(tester);

    expect(find.text('People we serve'), findsWidgets);
    expect(find.byKey(const Key('person-p1')), findsOneWidget);
    expect(find.byKey(const Key('person-p2')), findsOneWidget);
    expect(find.byKey(const Key('person-v1')), findsNothing, reason: 'volunteers are in the other list');
    expect(find.text('2 registered'), findsOneWidget);
    expect(find.textContaining('Sharing location'), findsOneWidget);
    expect(find.textContaining('Not sharing location'), findsOneWidget);
  });

  _withApi('tapping Staff & volunteers lists them with where they stand', (tester, api) async {
    await _openAnalytics(tester, api);
    await tester.tap(find.byKey(const Key('stat-staff')));
    await _settle(tester);

    expect(find.byKey(const Key('person-v1')), findsOneWidget);
    expect(find.byKey(const Key('person-a1')), findsOneWidget);
    expect(find.byKey(const Key('person-p1')), findsNothing);
    expect(find.text('Volunteer · Approved'), findsOneWidget);
    expect(find.text('Volunteer · Waiting for approval'), findsOneWidget);
    expect(find.text('Admin · Full access'), findsOneWidget);
  });

  _withApi('the list can be searched by name', (tester, api) async {
    await _openAnalytics(tester, api);
    await tester.tap(find.byKey(const Key('stat-participants')));
    await _settle(tester);

    await tester.enterText(find.byKey(const Key('people-search')), 'bob');
    await tester.pump();
    expect(find.byKey(const Key('person-p2')), findsOneWidget);
    expect(find.byKey(const Key('person-p1')), findsNothing);
    expect(find.text('1 of 2'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('people-search')), 'zzz');
    await tester.pump();
    expect(find.byKey(const Key('people-no-match')), findsOneWidget);
  });

  _withApi("a person's profile shows who they are and where they stand, and nothing private", (tester, api) async {
    await _openAnalytics(tester, api);
    await tester.tap(find.byKey(const Key('stat-participants')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('person-p1')));
    await _settle(tester);

    expect(find.byKey(const Key('person-detail')), findsOneWidget);
    expect(find.text('jane@example.com'), findsOneWidget);
    expect(find.text('(912) 555-0101'), findsOneWidget);
    expect(find.text('Female'), findsOneWidget);
    expect(find.text('On'), findsOneWidget, reason: 'sharing location');
    expect(find.text('12 min ago'), findsOneWidget);
    expect(find.text('On · 2 on file'), findsOneWidget);
    expect(find.text('3 asked · 2 done'), findsOneWidget);
    expect(find.textContaining('Each time a profile is opened it is recorded'), findsOneWidget);
    expect(api.profileLooks, ['p1']);
    for (final private in ['Messages', 'Appointments', 'Calendar']) {
      expect(find.text(private), findsNothing, reason: '$private is private');
    }
  });

  _withApi('details someone never gave say so, and a non-sharing person has no check-in', (tester, api) async {
    await _openAnalytics(tester, api);
    await tester.tap(find.byKey(const Key('stat-participants')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('person-p2')));
    await _settle(tester);

    expect(find.text('Not given'), findsNWidgets(3), reason: 'no email, phone or gender');
    expect(find.byKey(const Key('detail-checkin')), findsNothing);
    expect(find.text('Off'), findsWidgets);
  });

  _withApi("a volunteer's profile shows their standing, help given and thumbs", (tester, api) async {
    await _openAnalytics(tester, api);
    await tester.tap(find.byKey(const Key('stat-staff')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('person-v1')));
    await _settle(tester);

    expect(find.text('sam@example.com'), findsOneWidget);
    expect(find.text('Approved'), findsOneWidget);
    expect(find.text('6'), findsOneWidget, reason: 'requests helped');
    expect(find.textContaining('4'), findsWidgets);
    expect(find.byKey(const Key('detail-thumbs')), findsOneWidget);
  });

  _withApi('a list that fails to load says so and can be retried', (tester, api) async {
    api.peopleError = 'Something went wrong';
    await _openAnalytics(tester, api);
    await tester.tap(find.byKey(const Key('stat-participants')));
    await _settle(tester);
    expect(find.byKey(const Key('people-error')), findsOneWidget);

    api.peopleError = null;
    await tester.tap(find.text('Try again'));
    await _settle(tester);
    expect(find.byKey(const Key('person-p1')), findsOneWidget);
  });

  _withApi('a volunteer never gets the lists, because they never get Analytics', (tester, api) async {
    await _openAnalytics(tester, api, personType: 'volunteer');
    expect(find.byKey(const Key('stat-participants')), findsNothing);
    expect(api.routes.where((r) => r.contains('/api/admin/people')), isEmpty);
  });
}
