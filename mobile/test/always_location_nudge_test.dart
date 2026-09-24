import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:ground_to_growth_connect/app_state.dart';
import 'package:ground_to_growth_connect/models/models.dart';
import 'package:ground_to_growth_connect/nav.dart';
import 'package:ground_to_growth_connect/services/location_tracker.dart';
import 'package:ground_to_growth_connect/views/main_tab_view.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'support/fake_api.dart';

/// A real field report drove this: a tester's check-ins ran fine, then went
/// silent for 17+ hours once his phone sat locked — "While Using" access
/// doesn't wake the app in the background, only "Always" does. Rather than
/// wait for someone to notice a banner, the app now offers the upgrade the
/// moment they land inside with sharing on but only "While Using" granted.
void main() {
  tearDown(() => LocationTracker.debugOpenSettings = null);

  Future<void> pumpMainTabView(WidgetTester tester, AppState state) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: state),
        ChangeNotifierProvider(create: (_) => TabNav()),
      ],
      child: const MaterialApp(home: MainTabView()),
    ));
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('landing in the app with sharing on but only "While Using" access offers the Always upgrade', (tester) async {
    var opened = 0;
    LocationTracker.debugOpenSettings = () async {
      opened++;
      return true;
    };
    final api = FakeApi();
    await http.runWithClient(() async {
      FlutterSecureStorage.setMockInitialValues({'auth_token': 'tok'});
      final state = AppState()
        ..user = User.fromJson(api.user)
        ..isUnlocked = true
        ..consent = ConsentStatus(granted: true);
      state.locationTracker.authorizationStatus = LocationPermission.whileInUse;

      await pumpMainTabView(tester, state);

      expect(find.text('Keep sharing while your phone is locked?'), findsOneWidget);

      await tester.tap(find.byKey(const Key('always-nudge-open-settings')));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }

      expect(opened, 1);
      expect(state.locationTracker.alwaysNudgeDismissed, isTrue);
      expect(find.text('Keep sharing while your phone is locked?'), findsNothing);
    }, () => api.client);
  });

  testWidgets('"Not now" dismisses without opening Settings, and it does not come back this launch', (tester) async {
    var opened = 0;
    LocationTracker.debugOpenSettings = () async {
      opened++;
      return true;
    };
    final api = FakeApi();
    await http.runWithClient(() async {
      FlutterSecureStorage.setMockInitialValues({'auth_token': 'tok'});
      final state = AppState()
        ..user = User.fromJson(api.user)
        ..isUnlocked = true
        ..consent = ConsentStatus(granted: true);
      state.locationTracker.authorizationStatus = LocationPermission.whileInUse;

      await pumpMainTabView(tester, state);
      expect(find.text('Keep sharing while your phone is locked?'), findsOneWidget);

      await tester.tap(find.byKey(const Key('always-nudge-not-now')));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }

      expect(opened, 0);
      expect(state.locationTracker.alwaysNudgeDismissed, isTrue);

      // Something else notifies listeners later in the same launch (e.g. a
      // check-in) — the dialog must not reappear.
      state.locationTracker.notifyListeners();
      await tester.pump();
      expect(find.text('Keep sharing while your phone is locked?'), findsNothing);
    }, () => api.client);
  });

  testWidgets('already having "Always" access never shows the nudge', (tester) async {
    final api = FakeApi();
    await http.runWithClient(() async {
      FlutterSecureStorage.setMockInitialValues({'auth_token': 'tok'});
      final state = AppState()
        ..user = User.fromJson(api.user)
        ..isUnlocked = true
        ..consent = ConsentStatus(granted: true);
      state.locationTracker.authorizationStatus = LocationPermission.always;

      await pumpMainTabView(tester, state);

      expect(find.text('Keep sharing while your phone is locked?'), findsNothing);
    }, () => api.client);
  });

  testWidgets('sharing turned off means no nudge, even with only "While Using" access', (tester) async {
    final api = FakeApi();
    await http.runWithClient(() async {
      FlutterSecureStorage.setMockInitialValues({'auth_token': 'tok'});
      final state = AppState()
        ..user = User.fromJson(api.user)
        ..isUnlocked = true
        ..consent = ConsentStatus(granted: false);
      state.locationTracker.authorizationStatus = LocationPermission.whileInUse;

      await pumpMainTabView(tester, state);

      expect(find.text('Keep sharing while your phone is locked?'), findsNothing);
    }, () => api.client);
  });

  group('Precise Location upgrade', () {
    testWidgets('with "Always" already granted but Precise Location off, offers just that upgrade', (tester) async {
      var opened = 0;
      LocationTracker.debugOpenSettings = () async {
        opened++;
        return true;
      };
      final api = FakeApi();
      await http.runWithClient(() async {
        FlutterSecureStorage.setMockInitialValues({'auth_token': 'tok'});
        final state = AppState()
          ..user = User.fromJson(api.user)
          ..isUnlocked = true
          ..consent = ConsentStatus(granted: true);
        state.locationTracker
          ..authorizationStatus = LocationPermission.always
          ..accuracyStatus = LocationAccuracyStatus.reduced;

        await pumpMainTabView(tester, state);

        expect(find.text('Keep sharing while your phone is locked?'), findsNothing);
        expect(find.text('Make your location more accurate?'), findsOneWidget);

        await tester.tap(find.byKey(const Key('precise-nudge-open-settings')));
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 300));
        }

        expect(opened, 1);
        expect(state.locationTracker.preciseNudgeDismissed, isTrue);
        expect(find.text('Make your location more accurate?'), findsNothing);
      }, () => api.client);
    });

    testWidgets('"Not now" dismisses the precise-location nudge without opening Settings', (tester) async {
      var opened = 0;
      LocationTracker.debugOpenSettings = () async {
        opened++;
        return true;
      };
      final api = FakeApi();
      await http.runWithClient(() async {
        FlutterSecureStorage.setMockInitialValues({'auth_token': 'tok'});
        final state = AppState()
          ..user = User.fromJson(api.user)
          ..isUnlocked = true
          ..consent = ConsentStatus(granted: true);
        state.locationTracker
          ..authorizationStatus = LocationPermission.always
          ..accuracyStatus = LocationAccuracyStatus.reduced;

        await pumpMainTabView(tester, state);
        await tester.tap(find.byKey(const Key('precise-nudge-not-now')));
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 300));
        }

        expect(opened, 0);
        expect(state.locationTracker.preciseNudgeDismissed, isTrue);
      }, () => api.client);
    });

    testWidgets('needing both upgrades shows Always first, then Precise once that is resolved — never stacked', (tester) async {
      final api = FakeApi();
      await http.runWithClient(() async {
        FlutterSecureStorage.setMockInitialValues({'auth_token': 'tok'});
        final state = AppState()
          ..user = User.fromJson(api.user)
          ..isUnlocked = true
          ..consent = ConsentStatus(granted: true);
        state.locationTracker
          ..authorizationStatus = LocationPermission.whileInUse
          ..accuracyStatus = LocationAccuracyStatus.reduced;

        await pumpMainTabView(tester, state);

        expect(find.text('Keep sharing while your phone is locked?'), findsOneWidget);
        expect(find.text('Make your location more accurate?'), findsNothing, reason: 'only one dialog at a time');

        await tester.tap(find.byKey(const Key('always-nudge-not-now')));
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 300));
        }

        expect(find.text('Keep sharing while your phone is locked?'), findsNothing);
        expect(find.text('Make your location more accurate?'), findsOneWidget, reason: 'the second nudge follows once the first is resolved');
      }, () => api.client);
    });

    testWidgets('precise accuracy already granted means no nudge', (tester) async {
      final api = FakeApi();
      await http.runWithClient(() async {
        FlutterSecureStorage.setMockInitialValues({'auth_token': 'tok'});
        final state = AppState()
          ..user = User.fromJson(api.user)
          ..isUnlocked = true
          ..consent = ConsentStatus(granted: true);
        state.locationTracker
          ..authorizationStatus = LocationPermission.always
          ..accuracyStatus = LocationAccuracyStatus.precise;

        await pumpMainTabView(tester, state);

        expect(find.text('Make your location more accurate?'), findsNothing);
      }, () => api.client);
    });
  });
}
