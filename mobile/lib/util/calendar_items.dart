import 'package:flutter/material.dart';

import '../data/calendar_content.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import 'time.dart';

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// Calendar-safe: adding days across a daylight-saving change keeps midnight.
DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

int daysBetween(DateTime a, DateTime b) => DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

/// Weeks start on Sunday, like Google Calendar in the US.
DateTime startOfWeek(DateTime d) => addDays(dateOnly(d), -(d.weekday % 7));

DateTime monthOf(DateTime d) => DateTime(d.year, d.month);

int daysInMonth(DateTime month) => DateTime(month.year, month.month + 1, 0).day;

/// Every day shown on a month grid: whole weeks, so it starts on the Sunday on
/// or before the 1st and ends on the Saturday on or after the last day.
List<DateTime> monthGridDays(DateTime month) {
  final first = DateTime(month.year, month.month);
  final start = startOfWeek(first);
  final weeks = ((first.weekday % 7) + daysInMonth(first) + 6) ~/ 7;
  return [for (var i = 0; i < weeks * 7; i++) addDays(start, i)];
}

const monthNames = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const weekdayShort = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const weekdayLetters = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

String monthTitle(DateTime d) => '${monthNames[d.month - 1]} ${d.year}';

/// "Thursday, Oct 8"
String dayTitle(DateTime d) => fullDate(d);

/// One thing on the calendar: a shelter/program event (read-only, from the
/// server) or the person's own private appointment (editable).
class CalendarItem {
  final String id;
  final String title;
  final DateTime start;
  final DateTime? end;
  final bool allDay;
  final String? location;
  final String? notes; // an appointment's notes, or an event's description
  final Appointment? appointment; // non-null only for a personal appointment or event
  final String? helper; // first name of a volunteer taking them there
  final HelpRequest? ride; // the ride asked for this appointment, if any

  const CalendarItem({
    required this.id,
    required this.title,
    required this.start,
    this.end,
    this.allDay = false,
    this.location,
    this.notes,
    this.appointment,
    this.helper,
    this.ride,
  });

  /// One of the person's own things (an appointment or an event), as opposed
  /// to a shelter or program event.
  bool get isAppointment => appointment != null;
  bool get isPersonalEvent => appointment?.isEvent == true;
  bool get needsRide => appointment?.needsRide == true;

  /// Something with no end time still takes up a visible hour on a time grid.
  DateTime get effectiveEnd => allDay ? addDays(dateOnly(start), 1) : (end ?? start.add(const Duration(hours: 1)));

  /// Whether any part of this falls on [day].
  bool occursOn(DateTime day) {
    final dayStart = dateOnly(day);
    final dayEnd = addDays(dayStart, 1);
    if (allDay) return !dayStart.isBefore(dateOnly(start)) && dayStart.isBefore(effectiveEnd);
    return start.isBefore(dayEnd) && effectiveEnd.isAfter(dayStart);
  }

  /// Something spanning a whole day or more is shown in the "all-day" strip.
  bool get showsAsAllDay => allDay || effectiveEnd.difference(start) >= const Duration(hours: 24);

  /// Appointments are orange, the person's own events lavender, shelter events blue.
  Color get color => isPersonalEvent ? const Color(0xFFB9A2FF) : (isAppointment ? Brand.orange : Brand.blue);
  Color get onColor => isPersonalEvent ? const Color(0xFF241447) : (isAppointment ? const Color(0xFF3A1D00) : const Color(0xFF06223F));
}

