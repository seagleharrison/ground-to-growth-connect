import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ground_to_growth_connect/app_state.dart';
import 'package:ground_to_growth_connect/models/models.dart';
import 'package:ground_to_growth_connect/nav.dart';
import 'package:ground_to_growth_connect/services/push_controller.dart';
import 'package:ground_to_growth_connect/views/main_tab_view.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'support/fake_api.dart';

const _channel = MethodChannel('g2g/push');

/// Pretends to be the iPhone side. [permission] is what the person has
/// answered so far; asking turns notDetermined into [answerWhenAsked].
class FakePhone {
  String permission;
  String answerWhenAsked;
  String token = 'tok-abc';
  final calls = <String>[];
  int? badge;
  Map<String, String>? launchTap;

  FakePhone({this.permission = 'notDetermined', this.answerWhenAsked = 'authorized'});

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'register':
          final ask = (call.arguments as Map)['ask'] == true;
          if (ask && permission == 'notDetermined') permission = answerWhenAsked;
          return permission == 'authorized' ? {'status': 'authorized', 'token': token} : {'status': permission};
        case 'setBadge':
          badge = (call.arguments as Map)['count'] as int;
          return null;
        case 'takeLaunchTap':
          final t = launchTap;
          launchTap = null;
          return t;
      }
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null));
  }

  /// Someone tapped a notification while the app was open.
  Future<void> tap(Map<String, String> data) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      'g2g/push',
      const StandardMethodCodec().encodeMethodCall(MethodCall('onTap', data)),
      (_) {},
    );
  }
}

void _withApi(String description, Future<void> Function(WidgetTester tester, FakeApi api, FakePhone phone) body,
    {FakePhone? phone}) {
  testWidgets(description, (tester) async {
    final api = FakeApi();
    final fake = (phone ?? FakePhone())..install();
    FlutterSecureStorage.setMockInitialValues({'auth_token': 'tok'});
    await http.runWithClient(() => body(tester, api, fake), () => api.client);
  });
}

