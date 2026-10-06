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
  api.user['personType'] = personType;
  api.user['isStaff'] = personType != 'homeless';
  api.user['name'] = name;
  final state = AppState()
    ..user = User.fromJson(api.user)
    ..isUnlocked = true;
  // Avoids the bundled-asset read, which hangs across repeated testWidgets runs.
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

Map<String, dynamic> _request(String id, {String status = 'open', String category = 'ride', String userId = 'p1', String name = 'Pat Participant', Map<String, dynamic>? appointment, bool mine = false, String? helper}) => {
      'id': id,
      'category': category,
      'note': 'Need to get across town',
      'status': status,
      'createdAt': DateTime.now().toUtc().subtract(const Duration(minutes: 20)).toIso8601String(),
      'claimedAt': null,
      'helperName': helper,
      'appointment': appointment,
      'userId': userId,
      'name': name,
      'claimedByMe': mine,
    };

void main() {
  group('a person getting support', () {
    _withApi('asking for a ride with a note sends it and shows it waiting', (tester, api) async {
      await _pump(tester, api);
      await tester.tap(find.byKey(const Key('ask-for-help-card')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('ask-for-help')));
      await _settle(tester);

      await tester.tap(find.byKey(const Key('category-ride')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('help-note-field')), 'To my ID appointment');
      await tester.tap(find.byKey(const Key('send-help-request')));
      await _settle(tester);

      expect(api.helpRequests.single['category'], 'ride');
      expect(api.helpRequests.single['note'], 'To my ID appointment');
      expect(find.text('Waiting for a volunteer'), findsOneWidget);
      expect(find.text('A ride'), findsOneWidget);
    });

    _withApi('the request cannot be sent until something is picked', (tester, api) async {
      await _pump(tester, api);
      await tester.tap(find.byKey(const Key('ask-for-help-card')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('ask-for-help')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('send-help-request')), warnIfMissed: false);
      await _settle(tester);
      expect(api.helpRequests, isEmpty);
    });

    _withApi('an appointment can be attached, and only that one is shared', (tester, api) async {
      final soon = DateTime.now().add(const Duration(days: 1));
      api.appointments.addAll([
        {'id': 'a1', 'title': 'DDS visit', 'notes': null, 'location': 'DDS', 'startsAt': soon.toUtc().toIso8601String(), 'createdAt': '2026-10-01T00:00:00Z'},
        {'id': 'a2', 'title': 'Private thing', 'notes': null, 'location': null, 'startsAt': soon.toUtc().toIso8601String(), 'createdAt': '2026-10-01T00:00:00Z'},
      ]);
      await _pump(tester, api);
      await tester.tap(find.byKey(const Key('ask-for-help-card')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('ask-for-help')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('category-ride')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('help-appointment-field')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.textContaining('DDS visit').last);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const Key('send-help-request')));
      await _settle(tester);

      final appt = api.helpRequests.single['appointment'] as Map<String, dynamic>?;
      expect(appt?['title'], 'DDS visit');
      expect(find.textContaining('Private thing'), findsNothing, reason: 'unattached appointments are never part of the request');
    });

    _withApi('when a volunteer takes it, the person sees who is helping, and the Calendar says so', (tester, api) async {
      final soon = DateTime.now().add(const Duration(hours: 5));
      final appt = {'id': 'a1', 'title': 'DDS visit', 'notes': null, 'location': 'DDS', 'startsAt': soon.toUtc().toIso8601String(), 'createdAt': '2026-10-01T00:00:00Z'};
      api.appointments.add(appt);
      api.helpRequests.add(_request('h1', status: 'claimed', userId: 'u1', name: 'Jane Doe', helper: 'Sam', appointment: {
        'id': 'a1', 'title': 'DDS visit', 'location': 'DDS', 'startsAt': appt['startsAt'],
      }));
      await _pump(tester, api, start: AppTab.calendar);
      expect(find.byKey(const Key('helper-a1')), findsOneWidget);
      expect(find.text('Sam is taking you'), findsOneWidget);
    });

    _withApi('"I\'m all set" closes a request, and a request can be cancelled', (tester, api) async {
      api.helpRequests
        ..add(_request('h1', userId: 'u1', name: 'Jane Doe'))
        ..add(_request('h2', userId: 'u1', name: 'Jane Doe', category: 'food'));
      await _pump(tester, api);
      await tester.tap(find.byKey(const Key('ask-for-help-card')));
      await _settle(tester);

      await tester.tap(find.byKey(const Key('all-set-h1')));
      await _settle(tester);
      expect(api.helpRequests.firstWhere((h) => h['id'] == 'h1')['status'], 'done');
      expect(find.byKey(const Key('all-set-h1')), findsNothing, reason: 'a finished request has no actions left');

      await tester.tap(find.byKey(const Key('cancel-h2')));
      await _settle(tester);
      expect(api.helpRequests.where((h) => h['id'] == 'h2'), isEmpty);
    });

    _withApi('Home shows contacts with unread counts, and opening one lets them chat', (tester, api) async {
      api.conversations.add({
        'userId': 'v1',
        'name': 'Sam',
        'role': 'volunteer',
        'lastMessage': 'I will pick you up at 9',
        'lastAt': DateTime.now().toUtc().subtract(const Duration(minutes: 3)).toIso8601String(),
        'unread': 2,
      });
      api.threads['v1'] = [
        {'id': 'm0', 'fromMe': false, 'body': 'I will pick you up at 9', 'createdAt': DateTime.now().toUtc().toIso8601String()},
      ];
      await _pump(tester, api);
      expect(find.byKey(const Key('home-contacts')), findsOneWidget);
      expect(find.text('Sam'), findsOneWidget);
      expect(find.byKey(const Key('unread-v1')), findsOneWidget);

      await tester.tap(find.byKey(const Key('contact-v1')));
      await _settle(tester);
      expect(find.text('Volunteer'), findsOneWidget);
      expect(find.text('I will pick you up at 9'), findsWidgets);

      await tester.enterText(find.byKey(const Key('chat-input')), 'Thank you!');
      await tester.tap(find.byKey(const Key('chat-send')));
      await _settle(tester);
      expect(find.text('Thank you!'), findsOneWidget);
      expect(api.threads['v1']!.last['body'], 'Thank you!');
      expect(api.routes, contains('POST /api/messages/v1'));
    });

    _withApi('with no contacts yet, Home has no messages section', (tester, api) async {
      await _pump(tester, api);
      expect(find.byKey(const Key('home-contacts')), findsNothing);
    });

    _withApi('Map lives under Me for them', (tester, api) async {
      await _pump(tester, api, start: AppTab.me);
      expect(find.byKey(const Key('open-my-map')), findsOneWidget);
      expect(find.byKey(const Key('open-staff-map')), findsNothing);
    });

    _withApi('the bar holds five icons and Map is not one of them', (tester, api) async {
      await _pump(tester, api);
      for (final label in ['Home', 'Calendar', 'Documents', 'Resources', 'Me']) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      expect(find.text('Map'), findsNothing);
      expect(find.text('Help'), findsNothing);
    });

    _withApi('signing out clears what they asked for, their appointments and their chats', (tester, api) async {
      api.helpRequests.add(_request('h1', userId: 'u1', name: 'Jane Doe'));
      final state = await _pump(tester, api);
      await state.help.refreshMine();
      await state.calendar.refreshAppointments();
      expect(state.help.mine, isNotEmpty);
      await state.signOut();
      expect(state.help.mine, isEmpty);
      expect(state.help.board, isEmpty);
      expect(state.calendar.appointments, isEmpty);
      expect(state.chat.conversations, isEmpty);
    });
  });

  group('a volunteer', () {
    _withApi('sees Help and Messages in the bar, and no Map tab', (tester, api) async {
      await _pump(tester, api, personType: 'volunteer', name: 'Sam Helper', start: AppTab.help);
      for (final label in ['Help', 'Messages', 'Me']) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      expect(find.text('Map'), findsNothing);
      expect(find.text('Home'), findsNothing);
    });

    _withApi('the board shows what people need, and "I can help" takes one on', (tester, api) async {
      api.helpRequests.add(_request('h1', appointment: {
        'id': 'a9', 'title': 'DDS visit', 'location': 'DDS Savannah', 'startsAt': DateTime.now().add(const Duration(days: 1)).toUtc().toIso8601String(),
      }));
      await _pump(tester, api, personType: 'volunteer', name: 'Sam Helper', start: AppTab.help);

      expect(find.text('A ride'), findsOneWidget);
      expect(find.textContaining('Pat Participant'), findsOneWidget);
      expect(find.text('Need to get across town'), findsOneWidget);
      expect(find.byKey(const Key('help-appt-h1')), findsOneWidget);
      expect(find.textContaining('DDS Savannah'), findsOneWidget);

      await tester.tap(find.byKey(const Key('claim-h1')));
      await _settle(tester);
      expect(find.text("You're on it"), findsOneWidget);
      expect(find.byKey(const Key('message-h1')), findsOneWidget);
      expect(api.helpRequests.single['status'], 'claimed');
      expect(find.byKey(const Key('claim-h1')), findsNothing);
    });

    _withApi('Done takes a finished request off the board; "Can\'t anymore" puts it back', (tester, api) async {
      api.helpRequests
        ..add(_request('h1', status: 'claimed', mine: true, helper: 'Sam'))
        ..add(_request('h2', status: 'claimed', mine: true, helper: 'Sam', category: 'food'));
      await _pump(tester, api, personType: 'volunteer', name: 'Sam Helper', start: AppTab.help);

      await tester.tap(find.byKey(const Key('release-h1')));
      await _settle(tester);
      expect(find.byKey(const Key('claim-h1')), findsOneWidget);

      await tester.tap(find.byKey(const Key('finish-h2')));
      await _settle(tester);
      expect(find.byKey(const Key('help-h2')), findsNothing);
    });

    _withApi('someone else\'s claim shows who, and a volunteer cannot free it up', (tester, api) async {
      api.helpRequests.add(_request('h1', status: 'claimed', helper: 'Pat'));
      await _pump(tester, api, personType: 'volunteer', name: 'Sam Helper', start: AppTab.help);
      expect(find.text('Pat is helping'), findsOneWidget);
      expect(find.byKey(const Key('claim-h1')), findsNothing);
      expect(find.byKey(const Key('free-h1')), findsNothing);
    });

    _withApi('an empty board says so', (tester, api) async {
      await _pump(tester, api, personType: 'volunteer', name: 'Sam Helper', start: AppTab.help);
      expect(find.byKey(const Key('board-empty')), findsOneWidget);
    });

    _withApi('Message opens a chat with the person they are helping', (tester, api) async {
      api.helpRequests.add(_request('h1', status: 'claimed', mine: true, helper: 'Sam'));
      await _pump(tester, api, personType: 'volunteer', name: 'Sam Helper', start: AppTab.help);
      await tester.tap(find.byKey(const Key('message-h1')));
      await _settle(tester);
      expect(find.text('Pat Participant'), findsWidgets);
      expect(find.text('Getting support'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('chat-input')), 'On my way');
      await tester.tap(find.byKey(const Key('chat-send')));
      await _settle(tester);
      expect(find.text('On my way'), findsOneWidget);
      expect(api.routes, contains('POST /api/messages/p1'));
    });

    _withApi('the Messages tab lists the people they can message', (tester, api) async {
      api.conversations.add({'userId': 'p1', 'name': 'Pat Participant', 'role': 'participant', 'lastMessage': null, 'lastAt': null, 'unread': 0});
      await _pump(tester, api, personType: 'volunteer', name: 'Sam Helper', start: AppTab.messages);
      expect(find.byKey(const Key('contact-p1')), findsOneWidget);
    });
  });

  group('an admin', () {
    _withApi('keeps Map in the bar next to Help, Messages and Analytics', (tester, api) async {
      await _pump(tester, api, personType: 'admin', name: 'Ada Admin', start: AppTab.help);
      for (final label in ['Map', 'Help', 'Messages', 'Analytics', 'Me']) {
        expect(find.text(label), findsWidgets, reason: label);
      }
    });

    _withApi('can free up a request someone else took', (tester, api) async {
      api.helpRequests.add(_request('h1', status: 'claimed', helper: 'Pat'));
      await _pump(tester, api, personType: 'admin', name: 'Ada Admin', start: AppTab.help);
      await tester.tap(find.byKey(const Key('free-h1')));
      await _settle(tester);
      expect(find.byKey(const Key('claim-h1')), findsOneWidget);
    });

    _withApi('previewing as a participant cannot ask for help or send a message', (tester, api) async {
      final state = await _pump(tester, api, personType: 'admin', name: 'Ada Admin', start: AppTab.me);
      state.viewAs(AppView.participant);
      await tester.pump(const Duration(milliseconds: 300));
      expect(await state.help.ask(category: HelpCategory.food), isNotNull);
      expect(await state.chat.send('x', 'hi'), isNotNull);
      expect(await state.calendar.addAppointment(title: 'x', startsAt: DateTime.now()), isNotNull);
      expect(api.helpRequests, isEmpty);
      expect(api.appointments, isEmpty);
      expect(api.routes, isNot(contains('POST /api/help-requests')));
    });
  });
}
