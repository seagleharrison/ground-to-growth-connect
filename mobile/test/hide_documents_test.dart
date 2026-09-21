import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ground_to_growth_connect/app_state.dart';
import 'package:ground_to_growth_connect/models/models.dart';
import 'package:ground_to_growth_connect/services/secure_storage_service.dart';
import 'package:ground_to_growth_connect/views/documents_view.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'support/fake_api.dart';

Finder _card(DocumentType t) => find.byKey(Key('wallet-card-${t.wireValue}'));
Finder _hide(DocumentType t) => find.byKey(Key('hide-${t.wireValue}'));

void _test(String description, Future<void> Function(WidgetTester tester, FakeApi api) body) {
  testWidgets(description, (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final api = FakeApi();
    await http.runWithClient(() => body(tester, api), () => api.client);
  });
}

Future<AppState> _pump(WidgetTester tester, FakeApi api, {Map<String, String> stored = const {}}) async {
  FlutterSecureStorage.setMockInitialValues({'auth_token': 'tok', ...stored});
  final state = AppState()
    ..user = User.fromJson(api.user)
    ..isUnlocked = true;
  state.hiddenDocuments = await SecureStorageService.loadHiddenDocuments(state.user!.id);
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: state,
    child: MaterialApp(
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange, brightness: Brightness.dark)),
      home: const DocumentsView(),
    ),
  ));
  await tester.pumpAndSettle();
  return state;
}

void main() {
  _test('every card that is not on file offers "I don\'t have this"', (tester, api) async {
    await _pump(tester, api);
    for (final t in DocumentType.coreChecklist) {
      expect(_hide(t), findsOneWidget);
    }
  });

  _test('hiding a document removes its card, and the count only asks for what is left', (tester, api) async {
    final state = await _pump(tester, api);
    expect(find.text('0 of 3 on file'), findsOneWidget);

    await tester.tap(_hide(DocumentType.birthCertificate));
    await tester.pumpAndSettle();

    expect(_card(DocumentType.birthCertificate), findsNothing);
    expect(_card(DocumentType.governmentId), findsOneWidget);
    expect(find.text('0 of 2 on file'), findsOneWidget);
    expect(state.hiddenDocuments, {DocumentType.birthCertificate});
    expect(find.byKey(const Key('hidden-documents')), findsOneWidget);
    expect(find.text('Birth certificate'), findsOneWidget, reason: 'listed under Hidden, with a way back');
  });

  _test('"Show again" and the snackbar\'s Undo both bring a card back', (tester, api) async {
    final state = await _pump(tester, api);

    await tester.tap(_hide(DocumentType.socialSecurityCard));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(_card(DocumentType.socialSecurityCard), findsOneWidget);
    expect(state.hiddenDocuments, isEmpty);

    await tester.tap(_hide(DocumentType.socialSecurityCard));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('unhide-social_security_card')));
    await tester.pumpAndSettle();
    expect(_card(DocumentType.socialSecurityCard), findsOneWidget);
    expect(find.text('0 of 3 on file'), findsOneWidget);
  });

  _test('the Start button skips over documents that are hidden', (tester, api) async {
    await _pump(tester, api);
    expect(find.text('Start: Government photo ID'), findsOneWidget);

    await tester.tap(_hide(DocumentType.governmentId));
    await tester.pumpAndSettle();
    expect(find.text('Start: Social Security card'), findsOneWidget);
  });

  _test('hiding everything leaves nothing on the list and nothing to nag about', (tester, api) async {
    final state = await _pump(tester, api);
    for (final t in DocumentType.coreChecklist) {
      await tester.tap(_hide(t));
      await tester.pumpAndSettle();
    }
    expect(state.documentChecklist, isEmpty);
    expect(find.text('Nothing left on your list'), findsOneWidget);
    expect(missingCoreDocuments(state.documents, hidden: state.hiddenDocuments), isEmpty);
    expect(find.textContaining('Start:'), findsNothing);
  });

  _test('a document that is already on file cannot be hidden, and one added later always shows', (tester, api) async {
    final state = await _pump(tester, api);
    await state.hideDocument(DocumentType.governmentId);
    expect(state.hiddenDocuments, {DocumentType.governmentId});

    // The person adds it after all: it must reappear on the list.
    state.documents = [
      DocumentMeta(id: 'd1', documentType: 'government_id', mimeType: 'image/jpeg', fileSizeBytes: 10, createdAt: '2026-09-21T12:00:00.000Z'),
    ];
    expect(state.documentChecklist, contains(DocumentType.governmentId));

    // And once something is on file, hiding it is refused.
    await state.unhideDocument(DocumentType.governmentId);
    await state.hideDocument(DocumentType.governmentId);
    expect(state.hiddenDocuments, isEmpty);
  });

  _test('the choice is remembered on this phone', (tester, api) async {
    final state = await _pump(tester, api);
    await tester.tap(_hide(DocumentType.birthCertificate));
    await tester.pumpAndSettle();
    final saved = await SecureStorageService.loadHiddenDocuments(state.user!.id);
    expect(saved, {DocumentType.birthCertificate});

    // Reopening the app (fresh state, same phone) still has it hidden.
    await tester.pumpWidget(const SizedBox());
    final again = await _pump(tester, api, stored: {'hidden_documents_${state.user!.id}': 'birth_certificate'});
    expect(again.hiddenDocuments, {DocumentType.birthCertificate});
    expect(_card(DocumentType.birthCertificate), findsNothing);
  });

  _test('signing out forgets the hidden list', (tester, api) async {
    final state = await _pump(tester, api);
    await state.hideDocument(DocumentType.governmentId);
    final id = state.user!.id;
    await state.signOut();
    expect(state.hiddenDocuments, isEmpty);
    expect(await SecureStorageService.loadHiddenDocuments(id), isEmpty);
  });
}