List<CalendarItem> buildCalendarItems(
  CalendarEventsContent? content,
  List<Appointment> appointments, {
  String? Function(String appointmentId)? helperFor,
  HelpRequest? Function(String appointmentId)? rideFor,
}) {
  final items = <CalendarItem>[
    for (final e in content?.events ?? const <CalendarEventInfo>[])
      CalendarItem(id: e.id, title: e.title, start: e.startsAtLocal, end: e.endsAtLocal, location: e.location, notes: e.description),
    for (final a in appointments)
      CalendarItem(
        id: a.id,
        title: a.title,
        start: a.startsAtLocal,
        end: a.endsAtLocal,
        allDay: a.allDay,
        location: a.location,
        notes: a.notes,
        appointment: a,
        helper: helperFor?.call(a.id),
        ride: rideFor?.call(a.id),
      ),
  ];
  items.sort(compareItems);
  return items;
}

/// All-day things first, then by start time, longest first.
int compareItems(CalendarItem a, CalendarItem b) {
  if (a.showsAsAllDay != b.showsAsAllDay) return a.showsAsAllDay ? -1 : 1;
  final byStart = a.start.compareTo(b.start);
  if (byStart != 0) return byStart;
  return b.effectiveEnd.compareTo(a.effectiveEnd);
}

List<CalendarItem> itemsOnDay(List<CalendarItem> items, DateTime day) => [for (final i in items) if (i.occursOn(day)) i];

/// "2:00 PM – 3:30 PM", "All day", or just "2:00 PM" when there's no end.
String itemTimeLabel(CalendarItem item, {DateTime? onDay}) {
  if (item.allDay) return 'All day';
  final end = item.end;
  if (end == null) return clockTime(item.start);
  final sameDayEnd = sameDay(item.start, end);
  return '${clockTime(item.start)} – ${sameDayEnd ? '' : '${shortDate(end)}, '}${clockTime(end)}';
}

/// An item placed on a single day's time grid.
class PlacedItem {
  final CalendarItem item;
  final int startMin;
  final int endMin;
  int lane = 0;
  int lanes = 1;
  PlacedItem(this.item, this.startMin, this.endMin);
}

/// Where each timed item sits on [day]'s grid, side by side when they overlap.
/// Anything shorter than [minMinutes] is drawn that tall so it stays tappable.
List<PlacedItem> layoutDay(List<CalendarItem> items, DateTime day, {int minMinutes = 30}) {
  final dayStart = dateOnly(day);
  final dayEnd = addDays(dayStart, 1);
  final placed = <PlacedItem>[];
  for (final item in items) {
    if (item.showsAsAllDay || !item.occursOn(day)) continue;
    final s = item.start.isBefore(dayStart) ? dayStart : item.start;
    final e = item.effectiveEnd.isAfter(dayEnd) ? dayEnd : item.effectiveEnd;
    final startMin = s.difference(dayStart).inMinutes;
    var endMin = e.difference(dayStart).inMinutes;
    if (endMin < startMin + minMinutes) endMin = startMin + minMinutes;
    if (endMin > 24 * 60) endMin = 24 * 60;
    placed.add(PlacedItem(item, startMin, endMin));
  }
  placed.sort((a, b) => a.startMin != b.startMin ? a.startMin.compareTo(b.startMin) : b.endMin.compareTo(a.endMin));

  var cluster = <PlacedItem>[];
  var clusterEnd = -1;
  void closeCluster() {
    final lanes = cluster.isEmpty ? 1 : cluster.map((p) => p.lane).reduce((a, b) => a > b ? a : b) + 1;
    for (final p in cluster) {
      p.lanes = lanes;
    }
    cluster = [];
  }

  final laneEnds = <int>[];
  for (final p in placed) {
    if (p.startMin >= clusterEnd) {
      closeCluster();
      laneEnds.clear();
      clusterEnd = -1;
    }
    var lane = laneEnds.indexWhere((end) => end <= p.startMin);
    if (lane == -1) {
      lane = laneEnds.length;
      laneEnds.add(p.endMin);
    } else {
      laneEnds[lane] = p.endMin;
    }
    p.lane = lane;
    cluster.add(p);
    if (p.endMin > clusterEnd) clusterEnd = p.endMin;
  }
  closeCluster();
  return placed;
}
