import 'package:flutter_test/flutter_test.dart';
import 'package:ground_to_growth_connect/models/models.dart';
import 'package:ground_to_growth_connect/util/journey.dart';
import 'package:ground_to_growth_connect/util/time.dart';
import 'package:latlong2/latlong.dart';

MyLocationReport report(String isoUtc, double lat, double lng) =>
    MyLocationReport(latitude: lat, longitude: lng, reportedAt: isoUtc);

void main() {
  group('groupByLocalDay', () {
    test('groups by the local calendar day and orders both days and stops', () {
      // Built from local times so the test passes in any time zone.
      String utc(int d, int h, int m) => DateTime(2026, 9, d, h, m).toUtc().toIso8601String();
      final days = groupByLocalDay([
        report(utc(21, 15, 0), 32.08, -81.09),
        report(utc(20, 9, 0), 32.07, -81.10),
        report(utc(21, 8, 30), 32.081, -81.091),
        report(utc(20, 21, 45), 32.075, -81.095), // 9:45 PM must stay on the 20th
      ]);

      expect(days.map((d) => d.key), ['2026-09-20', '2026-09-21']);
      expect(days[0].stops, 2);
      expect(days[1].stops, 2);
      expect(days[0].first.hour, 9);
      expect(days[0].last.hour, 21, reason: 'a late evening check-in belongs to that evening, not the next UTC day');
      expect(days[1].first.isBefore(days[1].last), isTrue);
    });

    test('ignores reports with unreadable times and handles no data', () {
      expect(groupByLocalDay([]), isEmpty);
      expect(groupByLocalDay([report('not a date', 1, 1)]), isEmpty);
    });
  });

  group('distance', () {
    test('haversine matches a known distance', () {
      // Savannah City Hall to Forsyth Park is roughly 1.7 km.
      final d = haversineMeters(const LatLng(32.0809, -81.0912), const LatLng(32.0682, -81.0959));
      expect(d, inInclusiveRange(1300, 1700));
      expect(haversineMeters(const LatLng(1, 1), const LatLng(1, 1)), 0);
    });

    test('formats in miles', () {
      expect(formatDistance(50), 'under 0.1 mi');
      expect(formatDistance(1609.344), '1.0 mi');
      expect(formatDistance(16093.44 * 2), '20 mi');
    });
  });

  group('replay path', () {
    const path = [LatLng(0, 0), LatLng(0, 1), LatLng(0, 3)]; // second hop is twice as long

    test('pointAlong moves at an even pace by distance', () {
      expect(pointAlong(path, 0), const LatLng(0, 0));
      expect(pointAlong(path, 1), const LatLng(0, 3));
      final mid = pointAlong(path, 0.5); // halfway = 1.5 degrees along
      expect(mid.longitude, closeTo(1.5, 0.01));
      final third = pointAlong(path, 1 / 3); // exactly the first stop
      expect(third.longitude, closeTo(1.0, 0.01));
    });

    test('pathUntil ends exactly where the marker is', () {
      final part = pathUntil(path, 0.5);
      expect(part.first, const LatLng(0, 0));
      expect(part.length, 3, reason: 'start, first stop, and the point partway to the last');
      expect(part.last.longitude, closeTo(1.5, 0.01));
      expect(pathUntil(path, 1), path);
      expect(pathUntil(path, 0), [const LatLng(0, 0)]);
    });

    test('a single point or no points does not crash', () {
      expect(pointAlong(const [LatLng(5, 5)], 0.7), const LatLng(5, 5));
      expect(pointAlong(const [], 0.5), const LatLng(0, 0));
      expect(pathUntil(const [], 0.5), isEmpty);
    });
  });

  group('labels', () {
    final now = DateTime(2026, 9, 21, 14, 0);
    test('day labels', () {
      expect(dayLabel(DateTime(2026, 9, 21), now: now), 'Today');
      expect(dayLabel(DateTime(2026, 9, 20), now: now), 'Yesterday');
      expect(dayLabel(DateTime(2026, 9, 12), now: now), 'Sep 12');
    });

    test('time ago', () {
      expect(timeAgo(now.subtract(const Duration(seconds: 20)), now: now), 'just now');
      expect(timeAgo(now.subtract(const Duration(minutes: 4)), now: now), '4 min ago');
      expect(timeAgo(now.subtract(const Duration(hours: 3)), now: now), '3 h ago');
      expect(timeAgo(now.subtract(const Duration(days: 1, hours: 2)), now: now), 'Yesterday');
      expect(timeAgo(now.subtract(const Duration(days: 20)), now: now), 'Sep 1');
    });

    test('clock time and names', () {
      expect(clockTime(DateTime(2026, 1, 1, 0, 5)), '12:05 AM');
      expect(clockTime(DateTime(2026, 1, 1, 13, 30)), '1:30 PM');
      expect(firstName('  Jane Q. Doe '), 'Jane');
      expect(firstName(''), 'there');
      expect(greeting(DateTime(2026, 1, 1, 9)), 'Good morning');
      expect(greeting(DateTime(2026, 1, 1, 15)), 'Good afternoon');
      expect(greeting(DateTime(2026, 1, 1, 20)), 'Good evening');
    });

    test('recency thresholds', () {
      expect(recencyOf(now.subtract(const Duration(minutes: 10)), now: now), Recency.activeNow);
      expect(recencyOf(now.subtract(const Duration(minutes: 90)), now: now), Recency.recent);
      expect(recencyOf(now.subtract(const Duration(hours: 5)), now: now), Recency.stale);
    });
  });
}
