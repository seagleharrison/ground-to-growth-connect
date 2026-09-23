import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:ground_to_growth_connect/services/location_tracker.dart';

void main() {
  group('friendlyLocationError', () {
    test('a denied permission reads as plain instructions, not the raw platform message', () {
      // What iOS actually hands the plugin in the field (see the App Store
      // build 3 report): PermissionDeniedException.message carries the raw
      // CoreLocation string, so the translation must not just re-print it.
      final e = const PermissionDeniedException("The operation couldn't be completed. (kCLErrorDomain error 1.)");
      final message = friendlyLocationError(e);
      expect(message, contains('Settings'));
      expect(message, isNot(contains('kCLErrorDomain')));
      expect(message, isNot(contains('operation couldn')));
    });

    test('location services being off reads as plain instructions', () {
      final message = friendlyLocationError(const LocationServiceDisabledException());
      expect(message, contains('Settings'));
      expect(message, isNot(contains('disabled')), reason: 'not the plugin\'s own wording');
    });

    test('anything else still reads as a sentence, never a raw exception dump', () {
      final message = friendlyLocationError(Exception('SocketException: Connection reset by peer'));
      expect(message, isNot(contains('SocketException')));
      expect(message, isNot(contains('Connection reset')));
    });
  });
}
