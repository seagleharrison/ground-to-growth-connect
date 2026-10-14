// Renders the Google Play screenshots (1080x2160) and the feature graphic:
//   flutter test tool/store_shots_test.dart --dart-define=SHOT_DIR=/some/dir
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
import 'package:ground_to_growth_connect/views/main_tab_view.dart';
import 'package:ground_to_growth_connect/views/my_help_view.dart';

import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../test/support/fake_api.dart';

const _outDir = String.fromEnvironment('SHOT_DIR', defaultValue: '/tmp/g2g-store');
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
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    await Directory(_outDir).create(recursive: true);
    await File('$_outDir/$name.png').writeAsBytes(bytes.buffer.asUint8List());
  });
}

String _at(int dayOffset, int hour) {
  final t = DateTime.now();
  return DateTime(t.year, t.month, t.day + dayOffset, hour).toUtc().toIso8601String();
}

Map<String, dynamic> _appt(String id, String title, int day, int h, {int? endH, String? location, bool allDay = false, String kind = 'appointment', bool ride = false}) => {
      'id': id,
      'title': title,
      'notes': null,
      'location': location,
      'startsAt': _at(day, h),
      'endsAt': endH == null ? null : _at(day, endH),
      'allDay': allDay,
      'kind': kind,
      'needsRide': ride,
      'createdAt': '2026-09-26T12:00:00.000Z',
    };

Map<String, dynamic> _req(String id, String category, {String status = 'open', String? helper, bool mine = false, String? progress, List<String> items = const [], Map<String, dynamic>? appointment, String who = 'Jane Doe', String? userId}) => {
      'id': id,
      'category': category,
      'note': null,
      'status': status,
      'createdAt': _at(0, 8),
      'claimedAt': null,
      'helperName': status == 'open' ? null : (helper ?? 'Sam'),
      'appointment': appointment,
      'userId': userId ?? 'u1',
      'name': who,
      'claimedByMe': mine,
      'progress': progress,
      'progressMinutes': null,
      'items': items,
    };

