import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ground_to_growth_connect/app_state.dart';
import 'package:ground_to_growth_connect/models/models.dart';
import 'package:ground_to_growth_connect/nav.dart';
import 'package:ground_to_growth_connect/views/main_tab_view.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'support/fake_api.dart';

Future<AppState> _pump(WidgetTester tester, FakeApi api, String personType, {AppTab start = AppTab.me}) async {
  tester.view.physicalSize = const Size(1200, 4200);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  FlutterSecureStorage.setMockInitialValues({'auth_token': 'tok'});
  api.user['personType'] = personType;
  api.user['isStaff'] = personType != 'homeless';
  final state = AppState()
    ..user = User.fromJson(api.user)
    ..isUnlocked = true;
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: state),
      ChangeNotifierProvider(create: (_) => TabNav(current: start)),
    ],
    child: const MaterialApp(home: MainTabView()),
  ));
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 400));
  }
  return state;
}

void _withApi(String description, Future<void> Function(WidgetTester tester, FakeApi api) body) {
  testWidgets(description, (tester) async {
    final api = FakeApi();
    await http.runWithClient(() => body(tester, api), () => api.client);
  });
}

Future<void> _pick(WidgetTester tester, AppView v) async {
  await tester.ensureVisible(find.byKey(Key('view-as-${v.name}')));
  await tester.tap(find.byKey(Key('view-as-${v.name}')));
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 400));
  }
}

void main() {
  _withApi('an admin sees the view switcher in Me, starting on Admin', (tester, api) async {
    final state = await _pump(tester, api, 'admin');
    expect(find.byKey(const Key('view-as-card')), findsOneWidget);
    for (final v in AppView.values) {
      expect(find.byKey(Key('view-as-${v.name}')), findsOneWidget);
    }
    expect(state.currentView, AppView.admin);
    expect(state.isPreviewing, isFalse);
    expect(find.byKey(const Key('preview-banner')), findsNothing);
    expect(find.text('Analytics'), findsWidgets, reason: 'admins get the Analytics tab');
  });

  for (final role in ['volunteer', 'homeless']) {
    _withApi('$role accounts never see the switcher, and cannot switch even if asked', (tester, api) async {
      final state = await _pump(tester, api, role);
      expect(find.byKey(const Key('view-as-card')), findsNothing);
      state.viewAs(AppView.admin);
      state.viewAs(AppView.participant);
      expect(state.previewView, isNull);
      expect(state.currentView, role == 'homeless' ? AppView.participant : AppView.volunteer);
    });
  }

  _withApi('previewing as Volunteer shows the volunteer tabs, with a banner and a way back', (tester, api) async {
    final state = await _pump(tester, api, 'admin');
    await _pick(tester, AppView.volunteer);

    expect(state.currentView, AppView.volunteer);
    expect(state.isPreviewing, isTrue);
    expect(find.byKey(const Key('preview-banner')), findsOneWidget);
    expect(find.text('Previewing as Volunteer'), findsOneWidget);
    expect(find.text('Analytics'), findsNothing, reason: 'volunteers have no Analytics');
    expect(find.text('Home'), findsNothing);
    expect(find.text('Documents'), findsNothing);
    expect(find.text('Map'), findsWidgets);

    // The account itself is untouched.
    expect(state.user!.personType, 'admin');
    expect(api.user['personType'], 'admin');

    await tester.tap(find.byKey(const Key('exit-preview')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(state.currentView, AppView.admin);
    expect(find.byKey(const Key('preview-banner')), findsNothing);
    expect(find.text('Analytics'), findsWidgets);
  });

  _withApi('previewing as Getting support shows the participant tabs', (tester, api) async {
    final state = await _pump(tester, api, 'admin');
    await _pick(tester, AppView.participant);

    expect(state.currentView, AppView.participant);
    expect(find.text('Previewing as Getting support'), findsOneWidget);
    for (final label in ['Home', 'Map', 'Documents', 'Resources', 'Me']) {
      expect(find.text(label), findsWidgets, reason: '$label tab');
    }
    expect(find.text('Analytics'), findsNothing);
    expect(state.user!.isAdmin, isTrue, reason: 'still an admin underneath');
  });

  _withApi('the switcher stays reachable from inside a preview, so switching views is one tap', (tester, api) async {
    final state = await _pump(tester, api, 'admin');
    await _pick(tester, AppView.participant);
    // In the participant view Me is a tab too; go there and hop straight to the volunteer view.
    nav(tester).go(AppTab.me);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('view-as-card')), findsOneWidget);
    await _pick(tester, AppView.volunteer);
    expect(state.currentView, AppView.volunteer);
  });

  _withApi('a preview cannot turn on location sharing, upload documents, or touch the server', (tester, api) async {
    final state = await _pump(tester, api, 'admin');
    await _pick(tester, AppView.participant);
    api.routes.clear();

    await state.grantConsent();
    await state.grantDocumentConsent();
    final uploaded = await state.uploadDocument(type: DocumentType.governmentId, imageBytes: [1, 2, 3]);
    await state.hideDocument(DocumentType.birthCertificate);
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 400)); // build, show the message, animate it in
    }

    expect(uploaded, isNull);
    expect(state.hiddenDocuments, isEmpty);
    expect(api.routes.where((r) => r.startsWith('POST') || r.startsWith('PUT') || r.startsWith('DELETE')), isEmpty,
        reason: 'nothing may be written while previewing: ${api.routes}');
    expect(find.textContaining("You're previewing the app"), findsOneWidget, reason: 'the person is told why');
  });

  _withApi('the same actions work normally on the admin\'s own view', (tester, api) async {
    final state = await _pump(tester, api, 'admin');
    api.routes.clear();
    await state.grantConsent();
    expect(api.routes, contains('POST /api/consent'));
    expect(state.previewNotice, isNull);
  });

  _withApi('signing out or stepping down from admin ends the preview', (tester, api) async {
    final state = await _pump(tester, api, 'admin');
    await _pick(tester, AppView.participant);
    expect(state.isPreviewing, isTrue);

    final error = await state.changeAccountType(PersonType.volunteer, staffCode: FakeApi.staffCode);
    expect(error, isNull);
    expect(state.previewView, isNull);
    expect(state.currentView, AppView.volunteer);

    state.user = User.fromJson({...api.user, 'personType': 'admin', 'isStaff': true});
    state.viewAs(AppView.participant);
    await state.signOut();
    expect(state.previewView, isNull);
    expect(state.previewNotice, isNull);
  });
}

TabNav nav(WidgetTester tester) => Provider.of<TabNav>(tester.element(find.byType(MainTabView)), listen: false);
