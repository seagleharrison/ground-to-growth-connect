import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ground_to_growth_connect/app_state.dart';
import 'package:ground_to_growth_connect/models/models.dart';
import 'package:ground_to_growth_connect/nav.dart';
import 'package:ground_to_growth_connect/theme/app_theme.dart';
import 'package:ground_to_growth_connect/views/map_tab_view.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'support/fake_api.dart';

/// Staff never see their own pin among "everyone" (the backend deliberately
/// excludes the viewer's own row — they already know where they are), which
/// meant there was no way for a staff member to confirm their own sharing was
/// actually working, only that they'd turned it on. This is what fills that
/// gap: a status line, sourced entirely from the local tracker rather than
/// the "everyone" list.
void main() {
  Future<AppState> pumpStaffMap(WidgetTester tester, {required DateTime? lastReportAt}) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final api = FakeApi();
    late AppState state;
    await http.runWithClient(() async {
      FlutterSecureStorage.setMockInitialValues({'auth_token': 'tok'});
      api.user['personType'] = 'admin';
      api.user['isStaff'] = true;
      state = AppState()
        ..user = User.fromJson(api.user)
        ..isUnlocked = true
        ..consent = ConsentStatus(granted: true);
      state.locationTracker.lastReportAt = lastReportAt;
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: state),
          ChangeNotifierProvider(create: (_) => TabNav(current: AppTab.map)),
        ],
        child: const MaterialApp(home: MapTabView()),
      ));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
    }, () => api.client);
    return state;
  }

  testWidgets('sharing on with a recent check-in shows a confirming status, not just silence', (tester) async {
    await pumpStaffMap(tester, lastReportAt: DateTime.now().subtract(const Duration(minutes: 3)));
    expect(find.byKey(const Key('self-sharing-status')), findsOneWidget);
    expect(find.textContaining('Sharing on'), findsOneWidget);
    expect(find.textContaining('3 min ago'), findsOneWidget);
  });

  testWidgets('before the first check-in, it says so instead of looking broken', (tester) async {
    await pumpStaffMap(tester, lastReportAt: null);
    expect(find.textContaining('waiting for your first check-in'), findsOneWidget);
  });

  testWidgets('a stale check-in is visually flagged, same threshold as the participant Home screen', (tester) async {
    await pumpStaffMap(tester, lastReportAt: DateTime.now().subtract(const Duration(hours: 1)));
    final text = tester.widget<Text>(find.byKey(const Key('self-sharing-status')));
    expect(text.style!.color, Brand.amber);
    expect(find.textContaining('1 h ago'), findsOneWidget);
  });

  testWidgets('sharing off shows nothing — the toggle chip alone is enough', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final api = FakeApi();
    await http.runWithClient(() async {
      FlutterSecureStorage.setMockInitialValues({'auth_token': 'tok'});
      api.user['personType'] = 'admin';
      api.user['isStaff'] = true;
      final state = AppState()
        ..user = User.fromJson(api.user)
        ..isUnlocked = true
        ..consent = ConsentStatus(granted: false);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: state),
          ChangeNotifierProvider(create: (_) => TabNav(current: AppTab.map)),
        ],
        child: const MaterialApp(home: MapTabView()),
      ));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(find.byKey(const Key('self-sharing-status')), findsNothing);
    }, () => api.client);
  });
}
