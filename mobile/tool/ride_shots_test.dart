// Renders the ride-matching and people screens as PNGs for design review:
//   flutter test tool/ride_shots_test.dart --dart-define=SHOT_DIR=/some/dir
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
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../test/support/fake_api.dart';

const _outDir = String.fromEnvironment('SHOT_DIR', defaultValue: '/tmp/g2g-rides');
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

String _at(int dayOffset, int hour) {
  final t = DateTime.now();
  return DateTime(t.year, t.month, t.day + dayOffset, hour).toUtc().toIso8601String();
}

Map<String, dynamic> _ride(String id, {String status = 'claimed', bool mine = false, String? helper = 'Sam', String? progress, int? minutes, List<Map<String, dynamic>>? offers, String? myOffer, String who = 'Jane Doe', String? userId}) => {
      'id': id,
      'category': 'ride',
      'note': 'Please be on time, I use a cane',
      'status': status,
      'createdAt': _at(0, 8),
      'claimedAt': null,
      'helperName': status == 'open' ? null : helper,
      'appointment': {'id': 'a1', 'title': 'ID appointment', 'location': 'DDS, 1117 Eisenhower Dr', 'startsAt': _at(1, 10)},
      'userId': userId ?? 'p1',
      'name': who,
      'claimedByMe': mine,
      'progress': progress,
      'progressMinutes': minutes,
      'myOffer': myOffer,
      'myOfferId': myOffer == null ? null : 'o9',
      'offers': offers ?? [],
    };

void main() {
  setUpAll(_loadFonts);

  Future<void> run(WidgetTester tester, String name, {required String type, required AppTab start, required void Function(FakeApi) seed, Future<void> Function()? after, String who = 'Jane Doe'}) async {
    final api = FakeApi();
    await http.runWithClient(() async {
      api.user
        ..['personType'] = type
        ..['isStaff'] = type != 'homeless'
        ..['name'] = who;
      seed(api);
      tester.view.physicalSize = const Size(780, 1688);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      FlutterSecureStorage.setMockInitialValues({'auth_token': 'tok'});
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

  testWidgets('volunteer: offer waiting', (t) => run(t, '1-volunteer-offer', type: 'volunteer', start: AppTab.help, who: 'Sam Helper', seed: (api) {
        api.helpRequests
          ..add(_ride('h1', status: 'open', myOffer: 'pending'))
          ..add(_ride('h2', status: 'open', who: 'Bob Smith', userId: 'p2'));
      }));
  testWidgets('volunteer: on a ride', (t) => run(t, '2-volunteer-ride', type: 'volunteer', start: AppTab.help, who: 'Sam Helper', seed: (api) {
        api.helpRequests.add(_ride('h1', mine: true, progress: 'on_my_way'));
      }));
  testWidgets('admin: confirm', (t) => run(t, '3-admin-confirm', type: 'admin', start: AppTab.help, who: 'Ada Admin', seed: (api) {
        api.helpRequests.add(_ride('h1', status: 'open', offers: [
          {'id': 'o1', 'volunteerId': 'v1', 'volunteerName': 'Sam Helper', 'createdAt': _at(0, 9), 'thumbsUp': 4, 'thumbsDown': 1},
          {'id': 'o2', 'volunteerId': 'v2', 'volunteerName': 'Pat Newcomer', 'createdAt': _at(0, 9), 'thumbsUp': 0, 'thumbsDown': 0},
        ]));
      }));
  testWidgets('person: ride on the way', (t) => run(t, '4-person-ride', type: 'homeless', start: AppTab.home, seed: (api) {
        api.helpRequests.add(_ride('h1', progress: 'late', minutes: 20, userId: 'u1'));
      }, after: () async {
        await t.tap(find.byKey(const Key('ask-for-help-card')));
        await _settle(t);
      }));
  testWidgets('person: ask for a ride', (t) => run(t, '5-person-ask', type: 'homeless', start: AppTab.home, seed: (api) {
        api.appointments.add({'id': 'a1', 'title': 'ID appointment', 'notes': null, 'location': 'DDS', 'startsAt': _at(1, 10), 'createdAt': '2026-10-01T00:00:00Z'});
      }, after: () async {
        await t.tap(find.byKey(const Key('ask-for-help-card')));
        await _settle(t);
        await t.tap(find.byKey(const Key('ask-for-help')));
        await _settle(t);
        await t.tap(find.byKey(const Key('category-ride')));
        await _settle(t, times: 2);
        await t.enterText(find.byKey(const Key('help-note-field')), 'I use a cane, please be on time');
        await _settle(t, times: 2);
      }));
  testWidgets('admin: people list', (t) => run(t, '6-people-list', type: 'admin', start: AppTab.analytics, who: 'Ada Admin', seed: (api) {
        api.people.addAll([
          {'userId': 'p1', 'name': 'Jane Doe', 'role': 'participant', 'joinedAt': _at(-2, 12), 'sharing': true},
          {'userId': 'p2', 'name': 'Bob Smith', 'role': 'participant', 'joinedAt': _at(-12, 12), 'sharing': false},
          {'userId': 'p3', 'name': 'Marcus Hill', 'role': 'participant', 'joinedAt': _at(-20, 12), 'sharing': true},
        ]);
      }, after: () async {
        await t.tap(find.byKey(const Key('stat-participants')));
        await _settle(t);
      }));
  testWidgets('admin: person detail', (t) => run(t, '7-person-detail', type: 'admin', start: AppTab.analytics, who: 'Ada Admin', seed: (api) {
        api.people.add({'userId': 'p1', 'name': 'Jane Doe', 'role': 'participant', 'joinedAt': _at(-2, 12), 'sharing': true});
        api.personExtras['p1'] = {'email': 'jane@example.com', 'phone': '(912) 555-0101', 'gender': 'female', 'lastCheckIn': DateTime.now().toUtc().subtract(const Duration(minutes: 12)).toIso8601String(), 'documentStorage': true, 'documentsOnFile': 2, 'helpRequests': 3, 'helpRequestsDone': 2};
      }, after: () async {
        await t.tap(find.byKey(const Key('stat-participants')));
        await _settle(t);
        await t.tap(find.byKey(const Key('person-p1')));
        await _settle(t);
      }));
}
