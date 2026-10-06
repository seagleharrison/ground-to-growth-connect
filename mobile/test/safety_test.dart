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

Future<AppState> _pump(
  WidgetTester tester,
  FakeApi api, {
  String personType = 'homeless',
  String name = 'Jane Doe',
  AppTab start = AppTab.home,
}) async {
  tester.view.physicalSize = const Size(1200, 3600);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  FlutterSecureStorage.setMockInitialValues({'auth_token': 'tok'});
  api.user
    ..['personType'] = personType
    ..['isStaff'] = personType != 'homeless'
    ..['name'] = name;
  final state = AppState()
    ..user = User.fromJson(api.user)
    ..isUnlocked = true;
  state.calendar.debugPreloadEvents(const CalendarEventsContent(updatedAt: '2026-01-01', events: []));
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: state),
      ChangeNotifierProvider(create: (_) => TabNav(current: start)),
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

void _seedContact(FakeApi api, {String role = 'volunteer', String name = 'Sam', String id = 'v1'}) {
  api.conversations.add({
    'userId': id,
    'name': name,
    'role': role,
    'lastMessage': 'See you soon',
    'lastAt': DateTime.now().toUtc().subtract(const Duration(minutes: 4)).toIso8601String(),
    'unread': 0,
    'canSend': true,
  });
  api.threads[id] = [
    {'id': 'm1', 'fromMe': false, 'body': 'See you soon', 'createdAt': DateTime.now().toUtc().toIso8601String()},
  ];
}

Future<void> _openChat(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(Key('contact-$id')));
  await _settle(tester);
}

Future<void> _menu(WidgetTester tester, String item) async {
  await tester.tap(find.byKey(const Key('chat-menu')));
  await tester.pumpAndSettle();
  final target = find.text(item == 'menu-report' ? 'Report a problem' : 'Block Sam');
  await tester.tap(target);
  await _settle(tester);
}

