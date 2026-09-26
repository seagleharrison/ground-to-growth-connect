import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// A shelter/program event (a meal, a drive, office hours) shown on the
/// Calendar tab. Comes from the server (so it can be added or changed without
/// a new app release), with a copy bundled in the app for when there's no signal.
class CalendarEventInfo {
  final String id;
  final String title;
  final String? description;
  final String? location;
  final String startsAt;

  const CalendarEventInfo({
    required this.id,
    required this.title,
    this.description,
    this.location,
    required this.startsAt,
  });

  DateTime get startsAtLocal => DateTime.parse(startsAt).toLocal();

  factory CalendarEventInfo.fromJson(Map<String, dynamic> json) => CalendarEventInfo(
    id: json['id'] as String,
    title: json['title'] as String,
    description: json['description'] as String?,
    location: json['location'] as String?,
    startsAt: json['startsAt'] as String,
  );
}

class CalendarEventsContent {
  final String updatedAt;
  final List<CalendarEventInfo> events;

  const CalendarEventsContent({required this.updatedAt, required this.events});

  factory CalendarEventsContent.fromJson(Map<String, dynamic> json) => CalendarEventsContent(
    updatedAt: json['updatedAt'] as String,
    events: [for (final e in (json['events'] as List? ?? [])) CalendarEventInfo.fromJson(e as Map<String, dynamic>)],
  );

  static Future<CalendarEventsContent> loadBundled() async {
    final raw = await rootBundle.loadString('assets/events.json');
    return CalendarEventsContent.fromRaw(raw);
  }

  /// Reads the server's JSON. Throws [FormatException] if it isn't the expected shape,
  /// so a bad response can never replace good content.
  static CalendarEventsContent fromRaw(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) throw const FormatException('Events content must be a JSON object');
    return CalendarEventsContent.fromJson(decoded);
  }
}
