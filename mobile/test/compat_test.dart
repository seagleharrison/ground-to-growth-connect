// Every main screen, for every kind of account, on a small phone with large
// text, a medium phone, and a big phone. Any overflow, clipped layout or crash
// fails the test. It doesn't replace trying the app on real phones; it catches
// the layout problems that are easy to miss on one screen size.
import 'dart:io';

import 'package:flutter/material.dart';
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
import 'package:ground_to_growth_connect/widgets/text_scale_cap.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'support/fake_api.dart';

// Without the real fonts the test falls back to a block font that is far wider
// than Roboto, which would report overflows that don't exist on a phone.
final _fonts = '${Platform.environment['HOME']}/development/flutter/bin/cache/artifacts/material_fonts';

Future<void> _loadFonts() async {
  Future<ByteData> read(String f) async => ByteData.view((await File('$_fonts/$f').readAsBytes()).buffer);
  final roboto = FontLoader('Roboto')
    ..addFont(read('Roboto-Regular.ttf'))
    ..addFont(read('Roboto-Bold.ttf'));
  await roboto.load();
  final icons = FontLoader('MaterialIcons')..addFont(read('MaterialIcons-Regular.otf'));
  await icons.load();
}

class _Screen {
  final String name;
  final Size size; // logical pixels
  final double textScale;
  const _Screen(this.name, this.size, this.textScale);
}

const _screens = [
  _Screen('small phone, huge text', Size(320, 568), 2.0),
  _Screen('small phone', Size(320, 568), 1.0),
  _Screen('medium phone, large text', Size(375, 812), 1.5),
  _Screen('big phone', Size(430, 932), 1.0),
];

final _tabs = <String, List<AppTab>>{
  'homeless': [AppTab.home, AppTab.calendar, AppTab.documents, AppTab.resources, AppTab.me],
  'volunteer': [AppTab.help, AppTab.messages, AppTab.me],
  'admin': [AppTab.map, AppTab.help, AppTab.messages, AppTab.analytics, AppTab.me],
};

String _at(int days, int hour) {
  final t = DateTime.now();
  return DateTime(t.year, t.month, t.day + days, hour).toUtc().toIso8601String();
}

const _longName = 'Alexandria Montgomery-Washington';

FakeApi _seeded() {
  final api = FakeApi();
  api.appointments.addAll([
    {'id': 'a1', 'title': 'Social Security office appointment to replace my card', 'notes': 'Bring the letter', 'location': 'Social Security Administration, 1 Diamond Causeway, Savannah GA', 'startsAt': _at(0, 14), 'endsAt': _at(0, 15), 'allDay': false, 'kind': 'appointment', 'needsRide': true, 'createdAt': '2026-10-01T00:00:00Z'},
    {'id': 'a2', 'title': "Cousin's birthday dinner", 'notes': null, 'location': null, 'startsAt': _at(1, 18), 'endsAt': null, 'allDay': false, 'kind': 'event', 'needsRide': false, 'createdAt': '2026-10-01T00:00:00Z'},
    {'id': 'a3', 'title': 'Court date', 'notes': null, 'location': null, 'startsAt': _at(2, 0), 'endsAt': null, 'allDay': true, 'kind': 'appointment', 'needsRide': false, 'createdAt': '2026-10-01T00:00:00Z'},
  ]);
  api.eventsBody = '{"updatedAt":"2026-10-06","events":[{"id":"meal","title":"Community meal at the Union Mission","description":"Hot dinner, everyone welcome","location":"Union Mission, 120 Fahm St","startsAt":"${_at(0, 17)}","endsAt":"${_at(0, 19)}"}]}';
  final appt = {'id': 'a1', 'title': 'Social Security office appointment to replace my card', 'location': 'Social Security Administration, 1 Diamond Causeway', 'startsAt': _at(0, 14)};
  Map<String, dynamic> request(String id, String category, {String status = 'open', String? helper, bool mine = false, String? progress, List<String> items = const [], Map<String, dynamic>? appointment, String who = _longName}) => {
        'id': id,
        'category': category,
        'note': 'Please be on time, I use a cane and need a little extra help getting in the door',
        'status': status,
        'createdAt': DateTime.now().toUtc().subtract(const Duration(hours: 2)).toIso8601String(),
        'claimedAt': null,
        'helperName': status == 'open' ? null : (helper ?? 'Bartholomew'),
        'appointment': appointment,
        'userId': 'u1',
        'name': who,
        'claimedByMe': mine,
        'progress': progress,
        'progressMinutes': progress == 'late' ? 20 : null,
        'items': items,
      };
  api.helpRequests.addAll([
    request('h1', 'ride', appointment: appt),
    request('h2', 'ride', status: 'claimed', mine: true, progress: 'late', appointment: appt, who: 'Pat Participant'),
    request('h3', 'supplies', items: ['meal', 'water', 'snacks', 'socks', 'underwear', 'shirt', 'pants', 'shoes', 'coat', 'hygiene_kit'], who: 'Bob Smith'),
  ]);
  api.conversations.addAll([
    {'userId': 't1', 'name': 'Ground to Growth Team', 'role': 'team', 'lastMessage': 'Hi, a volunteer will be in touch about your ride tomorrow', 'lastAt': _at(0, 9), 'unread': 3},
    {'userId': 'p1', 'name': _longName, 'role': 'participant', 'lastMessage': null, 'lastAt': null, 'unread': 0},
  ]);
  api.people.addAll([
    {'userId': 'p1', 'name': _longName, 'role': 'participant', 'joinedAt': '2026-10-01T12:00:00.000Z', 'sharing': true},
    {'userId': 'v1', 'name': 'Bartholomew Fitzgerald-Jones', 'role': 'volunteer', 'joinedAt': '2026-09-25T12:00:00.000Z', 'approved': false},
  ]);
  return api;
}

