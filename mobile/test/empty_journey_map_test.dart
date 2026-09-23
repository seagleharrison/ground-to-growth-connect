import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ground_to_growth_connect/app_state.dart';
import 'package:ground_to_growth_connect/models/models.dart';
import 'package:ground_to_growth_connect/nav.dart';
import 'package:ground_to_growth_connect/views/my_map_tab_view.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'support/fake_api.dart';

Future<void> _pump(WidgetTester tester, FakeApi api, AppState state) async {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  FlutterSecureStorage.setMockInitialValues({'auth_token': 'tok'});
  await http.runWithClient(() async {
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: state),
        ChangeNotifierProvider(create: (_) => TabNav(current: AppTab.map)),
      ],
      child: const MaterialApp(home: MyMapTabView()),
    ));
    await tester.pump(const Duration(seconds: 1));
  }, () => api.client);
}

void main() {
  // A real field report: a participant who had already turned sharing on saw
  // "turn on sharing" here before any check-in had come in, which reads as
  // if sharing were off.
  testWidgets('with sharing off and nothing recorded, it says how to turn sharing on', (tester) async {
    final api = FakeApi();
    final state = AppState()
      ..user = User.fromJson(api.user)
      ..isUnlocked = true
      ..consent = ConsentStatus(granted: false);
    await _pump(tester, api, state);

    expect(find.text('Your journey will show up here'), findsOneWidget);
    expect(find.text('Go to Home to turn on sharing'), findsOneWidget);
    expect(find.text('Waiting for your first check-in'), findsNothing);
  });

  testWidgets('with sharing already on and nothing recorded yet, it does not tell them to turn it on', (tester) async {
    final api = FakeApi();
    final state = AppState()
      ..user = User.fromJson(api.user)
      ..isUnlocked = true
      ..consent = ConsentStatus(granted: true);
    await _pump(tester, api, state);

    expect(find.text('Waiting for your first check-in'), findsOneWidget);
    expect(find.textContaining('up to 15 minutes'), findsOneWidget);
    expect(find.text('Go to Home to turn on sharing'), findsNothing, reason: 'sharing is already on');
    expect(find.text('Your journey will show up here'), findsNothing);
  });
}
