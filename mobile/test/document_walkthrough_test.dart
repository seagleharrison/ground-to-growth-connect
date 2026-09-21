import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ground_to_growth_connect/app_state.dart';
import 'package:ground_to_growth_connect/models/models.dart';
import 'package:ground_to_growth_connect/services/biometric_auth.dart';
import 'package:ground_to_growth_connect/views/documents_view.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'support/fake_api.dart';

const _pickerChannel = MethodChannel('plugins.flutter.io/image_picker');

Finder get _needed => find.byKey(const Key('status-needed'));
Finder get _onFile => find.byKey(const Key('status-on-file'));
Finder _card(DocumentType type) => find.byKey(Key('wallet-card-${type.wireValue}'));

/// The cards overlap, like Apple Wallet, so only the top strip of each is
/// tappable. Tap inside that strip rather than the card's centre.
Future<void> _tapCard(WidgetTester tester, DocumentType type) async {
  await tester.tapAt(tester.getTopLeft(_card(type)) + const Offset(60, 30));
  await tester.pumpAndSettle();
}

/// Picks a photo (via the stand-in system picker) and waits for the upload.
/// Reading the picked file is real disk I/O the test clock can't advance, so
/// give it real time and let the app react in between.
Future<void> _choosePhotoAndWaitForUploads(WidgetTester tester, FakeApi api, {required int expectedUploads}) async {
  await tester.tap(find.text('Choose from photos'));
  for (var i = 0; i < 40 && api.uploadBodies.length < expectedUploads; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void _test(String description, Future<void> Function(WidgetTester tester, FakeApi api) body) {
  testWidgets(description, (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    // The real Face ID / passcode prompt needs a device; here it just says yes.
    BiometricAuth.debugOverride = (_) async => true;
    addTearDown(() => BiometricAuth.debugOverride = null);

    // A photo on disk for the stand-in system picker to hand back.
    final photo = File('${Directory.systemTemp.path}/doc_test_${DateTime.now().microsecondsSinceEpoch}.jpg');
    await tester.runAsync(() => photo.writeAsBytes(List<int>.generate(2048, (i) => i % 251)));
    addTearDown(() {
      if (photo.existsSync()) photo.deleteSync();
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      _pickerChannel,
      (call) async => call.method == 'pickMultiImage' ? [photo.path] : null,
    );
    addTearDown(() =>
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_pickerChannel, null));

    final api = FakeApi();
    await http.runWithClient(() => body(tester, api), () => api.client);
  });
}

Future<AppState> _pumpDocuments(WidgetTester tester, FakeApi api) async {
  FlutterSecureStorage.setMockInitialValues({'auth_token': 'tok'});
  final state = AppState()
    ..user = User.fromJson(api.user)
    ..isUnlocked = true;
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
        theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange, brightness: Brightness.dark)),
        home: const DocumentsView(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return state;
}

void main() {
  _test('starts as three wallet cards, none added, with a Start button', (tester, api) async {
    await _pumpDocuments(tester, api);

    for (final type in DocumentType.coreChecklist) {
      expect(_card(type), findsOneWidget, reason: '${type.label} card');
    }
    expect(_needed, findsNWidgets(3), reason: 'an empty circle on each card');
    expect(_onFile, findsNothing);
    expect(find.text('0 of 3 on file'), findsOneWidget);
    expect(find.text('Start: Government photo ID'), findsOneWidget);
  });

  _test('the cards stack like Apple Wallet: each overlaps the one above', (tester, api) async {
    await _pumpDocuments(tester, api);

    final tops = [for (final t in DocumentType.coreChecklist) tester.getTopLeft(_card(t)).dy];
    final height = tester.getSize(_card(DocumentType.governmentId)).height;
    expect(tops[1] - tops[0], lessThan(height), reason: 'second card must overlap the first');
    expect(tops[2] - tops[1], lessThan(height));
    expect(tops[0], lessThan(tops[1]));
    expect(tops[1], lessThan(tops[2]));
  });

  _test('walking through all three documents ends with a green check on each card', (tester, api) async {
    await _pumpDocuments(tester, api);

    // Step 1: Government ID
    await tester.tap(find.text('Start: Government photo ID'));
    await tester.pumpAndSettle();
    expect(find.text('Government photo ID'), findsWidgets);
    expect(find.text('Lay your ID flat in good light. Scan the front, and the back too if it has one.'), findsOneWidget);
    expect(find.text('Scan with camera'), findsOneWidget);
    expect(find.text('Choose from photos'), findsOneWidget);

    await _choosePhotoAndWaitForUploads(tester, api, expectedUploads: 1);
    expect(find.text('Government photo ID saved'), findsOneWidget);
    expect(find.text('1 of 3 on file'), findsOneWidget);
    expect(find.text('Next: Social Security card'), findsOneWidget);

    // Step 2: Social Security card
    await tester.tap(find.text('Next: Social Security card'));
    await tester.pumpAndSettle();
    expect(find.text('Scan the front of your Social Security card.'), findsOneWidget);
    await _choosePhotoAndWaitForUploads(tester, api, expectedUploads: 2);
    expect(find.text('Social Security card saved'), findsOneWidget);
    expect(find.text('2 of 3 on file'), findsOneWidget);
    expect(find.text('Next: Birth certificate'), findsOneWidget);

    // Step 3: Birth certificate — nothing left afterwards
    await tester.tap(find.text('Next: Birth certificate'));
    await tester.pumpAndSettle();
    await _choosePhotoAndWaitForUploads(tester, api, expectedUploads: 3);
    expect(find.text('Birth certificate saved'), findsOneWidget);
    expect(find.text('All done'), findsOneWidget);
    expect(find.textContaining('Next:'), findsNothing);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    // Back on the wallet: every card now has its green check.
    expect(_onFile, findsNWidgets(3));
    expect(_needed, findsNothing);
    expect(find.text('3 of 3 on file'), findsOneWidget);
    expect(find.text("Everything on your list is on file. You're all set."), findsOneWidget);
    expect(find.textContaining('Start:'), findsNothing);

    expect([for (final u in api.uploadBodies) u['documentType']],
        ['government_id', 'social_security_card', 'birth_certificate']);
    expect(api.uploadBodies.every((u) => u['mimeType'] == 'image/jpeg'), isTrue);
  });

  _test('the check appears only on the card that was added', (tester, api) async {
    await _pumpDocuments(tester, api);
    await tester.tap(find.text('Start: Government photo ID'));
    await tester.pumpAndSettle();
    await _choosePhotoAndWaitForUploads(tester, api, expectedUploads: 1);

    // Leave the walkthrough part-way, like someone who taps "I'll finish later".
    await tester.tap(find.text("I'll finish later"));
    await tester.pumpAndSettle();

    expect(_onFile, findsOneWidget);
    expect(_needed, findsNWidgets(2));
    expect(find.descendant(of: _card(DocumentType.governmentId), matching: _onFile), findsOneWidget);
    expect(find.descendant(of: _card(DocumentType.socialSecurityCard), matching: _needed), findsOneWidget);
    expect(find.descendant(of: _card(DocumentType.birthCertificate), matching: _needed), findsOneWidget);
    expect(find.text('1 of 3 on file'), findsOneWidget);
    expect(find.text('Next: Social Security card'), findsOneWidget, reason: 'the button moves on to what is missing');
  });

  _test('tapping a card that is not added starts adding that document', (tester, api) async {
    await _pumpDocuments(tester, api);

    await _tapCard(tester, DocumentType.socialSecurityCard);

    expect(find.text('Scan the front of your Social Security card.'), findsOneWidget);
    expect(find.text('Choose from photos'), findsOneWidget);
  });

  _test('tapping a card that is on file opens the stored document', (tester, api) async {
    await _pumpDocuments(tester, api);
    await tester.tap(find.text('Start: Government photo ID'));
    await tester.pumpAndSettle();
    await _choosePhotoAndWaitForUploads(tester, api, expectedUploads: 1);
    await tester.tap(find.text("I'll finish later"));
    await tester.pumpAndSettle();

    await _tapCard(tester, DocumentType.governmentId);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(DocumentDetailView), findsOneWidget);
    expect(find.byType(Image), findsOneWidget, reason: 'the decrypted document is displayed');
  });

  _test('a failed upload shows the error, stays on the scan step, and adds no check', (tester, api) async {
    api.failUploadsWith = 'Invalid JSON body, or file too large';
    await _pumpDocuments(tester, api);

    await tester.tap(find.text('Start: Government photo ID'));
    await tester.pumpAndSettle();
    await _choosePhotoAndWaitForUploads(tester, api, expectedUploads: 1);

    expect(find.textContaining('That file is too big'), findsOneWidget);
    expect(find.text('Choose from photos'), findsOneWidget, reason: 'still on the scan step so they can retry');
    expect(find.textContaining('saved'), findsNothing);

    // Back out: nothing was added, so nothing is checked.
    await tester.tap(find.byIcon(Icons.arrow_back)); // back to choosing a type
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close)); // leave the walkthrough
    await tester.pumpAndSettle();
    expect(_onFile, findsNothing);
    expect(_needed, findsNWidgets(3));
  });

  _test('the biometric check gates adding a document', (tester, api) async {
    BiometricAuth.debugOverride = (_) async => false; // Face ID fails
    await _pumpDocuments(tester, api);

    await tester.tap(find.text('Start: Government photo ID'));
    await tester.pumpAndSettle();

    expect(find.text('Choose from photos'), findsNothing, reason: 'must not open the walkthrough without Face ID');
    expect(find.text('Start: Government photo ID'), findsOneWidget);
  });
}
