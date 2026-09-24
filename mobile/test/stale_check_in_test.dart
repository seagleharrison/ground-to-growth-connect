import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ground_to_growth_connect/app_state.dart';
import 'package:ground_to_growth_connect/models/models.dart';
import 'package:ground_to_growth_connect/nav.dart';
import 'package:ground_to_growth_connect/views/home_view.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'support/fake_api.dart';

/// A stale check-in looks exactly like a fresh one otherwise — nothing tells
/// a participant their sharing quietly stopped (e.g. the app got force-quit,
/// which iOS won't relaunch for background location). Home now says so.
void main() {
  Future<AppState> pumpHome(WidgetTester tester, {required DateTime? lastReportAt}) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final api = FakeApi();
    late AppState state;
    await http.runWithClient(() async {
      FlutterSecureStorage.setMockInitialValues({'auth_token': 'tok'});
      state = AppState()
        ..user = User.fromJson(api.user)
        ..isUnlocked = true
        ..consent = ConsentStatus(granted: true);
      state.locationTracker.lastReportAt = lastReportAt;
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: state),
          ChangeNotifierProvider(create: (_) => TabNav()),
        ],
        child: const MaterialApp(home: HomeView()),
      ));
      await tester.pump(const Duration(seconds: 1));
    }, () => api.client);
    return state;
  }

  testWidgets('a check-in from 10 minutes ago looks normal, no stale warning', (tester) async {
    await pumpHome(tester, lastReportAt: DateTime.now().subtract(const Duration(minutes: 10)));
    expect(find.textContaining('longer than usual'), findsNothing);
  });

  testWidgets('a check-in from over an hour ago is flagged, with a hint to reopen the app', (tester) async {
    await pumpHome(tester, lastReportAt: DateTime.now().subtract(const Duration(hours: 1)));
    expect(find.textContaining('longer than usual'), findsOneWidget);
    expect(find.textContaining('reopen it'), findsOneWidget);
  });

  testWidgets('no check-in yet at all is not treated as stale', (tester) async {
    await pumpHome(tester, lastReportAt: null);
    expect(find.text('Waiting for your first check-in…'), findsOneWidget);
    expect(find.textContaining('longer than usual'), findsNothing);
  });
}
