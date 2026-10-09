import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ground_to_growth_connect/app_state.dart';
import 'package:ground_to_growth_connect/data/calendar_content.dart';
import 'package:ground_to_growth_connect/models/models.dart';
import 'package:ground_to_growth_connect/nav.dart';
import 'package:ground_to_growth_connect/theme/app_theme.dart';
import 'package:ground_to_growth_connect/util/calendar_items.dart';
import 'package:ground_to_growth_connect/util/time.dart';
import 'package:ground_to_growth_connect/views/main_tab_view.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'support/fake_api.dart';

Future<AppState> _pump(WidgetTester tester, FakeApi api, {String? mode}) async {
  tester.view.physicalSize = const Size(1200, 3200);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  FlutterSecureStorage.setMockInitialValues({'auth_token': 'tok', 'calendar_mode': ?mode});
  final state = AppState()
    ..user = User.fromJson(api.user)
    ..isUnlocked = true;
  state.calendar.debugPreloadEvents(const CalendarEventsContent(updatedAt: '2026-01-01', events: []));
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: state),
      ChangeNotifierProvider(create: (_) => TabNav(current: AppTab.calendar)),
    ],
    child: MaterialApp(theme: buildAppTheme(), darkTheme: buildAppTheme(), themeMode: ThemeMode.dark, home: const MainTabView()),
  ));
  await _settle(tester);
  return state;
}

Future<void> _settle(WidgetTester tester, {int times = 6}) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void _withApi(String description, Future<void> Function(WidgetTester tester, FakeApi api) body) {
  testWidgets(description, (tester) async {
    final api = FakeApi();
    await http.runWithClient(() => body(tester, api), () => api.client);
  });
}

DateTime get _today => dateOnly(DateTime.now());

Map<String, dynamic> _appt(String id, String title, DateTime start, {DateTime? end, bool allDay = false, String? location}) => {
      'id': id,
      'title': title,
      'notes': null,
      'location': location,
      'startsAt': start.toUtc().toIso8601String(),
      'endsAt': end?.toUtc().toIso8601String(),
      'allDay': allDay,
      'createdAt': '2026-09-26T12:00:00.000Z',
    };

String _dayKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

Future<void> _chooseView(WidgetTester tester, String name) async {
  await tester.tap(find.byKey(const Key('calendar-view-menu')));
  await _settle(tester, times: 3);
  await tester.tap(find.byKey(Key('view-$name')));
  await _settle(tester);
}