Future<AppState> _pump(WidgetTester tester, FakeApi api, String type, AppTab tab, _Screen screen) async {
  tester.view.physicalSize = screen.size * 2.0;
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  FlutterSecureStorage.setMockInitialValues({'auth_token': 'tok'});
  api.user
    ..['personType'] = type
    ..['isStaff'] = type != 'homeless'
    ..['name'] = _longName
    ..['email'] = 'alexandria.montgomery-washington@example.com';
  final state = AppState()
    ..user = User.fromJson(api.user)
    ..isUnlocked = true
    ..consent = ConsentStatus(granted: true);
  state.calendar.debugPreloadEvents(const CalendarEventsContent(updatedAt: '2026-01-01', events: []));
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: state),
      ChangeNotifierProvider(create: (_) => TabNav(current: tab)),
    ],
    child: MaterialApp(
      theme: buildAppTheme(),
      darkTheme: buildAppTheme(),
      themeMode: ThemeMode.dark,
      // The phone's text setting, then the same cap the real app applies.
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(screen.textScale)), child: capTextScale(child!)),
      home: const MainTabView(),
    ),
  ));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
  return state;
}

void main() {
  setUpAll(_loadFonts);

  for (final screen in _screens) {
    for (final entry in _tabs.entries) {
      for (final tab in entry.value) {
        testWidgets('${entry.key} · ${tab.name} · ${screen.name}', (tester) async {
          final api = _seeded();
          // Say where an overflow is while the widgets still exist, so the
          // report points at the screen's own code rather than a torn-down tree.
          final previous = FlutterError.onError;
          FlutterError.onError = (details) {
            final where = details.informationCollector?.call().map((n) => n.toStringDeep()).join(' ') ?? '';
            final mine = RegExp(r'lib/[a-z_/]+\.dart:\d+').allMatches(where).map((m) => m.group(0)).toSet().join(', ');
            // ignore: avoid_print
            print('LAYOUT PROBLEM: ${details.exceptionAsString().split('\n').first} ${mine.isEmpty ? '' : '(in $mine)'}');
            previous?.call(details);
          };
          addTearDown(() => FlutterError.onError = previous);
          await http.runWithClient(() async {
            await _pump(tester, api, entry.key, tab, screen);
            // Name the screen's own widgets around anything overflowing.
            final dump = tester.binding.renderViews.first.toStringDeep();
            final lines = dump.split('\n');
            for (var i = 0; i < lines.length; i++) {
              if (lines[i].contains('OVERFLOWING')) {
                final chain = lines.skip(i).take(6).where((l) => l.contains('creator:') || l.contains('←')).join(' ').replaceAll(RegExp(r'\s+'), ' ');
                // ignore: avoid_print
                final texts = lines.skip(i).take(60).where((l) => l.contains('TextSpan') || l.contains('"') && l.contains('text:')).take(3).map((l) => l.trim()).join(' | ');
                print('OVERFLOWING: ${chain.length > 200 ? chain.substring(0, 200) : chain} TEXT: $texts');
              }
            }
            // Scroll to the bottom too, where the last cards and the bar meet.
            final scrollable = find.byType(Scrollable);
            if (scrollable.evaluate().isNotEmpty) {
              await tester.drag(scrollable.first, const Offset(0, -3000));
              await tester.pump(const Duration(milliseconds: 400));
            }
          }, () => api.client);
        });
      }
    }
  }

  // Screens that open on top of the main tabs.
  final stressScreens = [_screens[0], _screens[3]];
  for (final screen in stressScreens) {
    Future<void> inApp(WidgetTester tester, String type, AppTab tab, Future<void> Function(FakeApi api) body) async {
      final api = _seeded();
      final previous = FlutterError.onError;
      addTearDown(() => FlutterError.onError = previous);
      await http.runWithClient(() async {
        await _pump(tester, api, type, tab, screen);
        await body(api);
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 300));
        }
        final lines = tester.binding.renderViews.first.toStringDeep().split('\n');
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].contains('OVERFLOWING')) {
            // ignore: avoid_print
            print('OVERFLOWING: ${lines.skip(i).take(40).map((l) => l.replaceAll(RegExp(r'[╎│]'), '').trim()).where((l) => l.startsWith('creator:') || l.startsWith('size:') || l.startsWith('constraints:') || l.contains('text:')).take(6).join(' || ')}');
          }
        }
      }, () => api.client);
    }

    // On a small screen with big text a lot is below the fold: scroll to it first.
    Future<void> tapKey(WidgetTester tester, String key) async {
      await tester.scrollUntilVisible(find.byKey(Key(key)), 300, scrollable: find.byType(Scrollable).first, maxScrolls: 40);
      // Lift it clear of the floating bottom bar before tapping.
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -180));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(Key(key)));
    }

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
    }

    testWidgets('ask for help sheet with basic items · ${screen.name}', (tester) => inApp(tester, 'homeless', AppTab.home, (api) async {
          // Open the sheet directly: on a small screen the Home card can sit under the bottom bar.
          // ignore: unawaited_futures
          showAskForHelpSheet(tester.element(find.byType(MainTabView)));
          await settle(tester);
          await tester.tap(find.byKey(const Key('category-supplies')));
          await settle(tester);
          for (final c in ['socks', 'blanket', 'hygiene_kit']) {
            await tester.ensureVisible(find.byKey(Key('item-$c')));
            await tester.tap(find.byKey(Key('item-$c')));
            await tester.pump();
          }
          await tester.ensureVisible(find.byKey(const Key('send-help-request')));
        }));

    testWidgets('my requests with a ride and items · ${screen.name}', (tester) => inApp(tester, 'homeless', AppTab.home, (api) async {
          api.helpRequests.addAll([
            {'id': 'm1', 'category': 'ride', 'note': 'Please be on time, I use a cane', 'status': 'claimed', 'createdAt': DateTime.now().toUtc().toIso8601String(), 'claimedAt': null, 'helperName': 'Bartholomew', 'appointment': {'id': 'a1', 'title': 'Social Security office appointment to replace my card', 'location': 'Social Security Administration', 'startsAt': _at(0, 14)}, 'userId': 'u1', 'name': _longName, 'claimedByMe': false, 'progress': 'late', 'progressMinutes': 20, 'items': <String>[]},
            {'id': 'm2', 'category': 'supplies', 'note': null, 'status': 'done', 'createdAt': DateTime.now().toUtc().toIso8601String(), 'claimedAt': null, 'helperName': 'Bartholomew', 'appointment': null, 'userId': 'u1', 'name': _longName, 'claimedByMe': false, 'items': ['socks', 'blanket', 'water', 'hygiene_kit']},
          ]);
          await tapKey(tester, 'ask-for-help-card');
          await settle(tester);
        }));

    testWidgets('new appointment editor · ${screen.name}', (tester) => inApp(tester, 'homeless', AppTab.calendar, (api) async {
          await tester.tap(find.byKey(const Key('add-appointment')));
          await settle(tester);
          await tester.ensureVisible(find.byKey(const Key('appointment-ride-switch')));
          await tester.tap(find.byKey(const Key('appointment-ride-switch')));
          await tester.pump();
          await tester.ensureVisible(find.byKey(const Key('save-appointment')));
        }));

    for (final mode in ['schedule', 'day', 'week', 'month']) {
      testWidgets('calendar $mode view · ${screen.name}', (tester) async {
        final api = _seeded();
        await http.runWithClient(() async {
          await _pump(tester, api, 'homeless', AppTab.calendar, screen);
          await tester.tap(find.byKey(const Key('calendar-view-menu')));
          await settle(tester);
          await tester.tap(find.byKey(Key('view-$mode')));
          await settle(tester);
        }, () => api.client);
      });
    }

    testWidgets('chat with the team · ${screen.name}', (tester) => inApp(tester, 'homeless', AppTab.home, (api) async {
          api.threads['t1'] = [
            {'id': 'm1', 'fromMe': false, 'body': 'Hi, a volunteer will be in touch about your ride tomorrow at the Social Security office', 'createdAt': DateTime.now().toUtc().toIso8601String()},
            {'id': 'm2', 'fromMe': true, 'body': 'Thank you so much, I will be waiting outside the shelter entrance', 'createdAt': DateTime.now().toUtc().toIso8601String()},
          ];
          await tapKey(tester, 'contact-t1');
          await settle(tester);
        }));

    testWidgets('volunteer board menu · ${screen.name}', (tester) => inApp(tester, 'volunteer', AppTab.help, (api) async {
          await tapKey(tester, 'more-h2');
          await settle(tester);
        }));

    testWidgets('admin people list and profile · ${screen.name}', (tester) => inApp(tester, 'admin', AppTab.analytics, (api) async {
          api.personExtras['p1'] = {'email': 'alexandria.montgomery-washington@example.com', 'phone': '(912) 555-0101', 'gender': 'female', 'documentStorage': true, 'documentsOnFile': 2, 'helpRequests': 3, 'helpRequestsDone': 2};
          await tester.tap(find.byKey(const Key('stat-participants')));
          await settle(tester);
          await tester.tap(find.byKey(const Key('person-p1')));
          await settle(tester);
        }));

    testWidgets('admin safety screen · ${screen.name}', (tester) => inApp(tester, 'admin', AppTab.messages, (api) async {
          await tester.tap(find.byKey(const Key('open-safety')));
          await settle(tester);
        }));
  }
}
