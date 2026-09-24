import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:ground_to_growth_connect/app_state.dart';
import 'package:ground_to_growth_connect/main.dart';
import 'package:ground_to_growth_connect/models/models.dart';
import 'package:ground_to_growth_connect/nav.dart';
import 'package:ground_to_growth_connect/services/biometric_auth.dart';
import 'package:http/http.dart' as http;
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'support/fake_api.dart';

/// A minimal stand-in, just enough to prove RootView actually re-checks
/// permission on resume — the full behavior of that re-check itself is
/// covered by location_tracker_test.dart's own FakeGeolocatorPlatform.
class _FakeGeolocatorPlatform extends GeolocatorPlatform with MockPlatformInterfaceMixin {
  LocationPermission permission = LocationPermission.deniedForever;
  int checkPermissionCalls = 0;
  final _controller = StreamController<Position>.broadcast();

  @override
  Future<LocationPermission> checkPermission() async {
    checkPermissionCalls++;
    return permission;
  }

  @override
  Future<LocationPermission> requestPermission() async => permission;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationAccuracyStatus> getLocationAccuracy() async => LocationAccuracyStatus.precise;

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) async => Position(
        latitude: 32.08,
        longitude: -81.09,
        timestamp: DateTime.now(),
        accuracy: 65,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) => _controller.stream;

  @override
  Future<bool> openAppSettings() async => true;
}

void main() {
  testWidgets(
    'coming back to the app after fixing location permission in Settings picks it up, with no other action needed',
    (tester) async {
      final fakePlatform = _FakeGeolocatorPlatform();
      GeolocatorPlatform.instance = fakePlatform;
      BiometricAuth.debugOverride = (_) async => true;
      addTearDown(() => BiometricAuth.debugOverride = null);
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      final api = FakeApi();
      await http.runWithClient(() async {
        FlutterSecureStorage.setMockInitialValues({'auth_token': 'tok'});
        final state = AppState()
          ..isInitializing = false
          ..user = User.fromJson(api.user)
          ..isUnlocked = true
          ..consent = ConsentStatus(granted: true);

        await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: state),
            ChangeNotifierProvider(create: (_) => TabNav()),
          ],
          child: const MaterialApp(home: RootView()),
        ));
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 300));
        }

        await state.locationTracker.updateConsent(granted: true);
        await tester.pump();
        expect(state.locationTracker.permissionBlocked, isTrue, reason: 'starts out blocked, like a real revoked permission');

        // They background the app, fix it in Settings, and come back.
        fakePlatform.permission = LocationPermission.always;
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 300));
        }

        expect(state.locationTracker.permissionBlocked, isFalse);
        expect(state.locationTracker.authorizationStatus, LocationPermission.always);
        state.locationTracker.dispose();
      }, () => api.client);
    },
  );
}
