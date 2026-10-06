// Renders the real screens with the real fonts and saves them as PNGs, for
// design review. Not part of the normal suite:
//   flutter test tool/screenshots_test.dart
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

const _outDir = String.fromEnvironment('SHOT_DIR', defaultValue: '/tmp/g2g-screens');
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

// In tests, text styles with no font family fall back to a block font; give
// the chips (which have one) the real font so the pictures read properly.
ThemeData _theme() {
  final t = buildAppTheme();
  return t.copyWith(
    chipTheme: t.chipTheme.copyWith(labelStyle: (t.chipTheme.labelStyle ?? const TextStyle()).copyWith(fontFamily: 'Roboto')),
  );
}

String _iso(Duration fromNow) => DateTime.now().add(fromNow).toUtc().toIso8601String();

Future<void> _settle(WidgetTester tester, {int times = 10}) async {
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

Future<AppState> _open(
  WidgetTester tester,
  FakeApi api, {
  String type = 'homeless',
  String name = 'Jane Doe',
  AppTab start = AppTab.home,
}) async {
  tester.view.physicalSize = const Size(780, 1688);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  FlutterSecureStorage.setMockInitialValues({'auth_token': 'tok'});
  api.user
    ..['personType'] = type
    ..['isStaff'] = type != 'homeless'
    ..['name'] = name;
  final state = AppState()
    ..user = User.fromJson(api.user)
    ..isUnlocked = true
    ..consent = ConsentStatus(granted: true);
  state.locationTracker.lastReportAt = DateTime.now().subtract(const Duration(minutes: 4));
  state.calendar.debugPreloadEvents(CalendarEventsContent(updatedAt: '2026-10-06', events: [
    CalendarEventInfo(
      id: 'meal',
      title: 'Community meal',
      description: 'Hot dinner, everyone welcome',
      location: 'Union Mission, 120 Fahm St',
      startsAt: _iso(const Duration(days: 2, hours: 3)),
    ),
  ]));
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
  await _settle(tester);
  return state;
}

Map<String, dynamic> _req(String id, String category, String who, String note, {String status = 'open', String? helper, bool mine = false, Map<String, dynamic>? appt, String userId = 'p1', int minsAgo = 25}) => {
      'id': id,
      'category': category,
      'note': note,
      'status': status,
      'createdAt': _iso(Duration(minutes: -minsAgo)),
      'claimedAt': null,
      'helperName': helper,
      'appointment': appt,
      'userId': userId,
      'name': who,
      'claimedByMe': mine,
    };

void main() {
  setUpAll(_loadFonts);

  void seedJane(FakeApi api) {
    api.appointments
      ..add({'id': 'a1', 'title': 'ID appointment', 'notes': null, 'location': 'DDS, 1117 Eisenhower Dr', 'startsAt': _iso(const Duration(days: 1, hours: 2)), 'createdAt': _iso(const Duration(days: -1))})
      ..add({'id': 'a2', 'title': 'Case worker check-in', 'notes': null, 'location': null, 'startsAt': _iso(const Duration(days: 3)), 'createdAt': _iso(const Duration(days: -1))});
    api.helpRequests.add(_req('h1', 'ride', 'Jane Doe', 'To my ID appointment', status: 'claimed', helper: 'Sam', userId: 'u1', appt: {
      'id': 'a1', 'title': 'ID appointment', 'location': 'DDS, 1117 Eisenhower Dr', 'startsAt': api.appointments.first['startsAt'],
    }));
    api.conversations
      ..add({'userId': 'v1', 'name': 'Sam', 'role': 'volunteer', 'lastMessage': "I'll be there at 9 to pick you up", 'lastAt': _iso(const Duration(minutes: -6)), 'unread': 1})
      ..add({'userId': 'ada', 'name': 'Ada', 'role': 'team', 'lastMessage': null, 'lastAt': null, 'unread': 0});
    api.threads['v1'] = [
      {'id': 'm1', 'fromMe': true, 'body': 'Hi Sam, thank you for helping with my ride', 'createdAt': _iso(const Duration(minutes: -30))},
      {'id': 'm2', 'fromMe': false, 'body': "Happy to! Your ID appointment is tomorrow at 10, right?", 'createdAt': _iso(const Duration(minutes: -20))},
      {'id': 'm3', 'fromMe': true, 'body': 'Yes, at the DDS on Eisenhower', 'createdAt': _iso(const Duration(minutes: -12))},
      {'id': 'm4', 'fromMe': false, 'body': "I'll be there at 9 to pick you up", 'createdAt': _iso(const Duration(minutes: -6))},
    ];
  }

  void withApi(String name, Future<void> Function(WidgetTester, FakeApi) body) =>
      testWidgets(name, (tester) async {
        final api = FakeApi();
        await http.runWithClient(() => body(tester, api), () => api.client);
      });

  withApi('participant', (tester, api) async {
    seedJane(api);
    await _open(tester, api);
    await _shot(tester, '1-participant-home');

    await tester.tap(find.byKey(const Key('ask-for-help-card')));
    await _settle(tester);
    await _shot(tester, '2-participant-ask-for-help');

    await tester.tap(find.byKey(const Key('ask-for-help')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('category-ride')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('help-note-field')), 'To my ID appointment tomorrow');
    await tester.pump();
    await _shot(tester, '3-participant-request-form');
  });

  withApi('participant calendar and chat', (tester, api) async {
    seedJane(api);
    await _open(tester, api, start: AppTab.calendar);
    await _shot(tester, '4-participant-calendar');
  });

  withApi('participant chat', (tester, api) async {
    seedJane(api);
    await _open(tester, api);
    await tester.tap(find.byKey(const Key('contact-v1')));
    await _settle(tester);
    await _shot(tester, '5-participant-chat');
  });

  withApi('participant me', (tester, api) async {
    seedJane(api);
    await _open(tester, api, start: AppTab.me);
    await _shot(tester, '6-participant-me-map-under-me');
  });

  withApi('volunteer', (tester, api) async {
    api.helpRequests
      ..add(_req('h1', 'ride', 'Pat Morgan', 'Need to get to my ID appointment tomorrow morning', appt: {
        'id': 'a9', 'title': 'ID appointment', 'location': 'DDS, 1117 Eisenhower Dr', 'startsAt': _iso(const Duration(days: 1, hours: 2)),
      }, minsAgo: 40))
      ..add(_req('h2', 'food', 'Lee Carter', 'Haven\'t eaten since yesterday', minsAgo: 95))
      ..add(_req('h3', 'clothing', 'Robin Ellis', 'Winter coat, size L', status: 'claimed', mine: true, helper: 'Sam', minsAgo: 180, userId: 'p3'))
      ..add(_req('h4', 'documents', 'Taylor Brooks', 'Lost my birth certificate', status: 'claimed', helper: 'Dana', minsAgo: 300, userId: 'p4'));
    api.conversations.add({'userId': 'p3', 'name': 'Robin Ellis', 'role': 'participant', 'lastMessage': 'Thanks, I will meet you at the door', 'lastAt': _iso(const Duration(minutes: -15)), 'unread': 1});
    await _open(tester, api, type: 'volunteer', name: 'Sam Helper', start: AppTab.help);
    await _shot(tester, '7-volunteer-help-board');
  });

  withApi('volunteer messages and me', (tester, api) async {
    api.conversations.add({'userId': 'p3', 'name': 'Robin Ellis', 'role': 'participant', 'lastMessage': 'Thanks, I will meet you at the door', 'lastAt': _iso(const Duration(minutes: -15)), 'unread': 1});
    await _open(tester, api, type: 'volunteer', name: 'Sam Helper', start: AppTab.messages);
    await _shot(tester, '8-volunteer-messages');
  });

  withApi('volunteer me', (tester, api) async {
    await _open(tester, api, type: 'volunteer', name: 'Sam Helper', start: AppTab.me);
    await _shot(tester, '9-volunteer-me-map-under-me');
  });

  withApi('safety', (tester, api) async {
    seedJane(api);
    api.threads['v1'] = [
      {'id': 'm1', 'fromMe': true, 'body': 'Hi Sam, thank you for helping with my ride', 'createdAt': _iso(const Duration(minutes: -30))},
      {'id': 'm2', 'fromMe': false, 'body': "Happy to! I'll be there at 9", 'createdAt': _iso(const Duration(minutes: -20))},
    ];
    await _open(tester, api);
    await tester.tap(find.byKey(const Key('contact-v1')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('chat-menu')));
    await tester.pumpAndSettle();
    await _shot(tester, '10-chat-with-safety-notice-and-menu');
  });

  withApi('safety closed chat', (tester, api) async {
    seedJane(api);
    api.threadCanSend['v1'] = false;
    await _open(tester, api);
    await tester.tap(find.byKey(const Key('contact-v1')));
    await _settle(tester);
    await _shot(tester, '11-chat-closed-after-help-ends');
  });

  withApi('admin safety', (tester, api) async {
    api.volunteers
      ..add({'userId': 'v2', 'name': 'Nia Patel', 'approved': false, 'paused': false, 'createdAt': _iso(const Duration(hours: -5))})
      ..add({'userId': 'v1', 'name': 'Sam Helper', 'approved': true, 'paused': false, 'createdAt': _iso(const Duration(days: -30))})
      ..add({'userId': 'v3', 'name': 'Dana Ruiz', 'approved': true, 'paused': true, 'createdAt': _iso(const Duration(days: -60))});
    api.reports.add({
      'id': 'r1',
      'status': 'open',
      'createdAt': _iso(const Duration(hours: -2)),
      'reason': 'Asked for my phone number and where I sleep',
      'reporter': {'userId': 'p1', 'name': 'Pat Morgan', 'role': 'participant'},
      'subject': {'userId': 'v3', 'name': 'Dana Ruiz', 'role': 'volunteer'},
    });
    api.adminConversations.add({
      'a': {'userId': 'p1', 'name': 'Pat Morgan', 'role': 'participant'},
      'b': {'userId': 'v3', 'name': 'Dana Ruiz', 'role': 'volunteer'},
      'count': 12,
      'lastAt': _iso(const Duration(hours: -3)),
      'flagged': true,
    });
    api.accessLog.add({'admin': 'Ada Admin', 'a': 'Lee Carter', 'b': 'Sam Helper', 'createdAt': _iso(const Duration(days: -1))});
    await _open(tester, api, type: 'admin', name: 'Ada Admin', start: AppTab.messages);
    await _shot(tester, '12-admin-messages-with-safety');
    await tester.tap(find.byKey(const Key('open-safety')));
    await _settle(tester);
    await _shot(tester, '13-admin-safety-review');
  });

  withApi('pending volunteer', (tester, api) async {
    api.volunteerApproved = false;
    await _open(tester, api, type: 'volunteer', name: 'Nia Patel', start: AppTab.help);
    await _shot(tester, '14-volunteer-waiting-for-approval');
  });
}
