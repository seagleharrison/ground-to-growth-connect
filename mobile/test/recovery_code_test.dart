import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ground_to_growth_connect/app_state.dart';
import 'package:ground_to_growth_connect/main.dart';
import 'package:ground_to_growth_connect/models/models.dart';
import 'package:ground_to_growth_connect/nav.dart';
import 'package:ground_to_growth_connect/services/biometric_auth.dart';
import 'package:ground_to_growth_connect/views/recover_account_view.dart';
import 'package:ground_to_growth_connect/widgets/ui.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'support/fake_api.dart';

void _withApi(String description, Future<void> Function(WidgetTester tester, FakeApi api) body) {
  testWidgets(description, (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    BiometricAuth.debugOverride = (_) async => true;
    addTearDown(() => BiometricAuth.debugOverride = null);
    FlutterSecureStorage.setMockInitialValues({});
    final api = FakeApi();
    await http.runWithClient(() => body(tester, api), () => api.client);
  });
}

Future<void> _pumpRoot(WidgetTester tester) async {
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => AppState()..isInitializing = false),
      ChangeNotifierProvider(create: (_) => TabNav()),
    ],
    child: const MaterialApp(home: RootView()),
  ));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  group('signing up', () {
    _withApi('after creating an account, the recovery code screen blocks everything else until it is acknowledged', (tester, api) async {
      api.recoveryCode = 'G7K4-9XPQ-3RTM';
      await _pumpRoot(tester);

      await tester.enterText(find.widgetWithText(TextField, 'Full name'), 'Jane Doe');
      await tester.enterText(find.widgetWithText(TextField, 'Phone'), '912-555-0100');
      await tester.pump();
      await tester.tap(find.widgetWithText(GradientButton, 'Create my account'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }

      expect(find.text('Save your recovery code'), findsOneWidget);
      expect(find.byKey(const Key('recovery-code-text')), findsOneWidget);
      expect(find.text('G7K4-9XPQ-3RTM'), findsOneWidget);
      // The normal signed-in app must not be reachable yet.
      expect(find.text('Good morning, Jane'), findsNothing);
      expect(find.text('Good afternoon, Jane'), findsNothing);
      expect(find.text('Good evening, Jane'), findsNothing);

      await tester.tap(find.byKey(const Key('recovery-code-saved')));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(find.text('Save your recovery code'), findsNothing);
      expect(find.byIcon(Icons.home_rounded), findsOneWidget, reason: 'now in the signed-in app');
    });

    _withApi('the code can be copied to the clipboard', (tester, api) async {
      // A real signed-in session has a token saved — without one, RootView's
      // own bootstrap() finds no token, treats it as expired, and signs out.
      FlutterSecureStorage.setMockInitialValues({'auth_token': 'tok'});
      final state = AppState()..isInitializing = false;
      state.user = User.fromJson(api.user);
      state.isUnlocked = true;
      state.pendingRecoveryCode = 'G7K4-9XPQ-3RTM';
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: state),
          ChangeNotifierProvider(create: (_) => TabNav()),
        ],
        child: const MaterialApp(home: RootView()),
      ));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }

      expect(find.text('Copy code'), findsOneWidget);
      // Clipboard.setData goes through a real platform channel, which (with
      // no plugin registered here) needs the real event loop to resolve, not
      // the fake-clock test zone — same pattern as this suite's real I/O.
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('copy-recovery-code')));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      expect(find.text('Copied'), findsOneWidget);
    });
  });

  group('recovering an existing account', () {
    _withApi('"I already have an account" leads to a code entry screen', (tester, api) async {
      await _pumpRoot(tester);
      expect(find.byKey(const Key('go-to-recover')), findsOneWidget);
      await tester.tap(find.byKey(const Key('go-to-recover')));
      await tester.pumpAndSettle();
      expect(find.byType(RecoverAccountView), findsOneWidget);
      expect(find.byKey(const Key('recovery-code-field')), findsOneWidget);
    });

    _withApi('a matching code signs back into the same account, no new recovery code is shown', (tester, api) async {
      api.recoveryCode = 'G7K4-9XPQ-3RTM';
      api.user = {...api.user, 'name': 'Returning Person'};
      await _pumpRoot(tester);
      final state = Provider.of<AppState>(tester.element(find.byType(RootView)), listen: false);
      await tester.tap(find.byKey(const Key('go-to-recover')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('recovery-code-field')), 'g7k4 9xpq 3rtm');
      await tester.pump();
      await tester.tap(find.byKey(const Key('recover-submit')));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }

      // The staff/participant map's tile loading can eat the whole pump
      // budget, so check the actual state rather than racing its UI.
      expect(state.isSignedIn, isTrue);
      expect(state.isUnlocked, isTrue);
      expect(state.user?.name, 'Returning Person');
      expect(state.pendingRecoveryCode, isNull, reason: 'recovering does not hand out a new code');
      expect(find.byType(RecoverAccountView), findsNothing);
    });

    _withApi('a wrong code shows an error and does not sign anyone in', (tester, api) async {
      api.recoveryCode = 'G7K4-9XPQ-3RTM';
      await _pumpRoot(tester);
      await tester.tap(find.byKey(const Key('go-to-recover')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('recovery-code-field')), 'WRONG-CODE-HERE');
      await tester.pump();
      await tester.tap(find.byKey(const Key('recover-submit')));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }

      expect(find.textContaining("doesn't match"), findsOneWidget);
      expect(find.byType(RecoverAccountView), findsOneWidget, reason: 'stays on the recover screen');
    });

    _withApi('Continue stays off until something is typed', (tester, api) async {
      await _pumpRoot(tester);
      await tester.tap(find.byKey(const Key('go-to-recover')));
      await tester.pumpAndSettle();

      bool enabled() => tester.widget<GradientButton>(find.byKey(const Key('recover-submit'))).onPressed != null;
      expect(enabled(), isFalse);
      await tester.enterText(find.byKey(const Key('recovery-code-field')), 'G7K4-9XPQ-3RTM');
      await tester.pump();
      expect(enabled(), isTrue);
    });
  });
}
