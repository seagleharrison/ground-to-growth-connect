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

void main() {
  testWidgets('the map offers All days, Past 7 days and This month next to each day', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    FlutterSecureStorage.setMockInitialValues({'auth_token': 'tok'});
    final api = FakeApi();

    // One check-in today, one 3 days ago, one 40 days ago.
    String at(int daysAgo) {
      final n = DateTime.now();
      return DateTime(n.year, n.month, n.day - daysAgo, 9).toUtc().toIso8601String();
    }

    MyLocationReport report(int daysAgo, double lat) =>
        MyLocationReport(latitude: lat, longitude: -81.09, accuracyMeters: 65, reportedAt: at(daysAgo));

    await http.runWithClient(() async {
      final state = AppState()
        ..user = User.fromJson(api.user)
        ..isUnlocked = true
        ..myLocations = [report(40, 32.07), report(3, 32.08), report(0, 32.09)];
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: state),
          ChangeNotifierProvider(create: (_) => TabNav()),
        ],
        child: const MaterialApp(home: MyMapTabView()),
      ));
      await tester.pump(const Duration(seconds: 1));

      expect(find.byKey(const Key('chip-all')), findsOneWidget);
      expect(find.byKey(const Key('chip-week')), findsOneWidget);
      expect(find.byKey(const Key('chip-month')), findsOneWidget);
      expect(find.text('Your journey'), findsOneWidget);

      await tester.tap(find.byKey(const Key('chip-week')));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Past 7 days'), findsWidgets);
      expect(find.text('2'), findsWidgets, reason: 'two days and two check-ins fall inside the past week');
      expect(find.text('Your journey'), findsNothing);

      await tester.tap(find.byKey(const Key('chip-all')));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Your journey'), findsOneWidget);
      expect(find.text('3'), findsWidgets);
    }, () => api.client);
  });
}
