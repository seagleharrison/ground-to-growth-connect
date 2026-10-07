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

/// An admin starts on the staff "everyone" Map; a volunteer has no map at all
/// (only admins see where people are) and starts on Me, where their own
/// sharing switch lives.
Future<AppState> _pump(WidgetTester tester, FakeApi api, String personType, {AppTab? start}) async {
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
  final startTab = start ?? (personType == 'volunteer' ? AppTab.me : AppTab.map);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: state),
      ChangeNotifierProvider(create: (_) => TabNav(current: startTab)),
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

  _withApi('an admin gets a Share my location chip on the staff map, off by default', (tester, api) async {
    await _pump(tester, api, 'admin');
    expect(find.byKey(const Key('share-my-location-chip')), findsOneWidget);
    expect(find.text('Share my location'), findsOneWidget);
    expect(find.text('Sharing'), findsNothing);
  });

  _withApi('turning it on opens the admin-worded consent sheet; accepting turns sharing on', (tester, api) async {
    await _pump(tester, api, 'admin');

    await tester.tap(find.byKey(const Key('share-my-location-chip')));
    await _settle(tester);

    expect(find.text('Share your location with admins?'), findsOneWidget);
    expect(find.textContaining('never see this'), findsOneWidget);

    await tester.tap(find.text('I understand — turn on sharing'));
    await _settle(tester);

    expect(find.text('Sharing'), findsOneWidget);
    expect(find.text('Share my location'), findsNothing);
    expect(api.locationConsentGranted, isTrue);
    expect(api.routes, contains('POST /api/consent'));
  });

  group('a volunteer', () {
    _withApi('has no map: no Map card, no Map tab, no way to see where anyone is', (tester, api) async {
      await _pump(tester, api, 'volunteer');
      expect(find.byKey(const Key('open-staff-map')), findsNothing);
      expect(find.byKey(const Key('share-my-location-chip')), findsNothing);
      expect(find.text('Map'), findsNothing);
      expect(find.byKey(const Key('volunteer-share-card')), findsOneWidget);
    });

    _withApi('can let admins see them, and turn it off again', (tester, api) async {
      await _pump(tester, api, 'volunteer');
      final switchFinder = find.byKey(const Key('volunteer-share-switch'));
      expect(tester.widget<Switch>(switchFinder).value, isFalse, reason: 'off unless they turn it on');

      await tester.tap(switchFinder);
      await _settle(tester);
      expect(find.text('Share your location with admins?'), findsOneWidget);
      await tester.tap(find.text('I understand — turn on sharing'));
      await _settle(tester);
      expect(api.locationConsentGranted, isTrue);
      expect(tester.widget<Switch>(switchFinder).value, isTrue);
      // The sheet stays up in this test (closing waits on the phone's real
      // location services, which don't exist here); dismiss it as a person would.
      await tester.tapAt(const Offset(10, 10));
      await _settle(tester);

      await tester.tap(switchFinder);
      await _settle(tester);
      expect(api.locationConsentGranted, isFalse);
      expect(tester.widget<Switch>(switchFinder).value, isFalse);
    });

    _withApi('a volunteer who was already sharing can still switch it off', (tester, api) async {
      api.locationConsentGranted = true;
      final state = await _pump(tester, api, 'volunteer');
      state.consent = ConsentStatus(granted: true);
      state.notifyListeners();
      await tester.pump();
      await tester.tap(find.byKey(const Key('volunteer-share-switch')));
      await _settle(tester);
      expect(api.locationConsentGranted, isFalse);
    });
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

  _withApi('a staff member sees themselves in the list too, marked "You"', (tester, api) async {
    // 'u1' is FakeApi's default signed-in user id.
    api.staffLocations = [staffLoc('u1', 'Ada Admin', 'admin'), staffLoc('p2', 'Jane Doe', 'homeless')];
    await _pump(tester, api, 'admin');
    await _settle(tester);

    expect(find.byKey(const Key('row-u1')), findsOneWidget);
    final youPillsOnSelf = find.descendant(of: find.byKey(const Key('row-u1')), matching: find.byKey(const Key('you-pill')));
    final youPillsOnOther = find.descendant(of: find.byKey(const Key('row-p2')), matching: find.byKey(const Key('you-pill')));
    expect(youPillsOnSelf, findsOneWidget);
    expect(youPillsOnOther, findsNothing);
  });

  _withApi('an admin previewing as a volunteer cannot turn on sharing without exiting the preview', (tester, api) async {
    final state = await _pump(tester, api, 'admin', start: AppTab.me);
    state.viewAs(AppView.volunteer);
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byKey(const Key('volunteer-share-switch')));
    await _settle(tester);
    await tester.tap(find.text('I understand — turn on sharing'), warnIfMissed: false);
    await _settle(tester, times: 3);

    expect(api.locationConsentGranted, isFalse);
    expect(api.routes, isNot(contains('POST /api/consent')));
    expect(find.textContaining("You're previewing the app"), findsOneWidget);
  });
}
