import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../models/models.dart';
import 'time.dart';

/// One local calendar day of check-ins, oldest first.
class JourneyDay {
  final String key; // yyyy-MM-dd in the person's own time zone
  final DateTime date; // local midnight of that day
  final List<MyLocationReport> reports;
  final List<DateTime> times; // local time of each report, same order
  final List<LatLng> points;

  JourneyDay({required this.key, required this.date, required this.reports, required this.times})
      : points = [for (final r in reports) LatLng(r.latitude, r.longitude)];

  int get stops => reports.length;
  DateTime get first => times.first;
  DateTime get last => times.last;
  LatLng get anchor => points.last;
  double get distanceMeters => pathLengthMeters(points);
}

/// Groups check-ins by the person's *local* day. Grouping by UTC would put
/// a 9 PM check-in on "tomorrow" for anyone in Georgia.
List<JourneyDay> groupByLocalDay(List<MyLocationReport> reports) {
  final byDay = <String, List<(DateTime, MyLocationReport)>>{};
  for (final r in reports) {
    final t = DateTime.tryParse(r.reportedAt)?.toLocal();
    if (t == null) continue;
    final key = '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
    (byDay[key] ??= []).add((t, r));
  }
  final days = byDay.entries.map((e) {
    final sorted = [...e.value]..sort((a, b) => a.$1.compareTo(b.$1));
    final t = sorted.first.$1;
    return JourneyDay(
      key: e.key,
      date: DateTime(t.year, t.month, t.day),
      reports: [for (final s in sorted) s.$2],
      times: [for (final s in sorted) s.$1],
    );
  }).toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  return days;
}

const _earthRadiusMeters = 6371000.0;

double haversineMeters(LatLng a, LatLng b) {
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(b.latitude - a.latitude);
  final dLng = rad(b.longitude - a.longitude);
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(a.latitude)) * math.cos(rad(b.latitude)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * _earthRadiusMeters * math.asin(math.min(1, math.sqrt(h)));
}

double pathLengthMeters(List<LatLng> points) {
  var total = 0.0;
  for (var i = 1; i < points.length; i++) {
    total += haversineMeters(points[i - 1], points[i]);
  }
  return total;
}

/// "0.3 mi" — miles, because that's what people in Savannah think in.
String formatDistance(double meters) {
  final miles = meters / 1609.344;
  if (miles < 0.1) return 'under 0.1 mi';
  return '${miles.toStringAsFixed(miles < 10 ? 1 : 0)} mi';
}

String dayLabel(DateTime date, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final d0 = DateTime(date.year, date.month, date.day);
  final t0 = DateTime(today.year, today.month, today.day);
  final diff = t0.difference(d0).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return shortDate(date);
}

/// The point [t] (0..1) of the way along the path, measured by distance so a
/// replay moves at an even pace instead of speeding through short hops.
LatLng pointAlong(List<LatLng> points, double t) {
  if (points.isEmpty) return const LatLng(0, 0);
  if (points.length == 1 || t <= 0) return points.first;
  if (t >= 1) return points.last;
  final total = pathLengthMeters(points);
  if (total == 0) return points.first;
  var remaining = total * t;
  for (var i = 1; i < points.length; i++) {
    final seg = haversineMeters(points[i - 1], points[i]);
    if (remaining <= seg) {
      final f = seg == 0 ? 0.0 : remaining / seg;
      return LatLng(
        points[i - 1].latitude + (points[i].latitude - points[i - 1].latitude) * f,
        points[i - 1].longitude + (points[i].longitude - points[i - 1].longitude) * f,
      );
    }
    remaining -= seg;
  }
  return points.last;
}

/// The part of the path travelled so far, ending exactly at [pointAlong].
List<LatLng> pathUntil(List<LatLng> points, double t) {
  if (points.length < 2 || t <= 0) return points.isEmpty ? [] : [points.first];
  if (t >= 1) return List.of(points);
  final total = pathLengthMeters(points);
  if (total == 0) return [points.first];
  final target = total * t;
  final out = <LatLng>[points.first];
  var walked = 0.0;
  for (var i = 1; i < points.length; i++) {
    final seg = haversineMeters(points[i - 1], points[i]);
    if (walked + seg >= target) {
      out.add(pointAlong(points, t));
      return out;
    }
    walked += seg;
    out.add(points[i]);
  }
  return out;
}

/// How long ago a staff member's person was last seen, for colouring markers.
enum Recency { activeNow, recent, stale }

Recency recencyOf(DateTime reportedAt, {DateTime? now}) {
  final age = (now ?? DateTime.now()).difference(reportedAt);
  if (age.inMinutes < 30) return Recency.activeNow;
  if (age.inHours < 2) return Recency.recent;
  return Recency.stale;
}