Future<AppState> _pump(WidgetTester tester, FakeApi api, String personType, {AppTab? start}) async {
  tester.view.physicalSize = const Size(1200, 4200);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  api.user['personType'] = personType;
  api.user['isStaff'] = personType != 'homeless';
  final state = AppState()
    ..user = User.fromJson(api.user)
    ..isUnlocked = true;
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: state),
      ChangeNotifierProvider(create: (_) => TabNav(current: start ?? (personType == 'homeless' ? AppTab.home : AppTab.me))),
    ],
    child: const MaterialApp(home: MainTabView()),
  ));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 400));
  }
  return state;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  _withApi('someone who already said yes is registered quietly, with no prompt', (tester, api, phone) async {
    phone.permission = 'authorized';
    final state = await _pump(tester, api, 'homeless');
    expect(state.push.status, PushStatus.enabled);
    expect(api.pushTokens, ['tok-abc']);
    expect(find.byKey(const Key('notifications-card')), findsNothing);
  });

  _withApi('a participant who has not been asked sees the offer, and Turn on asks and registers', (tester, api, phone) async {
    final state = await _pump(tester, api, 'homeless');
    expect(state.push.status, PushStatus.notDetermined);
    expect(api.pushTokens, isEmpty, reason: 'nothing is registered until they say yes');
    expect(find.byKey(const Key('notifications-card')), findsOneWidget);
    expect(find.textContaining('never show your messages'), findsOneWidget);

    await tester.tap(find.byKey(const Key('enable-notifications')));
    await _settle(tester);

    expect(state.push.status, PushStatus.enabled);
    expect(api.pushTokens, ['tok-abc']);
    expect(find.byKey(const Key('notifications-card')), findsNothing);
  });

  _withApi('Not now hides the offer and nothing is registered', (tester, api, phone) async {
    final state = await _pump(tester, api, 'homeless');
    await tester.tap(find.byKey(const Key('notifications-not-now')));
    await _settle(tester);
    expect(find.byKey(const Key('notifications-card')), findsNothing);
    expect(api.pushTokens, isEmpty);
    expect(state.push.status, PushStatus.notDetermined);
  });

  _withApi('the offer stays away for a week after Not now, then comes back', (tester, api, phone) async {
    FlutterSecureStorage.setMockInitialValues({
      'auth_token': 'tok',
      'push_prompt_dismissed_at': DateTime.now().subtract(const Duration(days: 2)).toIso8601String(),
    });
    await _pump(tester, api, 'homeless');
    expect(find.byKey(const Key('notifications-card')), findsNothing, reason: 'dismissed 2 days ago');
    await tester.pumpWidget(const SizedBox());

    FlutterSecureStorage.setMockInitialValues({
      'auth_token': 'tok',
      'push_prompt_dismissed_at': DateTime.now().subtract(const Duration(days: 8)).toIso8601String(),
    });
    await _pump(tester, api, 'homeless');
    expect(find.byKey(const Key('notifications-card')), findsOneWidget, reason: 'dismissed 8 days ago');
  });

  _withApi('saying no in the phone prompt registers nothing and Me points to Settings', (tester, api, phone) async {
    phone.answerWhenAsked = 'denied';
    final state = await _pump(tester, api, 'volunteer');
    await tester.tap(find.byKey(const Key('notifications-row')).hitTestable(), warnIfMissed: false);
    await state.push.enable();
    await _settle(tester);

    expect(state.push.status, PushStatus.denied);
    expect(api.pushTokens, isEmpty);
    expect(find.byKey(const Key('notifications-card')), findsNothing, reason: 'no point offering what the phone refuses');
    expect(find.textContaining('Turn them on in your phone'), findsOneWidget);
    expect(find.byKey(const Key('notifications-action')), findsOneWidget);
  });

  _withApi('Me shows Notifications: On once enabled', (tester, api, phone) async {
    phone.permission = 'authorized';
    await _pump(tester, api, 'volunteer');
    expect(find.byKey(const Key('notifications-row')), findsOneWidget);
    expect(find.text('On'), findsOneWidget);
    expect(find.byKey(const Key('notifications-action')), findsNothing);
  });

  _withApi('without phone support (Android, tests) nothing is shown and nothing breaks', (tester, api, phone) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null);
    final state = await _pump(tester, api, 'homeless');
    // Each question to the missing phone is answered by the real event loop.
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(state.push.status, PushStatus.unavailable);
    expect(find.byKey(const Key('notifications-card')), findsNothing);
    expect(find.byKey(const Key('notifications-row')), findsNothing);
    expect(api.pushTokens, isEmpty);
  });

  _withApi('signing out stops alerts for this phone first and clears the badge', (tester, api, phone) async {
    phone.permission = 'authorized';
    final state = await _pump(tester, api, 'homeless');
    expect(api.pushTokens, ['tok-abc']);
    phone.badge = 3;

    await tester.runAsync(() => state.signOut());
    expect(api.pushTokens, isEmpty, reason: 'the next person on this phone must not get these alerts');
    expect(phone.badge, 0);
    expect(state.push.status, PushStatus.unknown);
  });

  _withApi('tapping a "new request" alert opens the Help board for a volunteer', (tester, api, phone) async {
    phone.permission = 'authorized';
    await _pump(tester, api, 'volunteer', start: AppTab.me);
    await phone.tap({'kind': 'help'});
    await _settle(tester);
    final nav = Provider.of<TabNav>(tester.element(find.byType(MainTabView)), listen: false);
    expect(nav.current, AppTab.help);
  });

  _withApi('a notification that opened the closed app is acted on at launch', (tester, api, phone) async {
    phone.permission = 'authorized';
    phone.launchTap = {'kind': 'safety'};
    await _pump(tester, api, 'admin', start: AppTab.me);
    final nav = Provider.of<TabNav>(tester.element(find.byType(MainTabView)), listen: false);
    expect(nav.current, AppTab.messages);
  });

  _withApi('a "volunteer is on your request" alert takes a participant Home', (tester, api, phone) async {
    phone.permission = 'authorized';
    await _pump(tester, api, 'homeless', start: AppTab.me);
    await phone.tap({'kind': 'help-claimed'});
    await _settle(tester);
    final nav = Provider.of<TabNav>(tester.element(find.byType(MainTabView)), listen: false);
    expect(nav.current, AppTab.home);
  });
}
