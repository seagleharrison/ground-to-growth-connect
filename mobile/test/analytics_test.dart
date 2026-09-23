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

Future<AppState> _pumpApp(
  WidgetTester tester,
  FakeApi api,
  String personType,
) async {
  tester.view.physicalSize = const Size(1200, 4200);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  FlutterSecureStorage.setMockInitialValues({'auth_token': 'tok'});
  api.user['personType'] = personType;
  api.user['isStaff'] = personType != 'homeless';
  final state = AppState()
    ..user = User.fromJson(api.user)
    ..isUnlocked = true;
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: state),
        ChangeNotifierProvider(create: (_) => TabNav(current: AppTab.map)),
      ],
      child: const MaterialApp(home: MainTabView()),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
  return state;
}

void _withFakeApi(
  String description,
  Future<void> Function(WidgetTester tester, FakeApi api) body,
) {
  testWidgets(description, (tester) async {
    final api = FakeApi();
    await http.runWithClient(() => body(tester, api), () => api.client);
  });
}

void main() {
  for (final role in ['homeless', 'volunteer']) {
    _withFakeApi(
      '$role accounts have no Analytics tab and never ask for the numbers',
      (tester, api) async {
        await _pumpApp(tester, api, role);
        expect(find.text('Analytics'), findsNothing);
        expect(api.analyticsRequests, 0);
      },
    );
  }

  _withFakeApi('an admin gets an Analytics tab with the totals', (
    tester,
    api,
  ) async {
    await _pumpApp(tester, api, 'admin');
    expect(find.text('Analytics'), findsOneWidget, reason: 'the tab label');

    await tester.tap(find.text('Analytics'));
    await tester.pump(const Duration(seconds: 2));

    expect(api.analyticsRequests, greaterThan(0));
    expect(find.text('People we serve'), findsOneWidget);
    expect(find.text('40'), findsOneWidget);
    expect(find.text('7'), findsOneWidget, reason: '5 volunteers + 2 admins');
    expect(
      find.text('30 of 40'),
      findsOneWidget,
      reason: 'participants sharing',
    );
    expect(
      find.text('9 of 40'),
      findsOneWidget,
      reason: 'all three documents on file',
    );
    expect(find.textContaining('61 documents stored'), findsOneWidget);
    expect(
      find.text(
        'Only admins can see this page. It shows totals only — never names, locations or documents.',
      ),
      findsOneWidget,
    );
  });

  _withFakeApi(
    'stepping down from admin removes the tab and the cached numbers',
    (tester, api) async {
      final state = await _pumpApp(tester, api, 'admin');
      await tester.tap(find.text('Analytics'));
      await tester.pump(const Duration(seconds: 2));
      expect(state.analytics, isNotNull);

      final error = await state.changeAccountType(
        PersonType.volunteer,
        staffCode: FakeApi.staffCode,
      );
      await tester.pump(const Duration(seconds: 1));

      expect(error, isNull);
      expect(
        state.analytics,
        isNull,
        reason: 'admin-only data must not linger',
      );
      expect(find.text('Analytics'), findsNothing);
    },
  );

  _withFakeApi('a failed load shows a plain message and a retry button', (
    tester,
    api,
  ) async {
    api.failAnalytics = true;
    final state = await _pumpApp(tester, api, 'admin');
    await tester.tap(find.text('Analytics'));
    await tester.pump(const Duration(seconds: 2));

    expect(state.analytics, isNull);
    expect(find.byKey(const Key('analytics-error')), findsOneWidget);
    expect(
      find.textContaining('Something went wrong on our end'),
      findsOneWidget,
      reason: 'plain words, not "Internal server error"',
    );

    api.failAnalytics = false;
    await tester.tap(find.text('Try again'));
    await tester.pump(const Duration(seconds: 2));
    expect(
      state.analytics,
      isNotNull,
      reason: 'Try again recovers once the server answers',
    );
    expect(find.byKey(const Key('analytics-error')), findsNothing);
  });

  _withFakeApi(
    'an admin is told which official pages changed, and can mark one as still right',
    (tester, api) async {
      api.flaggedSources = [
        {
          'url': 'https://dds.georgia.gov/how-do-i-id-card',
          'status': 200,
          'reason': "The page's wording changed since it was last reviewed. Check that our guide still matches.",
        },
        {
          'url': 'https://www.ssa.gov/locator',
          'status': 404,
          'reason': 'Page returned an error (HTTP 404). It may have moved or been taken down.',
        },
      ];
      final state = await _pumpApp(tester, api, 'admin');
      await tester.tap(find.text('Analytics'));
      await tester.pump(const Duration(seconds: 2));

      await tester.scrollUntilVisible(
        find.byKey(const Key('sources-card')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('2 of 12 official pages need a look.'), findsOneWidget);
      expect(find.text('dds.georgia.gov'), findsOneWidget);
      expect(find.textContaining('wording changed'), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(
          const Key('reviewed-https://dds.georgia.gov/how-do-i-id-card'),
        ),
      );
      await tester.tap(
        find.byKey(
          const Key('reviewed-https://dds.georgia.gov/how-do-i-id-card'),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(find.text('1 of 12 official pages need a look.'), findsOneWidget);
      expect(
        state.sourceReport!.needsAttention.single.url,
        'https://www.ssa.gov/locator',
      );

      await tester.ensureVisible(
        find.byKey(const Key('reviewed-https://www.ssa.gov/locator')),
      );
      await tester.tap(
        find.byKey(const Key('reviewed-https://www.ssa.gov/locator')),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(find.textContaining('All 12 official pages'), findsOneWidget);
    },
  );

  _withFakeApi(
    'pages that refuse automatic checks are listed calmly, not counted as problems',
    (tester, api) async {
      api.flaggedSources = [];
      api.blockedSources = [
        {
          'url': 'https://www.ssa.gov/locator',
          'status': 403,
          'reason': 'This website turns away automatic checks (HTTP 403).',
        },
        {
          'url': 'https://www.ssa.gov/myaccount',
          'status': 403,
          'reason': 'This website turns away automatic checks (HTTP 403).',
        },
      ];
      await _pumpApp(tester, api, 'admin');
      await tester.tap(find.text('Analytics'));
      await tester.pump(const Duration(seconds: 2));

      await tester.scrollUntilVisible(
        find.byKey(const Key('sources-card')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.textContaining('All 12 official pages'),
        findsOneWidget,
        reason: 'nothing is actually wrong',
      );
      expect(find.byKey(const Key('cannot-check-summary')), findsOneWidget);
      expect(
        find.textContaining('2 websites turn away automatic checks'),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('open-blocked-https://www.ssa.gov/locator')),
        findsOneWidget,
      );
    },
  );

  _withFakeApi('a participant or non-admin never sees the page-watch list', (
    tester,
    api,
  ) async {
    await _pumpApp(tester, api, 'volunteer');
    expect(find.byKey(const Key('sources-card')), findsNothing);
  });
}
