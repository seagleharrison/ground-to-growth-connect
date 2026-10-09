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

Map<String, dynamic> _request(String id, {String status = 'open', String category = 'ride', String userId = 'p1', String name = 'Pat Participant', Map<String, dynamic>? appointment, bool mine = false, String? helper, Map<String, dynamic>? extra}) => {
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
      ...?extra,
    };

Future<void> _openMenu(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(Key('more-$id')));
  await _settle(tester, times: 3);
}

void main() {
  group('a person getting support', () {
    _withApi('asking for basic items means picking from a list, and sends it waiting', (tester, api) async {
      await _pump(tester, api);
      await tester.tap(find.byKey(const Key('ask-for-help-card')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('ask-for-help')));
      await _settle(tester);

      await tester.tap(find.byKey(const Key('category-supplies')));
      await tester.pump();
      expect(find.text('Pick what you need'), findsOneWidget);
      // Nothing picked yet: nothing is sent.
      await tester.tap(find.byKey(const Key('send-help-request')), warnIfMissed: false);
      await _settle(tester);
      expect(api.helpRequests, isEmpty);

      await tester.ensureVisible(find.byKey(const Key('item-socks')));
      await tester.tap(find.byKey(const Key('item-socks')));
      await tester.tap(find.byKey(const Key('item-blanket')));
      await tester.pump();
      expect(find.text('2 picked'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('send-help-request')));
      await tester.tap(find.byKey(const Key('send-help-request')));
      await _settle(tester);

      expect(api.helpRequests.single['category'], 'supplies');
      expect(api.helpRequests.single['items'], ['socks', 'blanket']);
      expect(find.text('Waiting for a volunteer'), findsOneWidget);
      expect(find.text('Socks and a blanket'), findsOneWidget);
    });

    _withApi('a pick can be taken back, and no more than ten at once', (tester, api) async {
      await _pump(tester, api);
      await tester.tap(find.byKey(const Key('ask-for-help-card')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('ask-for-help')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('category-supplies')));
      await tester.pump();
      for (final code in ['meal', 'water', 'snacks', 'socks', 'underwear', 'shirt', 'pants', 'shoes', 'coat', 'hat_gloves', 'blanket']) {
        await tester.ensureVisible(find.byKey(Key('item-$code')));
        await tester.tap(find.byKey(Key('item-$code')));
        await tester.pump();
      }
      expect(find.textContaining('10 picked'), findsOneWidget, reason: 'the eleventh is not added');
      await tester.tap(find.byKey(const Key('item-meal')));
      await tester.pump();
      expect(find.text('9 picked'), findsOneWidget);
    });

    _withApi('rides are not asked for here: the sheet points to the Calendar', (tester, api) async {
      await _pump(tester, api);
      await tester.tap(find.byKey(const Key('ask-for-help-card')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('ask-for-help')));
      await _settle(tester);
      expect(find.byKey(const Key('category-ride')), findsNothing);
      expect(find.byKey(const Key('ride-hint')), findsOneWidget);
    });

    _withApi('a note stops at 140 characters', (tester, api) async {
      await _pump(tester, api);
      await tester.tap(find.byKey(const Key('ask-for-help-card')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('ask-for-help')));
      await _settle(tester);
      await tester.enterText(find.byKey(const Key('help-note-field')), 'x' * 200);
      await tester.pump();
      expect(tester.widget<TextField>(find.byKey(const Key('help-note-field'))).controller!.text.length, 140);
      expect(find.text('140/140'), findsOneWidget);
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
      await tester.tap(find.byKey(const Key('category-documents')));
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

    _withApi('while a volunteer is on the request, the person is offered the team to message, not the volunteer', (tester, api) async {
      api.conversations.add({'userId': 't1', 'name': 'Ada', 'role': 'team', 'lastMessage': null, 'lastAt': null, 'unread': 0});
      api.helpRequests.add(_request('h1', status: 'claimed', mine: true, userId: 'u1', name: 'Jane Doe', helper: 'Sam'));
      await _pump(tester, api);
      await tester.tap(find.byKey(const Key('ask-for-help-card')));
      await _settle(tester);
      expect(find.text('Sam is helping'), findsOneWidget);
      expect(find.text('Message the team'), findsOneWidget);
      expect(find.text('Message Sam'), findsNothing);
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

      expect(find.text('Ride to DDS visit'), findsOneWidget);
      expect(find.textContaining('Pat Participant'), findsOneWidget);
      expect(find.text('Need to get across town'), findsOneWidget);
      expect(find.byKey(const Key('help-appt-h1')), findsOneWidget);
      expect(find.textContaining('DDS Savannah'), findsOneWidget);

      await tester.tap(find.byKey(const Key('claim-h1')));
      await _settle(tester);
      // Accepting is immediate: it's theirs, and the next step is one tap away.
      expect(find.text("You're on it"), findsOneWidget);
      expect(api.helpRequests.single['status'], 'claimed');
      expect(find.byKey(const Key('claim-h1')), findsNothing);
      expect(find.byKey(const Key('step-on-my-way-h1')), findsOneWidget);
    });

    _withApi('Done takes a finished request off the board; "Can\'t make it" puts it back', (tester, api) async {
      api.helpRequests
        ..add(_request('h1', status: 'claimed', mine: true, helper: 'Sam'))
        ..add(_request('h2', status: 'claimed', mine: true, helper: 'Sam', category: 'food'));
      await _pump(tester, api, personType: 'volunteer', name: 'Sam Helper', start: AppTab.help);

      await _openMenu(tester, 'h1');
      await tester.tap(find.byKey(const Key('cant-make-it-h1')));
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

    _withApi('"Message the team" opens a chat with an admin, never with the person they are helping', (tester, api) async {
      api.conversations.add({'userId': 't1', 'name': 'Ada', 'role': 'team', 'lastMessage': null, 'lastAt': null, 'unread': 0});
      api.helpRequests.add(_request('h1', status: 'claimed', mine: true, helper: 'Sam'));
      await _pump(tester, api, personType: 'volunteer', name: 'Sam Helper', start: AppTab.help);
      await _openMenu(tester, 'h1');
      expect(find.text('Message the team'), findsOneWidget);
      expect(find.text('Message Pat Participant'), findsNothing);
      await tester.tap(find.byKey(const Key('message-h1')));
      await _settle(tester);
      expect(find.text('Ada'), findsWidgets);
      await tester.enterText(find.byKey(const Key('chat-input')), 'On my way');
      await tester.tap(find.byKey(const Key('chat-send')));
      await _settle(tester);
      expect(find.text('On my way'), findsOneWidget);
      expect(api.routes, contains('POST /api/messages/t1'));
      expect(api.routes, isNot(contains('POST /api/messages/p1')));
    });

    _withApi('with no team contact loaded there is no message button, and never one to the person', (tester, api) async {
      api.helpRequests.add(_request('h1', status: 'claimed', mine: true, helper: 'Sam'));
      await _pump(tester, api, personType: 'volunteer', name: 'Sam Helper', start: AppTab.help);
      await _openMenu(tester, 'h1');
      expect(find.byKey(const Key('message-h1')), findsNothing);
    });

    _withApi('the Messages tab lists the team to message', (tester, api) async {
      api.conversations.add({'userId': 't1', 'name': 'Ada', 'role': 'team', 'lastMessage': null, 'lastAt': null, 'unread': 0});
      await _pump(tester, api, personType: 'volunteer', name: 'Sam Helper', start: AppTab.messages);
      expect(find.byKey(const Key('contact-t1')), findsOneWidget);
    });
  });

  group('an admin', () {
    _withApi('keeps Map in the bar next to Help, Messages and Analytics', (tester, api) async {
      await _pump(tester, api, personType: 'admin', name: 'Ada Admin', start: AppTab.help);
      for (final label in ['Map', 'Help', 'Messages', 'Analytics', 'Me']) {
        expect(find.text(label), findsWidgets, reason: label);
      }
    });

    _withApi('can message the person who asked, right from the board', (tester, api) async {
      api.helpRequests.add(_request('h1'));
      await _pump(tester, api, personType: 'admin', name: 'Ada Admin', start: AppTab.help);
      await _openMenu(tester, 'h1');
      expect(find.text('Message Pat Participant'), findsOneWidget);
      await tester.tap(find.byKey(const Key('message-h1')));
      await _settle(tester);
      await tester.enterText(find.byKey(const Key('chat-input')), 'Hi Pat, a volunteer is on the way');
      await tester.tap(find.byKey(const Key('chat-send')));
      await _settle(tester);
      expect(api.routes, contains('POST /api/messages/p1'));
    });

    _withApi('can free up a request someone else took', (tester, api) async {
      api.helpRequests.add(_request('h1', status: 'claimed', helper: 'Pat'));
      await _pump(tester, api, personType: 'admin', name: 'Ada Admin', start: AppTab.help);
      await _openMenu(tester, 'h1');
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

  group('a ride, step by step, with taps instead of typing', () {
    Map<String, dynamic> ride(String id, {String status = 'claimed', bool mine = true, String? progress, int? minutes, String? helper = 'Sam'}) => _request(
          id,
          category: 'ride',
          status: status,
          mine: mine,
          helper: status == 'open' ? null : helper,
          appointment: {'id': 'a9', 'title': 'DDS visit', 'location': 'DDS Savannah', 'startsAt': DateTime.now().add(const Duration(hours: 5)).toUtc().toIso8601String()},
          extra: {'progress': progress, 'progressMinutes': minutes},
        );

    _withApi('the volunteer taps On my way, then I\'ve arrived, then Done', (tester, api) async {
      api.helpRequests.add(ride('h1'));
      await _pump(tester, api, personType: 'volunteer', name: 'Sam Helper', start: AppTab.help);
      expect(find.text("You're on it"), findsOneWidget);
      expect(find.byKey(const Key('step-arrived-h1')), findsNothing, reason: 'on my way comes first');

      await tester.tap(find.byKey(const Key('step-on-my-way-h1')));
      await _settle(tester);
      expect(api.progressTaps, ['on_my_way']);
      expect(find.text("You're on your way"), findsOneWidget);
      expect(find.byKey(const Key('step-on-my-way-h1')), findsNothing);

      await tester.tap(find.byKey(const Key('step-arrived-h1')));
      await _settle(tester);
      expect(api.progressTaps, ['on_my_way', 'arrived']);
      expect(find.text("You've arrived"), findsOneWidget);
      expect(find.byKey(const Key('finish-h1')), findsOneWidget);
    });

    _withApi('running late is a tap and a choice of minutes', (tester, api) async {
      api.helpRequests.add(ride('h1', progress: 'on_my_way'));
      await _pump(tester, api, personType: 'volunteer', name: 'Sam Helper', start: AppTab.help);
      await _openMenu(tester, 'h1');
      await tester.tap(find.byKey(const Key('late-h1-20')));
      await _settle(tester);
      expect(api.progressTaps, ['running_late']);
      expect(find.text("You're running late (~20 min)"), findsOneWidget);
    });

    _withApi('"I don\'t feel safe" asks once, then alerts the admins and ends the match', (tester, api) async {
      api.helpRequests.add(ride('h1'));
      await _pump(tester, api, personType: 'volunteer', name: 'Sam Helper', start: AppTab.help);
      await tester.tap(find.byKey(const Key('unsafe-h1')));
      await _settle(tester, times: 3);
      expect(find.byKey(const Key('unsafe-dialog')), findsOneWidget);
      expect(find.textContaining('every Ground to Growth admin'), findsOneWidget);

      await tester.tap(find.byKey(const Key('unsafe-cancel')));
      await _settle(tester, times: 3);
      expect(api.progressTaps, isEmpty, reason: 'cancelling sends nothing');

      await tester.tap(find.byKey(const Key('unsafe-h1')));
      await _settle(tester, times: 3);
      await tester.tap(find.byKey(const Key('unsafe-confirm')));
      await _settle(tester);
      expect(api.progressTaps, ['unsafe']);
      expect(find.byKey(const Key('step-on-my-way-h1')), findsNothing, reason: 'the match is over');
    });

    _withApi('an admin can accept a ride too, and sees where and when', (tester, api) async {
      api.helpRequests.add(ride('h1', status: 'open', mine: false));
      await _pump(tester, api, personType: 'admin', name: 'Ada Admin', start: AppTab.help);
      expect(find.text('Ride to DDS visit'), findsOneWidget);
      expect(find.byKey(const Key('help-appt-h1')), findsOneWidget);
      expect(find.text('I can give this ride'), findsOneWidget);
      await tester.tap(find.byKey(const Key('claim-h1')));
      await _settle(tester);
      expect(api.helpRequests.single['status'], 'claimed');
      expect(find.text("You're on it"), findsOneWidget);
    });

    _withApi('rides come first on the board, and nothing is held up waiting for an admin', (tester, api) async {
      api.helpRequests.add(ride('h1', status: 'open', mine: false));
      await _pump(tester, api, personType: 'volunteer', name: 'Sam Helper', start: AppTab.help);
      expect(find.text('I can give this ride'), findsOneWidget);
      await tester.tap(find.byKey(const Key('claim-h1')));
      await _settle(tester);
      expect(find.byKey(const Key('step-on-my-way-h1')), findsOneWidget, reason: 'accepted straight away');
    });

    _withApi('a basic items request lists the items and has a They\'re ready tap', (tester, api) async {
      api.helpRequests.add(_request('h1', status: 'claimed', mine: true, helper: 'Sam', category: 'supplies', extra: {'items': ['socks', 'blanket', 'water']}));
      await _pump(tester, api, personType: 'volunteer', name: 'Sam Helper', start: AppTab.help);
      expect(find.byKey(const Key('items-h1')), findsOneWidget);
      expect(find.text('Socks'), findsOneWidget);
      expect(find.text('A blanket'), findsOneWidget);
      expect(find.text('Water'), findsOneWidget);
      await tester.tap(find.byKey(const Key('step-ready-h1')));
      await _settle(tester);
      expect(api.progressTaps, ['ready']);
      expect(find.text('Ready for pickup'), findsOneWidget);
      expect(find.byKey(const Key('step-ready-h1')), findsNothing);
    });

    _withApi('the person sees each step as it happens', (tester, api) async {
      api.helpRequests.add(ride('h1', mine: false, progress: 'on_my_way')..['userId'] = 'u1');
      final state = await _pump(tester, api);
      await tester.tap(find.byKey(const Key('ask-for-help-card')));
      await _settle(tester);
      expect(find.text('Sam is on the way'), findsOneWidget);
      api.helpRequests.single['progress'] = 'late';
      api.helpRequests.single['progressMinutes'] = 20;
      await state.help.refreshMine();
      await _settle(tester);
      expect(find.text('Sam is running late (about 20 min)'), findsOneWidget);
    });

    _withApi('the person can press "I don\'t feel safe" and the match ends', (tester, api) async {
      api.helpRequests.add(ride('h1', mine: false)..['userId'] = 'u1');
      await _pump(tester, api);
      await tester.tap(find.byKey(const Key('ask-for-help-card')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('unsafe-h1')));
      await _settle(tester, times: 3);
      expect(find.textContaining("won't be able to take your requests again"), findsOneWidget);
      await tester.tap(find.byKey(const Key('unsafe-confirm')));
      await _settle(tester);
      expect(api.progressTaps, ['unsafe']);
      expect(find.text('Waiting for a volunteer'), findsOneWidget, reason: 'the request is back to waiting');
    });

    _withApi('after it is done the person gives a thumbs up, once', (tester, api) async {
      api.helpRequests.add(ride('h1', status: 'done', mine: false)..['userId'] = 'u1'..['helperName'] = 'Sam');
      await _pump(tester, api);
      await tester.tap(find.byKey(const Key('ask-for-help-card')));
      await _settle(tester);
      expect(find.text('How did it go with Sam?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('rate-up-h1')));
      await _settle(tester);
      expect(api.helpRequests.single['rating'], 1);
      expect(find.byKey(const Key('rate-up-h1')), findsNothing);
      expect(find.byKey(const Key('rated-h1')), findsOneWidget);
    });

    _withApi('a finished request nobody helped with is not rated', (tester, api) async {
      api.helpRequests.add(_request('h1', status: 'done', userId: 'u1', name: 'Jane Doe', category: 'food'));
      await _pump(tester, api);
      await tester.tap(find.byKey(const Key('ask-for-help-card')));
      await _settle(tester);
      expect(find.byKey(const Key('rate-up-h1')), findsNothing);
    });
  });
}
