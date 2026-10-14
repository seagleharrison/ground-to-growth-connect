import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ground_to_growth_connect/app_state.dart';
import 'package:ground_to_growth_connect/models/models.dart';
import 'package:ground_to_growth_connect/nav.dart';
import 'package:ground_to_growth_connect/theme/app_theme.dart';
import 'package:ground_to_growth_connect/util/launch.dart';
import 'package:ground_to_growth_connect/views/main_tab_view.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'support/fake_api.dart';

void main() {
  testWidgets('Me has Privacy policy and Support links that open our own pages', (tester) async {
    final api = FakeApi();
    final opened = <Uri>[];
    Launch.debugOverride = (uri) async {
      opened.add(uri);
      return true;
    };
    addTearDown(() => Launch.debugOverride = null);
    await http.runWithClient(() async {
      tester.view.physicalSize = const Size(1200, 4200);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      FlutterSecureStorage.setMockInitialValues({'auth_token': 'tok'});
      final state = AppState()
        ..user = User.fromJson(api.user)
        ..isUnlocked = true;
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: state),
          ChangeNotifierProvider(create: (_) => TabNav(current: AppTab.me)),
        ],
        child: MaterialApp(theme: buildAppTheme(), darkTheme: buildAppTheme(), themeMode: ThemeMode.dark, home: const MainTabView()),
      ));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      await tester.ensureVisible(find.byKey(const Key('open-privacy')));
      await tester.tap(find.byKey(const Key('open-privacy')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('open-support')));
      await tester.tap(find.byKey(const Key('open-support')));
      await tester.pump();
    }, () => api.client);
    expect(opened.map((u) => u.toString()), ['https://api.groundtogrowth.org/privacy', 'https://api.groundtogrowth.org/support']);
    expect(Uri.parse(kPrivacyUrl).scheme, 'https');
  });
}