void main() {
  group('Month', () {
    _withApi('is where it opens, titled with the month, with today selected', (tester, api) async {
      api.appointments.add(_appt('a1', 'Dentist', DateTime(_today.year, _today.month, _today.day, 15), end: DateTime(_today.year, _today.month, _today.day, 16, 30)));
      await _pump(tester, api);
      expect(find.text(monthTitle(_today)), findsOneWidget);
      expect(find.byKey(Key('month-day-${_dayKey(_today)}')), findsOneWidget);
      expect(find.text(dayTitle(_today)), findsOneWidget);
      // Today's list shows it with its time range.
      expect(find.byKey(const Key('appointment-a1')), findsOneWidget);
      expect(find.text('3:00 PM – 4:30 PM'), findsOneWidget);
    });

    _withApi('tapping another day lists that day, and Today brings you back', (tester, api) async {
      final tomorrow = addDays(_today, 1);
      api.appointments.add(_appt('a1', 'Dentist', DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 10)));
      await _pump(tester, api);
      expect(find.byKey(const Key('appointment-a1')), findsNothing, reason: "it's tomorrow, not today");
      expect(find.byKey(const Key('day-empty')), findsOneWidget);

      await tester.tap(find.byKey(Key('month-day-${_dayKey(tomorrow)}')));
      await _settle(tester);
      expect(find.text(dayTitle(tomorrow)), findsOneWidget);
      expect(find.byKey(const Key('appointment-a1')), findsOneWidget);

      await tester.tap(find.byKey(const Key('calendar-today')));
      await _settle(tester);
      expect(find.text(dayTitle(_today)), findsOneWidget);
      expect(find.byKey(const Key('appointment-a1')), findsNothing);
    });

    _withApi('swiping moves to the next month', (tester, api) async {
      await _pump(tester, api);
      final next = DateTime(_today.year, _today.month + 1);
      await tester.drag(find.byKey(const Key('month-pages')), const Offset(-500, 0));
      await _settle(tester, times: 8);
      expect(find.text(monthTitle(next)), findsOneWidget);
      expect(find.text(dayTitle(next)), findsOneWidget, reason: 'the 1st of that month is selected');
    });

    _withApi('days with something on show it right in the grid', (tester, api) async {
      api.appointments.add(_appt('a1', 'Dentist', DateTime(_today.year, _today.month, _today.day, 15)));
      await _pump(tester, api);
      final cell = find.byKey(Key('month-day-${_dayKey(_today)}'));
      expect(find.descendant(of: cell, matching: find.text('Dentist')), findsOneWidget);
    });

    _withApi('a shelter event opens a read-only detail, and appointments open to edit', (tester, api) async {
      api.eventsBody = jsonEncode({
        'updatedAt': '2026-09-26',
        'events': [
          {'id': 'meal', 'title': 'Community Meal', 'description': 'Hot dinner, everyone welcome', 'location': 'Union Mission', 'startsAt': DateTime(_today.year, _today.month, _today.day, 17, 30).toUtc().toIso8601String()},
        ],
      });
      await _pump(tester, api);
      await _settle(tester);
      await tester.tap(find.byKey(const Key('event-meal')));
      await _settle(tester);
      expect(find.byKey(const Key('event-detail')), findsOneWidget);
      expect(find.text('Hot dinner, everyone welcome'), findsOneWidget);
      expect(find.text('Union Mission'), findsWidgets);
      expect(find.byKey(const Key('delete-appointment')), findsNothing, reason: 'shelter events are not yours to change');
    });

    _withApi('the + button adds an appointment on the selected day', (tester, api) async {
      final tomorrow = addDays(_today, 1);
      await _pump(tester, api);
      await tester.tap(find.byKey(Key('month-day-${_dayKey(tomorrow)}')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('add-appointment')));
      await _settle(tester);
      expect(find.text(shortDate(tomorrow)), findsWidgets, reason: 'the editor starts on the day you were looking at');
      expect(find.text('9:00 AM'), findsWidgets, reason: 'a day with no time starts mid-morning');
      await tester.enterText(find.byKey(const Key('appointment-title-field')), 'Shelter intake');
      await tester.tap(find.byKey(const Key('save-appointment')));
      await _settle(tester);
      final saved = api.appointments.single;
      expect(saved['title'], 'Shelter intake');
      expect(DateTime.parse(saved['startsAt'] as String).toLocal().day, tomorrow.day);
      expect(saved['endsAt'], isNotNull, reason: 'an hour by default');
    });
  });

  group('the editor', () {
    _withApi('All day hides the times and saves a whole-day appointment', (tester, api) async {
      await _pump(tester, api);
      await tester.tap(find.byKey(const Key('add-appointment')));
      await _settle(tester);
      expect(find.byKey(const Key('appointment-time-button')), findsOneWidget);
      expect(find.byKey(const Key('appointment-end-time-button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('appointment-allday-switch')));
      await _settle(tester, times: 3);
      expect(find.byKey(const Key('appointment-time-button')), findsNothing);
      expect(find.byKey(const Key('appointment-end-time-button')), findsNothing);

      await tester.enterText(find.byKey(const Key('appointment-title-field')), 'Court date');
      await tester.tap(find.byKey(const Key('save-appointment')));
      await _settle(tester);
      final saved = api.appointments.single;
      expect(saved['allDay'], true);
      expect(saved['endsAt'], isNull);
      expect(DateTime.parse(saved['startsAt'] as String).toLocal().hour, 0, reason: 'a whole day starts at midnight');
    });

    _withApi('editing keeps the end time, and turning on All day clears it', (tester, api) async {
      api.appointments.add(_appt('a1', 'Dentist', DateTime(_today.year, _today.month, _today.day, 15), end: DateTime(_today.year, _today.month, _today.day, 16)));
      await _pump(tester, api);
      await tester.tap(find.byKey(const Key('appointment-a1')));
      await _settle(tester);
      expect(find.byKey(const Key('appointment-end-time-button')), findsOneWidget);
      expect(find.text('4:00 PM'), findsOneWidget);

      await tester.tap(find.byKey(const Key('appointment-allday-switch')));
      await _settle(tester, times: 3);
      await tester.tap(find.byKey(const Key('save-appointment')));
      await _settle(tester);
      expect(api.appointments.single['allDay'], true);
      expect(api.appointments.single['endsAt'], isNull);
    });
  });

  group('an appointment or an event, and asking for a ride', () {
    _withApi('the editor offers both, and an event has no ride', (tester, api) async {
      await _pump(tester, api);
      await tester.tap(find.byKey(const Key('add-appointment')));
      await _settle(tester);
      expect(find.byKey(const Key('kind-picker')), findsOneWidget);
      expect(find.text('New appointment'), findsOneWidget);
      expect(find.byKey(const Key('appointment-ride-switch')), findsOneWidget);

      await tester.tap(find.descendant(of: find.byKey(const Key('kind-picker')), matching: find.text('Event')));
      await _settle(tester, times: 3);
      expect(find.text('New event'), findsOneWidget);
      expect(find.byKey(const Key('appointment-ride-switch')), findsNothing, reason: 'only an appointment can have a ride');

      await tester.enterText(find.byKey(const Key('appointment-title-field')), 'Birthday dinner');
      await tester.tap(find.byKey(const Key('save-appointment')));
      await _settle(tester);
      expect(api.appointments.single['kind'], 'event');
      expect(api.appointments.single['needsRide'], false);
      expect(api.helpRequests, isEmpty);
    });

    _withApi('"I need a ride" puts the ride on the board and says so on the calendar', (tester, api) async {
      await _pump(tester, api, mode: 'schedule');
      await tester.tap(find.byKey(const Key('add-appointment')));
      await _settle(tester);
      await tester.enterText(find.byKey(const Key('appointment-title-field')), 'DDS visit');
      await tester.ensureVisible(find.byKey(const Key('appointment-ride-switch')));
      await tester.tap(find.byKey(const Key('appointment-ride-switch')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('save-appointment')));
      await tester.tap(find.byKey(const Key('save-appointment')));
      await _settle(tester);

      expect(api.appointments.single['kind'], 'appointment');
      expect(api.appointments.single['needsRide'], true);
      final ride = api.helpRequests.single;
      expect(ride['category'], 'ride');
      expect((ride['appointment'] as Map)['title'], 'DDS visit');
      expect(find.text('Ride requested · waiting for a volunteer'), findsOneWidget);
    });

    _withApi('turning the ride off, or deleting the appointment, takes it off the board', (tester, api) async {
      api.appointments.add({..._appt('a1', 'DDS visit', DateTime(_today.year, _today.month, _today.day, 15)), 'needsRide': true});
      final state = await _pump(tester, api, mode: 'schedule');
      state.help.mine = [];
      api.helpRequests.add({
        'id': 'h1', 'category': 'ride', 'note': null, 'status': 'open', 'createdAt': DateTime.now().toUtc().toIso8601String(), 'claimedAt': null,
        'helperName': null, 'appointment': {'id': 'a1', 'title': 'DDS visit', 'location': null, 'startsAt': api.appointments.single['startsAt']},
        'userId': 'u1', 'name': 'Jane Doe', 'claimedByMe': false,
      });
      await tester.tap(find.byKey(const Key('appointment-a1')));
      await _settle(tester);
      expect(tester.widget<Switch>(find.descendant(of: find.byKey(const Key('appointment-ride-switch')), matching: find.byType(Switch))).value, true);
      await tester.tap(find.byKey(const Key('appointment-ride-switch')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('save-appointment')));
      await tester.tap(find.byKey(const Key('save-appointment')));
      await _settle(tester);
      expect(api.helpRequests, isEmpty, reason: 'no ride any more');
      expect(api.appointments.single['needsRide'], false);
    });

    _withApi('an all-day appointment cannot ask for a ride', (tester, api) async {
      await _pump(tester, api);
      await tester.tap(find.byKey(const Key('add-appointment')));
      await _settle(tester);
      expect(find.byKey(const Key('appointment-ride-switch')), findsOneWidget);
      await tester.tap(find.byKey(const Key('appointment-allday-switch')));
      await _settle(tester, times: 3);
      expect(find.byKey(const Key('appointment-ride-switch')), findsNothing);
    });

    _withApi('a matched ride shows who is taking you', (tester, api) async {
      api.appointments.add({..._appt('a1', 'DDS visit', DateTime(_today.year, _today.month, _today.day, 15)), 'needsRide': true});
      api.helpRequests.add({
        'id': 'h1', 'category': 'ride', 'note': null, 'status': 'claimed', 'createdAt': DateTime.now().toUtc().toIso8601String(), 'claimedAt': null,
        'helperName': 'Sam', 'appointment': {'id': 'a1', 'title': 'DDS visit', 'location': null, 'startsAt': api.appointments.single['startsAt']},
        'userId': 'u1', 'name': 'Jane Doe', 'claimedByMe': false,
      });
      await _pump(tester, api, mode: 'schedule');
      expect(find.text('Sam is taking you'), findsOneWidget);
      expect(find.text('Ride requested · waiting for a volunteer'), findsNothing);
    });
  });

  group('Week and Day', () {
    _withApi('the menu switches view, and the choice is remembered', (tester, api) async {
      api.appointments.add(_appt('a1', 'Dentist', DateTime(_today.year, _today.month, _today.day, 15), end: DateTime(_today.year, _today.month, _today.day, 16)));
      await _pump(tester, api);
      await _chooseView(tester, 'week');
      expect(find.byKey(const Key('time-grid-pages')), findsOneWidget);
      expect(find.byKey(Key('grid-head-${_today.year}-${_today.month}-${_today.day}')), findsOneWidget);
      expect(await FlutterSecureStorage().read(key: 'calendar_mode'), 'week');

      // Reopening the tab starts where they left off.
      await tester.pumpWidget(const SizedBox());
      await _pump(tester, api, mode: 'week');
      expect(find.byKey(const Key('time-grid-pages')), findsOneWidget);
    });

    _withApi('an appointment is a block on its day, and tapping it opens it', (tester, api) async {
      api.appointments.add(_appt('a1', 'Dentist', DateTime(_today.year, _today.month, _today.day, 15), end: DateTime(_today.year, _today.month, _today.day, 16)));
      await _pump(tester, api, mode: 'week');
      final block = find.byKey(Key('block-a1-${_today.day}'));
      // Put 3 PM near the top of the grid so it isn't behind the bottom bar.
      tester.state<ScrollableState>(find.descendant(of: find.byKey(const Key('time-grid-scroll')), matching: find.byType(Scrollable)).first).position.jumpTo(14 * 56);
      await _settle(tester, times: 2);
      expect(block, findsOneWidget);
      await tester.tap(block);
      await _settle(tester);
      expect(find.text('Edit appointment'), findsOneWidget);
    });

    _withApi('a line marks the current time on today', (tester, api) async {
      await _pump(tester, api, mode: 'day');
      expect(find.byKey(const Key('now-line'), skipOffstage: false), findsOneWidget);
    });

    _withApi('tapping an empty slot starts a new appointment at that time', (tester, api) async {
      await _pump(tester, api, mode: 'week');
      final scroll = tester.state<ScrollableState>(find.descendant(of: find.byKey(const Key('time-grid-scroll')), matching: find.byType(Scrollable)).first);
      scroll.position.jumpTo(0);
      await _settle(tester, times: 2);
      final col = find.byKey(Key('grid-col-${_today.year}-${_today.month}-${_today.day}'));
      // 9:15 on the grid (56px an hour) lands in the 9:00 slot.
      await tester.tapAt(tester.getTopLeft(col) + const Offset(6, 9 * 56 + 14));
      await _settle(tester);
      expect(find.text('New appointment'), findsOneWidget);
      expect(find.text('9:00 AM'), findsOneWidget);
      expect(find.text('10:00 AM'), findsOneWidget, reason: 'it runs an hour by default');
    });

    _withApi('tapping a date in the week jumps to that Day', (tester, api) async {
      await _pump(tester, api, mode: 'week');
      await tester.tap(find.byKey(Key('grid-head-${_today.year}-${_today.month}-${_today.day}')));
      await _settle(tester);
      final days = tester.widgetList(find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('grid-col-'))).length;
      expect(days, 1, reason: 'Day view has a single column');
    });

    _withApi('all-day items sit in a strip at the top', (tester, api) async {
      api.appointments.add(_appt('a1', 'Court date', _today, allDay: true));
      await _pump(tester, api, mode: 'day');
      expect(find.text('all-day'), findsOneWidget);
      expect(find.text('Court date'), findsOneWidget);
      expect(find.byKey(Key('block-a1-${_today.day}')), findsNothing, reason: 'not drawn on the hour grid');
    });
  });

  group('Schedule', () {
    _withApi('lists today first even when empty, then each day that has something', (tester, api) async {
      final later = addDays(_today, 3);
      api.appointments.add(_appt('a1', 'Dentist', DateTime(later.year, later.month, later.day, 10)));
      await _pump(tester, api, mode: 'schedule');
      expect(find.text('Nothing planned'), findsOneWidget, reason: 'today has nothing, and says so');
      expect(find.byKey(const Key('appointment-a1')), findsOneWidget);
      expect(find.text('Nothing coming up'), findsNothing);
    });

    _withApi('shows a friendly note when there is nothing at all', (tester, api) async {
      await _pump(tester, api, mode: 'schedule');
      expect(find.text('Nothing coming up'), findsOneWidget);
    });
  });
}
