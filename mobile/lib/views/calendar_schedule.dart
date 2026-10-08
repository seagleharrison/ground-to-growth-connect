import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../util/calendar_items.dart';
import '../widgets/ui.dart';
import 'calendar_widgets.dart';

/// "What's coming up": today and every later day that has something on, one
/// day after another, with the date on the left like Google's Schedule view.
class CalendarScheduleView extends StatelessWidget {
  final List<CalendarItem> items;
  final bool loading;
  final ValueChanged<CalendarItem> onOpen;
  final Future<void> Function() onRefresh;
  const CalendarScheduleView({
    super.key,
    required this.items,
    required this.loading,
    required this.onOpen,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final today = dateOnly(DateTime.now());
    final days = <DateTime>{};
    for (final i in items) {
      var d = dateOnly(i.start).isBefore(today) ? today : dateOnly(i.start);
      final last = dateOnly(
        i.effectiveEnd.subtract(const Duration(minutes: 1)),
      );
      // A long item (a multi-day event) appears on each day it covers.
      for (var n = 0; n < 60 && !d.isAfter(last); n++) {
        days.add(d);
        d = addDays(d, 1);
      }
    }
    final upcoming = days.where((d) => !d.isBefore(today)).toList()..sort();
    final withToday = upcoming.contains(today)
        ? upcoming
        : [today, ...upcoming];

    final children = <Widget>[];
    if (loading) {
      children.add(
        const Padding(
          padding: EdgeInsets.only(top: 80),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    } else if (upcoming.isEmpty) {
      children.add(
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Nothing coming up',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                SizedBox(height: 6),
                Text(
                  'Tap the + to add your own appointment. Shelter and program events will show up here too.',
                  style: TextStyle(color: Colors.white70, height: 1.4),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      DateTime? lastMonth;
      for (final day in withToday) {
        final dayItems = itemsOnDay(items, day);
        final newMonth =
            lastMonth == null ||
            lastMonth.month != day.month ||
            lastMonth.year != day.year;
        // The top of the screen already names the current month.
        if (newMonth &&
            !(lastMonth == null &&
                day.month == today.month &&
                day.year == today.year)) {
          children.add(
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                monthTitle(day),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: Colors.white70,
                ),
              ),
            ),
          );
        }
        if (newMonth) lastMonth = day;
        children.add(
          _ScheduleDay(
            day: day,
            isToday: sameDay(day, today),
            items: dayItems,
            onOpen: onOpen,
          ),
        );
      }
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        key: const Key('schedule-list'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: kNavBarClearance),
        children: children,
      ),
    );
  }
}

class _ScheduleDay extends StatelessWidget {
  final DateTime day;
  final bool isToday;
  final List<CalendarItem> items;
  final ValueChanged<CalendarItem> onOpen;
  const _ScheduleDay({
    required this.day,
    required this.isToday,
    required this.items,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 52,
            child: Column(
              children: [
                Text(
                  weekdayShort[day.weekday % 7].toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isToday ? Brand.orange : Colors.white54,
                  ),
                ),
                const SizedBox(height: 2),
                DayNumber(day: day, isToday: isToday, size: 34, fontSize: 17),
              ],
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'Nothing planned',
                      style: TextStyle(color: Colors.white38),
                    ),
                  )
                : Column(
                    children: [
                      for (final i in items)
                        EventTile(item: i, onTap: () => onOpen(i)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
