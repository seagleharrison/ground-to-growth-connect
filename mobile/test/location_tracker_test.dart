import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:ground_to_growth_connect/services/location_tracker.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// A controllable stand-in for the real location plugin, so the periodic
/// check-in timer can be tested deterministically without a device.
class FakeGeolocatorPlatform extends GeolocatorPlatform with MockPlatformInterfaceMixin {
  LocationPermission permission = LocationPermission.whileInUse;
  bool serviceEnabled = true;
  double lat = 32.0809;
  double lng = -81.0912;
  int currentPositionCalls = 0;
  final _controller = StreamController<Position>.broadcast();

  Position _position() => Position(
        latitude: lat,
        longitude: lng,
        timestamp: DateTime.now(),
        accuracy: 65,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );

  /// Simulates the device actually moving far enough for the OS to emit a
  /// new point on its own (distanceFilter-triggered), bypassing the timer.
  void moveAndEmit(double newLat, double newLng) {
    lat = newLat;
    lng = newLng;
    _controller.add(_position());
  }

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async => permission;

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) async {
    currentPositionCalls++;
    if (!serviceEnabled) throw const LocationServiceDisabledException();
    return _position();
  }

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) => _controller.stream;

  @override
  Future<bool> openAppSettings() async => true;
}

void main() {
  late FakeGeolocatorPlatform fakePlatform;
  late List<Map<String, dynamic>> posted;

  setUp(() {
    fakePlatform = FakeGeolocatorPlatform();
    GeolocatorPlatform.instance = fakePlatform;
    posted = [];
    FlutterSecureStorage.setMockInitialValues({'auth_token': 'tok'});
  });

  Future<T> withClient<T>(Future<T> Function() body) {
    final client = MockClient((request) async {
      if (request.method == 'POST' && request.url.path == '/api/locations') {
        posted.add({'at': DateTime.now()});
        return http.Response('{"report":{"id":"r1","reported_at":"2026-09-23T00:00:00.000Z","created_at":"2026-09-23T00:00:00.000Z"}}', 201,
            headers: {'content-type': 'application/json'});
      }
      return http.Response('{"error":"unexpected"}', 404);
    });
    return http.runWithClient(body, () => client);
  }

  testWidgets('a stationary device still checks in every 15 minutes, not just when it moves', (tester) async {
    await withClient(() async {
      final tracker = LocationTracker();
      await tracker.updateConsent(granted: true);
      await tester.pump(); // let the initial getCurrentPosition().then(...) resolve

      expect(posted.length, 1, reason: 'the first check-in happens immediately');

      // Nothing moves for 45 minutes — three 15-minute intervals — and the
      // fake never emits a stream event on its own (no moveAndEmit call).
      for (var i = 0; i < 3; i++) {
        await tester.pump(LocationTracker.reportInterval + const Duration(seconds: 1));
      }

      expect(posted.length, 4, reason: '1 initial + 3 scheduled check-ins while standing still');
      tracker.dispose();
    });
  });

  testWidgets('moving also still reports, and does not double up with the timer', (tester) async {
    await withClient(() async {
      final tracker = LocationTracker();
      await tracker.updateConsent(granted: true);
      await tester.pump();
      expect(posted.length, 1);

      // The device actually walks somewhere — a real, distance-triggered update.
      fakePlatform.moveAndEmit(32.09, -81.10);
      await tester.pump();
      expect(posted.length, 1, reason: 'too soon after the last report — still throttled to the interval');

      await tester.pump(LocationTracker.reportInterval + const Duration(seconds: 1));
      // Either the moved-to stream event or the timer's tick accounts for
      // this one; either way, exactly one more report goes out, not two.
      expect(posted.length, 2);
      tracker.dispose();
    });
  });

  testWidgets('turning sharing off stops the periodic timer', (tester) async {
    await withClient(() async {
      final tracker = LocationTracker();
      await tracker.updateConsent(granted: true);
      await tester.pump();
      expect(posted.length, 1);

      await tracker.updateConsent(granted: false);
      expect(tracker.isTracking, isFalse);

      await tester.pump(LocationTracker.reportInterval * 3);
      expect(posted.length, 1, reason: 'no more check-ins once sharing is off');
      tracker.dispose();
    });
  });

  testWidgets('a temporary GPS failure during a scheduled check-in is reported, not silent, and does not stop future ones', (tester) async {
    await withClient(() async {
      final tracker = LocationTracker();
      await tracker.updateConsent(granted: true);
      await tester.pump();
      expect(posted.length, 1);

      fakePlatform.serviceEnabled = false; // e.g. Location Services got turned off
      await tester.pump(LocationTracker.reportInterval + const Duration(seconds: 1));
      expect(tracker.lastError, isNotNull);
      expect(tracker.lastError, isNot(contains('PlatformException')), reason: 'still the friendly translation, not a raw dump');

      fakePlatform.serviceEnabled = true; // comes back before the next tick
      await tester.pump(LocationTracker.reportInterval + const Duration(seconds: 1));
      expect(posted.length, 2, reason: 'the next scheduled check-in still goes out once service is back');
      tracker.dispose();
    });
  });

  test('ApiClient plumbing sanity: dispose without ever starting is harmless', () {
    final tracker = LocationTracker();
    tracker.dispose();
  });
}