void main() {
  setUpAll(_loadFonts);

  Future<void> scene(WidgetTester tester, String name, {required String type, required AppTab start, required void Function(FakeApi) seed, Future<void> Function()? after, String who = 'Jane Doe', String mode = 'month'}) async {
    final api = FakeApi();
    await http.runWithClient(() async {
      api.user
        ..['personType'] = type
        ..['isStaff'] = type != 'homeless'
        ..['name'] = who;
      seed(api);
      // 360 x 720 points at 3x = 1080 x 2160, a 2:1 phone screenshot.
      tester.view.physicalSize = const Size(1080, 2160);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      FlutterSecureStorage.setMockInitialValues({'auth_token': 'tok', 'calendar_mode': mode});
      final state = AppState()
        ..user = User.fromJson(api.user)
        ..isUnlocked = true
        ..consent = ConsentStatus(granted: true);
      state.locationTracker.lastReportAt = DateTime.now().subtract(const Duration(minutes: 4));
      state.calendar.debugPreloadEvents(const CalendarEventsContent(updatedAt: '2026-01-01', events: []));
      await tester.pumpWidget(RepaintBoundary(
        key: _boundary,
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: state),
            ChangeNotifierProvider(create: (_) => TabNav(current: start)),
          ],
          child: MaterialApp(debugShowCheckedModeBanner: false, theme: _theme(), darkTheme: _theme(), themeMode: ThemeMode.dark, home: const MainTabView()),
        ),
      ));
      await _settle(tester, times: 12);
      if (after != null) await after();
      await _shot(tester, name);
    }, () => api.client);
  }

  testWidgets('1 home', (t) => scene(t, '1-home', type: 'homeless', start: AppTab.home, seed: (api) {
        api.conversations.add({'userId': 't1', 'name': 'Ada', 'role': 'team', 'lastMessage': 'Your ride is set for tomorrow at 10', 'lastAt': _at(0, 9), 'unread': 1});
      }));
  testWidgets('2 calendar', (t) => scene(t, '2-calendar', type: 'homeless', start: AppTab.calendar, seed: (api) {
        api.eventsBody = '{"updatedAt":"2026-10-06","events":[]}';
        api.appointments
          ..add(_appt('a1', 'ID appointment', 0, 10, endH: 11, location: 'DDS, Eisenhower Dr', ride: true))
          ..add(_appt('a2', 'Case worker check-in', 1, 14, endH: 15, location: 'Union Mission'))
          ..add(_appt('a3', 'Job interview', 3, 9, endH: 10, location: 'Kroger on Abercorn', ride: true))
          ..add(_appt('a4', 'Birthday dinner', 4, 18, kind: 'event'));
        api.helpRequests.add({..._req('h1', 'ride', status: 'claimed', helper: 'Sam', appointment: {'id': 'a1', 'title': 'ID appointment', 'location': null, 'startsAt': _at(0, 10)}), 'userId': 'u1'});
      }));
  testWidgets('3 ride help', (t) => scene(t, '3-help-board', type: 'volunteer', start: AppTab.help, who: 'Sam Helper', seed: (api) {
        api.helpRequests
          ..add(_req('h1', 'ride', appointment: {'id': 'a1', 'title': 'ID appointment', 'location': 'DDS, 1117 Eisenhower Dr', 'startsAt': _at(1, 10)}))
          ..add(_req('h2', 'supplies', who: 'Marcus Hill', userId: 'p2', items: ['socks', 'blanket', 'water', 'hygiene_kit']));
      }));
  testWidgets('4 ask for items', (t) => scene(t, '4-basic-items', type: 'homeless', start: AppTab.home, seed: (api) {}, after: () async {
        // ignore: unawaited_futures
        showAskForHelpSheet(t.element(find.byType(MainTabView)));
        await _settle(t);
        await t.tap(find.byKey(const Key('category-supplies')));
        await _settle(t, times: 2);
        for (final c in ['socks', 'blanket', 'water']) {
          await t.ensureVisible(find.byKey(Key('item-$c')));
          await t.tap(find.byKey(Key('item-$c')));
          await t.pump();
        }
        await t.drag(find.byType(SingleChildScrollView).last, const Offset(0, 420));
        await _settle(t, times: 2);
      }));
  testWidgets('5 documents', (t) => scene(t, '5-documents', type: 'homeless', start: AppTab.documents, seed: (api) {}));
  testWidgets('6 resources', (t) => scene(t, '6-resources', type: 'homeless', start: AppTab.resources, seed: (api) {}));

  testWidgets('feature graphic', (tester) async {
    tester.view.physicalSize = const Size(1024, 500);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(RepaintBoundary(
      key: _boundary,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _theme(),
        home: Scaffold(
          body: Container(
            decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFFB578), Color(0xFFFF8A3D)])),
            padding: const EdgeInsets.symmetric(horizontal: 72),
            child: Row(
              children: [
                Container(
                  width: 190,
                  height: 190,
                  decoration: BoxDecoration(color: const Color(0x33FFFFFF), borderRadius: BorderRadius.circular(48)),
                  child: const Icon(Icons.eco_rounded, size: 120, color: Color(0xFF3A1D00)),
                ),
                const SizedBox(width: 48),
                const Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Ground to Growth Connect', style: TextStyle(fontFamily: 'Roboto', fontSize: 54, fontWeight: FontWeight.w700, color: Color(0xFF2A1400), height: 1.1)),
                      SizedBox(height: 14),
                      Text('A path to healing, a journey to home.', style: TextStyle(fontFamily: 'Roboto', fontSize: 28, color: Color(0xFF3A1D00))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ));
    await _settle(tester, times: 3);
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_boundary));
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      await Directory(_outDir).create(recursive: true);
      await File('$_outDir/feature-graphic-1024x500.png').writeAsBytes(bytes.buffer.asUint8List());
    });
  });
}
