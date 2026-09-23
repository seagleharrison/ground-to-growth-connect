import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ground_to_growth_connect/app_state.dart';
import 'package:ground_to_growth_connect/data/help_content.dart';
import 'package:ground_to_growth_connect/models/models.dart';
import 'package:ground_to_growth_connect/nav.dart';
import 'package:ground_to_growth_connect/services/resources_controller.dart';
import 'package:ground_to_growth_connect/util/launch.dart';
import 'package:ground_to_growth_connect/views/main_tab_view.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import 'support/fake_api.dart';

final _bundledRaw = File('assets/resources.json').readAsStringSync();

const _ddsLocation = LatLng(32.0053, -81.0998); // at the Savannah DDS office
const _atlanta = LatLng(33.749, -84.388);
const _miami = LatLng(25.7617, -80.1918);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the content itself', () {
    late HelpContent content;
    setUpAll(() => content = HelpContent.fromRaw(_bundledRaw));

    test('the copy bundled in the app is identical to the one the server serves', () {
      final server = File('../backend/internal/content/resources.json').readAsStringSync();
      expect(_bundledRaw, server, reason: 'copy backend/internal/content/resources.json to mobile/assets/ after every edit');
    });

    test('every topic has a summary, real steps, and a unique id', () {
      final all = [...content.documentGuides, ...content.benefitPrograms];
      expect({for (final t in all) t.id}.length, all.length, reason: 'ids must be unique');
      for (final t in all) {
        expect(t.title, isNotEmpty);
        expect(t.summary, isNotEmpty, reason: t.id);
        expect(t.sections, isNotEmpty, reason: t.id);
        for (final s in t.sections) {
          expect(s.items, isNotEmpty, reason: '${t.id}/${s.heading}');
        }
      }
    });

    test('every link is a secure web address and every phone number is dialable', () {
      for (final t in [...content.documentGuides, ...content.benefitPrograms]) {
        for (final l in t.links) {
          expect(Uri.parse(l.url).scheme, 'https', reason: '${t.id}: ${l.url}');
        }
        for (final p in t.phones) {
          expect(p.dial, matches(RegExp(r'^\d{3,11}$')), reason: '${t.id}: ${p.display}');
        }
      }
      for (final p in content.places) {
        expect(p.phone.dial, matches(RegExp(r'^\d{10}$')), reason: p.name);
        expect(Uri.parse(p.url).scheme, 'https');
      }
    });

    test('the three core documents each have a replacement guide that leads back to the vault', () {
      for (final type in DocumentType.coreChecklist) {
        expect(content.documentGuides.where((g) => g.relatedDocument == type), hasLength(1), reason: type.label);
      }
    });

    test('the guides come in the order that works: birth certificate, then Social Security card, then ID', () {
      final ids = [for (final g in content.documentGuides) g.id];
      expect(ids.indexOf('birth-certificate'), lessThan(ids.indexOf('social-security-card')));
      expect(ids.indexOf('social-security-card'), lessThan(ids.indexOf('photo-id')));
    });

    test('the emergency numbers are built in and never depend on the server', () {
      expect(emergencyPhone.dial, '911');
      expect(crisisPhone.dial, '988');
      expect(localHelpPhone.dial, '211');
    });

    test('places sit in the Savannah area', () {
      expect(content.places, isNotEmpty);
      for (final p in content.places) {
        expect(p.lat, inInclusiveRange(31.8, 32.3), reason: p.name);
        expect(p.lng, inInclusiveRange(-81.4, -80.8), reason: p.name);
      }
    });

    test('a response that is not the expected shape is rejected instead of half-read', () {
      expect(() => HelpContent.fromRaw('[]'), throwsFormatException);
      expect(() => HelpContent.fromRaw('not json'), throwsFormatException);
      expect(() => HelpContent.fromRaw('{"updatedAt":"x"}'), throwsA(anything));
    });
  });

  group('keeping it current', () {
    Future<T> withApi<T>(FakeApi api, Future<T> Function() body) => http.runWithClient(body, () => api.client);

    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      ResourcesController.debugLocator = null;
    });
    tearDown(() => ResourcesController.debugLocator = null);

    String withUpdatedDate(String date, {String? phone}) {
      final json = jsonDecode(_bundledRaw) as Map<String, dynamic>;
      json['updatedAt'] = date;
      if (phone != null) (json['places'] as List).first['phone'] = {'display': phone, 'dial': '9125550000'};
      return jsonEncode(json);
    }

    test('starts from the bundled copy when there is no saved copy and no signal', () async {
      final api = FakeApi()..failResources = true;
      await withApi(api, () async {
        final r = ResourcesController();
        await r.refresh();
        expect(r.content, isNotNull, reason: 'the bundled copy is always there');
        expect(r.content!.updatedAt, HelpContent.fromRaw(_bundledRaw).updatedAt);
        expect(r.offline, isTrue);
      });
    });

    test('takes newer content from the server, and remembers it for next time', () async {
      final api = FakeApi()..resourcesBody = withUpdatedDate('2026-10-05', phone: '912-555-0000');
      await withApi(api, () async {
        final r = ResourcesController();
        await r.refresh();
        expect(r.content!.updatedAt, '2026-10-05');
        expect(r.content!.places.first.phone.display, '912-555-0000', reason: 'a corrected phone number reaches the app without a new release');
        expect(r.offline, isFalse);
        expect(r.lastCheckedAt, isNotNull);

        // Next launch, with no signal at all, still has the newer copy.
        api.failResources = true;
        final next = ResourcesController();
        await next.refresh();
        expect(next.content!.updatedAt, '2026-10-05');
        expect(next.offline, isTrue);
      });
    });

    test('asks "anything new?" with the copy it has, and an unchanged answer keeps it', () async {
      final api = FakeApi()..resourcesBody = withUpdatedDate('2026-10-05');
      await withApi(api, () async {
        final r = ResourcesController();
        await r.refresh();
        expect(api.lastIfNoneMatch, isNull, reason: 'first ever fetch has nothing to compare');

        await r.refresh();
        expect(api.lastIfNoneMatch, '"v1"');
        expect(r.content!.updatedAt, '2026-10-05');
        expect(r.offline, isFalse);
      });
    });

    test('a damaged response never replaces good content', () async {
      final api = FakeApi()..resourcesBody = '{"this":"is not resources"}';
      await withApi(api, () async {
        final r = ResourcesController();
        await r.refresh();
        expect(r.content!.updatedAt, HelpContent.fromRaw(_bundledRaw).updatedAt);
        expect(r.offline, isTrue);
        expect((await FlutterSecureStorage().read(key: 'resources_json')), isNull, reason: 'garbage must not be saved');
      });
    });

    test('checks again when the app comes back after a while, but not every few seconds', () async {
      final api = FakeApi()..resourcesBody = withUpdatedDate('2026-10-05');
      await withApi(api, () async {
        final r = ResourcesController();
        await r.refreshIfStale();
        expect(api.resourcesRequests, 1);
        await r.refreshIfStale();
        expect(api.resourcesRequests, 1, reason: 'just checked');

        r.lastCheckedAt = DateTime.now().subtract(const Duration(minutes: 20));
        await r.refreshIfStale();
        expect(api.resourcesRequests, 2);
      });
    });
  });

  group('near you', () {
    Future<ResourcesController> controllerAt(LatLng? at, {NearbyStatus status = NearbyStatus.ready}) async {
      ResourcesController.debugLocator = ({required bool ask}) async => (status: status, position: at);
      final r = ResourcesController();
      r.content = HelpContent.fromRaw(_bundledRaw);
      await r.locate();
      return r;
    }

    tearDown(() => ResourcesController.debugLocator = null);

    test('sorts by distance from the phone, nearest first', () async {
      final r = await controllerAt(_ddsLocation);
      final ids = [for (final n in r.nearby) n.place.id];
      expect(ids.first, 'dds-savannah');
      final distances = [for (final n in r.nearby) n.distanceMeters!];
      expect(distances, orderedEquals([...distances]..sort()));
      expect(distances.first, lessThan(500));
      expect(r.regionNotice, RegionNotice.none);
    });

    test('with no location, keeps the original order and shows no distances', () async {
      final r = await controllerAt(null, status: NearbyStatus.needsPermission);
      expect(r.nearby.every((n) => n.distanceMeters == null), isTrue);
      expect(r.nearby.map((n) => n.place.id), r.content!.places.map((p) => p.id));
      expect(r.regionNotice, RegionNotice.none);
    });

    test('elsewhere in Georgia: says the places are in Savannah and how far', () async {
      final r = await controllerAt(_atlanta);
      expect(r.regionNotice, RegionNotice.farFromSavannah);
      expect(r.nearby.first.distanceMeters, greaterThan(300000));
    });

    test('outside Georgia: warns that the state programs may not apply', () async {
      final r = await controllerAt(_miami);
      expect(r.regionNotice, RegionNotice.outsideGeorgia);
    });
  });

  group('the Resources tab', () {
    Future<List<Uri>> pumpApp(
      WidgetTester tester,
      FakeApi api,
      String personType, {
      AppTab start = AppTab.resources,
      LatLng? at,
      NearbyStatus status = NearbyStatus.needsPermission,
    }) async {
      tester.view.physicalSize = const Size(1200, 3600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      FlutterSecureStorage.setMockInitialValues({'auth_token': 'tok'});
      api.user['personType'] = personType;
      api.user['isStaff'] = personType != 'homeless';
      final opened = <Uri>[];
      Launch.debugOverride = (uri) async {
        opened.add(uri);
        return true;
      };
      ResourcesController.debugLocator = ({required bool ask}) async =>
          (status: at != null ? NearbyStatus.ready : (ask ? NearbyStatus.denied : status), position: at);
      addTearDown(() {
        Launch.debugOverride = null;
        ResourcesController.debugLocator = null;
      });
      final state = AppState()
        ..user = User.fromJson(api.user)
        ..isUnlocked = true;
      state.resources.debugPreload(HelpContent.fromRaw(_bundledRaw));
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: state),
          ChangeNotifierProvider(create: (_) => TabNav(current: start)),
        ],
        child: const MaterialApp(home: MainTabView()),
      ));
      // The tab checks the server, which takes a few async hops to land.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      return opened;
    }

    void withApi(String description, Future<void> Function(WidgetTester tester, FakeApi api) body) {
      testWidgets(description, (tester) async {
        final api = FakeApi()..resourcesBody = _bundledRaw;
        await http.runWithClient(() => body(tester, api), () => api.client);
      });
    }

    Future<void> see(WidgetTester tester, Finder f) =>
        tester.scrollUntilVisible(f, 300, scrollable: find.byType(Scrollable).first);

    withApi('participants get a Resources tab with the emergency numbers up top', (tester, api) async {
      await pumpApp(tester, api, 'homeless');
      expect(find.text('Need help right now?'), findsOneWidget);
      expect(find.text('Call 911'), findsOneWidget);
      expect(find.text('Call 988'), findsOneWidget);
      expect(find.byKey(const Key('open-replace-guides')), findsOneWidget);
      expect(find.byKey(const Key('open-benefits')), findsOneWidget);
    });

    for (final role in ['volunteer', 'admin']) {
      withApi('$role accounts do not get the participant Resources tab', (tester, api) async {
        await pumpApp(tester, api, role, start: AppTab.map);
        expect(find.text('Resources'), findsNothing);
        expect(api.resourcesRequests, 0, reason: 'nothing asks for it');
      });
    }

    withApi('opening the tab checks the server, and the screen says how current the info is', (tester, api) async {
      await pumpApp(tester, api, 'homeless');
      expect(api.resourcesRequests, greaterThan(0));
      final text = tester.widget<Text>(find.byKey(const Key('freshness-row'))).data!;
      expect(text, contains('Info updated Sep 21, 2026'));
      expect(text, contains('Checked'));
    });

    withApi('newer content from the server shows up on screen', (tester, api) async {
      final json = jsonDecode(_bundledRaw) as Map<String, dynamic>;
      json['updatedAt'] = '2026-11-02';
      (json['places'] as List).first['note'] = 'Brand new wording from the server.';
      api.resourcesBody = jsonEncode(json);
      await pumpApp(tester, api, 'homeless');
      expect(tester.widget<Text>(find.byKey(const Key('freshness-row'))).data, contains('Nov 2, 2026'));
      await see(tester, find.text('Brand new wording from the server.'));
      expect(find.text('Brand new wording from the server.'), findsOneWidget);
    });

    withApi('with no signal it says so and still shows the saved info', (tester, api) async {
      api.failResources = true;
      await pumpApp(tester, api, 'homeless');
      expect(tester.widget<Text>(find.byKey(const Key('freshness-row'))).data, contains("Can't reach the server"));
      expect(find.byKey(const Key('open-replace-guides')), findsOneWidget);
    });

    withApi('without location it lists the places and offers to use location, with a privacy promise', (tester, api) async {
      await pumpApp(tester, api, 'homeless');
      await see(tester, find.byKey(const Key('location-prompt')));
      expect(find.textContaining('stays on your phone'), findsOneWidget);
      expect(find.byKey(const Key('place-dds-savannah')), findsOneWidget);
      expect(find.byKey(const Key('distance-dds-savannah')), findsNothing);
    });

    withApi('tapping "Use my location" turns it on, and a refusal is explained instead of ignored', (tester, api) async {
      await pumpApp(tester, api, 'homeless');
      await see(tester, find.byKey(const Key('use-my-location')));
      await tester.tap(find.byKey(const Key('use-my-location')));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Location is off'), findsOneWidget);
      expect(find.byKey(const Key('use-my-location')), findsNothing, reason: 'nothing more to ask once it was refused');
    });

    withApi('with location, places show their distance, nearest first', (tester, api) async {
      await pumpApp(tester, api, 'homeless', at: _ddsLocation);
      await see(tester, find.byKey(const Key('place-dds-savannah')));
      expect(find.byKey(const Key('distance-dds-savannah')), findsOneWidget);
      expect(find.byKey(const Key('location-prompt')), findsNothing);
      final first = tester.getTopLeft(find.byKey(const Key('place-dds-savannah'))).dy;
      final other = tester.getTopLeft(find.byKey(const Key('place-va-savannah'))).dy;
      expect(first, lessThan(other), reason: 'the DDS office is the closest, so it comes first');
    });

    withApi('outside Georgia it warns, and offers 211', (tester, api) async {
      await pumpApp(tester, api, 'homeless', at: _miami);
      await see(tester, find.byKey(const Key('region-notice')));
      expect(find.textContaining('outside Georgia'), findsOneWidget);
      expect(find.text('Call 211'), findsOneWidget);
    });

    withApi('a place can be called, and directions open a map to its exact spot', (tester, api) async {
      final opened = await pumpApp(tester, api, 'homeless', at: _ddsLocation);
      Future<void> press(Key key) async {
        await tester.ensureVisible(find.byKey(key));
        await tester.pump();
        await tester.tap(find.byKey(key));
        await tester.pump();
      }

      await press(const Key('call-6784138400'));
      expect(opened.last.toString(), 'tel:6784138400');

      await press(const Key('directions-dds-savannah'));
      expect(opened.last.toString(), allOf(contains('32.0053555'), contains('-81.0998799')));
    });

    withApi('tapping Call 988 dials 988, and Call 911 dials 911', (tester, api) async {
      final opened = await pumpApp(tester, api, 'homeless');
      await tester.tap(find.byKey(const Key('call-988')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('call-911')));
      await tester.pump();
      expect(opened.map((u) => u.toString()), ['tel:988', 'tel:911']);
    });

    withApi('the replace-a-document list opens each guide with steps, cost, links and a way back to the vault', (tester, api) async {
      final opened = await pumpApp(tester, api, 'homeless');
      final content = HelpContent.fromRaw(_bundledRaw);
      await tester.tap(find.byKey(const Key('open-replace-guides')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('guides-order-tip')), findsOneWidget);
      for (final g in content.documentGuides) {
        expect(find.byKey(Key('topic-${g.id}')), findsOneWidget, reason: g.title);
      }

      await tester.tap(find.byKey(const Key('topic-social-security-card')));
      await tester.pumpAndSettle();
      expect(find.text('How to get it'), findsOneWidget);
      expect(find.textContaining('It costs nothing'), findsOneWidget);
      await see(tester, find.text('Call 1-800-772-1213'));

      await see(tester, find.byKey(const Key('link-https://www.ssa.gov/locator')));
      await tester.tap(find.byKey(const Key('link-https://www.ssa.gov/locator')));
      await tester.pump();
      expect(opened.single.toString(), 'https://www.ssa.gov/locator');

      await see(tester, find.byKey(const Key('add-to-vault')));
      await tester.tap(find.byKey(const Key('add-to-vault')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('guides-order-tip')), findsNothing, reason: 'back at the tabs');
      expect(find.text('Your documents'), findsWidgets, reason: 'the Documents tab is showing');
    });

    withApi('the benefits list covers Georgia\'s Medicaid situation and local clinics', (tester, api) async {
      await pumpApp(tester, api, 'homeless');
      final content = HelpContent.fromRaw(_bundledRaw);
      await tester.tap(find.byKey(const Key('open-benefits')));
      await tester.pumpAndSettle();
      for (final p in content.benefitPrograms) {
        await see(tester, find.byKey(Key('topic-${p.id}')));
        expect(find.byKey(Key('topic-${p.id}')), findsOneWidget, reason: p.title);
      }
      await tester.scrollUntilVisible(find.byKey(const Key('topic-medicaid')), -300, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.byKey(const Key('topic-medicaid')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Georgia Pathways to Coverage is for adults 19 to 64'), findsOneWidget);
      expect(find.textContaining('good cause'), findsOneWidget);
    });

    withApi('the Documents tab points to the replacement guides, even if Resources was never opened', (tester, api) async {
      await pumpApp(tester, api, 'homeless', start: AppTab.documents);
      await see(tester, find.byKey(const Key('replace-guides-card')));
      await tester.tap(find.byKey(const Key('replace-guides-card')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('guides-order-tip')), findsOneWidget);
    });
  });
}
