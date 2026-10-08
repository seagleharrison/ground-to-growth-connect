// Renders the Calendar in each view as PNGs for design review:
//   flutter test tool/calendar_shots_test.dart --dart-define=SHOT_DIR=/some/dir
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ground_to_growth_connect/app_state.dart';
import 'package:ground_to_growth_connect/data/calendar_content.dart';
import 'package:ground_to_growth_connect/models/models.dart';
import 'package:ground_to_growth_connect/nav.dart';
import 'package:ground_to_growth_connect/theme/app_theme.dart';
import 'package:ground_to_growth_connect/util/calendar_items.dart';
import 'package:ground_to_growth_connect/views/main_tab_view.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../test/support/fake_api.dart';

const _outDir = String.fromEnvironment('SHOT_DIR', defaultValue: '/tmp/g2g-calendar');
final _fonts = '${Platform.environment['HOME']}/development/flutter/bin/cache/artifacts/material_fonts';
final _boundary = GlobalKey();

Future<void> _loadFonts() async {
  Future<ByteData> read(String f) async => ByteData.view((await File('$_fonts/$f').readAsBytes()).buffer);
  final roboto = FontLoader('Roboto')
    ..addFont(read('Roboto-Regular.ttf'))
    ..addFont(read('Roboto-Bold.ttf'));
  await roboto.load();
  final icons = FontLoader('MaterialIcons')..addFont(read('MaterialIcons-Regular.otf'));
  await icons.load();
}

ThemeData _theme() {
  final t = buildAppTheme();
  return t.copyWith(chipTheme: t.chipTheme.copyWith(labelStyle: (t.chipTheme.labelStyle ?? const TextStyle()).copyWith(fontFamily: 'Roboto')));
}

Future<void> _settle(WidgetTester tester, {int times = 8}) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Future<void> _shot(WidgetTester tester, String name) async {
  await _settle(tester, times: 4);
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_boundary));
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    await Directory(_outDir).create(recursive: true);
    await File('$_outDir/$name.png').writeAsBytes(bytes.buffer.asUint8List());
  });
}

String _at(int dayOffset, int hour, [int minute = 0]) {
  final t = dateOnly(DateTime.now());
  return DateTime(t.year, t.month, t.day + dayOffset, hour, minute).toUtc().toIso8601String();
}

Map<String, dynamic> _appt(String id, String title, int day, int h, int m, {int? endH, int? endM, String? location, bool allDay = false}) => {
      'id': id,
      'title': title,
      'notes': null,
      'location': location,
      'startsAt': _at(day, h, m),
      'endsAt': endH == null ? null : _at(day, endH, endM ?? 0),
      'allDay': allDay,
      'createdAt': '2026-09-26T12:00:00.000Z',
    };

void main() {
  setUpAll(_loadFonts);

  Future<void> run(WidgetTester tester, String mode, String name, {Future<void> Function()? after}) async {
    final api = FakeApi();
    await http.runWithClient(() async {
      api.appointments
        ..add(_appt('a1', 'ID appointment', 0, 10, 0, endH: 11, endM: 30, location: 'DDS, 1117 Eisenhower Dr'))
        ..add(_appt('a2', 'Case worker check-in', 0, 10, 30, endH: 11, location: 'Union Mission'))
        ..add(_appt('a3', 'Dentist', 1, 14, 0, endH: 15, location: 'Curtis V. Cooper Clinic'))
        ..add(_appt('a4', 'Court date', 3, 0, 0, allDay: true))
        ..add(_appt('a5', 'Job interview', 4, 9, 0, endH: 10, endM: 0, location: 'Kroger on Abercorn'))
        ..add(_appt('a6', 'Housing workshop', 7, 13, 0, endH: 14, endM: 30));
      api.eventsBody = '{"updatedAt":"2026-10-06","events":['
          '{"id":"meal","title":"Community meal","description":"Hot dinner","location":"Union Mission","startsAt":"${_at(0, 17, 30)}","endsAt":"${_at(0, 19)}"},'
          '{"id":"clinic","title":"Free health clinic","location":"Curtis V. Cooper","startsAt":"${_at(2, 9)}","endsAt":"${_at(2, 12)}"},'
          '{"id":"meal2","title":"Community meal","location":"Union Mission","startsAt":"${_at(5, 17, 30)}","endsAt":"${_at(5, 19)}"}]}';
      api.helpRequests.add({
        'id': 'h1', 'category': 'ride', 'note': null, 'status': 'claimed', 'createdAt': _at(0, 8), 'claimedAt': null,
        'helperName': 'Sam', 'appointment': {'id': 'a1', 'title': 'ID appointment', 'location': null, 'startsAt': _at(0, 10)},
        'userId': 'u1', 'name': 'Jane Doe', 'claimedByMe': false,
      });
      tester.view.physicalSize = const Size(780, 1688);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      FlutterSecureStorage.setMockInitialValues({'auth_token': 'tok', 'calendar_mode': mode});
      final state = AppState()
        ..user = User.fromJson(api.user)
        ..isUnlocked = true
        ..consent = ConsentStatus(granted: true);
      state.calendar.debugPreloadEvents(const CalendarEventsContent(updatedAt: '2026-01-01', events: []));
      await tester.pumpWidget(RepaintBoundary(
        key: _boundary,
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: state),
            ChangeNotifierProvider(create: (_) => TabNav(current: AppTab.calendar)),
          ],
          child: MaterialApp(debugShowCheckedModeBanner: false, theme: _theme(), darkTheme: _theme(), themeMode: ThemeMode.dark, home: const MainTabView()),
        ),
      ));
      await _settle(tester, times: 12);
      if (after != null) await after();
      await _shot(tester, name);
    }, () => api.client);
  }

  testWidgets('month', (tester) => run(tester, 'month', '1-month'));
  testWidgets('week', (tester) => run(tester, 'week', '2-week', after: () async {
        final s = tester.state<ScrollableState>(find.descendant(of: find.byKey(const Key('time-grid-scroll')), matching: find.byType(Scrollable)).first);
        s.position.jumpTo(8 * 56);
        await _settle(tester, times: 2);
      }));
  testWidgets('day', (tester) => run(tester, 'day', '3-day', after: () async {
        final s = tester.state<ScrollableState>(find.descendant(of: find.byKey(const Key('time-grid-scroll')), matching: find.byType(Scrollable)).first);
        s.position.jumpTo(8 * 56);
        await _settle(tester, times: 2);
      }));
  testWidgets('schedule', (tester) => run(tester, 'schedule', '4-schedule'));
  testWidgets('editor', (tester) => run(tester, 'month', '5-editor', after: () async {
        await tester.tap(find.byKey(const Key('add-appointment')));
        await _settle(tester);
      }));
}
