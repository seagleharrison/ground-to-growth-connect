import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ground_to_growth_connect/app_state.dart';
import 'package:ground_to_growth_connect/models/models.dart';
import 'package:ground_to_growth_connect/nav.dart';
import 'package:ground_to_growth_connect/services/location_tracker.dart';
import 'package:ground_to_growth_connect/views/home_view.dart';
import 'package:ground_to_growth_connect/views/map_tab_view.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'support/fake_api.dart';

void main() {
  tearDown(() => LocationTracker.debugOpenSettings = null);

  group('a real field report: sharing is on but permission was pulled out from under it', () {
    testWidgets('Home shows an Open Settings button, and tapping it opens Settings', (tester) async {
      var opened = 0;
      LocationTracker.debugOpenSettings = () async {
        opened++;
        return true;
      };
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      final api = FakeApi();
      await http.runWithClient(() async {
        FlutterSecureStorage.setMockInitialValues({'auth_token': 'tok'});
        final state = AppState()
          ..user = User.fromJson(api.user)
          ..isUnlocked = true
          ..consent = ConsentStatus(granted: true);
        state.locationTracker
          ..lastError = "Location permission was turned off for this app. Turn it back on in your phone's Settings to keep sharing your location."
          ..permissionBlocked = true;
        await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: state),
            ChangeNotifierProvider(create: (_) => TabNav()),
          ],
          child: const MaterialApp(home: HomeView()),
        ));
        await tester.pump(const Duration(seconds: 1));

        expect(find.textContaining('Turn it back on'), findsOneWidget);
        final button = find.byKey(const Key('open-location-settings'));
        expect(button, findsOneWidget);

        await tester.tap(button);
        await tester.pump();
        expect(opened, 1);
      }, () => api.client);
    });

    testWidgets('a transient error with no permission problem does not offer Open Settings', (tester) async {
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      final api = FakeApi();
      await http.runWithClient(() async {
        FlutterSecureStorage.setMockInitialValues({'auth_token': 'tok'});
        final state = AppState()
          ..user = User.fromJson(api.user)
          ..isUnlocked = true
          ..consent = ConsentStatus(granted: true);
        state.locationTracker.lastError = "Couldn't get your location just now. We'll keep trying.";
        await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: state),
            ChangeNotifierProvider(create: (_) => TabNav()),
          ],
          child: const MaterialApp(home: HomeView()),
        ));
        await tester.pump(const Duration(seconds: 1));

        expect(find.textContaining("Couldn't get your location"), findsOneWidget);
        expect(find.byKey(const Key('open-location-settings')), findsNothing);
      }, () => api.client);
    });

    testWidgets('the staff map shows the same warning and Settings button for a sharing staff member', (tester) async {
      var opened = 0;
      LocationTracker.debugOpenSettings = () async {
        opened++;
        return true;
      };
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      final api = FakeApi();
      await http.runWithClient(() async {
        FlutterSecureStorage.setMockInitialValues({'auth_token': 'tok'});
        api.user['personType'] = 'admin';
        api.user['isStaff'] = true;
        final state = AppState()
          ..user = User.fromJson(api.user)
          ..isUnlocked = true
          ..consent = ConsentStatus(granted: true);
        state.locationTracker
          ..lastError = "Location permission was turned off for this app. Turn it back on in your phone's Settings to keep sharing your location."
          ..permissionBlocked = true;
        await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: state),
            ChangeNotifierProvider(create: (_) => TabNav(current: AppTab.map)),
          ],
          child: const MaterialApp(home: MapTabView()),
        ));
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 300));
        }

        expect(find.byKey(const Key('open-location-settings-map')), findsOneWidget);
        await tester.tap(find.byKey(const Key('open-location-settings-map')));
        await tester.pump();
        expect(opened, 1);
      }, () => api.client);
    });

    testWidgets('the staff map stays quiet when sharing is off, even with a leftover error', (tester) async {
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      final api = FakeApi();
      await http.runWithClient(() async {
        FlutterSecureStorage.setMockInitialValues({'auth_token': 'tok'});
        api.user['personType'] = 'volunteer';
        api.user['isStaff'] = true;
        final state = AppState()
          ..user = User.fromJson(api.user)
          ..isUnlocked = true
          ..consent = ConsentStatus(granted: false);
        state.locationTracker
          ..lastError = 'stale error from before they turned sharing off'
          ..permissionBlocked = true;
        await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: state),
            ChangeNotifierProvider(create: (_) => TabNav(current: AppTab.map)),
          ],
          child: const MaterialApp(home: MapTabView()),
        ));
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 300));
        }

        expect(find.byKey(const Key('open-location-settings-map')), findsNothing);
        expect(find.textContaining('stale error'), findsNothing);
      }, () => api.client);
    });
  });
}
