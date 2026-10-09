import 'package:flutter_test/flutter_test.dart';
import 'package:ground_to_growth_connect/models/models.dart';
import 'package:ground_to_growth_connect/theme/app_theme.dart';
import 'package:ground_to_growth_connect/util/calendar_items.dart';

CalendarItem item(String id, DateTime start, {DateTime? end, bool allDay = false}) =>
    CalendarItem(id: id, title: id, start: start, end: end, allDay: allDay);

void main() {
  group('dates', () {
    test('weeks start on Sunday', () {
      expect(startOfWeek(DateTime(2026, 10, 8)), DateTime(2026, 10, 4)); // Thursday -> Sunday
      expect(startOfWeek(DateTime(2026, 10, 4)), DateTime(2026, 10, 4)); // Sunday stays
      expect(startOfWeek(DateTime(2026, 10, 10)), DateTime(2026, 10, 4)); // Saturday
    });

    test('a month grid is whole weeks around the month', () {
      final oct = monthGridDays(DateTime(2026, 10)); // Oct 1 is a Thursday
      expect(oct.length, 35);
      expect(oct.first, DateTime(2026, 9, 27));
      expect(oct.last, DateTime(2026, 10, 31));
      final feb = monthGridDays(DateTime(2026, 2)); // starts on a Sunday, 28 days
      expect(feb.length, 28);
      final aug = monthGridDays(DateTime(2026, 8)); // starts on Saturday, 31 days
      expect(aug.length, 42);
      expect(aug.first, DateTime(2026, 7, 26));
    });

    test('adding days survives a daylight-saving change', () {
      expect(addDays(DateTime(2026, 3, 7), 2), DateTime(2026, 3, 9)); // US clocks change Mar 8
      expect(addDays(DateTime(2026, 10, 31), 1), DateTime(2026, 11, 1));
      expect(daysBetween(DateTime(2026, 3, 7), DateTime(2026, 3, 9)), 2);
    });
  });

  group('what falls on a day', () {
    test('a timed item is on its own day only', () {
      final i = item('a', DateTime(2026, 10, 8, 14), end: DateTime(2026, 10, 8, 15));
      expect(i.occursOn(DateTime(2026, 10, 8)), isTrue);
      expect(i.occursOn(DateTime(2026, 10, 7)), isFalse);
      expect(i.occursOn(DateTime(2026, 10, 9)), isFalse);
    });

    test('one ending at midnight does not spill into the next day', () {
      final i = item('a', DateTime(2026, 10, 8, 22), end: DateTime(2026, 10, 9));
      expect(i.occursOn(DateTime(2026, 10, 9)), isFalse);
    });

    test('one running past midnight shows on both days', () {
      final i = item('a', DateTime(2026, 10, 8, 22), end: DateTime(2026, 10, 9, 2));
      expect(i.occursOn(DateTime(2026, 10, 8)), isTrue);
      expect(i.occursOn(DateTime(2026, 10, 9)), isTrue);
    });

    test('an all-day item fills exactly its own day', () {
      final i = item('a', DateTime(2026, 10, 8), allDay: true);
      expect(i.occursOn(DateTime(2026, 10, 8)), isTrue);
      expect(i.occursOn(DateTime(2026, 10, 9)), isFalse);
      expect(i.showsAsAllDay, isTrue);
    });

    test('with no end time it still takes an hour', () {
      final i = item('a', DateTime(2026, 10, 8, 23, 30));
      expect(i.effectiveEnd, DateTime(2026, 10, 9, 0, 30));
      expect(i.occursOn(DateTime(2026, 10, 9)), isTrue);
    });
  });

  group('labels and order', () {
    test('time labels', () {
      expect(itemTimeLabel(item('a', DateTime(2026, 10, 8), allDay: true)), 'All day');
      expect(itemTimeLabel(item('a', DateTime(2026, 10, 8, 14))), '2:00 PM');
      expect(itemTimeLabel(item('a', DateTime(2026, 10, 8, 14), end: DateTime(2026, 10, 8, 15, 30))), '2:00 PM – 3:30 PM');
      expect(itemTimeLabel(item('a', DateTime(2026, 10, 8, 22), end: DateTime(2026, 10, 9, 2))), '10:00 PM – Oct 9, 2:00 AM');
    });

    test('all-day first, then by start time', () {
      final list = [
        item('late', DateTime(2026, 10, 8, 16)),
        item('early', DateTime(2026, 10, 8, 9)),
        item('allday', DateTime(2026, 10, 8), allDay: true),
      ]..sort(compareItems);
      expect(list.map((i) => i.id), ['allday', 'early', 'late']);
    });
  });

  group('laying out a day', () {
    final day = DateTime(2026, 10, 8);

    test('items that do not overlap each get the full width', () {
      final placed = layoutDay([
        item('a', DateTime(2026, 10, 8, 9), end: DateTime(2026, 10, 8, 10)),
        item('b', DateTime(2026, 10, 8, 11), end: DateTime(2026, 10, 8, 12)),
      ], day);
      expect(placed.map((p) => p.lanes), [1, 1]);
      expect(placed.map((p) => p.lane), [0, 0]);
    });

    test('overlapping items sit side by side', () {
      final placed = layoutDay([
        item('a', DateTime(2026, 10, 8, 9), end: DateTime(2026, 10, 8, 11)),
        item('b', DateTime(2026, 10, 8, 10), end: DateTime(2026, 10, 8, 12)),
      ], day);
      expect(placed.map((p) => p.lanes), [2, 2]);
      expect({placed[0].lane, placed[1].lane}, {0, 1});
    });

    test('a lane is reused once it is free', () {
      final placed = layoutDay([
        item('a', DateTime(2026, 10, 8, 9), end: DateTime(2026, 10, 8, 11)),
        item('b', DateTime(2026, 10, 8, 10), end: DateTime(2026, 10, 8, 12)),
        item('c', DateTime(2026, 10, 8, 11), end: DateTime(2026, 10, 8, 12, 30)),
      ], day);
      final c = placed.firstWhere((p) => p.item.id == 'c');
      expect(c.lane, 0, reason: 'a ended at 11, so its lane is free for c');
      expect(placed.every((p) => p.lanes == 2), isTrue);
    });

    test('a very short item is drawn tall enough to tap', () {
      final placed = layoutDay([item('a', DateTime(2026, 10, 8, 9), end: DateTime(2026, 10, 8, 9, 5))], day);
      expect(placed.single.endMin - placed.single.startMin, 30);
    });

    test('all-day items are left to the all-day strip', () {
      expect(layoutDay([item('a', DateTime(2026, 10, 8), allDay: true)], day), isEmpty);
    });

    test('an item running past midnight is cut at the end of the day', () {
      final placed = layoutDay([item('a', DateTime(2026, 10, 8, 22), end: DateTime(2026, 10, 9, 2))], day);
      expect(placed.single.startMin, 22 * 60);
      expect(placed.single.endMin, 24 * 60);
      final next = layoutDay([item('a', DateTime(2026, 10, 8, 22), end: DateTime(2026, 10, 9, 2))], DateTime(2026, 10, 9));
      expect(next.single.startMin, 0);
      expect(next.single.endMin, 2 * 60);
    });
  });

  group('colours say what kind of thing it is', () {
    Appointment appt(String kind) => Appointment(id: 'a', title: 't', startsAt: '2026-12-01T15:00:00Z', kind: kind, createdAt: '2026-10-01T00:00:00Z');

    test('appointments are orange, their own events lavender, shelter events blue', () {
      final start = DateTime(2026, 12, 1, 15);
      final appointment = CalendarItem(id: 'a', title: 't', start: start, appointment: appt('appointment'));
      final event = CalendarItem(id: 'e', title: 't', start: start, appointment: appt('event'));
      final shelter = CalendarItem(id: 's', title: 't', start: start);
      expect(appointment.color, Brand.orange);
      expect(shelter.color, Brand.blue);
      expect(event.color, isNot(anyOf(Brand.orange, Brand.blue)));
      expect(event.isPersonalEvent, isTrue);
      expect(appointment.isPersonalEvent, isFalse);
      expect(shelter.isAppointment, isFalse);
    });
  });
}
