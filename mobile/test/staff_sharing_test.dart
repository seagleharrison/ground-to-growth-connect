import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ground_to_growth_connect/app_state.dart';
import 'package:ground_to_growth_connect/models/models.dart';
import 'package:ground_to_growth_connect/nav.dart';
import 'package:ground_to_growth_connect/views/main_tab_view.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'support/fake_api.dart';

Map<String, dynamic> staffLoc(String id, String name, String personType, {int minsAgo = 5}) => {
      'userId': id,
      'name': name,
      'personType': personType,
      'latitude': 32.0809,
      'longitude': -81.0912,
      'reportedAt': DateTime.now().toUtc().subtract(Duration(minutes: minsAgo)).toIso8601String(),
    };

Future<AppState> _pump(WidgetTester tester, FakeApi api, String personType, {AppTab start = AppTab.map}) async {
  tester.view.physicalSize = const Size(1200, 3200);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  FlutterSecureStorage.setMockInitialValues({'auth_token': 'tok'});
  api.user['personType'] = personType;
  api.user['isStaff'] = personType != 'homeless';
  final state = AppState()
    ..user = User.fromJson(api.user)
    ..isUnlocked = true
    ..disclosure = DisclosureResponse(version: '1.0', text: 'Location disclosure text.');
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: state),
      ChangeNotifierProvider(create: (_) => TabNav(current: start)),
    ],
    child: const MaterialApp(home: MainTabView()),
  ));
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
  return state;
}

void _withApi(String description, Future<void> Function(WidgetTester tester, FakeApi api) body) {
  testWidgets(description, (tester) async {
    final api = FakeApi();
    await http.runWithClient(() => body(tester, api), () => api.client);
  });
}

/// Failed (mocked) map tile loads keep scheduling new frames on this screen,
/// so pumpAndSettle never settles here — pump a bounded number of times instead,
/// the same way the rest of this suite drives the map screens.
Future<void> _settle(WidgetTester tester, {int times = 6}) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  test('UserLocation.isStaffPerson is true for volunteer/admin and false for a participant', () {
    for (final t in ['volunteer', 'admin']) {
      expect(UserLocation.fromJson(staffLoc('x', 'X', t)).isStaffPerson, isTrue, reason: t);
    }
    expect(UserLocation.fromJson(staffLoc('x', 'X', 'homeless')).isStaffPerson, isFalse);
  });

  for (final role in ['volunteer', 'admin']) {
    _withApi('$role accounts get a Share my location chip on the staff map, off by default', (tester, api) async {
      await _pump(tester, api, role);
      expect(find.byKey(const Key('share-my-location-chip')), findsOneWidget);
      expect(find.text('Share my location'), findsOneWidget);
      expect(find.text('Sharing'), findsNothing);
    });
  }

  _withApi('turning it on opens the staff-worded consent sheet; accepting turns sharing on', (tester, api) async {
    await _pump(tester, api, 'volunteer');

    await tester.tap(find.byKey(const Key('share-my-location-chip')));
    await _settle(tester);

    expect(find.text('Share your location with staff?'), findsOneWidget);
    expect(find.textContaining('People we support never see this'), findsOneWidget);

    await tester.tap(find.text('I understand — turn on sharing'));
    await _settle(tester);

    expect(find.text('Sharing'), findsOneWidget);
    expect(find.text('Share my location'), findsNothing);
    expect(api.locationConsentGranted, isTrue);
    expect(api.routes, contains('POST /api/consent'));
  });

  _withApi('tapping it while sharing turns it off right away, no sheet', (tester, api) async {
    api.locationConsentGranted = true;
    final state = await _pump(tester, api, 'admin');
    state.consent = ConsentStatus(granted: true);
    state.notifyListeners();
    await tester.pump();
    expect(find.text('Sharing'), findsOneWidget);

    await tester.tap(find.byKey(const Key('share-my-location-chip')));
    await _settle(tester);

    expect(find.text('Share your location with staff?'), findsNothing, reason: 'turning off needs no sheet');
    expect(find.text('Share my location'), findsOneWidget);
    expect(api.locationConsentGranted, isFalse);
  });

  _withApi('a colleague sharing their location shows a Staff badge; a participant never does', (tester, api) async {
    api.staffLocations = [staffLoc('p1', 'Vic Volunteer', 'volunteer'), staffLoc('p2', 'Jane Doe', 'homeless')];
    await _pump(tester, api, 'admin');
    await _settle(tester);

    expect(find.byKey(const Key('row-p1')), findsOneWidget);
    expect(find.byKey(const Key('row-p2')), findsOneWidget);

    final staffPills = find.descendant(of: find.byKey(const Key('row-p1')), matching: find.byKey(const Key('staff-pill')));
    final participantPills = find.descendant(of: find.byKey(const Key('row-p2')), matching: find.byKey(const Key('staff-pill')));
    expect(staffPills, findsOneWidget);
    expect(participantPills, findsNothing);
  });

  _withApi('an admin previewing as another role cannot turn on sharing without exiting the preview', (tester, api) async {
    final state = await _pump(tester, api, 'admin', start: AppTab.me);
    state.viewAs(AppView.volunteer);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Map').last);
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byKey(const Key('share-my-location-chip')));
    await _settle(tester);
    await tester.tap(find.text('I understand — turn on sharing'));
    await _settle(tester, times: 3);

    expect(api.locationConsentGranted, isFalse);
    expect(api.routes, isNot(contains('POST /api/consent')));
    expect(find.textContaining("You're previewing the app"), findsOneWidget);
  });
}