void main() {
  group('inside a chat', () {
    _withApi('every chat says staff may review messages', (tester, api) async {
      _seedContact(api);
      await _pump(tester, api);
      await _openChat(tester, 'v1');
      expect(find.byKey(const Key('chat-safety-notice')), findsOneWidget);
      expect(find.textContaining('may review messages'), findsWidgets);
    });

    _withApi('a chat that has closed can be read but not written in', (tester, api) async {
      _seedContact(api);
      api.threadCanSend['v1'] = false;
      await _pump(tester, api);
      await _openChat(tester, 'v1');
      expect(find.byKey(const Key('chat-closed')), findsOneWidget);
      expect(find.byKey(const Key('chat-input')), findsNothing);
      expect(find.text('See you soon'), findsWidgets, reason: 'the history is still there');
    });

    _withApi('an open chat has the message box and no closed notice', (tester, api) async {
      _seedContact(api);
      await _pump(tester, api);
      await _openChat(tester, 'v1');
      expect(find.byKey(const Key('chat-input')), findsOneWidget);
      expect(find.byKey(const Key('chat-closed')), findsNothing);
    });

    _withApi('reporting a volunteer sends the reason, protects the person at once, and leaves the chat', (tester, api) async {
      _seedContact(api);
      await _pump(tester, api);
      await _openChat(tester, 'v1');
      await _menu(tester, 'menu-report');

      await tester.enterText(find.byKey(const Key('report-reason')), 'Asked for my phone number');
      await tester.tap(find.byKey(const Key('send-report')));
      await _settle(tester);

      expect(api.reports.single['reason'], 'Asked for my phone number');
      expect(api.reports.single['subject']['userId'], 'v1');
      expect(find.byKey(const Key('chat-input')), findsNothing, reason: 'back out of the chat');
      expect(find.byKey(const Key('contact-v1')), findsNothing, reason: 'the reported volunteer is no longer a contact');
      expect(find.textContaining("can't contact you"), findsOneWidget);
    });

    _withApi('a report can be cancelled without sending anything', (tester, api) async {
      _seedContact(api);
      await _pump(tester, api);
      await _openChat(tester, 'v1');
      await _menu(tester, 'menu-report');
      await tester.tap(find.text('Cancel'));
      await _settle(tester);
      expect(api.reports, isEmpty);
      expect(find.byKey(const Key('chat-input')), findsOneWidget);
    });

    _withApi('blocking asks first, then removes the contact', (tester, api) async {
      _seedContact(api);
      await _pump(tester, api);
      await _openChat(tester, 'v1');
      await _menu(tester, 'menu-block');
      expect(find.text('Block Sam?'), findsOneWidget);
      expect(api.blocked, isEmpty, reason: 'nothing happens until they confirm');

      await tester.tap(find.byKey(const Key('confirm-block')));
      await _settle(tester);
      expect(api.blocked.single['userId'], 'v1');
      expect(find.byKey(const Key('contact-v1')), findsNothing);
    });

    _withApi('cancelling the block confirmation changes nothing', (tester, api) async {
      _seedContact(api);
      await _pump(tester, api);
      await _openChat(tester, 'v1');
      await _menu(tester, 'menu-block');
      await tester.tap(find.text('Cancel'));
      await _settle(tester);
      expect(api.blocked, isEmpty);
      expect(find.byKey(const Key('chat-input')), findsOneWidget);
    });

    _withApi('the Ground to Growth team can be reported but not blocked', (tester, api) async {
      _seedContact(api, role: 'team', name: 'Ada', id: 'ada');
      await _pump(tester, api);
      await _openChat(tester, 'ada');
      await tester.tap(find.byKey(const Key('chat-menu')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('menu-report')), findsOneWidget);
      expect(find.byKey(const Key('menu-block')), findsNothing);
    });

    _withApi('a volunteer can report a participant but has no block option', (tester, api) async {
      _seedContact(api, role: 'participant', name: 'Pat Morgan', id: 'p1');
      await _pump(tester, api, personType: 'volunteer', name: 'Sam Helper', start: AppTab.messages);
      await _openChat(tester, 'p1');
      await tester.tap(find.byKey(const Key('chat-menu')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('menu-report')), findsOneWidget);
      expect(find.byKey(const Key('menu-block')), findsNothing);
    });
  });

  group('blocked people', () {
    _withApi('Me lists who is blocked, and Unblock undoes it', (tester, api) async {
      api.blocked.add({'userId': 'v1', 'name': 'Sam', 'role': 'volunteer'});
      await _pump(tester, api, start: AppTab.me);
      await tester.tap(find.byKey(const Key('open-blocked')));
      await _settle(tester);
      expect(find.byKey(const Key('blocked-v1')), findsOneWidget);

      await tester.tap(find.byKey(const Key('unblock-v1')));
      await _settle(tester);
      expect(api.blocked, isEmpty);
      expect(find.byKey(const Key('no-blocked')), findsOneWidget);
    });

    _withApi('volunteers and admins have no blocked-people row', (tester, api) async {
      await _pump(tester, api, personType: 'volunteer', name: 'Sam Helper', start: AppTab.me);
      expect(find.byKey(const Key('open-blocked')), findsNothing);
    });
  });

  group('a volunteer who is not approved yet', () {
    _withApi('is told they are waiting, not shown an empty board or an error', (tester, api) async {
      api.volunteerApproved = false;
      await _pump(tester, api, personType: 'volunteer', name: 'Sam Helper', start: AppTab.help);
      expect(find.byKey(const Key('awaiting-approval')), findsOneWidget);
      expect(find.text('Waiting for approval'), findsOneWidget);
      expect(find.byKey(const Key('board-empty')), findsNothing);
    });

    _withApi('"Check again" picks up the approval', (tester, api) async {
      api.volunteerApproved = false;
      await _pump(tester, api, personType: 'volunteer', name: 'Sam Helper', start: AppTab.help);
      api.volunteerApproved = true;
      await tester.tap(find.byKey(const Key('check-approval')));
      await _settle(tester);
      expect(find.byKey(const Key('awaiting-approval')), findsNothing);
      expect(find.byKey(const Key('board-empty')), findsOneWidget);
    });
  });

  group('admin safety review', () {
    Map<String, dynamic> vol(String id, String name, {bool approved = true, bool paused = false}) =>
        {'userId': id, 'name': name, 'approved': approved, 'paused': paused, 'createdAt': DateTime.now().toUtc().toIso8601String()};

    Map<String, dynamic> report(String id) => {
          'id': id,
          'status': 'open',
          'createdAt': DateTime.now().toUtc().subtract(const Duration(hours: 2)).toIso8601String(),
          'reason': 'Asked for my phone number',
          'reporter': {'userId': 'p1', 'name': 'Pat Morgan', 'role': 'participant'},
          'subject': {'userId': 'v1', 'name': 'Sam Helper', 'role': 'volunteer'},
        };

    Future<void> openSafety(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('open-safety')));
      await _settle(tester);
    }

    _withApi('the Messages tab flags how many things need an admin', (tester, api) async {
      api.volunteers.addAll([vol('v2', 'New Nia', approved: false), vol('v1', 'Sam Helper')]);
      api.reports.add(report('r1'));
      await _pump(tester, api, personType: 'admin', name: 'Ada Admin', start: AppTab.messages);
      expect(find.byKey(const Key('open-safety')), findsOneWidget);
      expect(tester.widget<Text>(find.descendant(of: find.byKey(const Key('safety-badge')), matching: find.byType(Text))).data, '2');
    });

    _withApi('a volunteer does not get the Safety card', (tester, api) async {
      await _pump(tester, api, personType: 'volunteer', name: 'Sam Helper', start: AppTab.messages);
      expect(find.byKey(const Key('open-safety')), findsNothing);
    });

    _withApi('approving a new volunteer moves them to the approved list', (tester, api) async {
      api.volunteers.add(vol('v2', 'New Nia', approved: false));
      await _pump(tester, api, personType: 'admin', name: 'Ada Admin', start: AppTab.messages);
      await openSafety(tester);
      expect(find.byKey(const Key('pending-v2')), findsOneWidget);

      await tester.tap(find.byKey(const Key('approve-v2')));
      await _settle(tester);
      expect(api.volunteers.single['approved'], isTrue);
      expect(find.byKey(const Key('pending-v2')), findsNothing);
      expect(find.byKey(const Key('volunteer-v2')), findsOneWidget);
      expect(find.byKey(const Key('no-pending')), findsOneWidget);
    });

    _withApi('a report shows who reported whom and why, and can be resolved', (tester, api) async {
      api.reports.add(report('r1'));
      await _pump(tester, api, personType: 'admin', name: 'Ada Admin', start: AppTab.messages);
      await openSafety(tester);
      expect(find.text('Pat Morgan reported Sam Helper'), findsOneWidget);
      expect(find.text('Asked for my phone number'), findsOneWidget);

      await tester.tap(find.byKey(const Key('resolve-r1')));
      await _settle(tester);
      expect(api.reports.single['status'], 'resolved');
      expect(find.byKey(const Key('report-r1')), findsNothing);
      expect(find.byKey(const Key('no-reports')), findsOneWidget);
    });

    _withApi('reviewing a chat shows it, says so, and the look is recorded and shown', (tester, api) async {
      api.reports.add(report('r1'));
      api.adminThreads['p1/v1'] = [
        {'id': 'm1', 'senderId': 'v1', 'body': 'Can I get your phone number?', 'createdAt': DateTime.now().toUtc().toIso8601String()},
        {'id': 'm2', 'senderId': 'p1', 'body': 'I would rather not', 'createdAt': DateTime.now().toUtc().toIso8601String()},
      ];
      await _pump(tester, api, personType: 'admin', name: 'Ada Admin', start: AppTab.messages);
      await openSafety(tester);
      expect(find.byKey(const Key('no-access')), findsOneWidget);

      await tester.tap(find.byKey(const Key('review-r1')));
      await _settle(tester);
      expect(find.byKey(const Key('review-notice')), findsOneWidget);
      expect(find.text('Can I get your phone number?'), findsOneWidget);
      expect(find.textContaining('Sam Helper ·'), findsOneWidget);
      expect(api.accessLog, hasLength(1), reason: 'the server was asked, so it logged the look');

      await tester.pageBack();
      await _settle(tester);
      expect(find.textContaining('Ada Admin reviewed Pat Morgan and Sam Helper'), findsOneWidget);
    });

    _withApi('conversations are listed without any message text; a reported one is marked', (tester, api) async {
      api.adminConversations.add({
        'a': {'userId': 'p1', 'name': 'Pat Morgan', 'role': 'participant'},
        'b': {'userId': 'v1', 'name': 'Sam Helper', 'role': 'volunteer'},
        'count': 7,
        'lastAt': DateTime.now().toUtc().toIso8601String(),
        'flagged': true,
      });
      await _pump(tester, api, personType: 'admin', name: 'Ada Admin', start: AppTab.messages);
      await openSafety(tester);
      expect(find.text('Pat Morgan & Sam Helper'), findsOneWidget);
      expect(find.textContaining('7 messages'), findsOneWidget);
      expect(find.text('Reported'), findsOneWidget);
    });

    _withApi('a volunteer can be paused, resumed, or have access removed', (tester, api) async {
      api.volunteers.add(vol('v1', 'Sam Helper'));
      await _pump(tester, api, personType: 'admin', name: 'Ada Admin', start: AppTab.messages);
      await openSafety(tester);

      await tester.tap(find.byKey(const Key('pause-v1')));
      await _settle(tester);
      expect(api.volunteers.single['paused'], isTrue);
      expect(find.text('Paused'), findsOneWidget);

      await tester.tap(find.byKey(const Key('unpause-v1')));
      await _settle(tester);
      expect(api.volunteers.single['paused'], isFalse);

      await tester.tap(find.byKey(const Key('revoke-v1')));
      await _settle(tester);
      expect(api.volunteers.single['approved'], isFalse);
      expect(find.byKey(const Key('pending-v1')), findsOneWidget, reason: 'they go back to waiting for approval');
    });

    _withApi('a report can pause the volunteer right from the card', (tester, api) async {
      api.volunteers.add(vol('v1', 'Sam Helper'));
      api.reports.add(report('r1'));
      await _pump(tester, api, personType: 'admin', name: 'Ada Admin', start: AppTab.messages);
      await openSafety(tester);
      await tester.tap(find.byKey(const Key('pause-report-r1')));
      await _settle(tester);
      expect(api.volunteers.single['paused'], isTrue);
    });

    _withApi('previewing as another role cannot approve, resolve, block or report', (tester, api) async {
      final state = await _pump(tester, api, personType: 'admin', name: 'Ada Admin', start: AppTab.me);
      state.viewAs(AppView.participant);
      await tester.pump(const Duration(milliseconds: 300));
      expect(await state.safety.volunteerAction('v2', 'approve'), isNotNull);
      expect(await state.safety.resolve('r1'), isNotNull);
      expect(await state.chat.block('v1'), isNotNull);
      expect((await state.chat.report('v1')).error, isNotNull);
      expect(api.routes, isNot(contains('POST /api/blocks')));
      expect(api.routes, isNot(contains('POST /api/reports')));
    });

    _withApi('signing out clears the safety review from the phone', (tester, api) async {
      api.volunteers.add(vol('v2', 'New Nia', approved: false));
      api.reports.add(report('r1'));
      final state = await _pump(tester, api, personType: 'admin', name: 'Ada Admin', start: AppTab.messages);
      await state.safety.refreshAll();
      expect(state.safety.reports, isNotEmpty);
      await state.signOut();
      expect(state.safety.reports, isEmpty);
      expect(state.safety.volunteers, isEmpty);
      expect(state.chat.blocked, isEmpty);
    });
  });
}
