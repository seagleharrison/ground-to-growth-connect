import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ground_to_growth_connect/app_state.dart';
import 'package:ground_to_growth_connect/main.dart';
import 'package:ground_to_growth_connect/services/biometric_auth.dart';
import 'package:provider/provider.dart';

void main() {
  tearDown(() => BiometricAuth.debugOverride = null);

  Future<AppState> pumpLocked(WidgetTester tester) async {
    final state = AppState()..isUnlocked = false;
    await tester.pumpWidget(
      ChangeNotifierProvider.value(value: state, child: const MaterialApp(home: LockedView())),
    );
    return state;
  }

  testWidgets('asks for Face ID by itself and unlocks without any tap', (tester) async {
    final reasons = <String>[];
    BiometricAuth.debugOverride = (reason) async {
      reasons.add(reason);
      return true;
    };

    final state = await pumpLocked(tester);
    await tester.pump();

    expect(reasons, hasLength(1));
    expect(state.isUnlocked, isTrue);
  });

  testWidgets('a cancelled Face ID stays locked, shows a hint, and the button retries', (tester) async {
    var attempts = 0;
    BiometricAuth.debugOverride = (_) async => ++attempts > 1;

    final state = await pumpLocked(tester);
    await tester.pump();
    expect(state.isUnlocked, isFalse);
    expect(find.textContaining("Face ID didn't work"), findsOneWidget);

    await tester.tap(find.text('Unlock'));
    await tester.pump();
    expect(state.isUnlocked, isTrue);
  });

  testWidgets('asks again on its own when the app comes back to the front', (tester) async {
    var attempts = 0;
    BiometricAuth.debugOverride = (_) async {
      attempts++;
      return attempts > 1; // first look fails, so the screen stays up
    };

    final state = await pumpLocked(tester);
    await tester.pump();
    expect(attempts, 1);
    expect(state.isUnlocked, isFalse);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(attempts, 2);
    expect(state.isUnlocked, isTrue);
  });
}
