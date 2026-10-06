import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ground_to_growth_connect/app_state.dart';
import 'package:ground_to_growth_connect/data/calendar_content.dart';
import 'package:ground_to_growth_connect/models/models.dart';
import 'package:ground_to_growth_connect/nav.dart';
import 'package:ground_to_growth_connect/theme/app_theme.dart';
import 'package:ground_to_growth_connect/views/main_tab_view.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'support/fake_api.dart';

String eventsJsonWith(List<Map<String, dynamic>> events) => jsonEncode({'updatedAt': '2026-09-26', 'events': events});

Future<AppState> _pump(WidgetTester tester, FakeApi api, {String personType = 'homeless'}) async {
  tester.view.physicalSize = const Size(1200, 3200);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  FlutterSecureStorage.setMockInitialValues({'auth_token': 'tok'});
  api.user['personType'] = personType;
  api.user['isStaff'] = personType != 'homeless';
  final state = AppState()
    ..user = User.fromJson(api.user)
    ..isUnlocked = true;
  // Skips the real bundled-asset read (flaky across repeated testWidgets runs
  // in the same file) — the server fetch below is what each test actually
  // means to exercise.
  state.calendar.debugPreloadEvents(const CalendarEventsContent(updatedAt: '2026-01-01', events: []));
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: state),
      ChangeNotifierProvider(create: (_) => TabNav(current: AppTab.calendar)),
    ],
    child: MaterialApp(theme: buildAppTheme(), darkTheme: buildAppTheme(), themeMode: ThemeMode.dark, home: const MainTabView()),
  ));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
  return state;
}

void _withApi(String description, Future<void> Function(WidgetTester tester, FakeApi api) body) {
  testWidgets(description, (tester) async {
    final api = FakeApi();
    await http.runWithClient(() => body(tester, api), () => api.client);
  });
}

Future<void> _settle(WidgetTester tester, {int times = 6}) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

final _bundledEventsRaw = File('assets/events.json').readAsStringSync();

void main() {
  group('the events content itself', () {
    test('the copy bundled in the app is identical to the one the server serves', () {
      final server = File('../backend/internal/content/events.json').readAsStringSync();
      expect(_bundledEventsRaw, server, reason: 'copy backend/internal/content/events.json to mobile/assets/ after every edit');
    });

    test('parses with an updatedAt and an events list', () {
      final content = CalendarEventsContent.fromRaw(_bundledEventsRaw);
      expect(content.updatedAt, isNotEmpty);
      expect(content.events, isA<List<CalendarEventInfo>>());
    });
  });

  _withApi('a participant gets a Calendar tab, not the old Map', (tester, api) async {
    await _pump(tester, api);
    expect(find.text('Calendar'), findsWidgets);
  });

  _withApi('a shelter event from the server shows up, grouped by day', (tester, api) async {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final iso = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 17, 30).toUtc().toIso8601String();
    api.eventsBody = eventsJsonWith([
      {'id': 'meal', 'title': 'Community Meal', 'location': 'Union Mission', 'startsAt': iso},
    ]);
    await _pump(tester, api);
    await _settle(tester);

    expect(find.text('Community Meal'), findsOneWidget);
    expect(find.text('Union Mission'), findsOneWidget);
  });

  _withApi('a past event never shows up', (tester, api) async {
    final yesterday = DateTime.now().subtract(const Duration(days: 2));
    api.eventsBody = eventsJsonWith([
      {'id': 'old', 'title': 'Long gone meal', 'startsAt': yesterday.toUtc().toIso8601String()},
    ]);
    await _pump(tester, api);
    await _settle(tester);

    expect(find.text('Long gone meal'), findsNothing);
    expect(find.text('Nothing coming up'), findsOneWidget);
  });

  _withApi('adding a personal appointment shows it, marked as your own', (tester, api) async {
    api.eventsBody = eventsJsonWith([]);
    await _pump(tester, api);
    await _settle(tester);

    await tester.tap(find.byKey(const Key('add-appointment')));
    await _settle(tester);

    await tester.enterText(find.byKey(const Key('appointment-title-field')), 'Case worker check-in');
    await tester.tap(find.byKey(const Key('save-appointment')));
    await _settle(tester);

    expect(find.text('Case worker check-in'), findsOneWidget);
    expect(api.appointments.single['title'], 'Case worker check-in');
  });

  _withApi('an empty title cannot be saved', (tester, api) async {
    api.eventsBody = eventsJsonWith([]);
    await _pump(tester, api);
    await _settle(tester);

    await tester.tap(find.byKey(const Key('add-appointment')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('save-appointment')));
    await tester.pump();

    expect(find.textContaining('Give it a title first'), findsOneWidget);
    expect(api.appointments, isEmpty);
  });

  _withApi('tapping an existing appointment opens it for editing, and it can be deleted', (tester, api) async {
    final soon = DateTime.now().add(const Duration(hours: 2));
    api.eventsBody = eventsJsonWith([]);
    api.appointments.add({
      'id': 'a1',
      'title': 'Dentist',
      'notes': null,
      'location': null,
      'startsAt': soon.toUtc().toIso8601String(),
      'createdAt': '2026-09-26T12:00:00.000Z',
    });
    await _pump(tester, api);
    await _settle(tester);

    expect(find.text('Dentist'), findsOneWidget);
    await tester.tap(find.byKey(const Key('appointment-a1')));
    await _settle(tester);

    expect(find.text('Edit appointment'), findsOneWidget);
    expect(find.byKey(const Key('delete-appointment')), findsOneWidget);

    await tester.tap(find.byKey(const Key('delete-appointment')));
    await _settle(tester);

    expect(find.text('Dentist'), findsNothing);
    expect(api.appointments, isEmpty);
  });

  _withApi('events and a personal appointment appear together, in order', (tester, api) async {
    final now = DateTime.now();
    final morning = DateTime(now.year, now.month, now.day, now.hour + 1);
    final afternoon = DateTime(now.year, now.month, now.day, now.hour + 3);
    api.eventsBody = eventsJsonWith([
      {'id': 'meal', 'title': 'Community Meal', 'startsAt': afternoon.toUtc().toIso8601String()},
    ]);
    api.appointments.add({
      'id': 'a1',
      'title': 'Case worker meeting',
      'notes': null,
      'location': null,
      'startsAt': morning.toUtc().toIso8601String(),
      'createdAt': '2026-09-26T12:00:00.000Z',
    });
    await _pump(tester, api);
    await _settle(tester);

    final titles = tester
        .widgetList<Text>(find.byWidgetPredicate((w) => w is Text && (w.style?.fontWeight == FontWeight.w800) && w.data != null))
        .map((t) => t.data!)
        .where((t) => t == 'Case worker meeting' || t == 'Community Meal')
        .toList();
    expect(titles, ['Case worker meeting', 'Community Meal'], reason: 'earlier in the day comes first');
  });
}
