import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ground_to_growth_connect/app_state.dart';
import 'package:ground_to_growth_connect/models/models.dart';
import 'package:ground_to_growth_connect/nav.dart';
import 'package:ground_to_growth_connect/views/home_view.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'support/fake_api.dart';

RegisterRequest _request({String type = 'homeless', String? code}) =>
    RegisterRequest(name: 'Jane Doe', personType: type, staffCode: code);

Future<AppState> _registerWith(MockClient client, {RegisterRequest? request}) async {
  FlutterSecureStorage.setMockInitialValues({});
  final state = AppState();
  await http.runWithClient(() => state.register(request ?? _request()), () => client);
  return state;
}

http.Response _json(Object body, int status) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

void main() {
  group('error messages people can actually read', () {
    test('no signal reads as a plain sentence, not a stack of technical words', () async {
      final state = await _registerWith(MockClient((_) async => throw const SocketException('Failed host lookup')));
      expect(state.errorMessage, contains("can't reach Ground to Growth"));
      expect(state.errorMessage, isNot(contains('Socket')));
      expect(state.errorMessage, isNot(contains('Network error')));
      expect(state.showWelcome, isFalse);
    });

    test('a wrong staff code says so kindly', () async {
      final state = await _registerWith(
        MockClient((_) async => _json({'error': 'A valid staff invite code is required for staff accounts.'}, 403)),
        request: _request(type: 'admin', code: 'nope'),
      );
      expect(state.errorMessage, contains("staff code doesn't look right"));
    });

    test('a server crash is not shown as "Internal server error"', () async {
      final state = await _registerWith(MockClient((_) async => _json({'error': 'Internal server error'}, 500)));
      expect(state.errorMessage, contains('Something went wrong on our end'));
    });

    test('an ordinary, already-readable server message is kept as is', () async {
      final state = await _registerWith(MockClient((_) async => _json({'error': 'Please slow down.'}, 429)));
      expect(state.errorMessage, 'Please slow down.');
    });
  });

  group('welcome moment', () {
    test('creating an account turns the welcome on; signing out clears it', () async {
      final user = {'id': 'u1', 'personType': 'homeless', 'name': 'Jane Doe', 'isStaff': false, 'hasProfilePicture': false};
      final client = MockClient((request) async {
        if (request.url.path == '/api/users') return _json({'user': user, 'token': 'tok'}, 201);
        return _json({'error': 'no'}, 404);
      });
      final state = await _registerWith(client);
      expect(state.isSignedIn, isTrue);
      expect(state.showWelcome, isTrue);

      await state.signOut();
      expect(state.showWelcome, isFalse);
    });

    testWidgets('Home greets a new person by name, and "Let\'s go" dismisses it', (tester) async {
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      final api = FakeApi();
      await http.runWithClient(() async {
        FlutterSecureStorage.setMockInitialValues({'auth_token': 'tok'});
        final state = AppState()
          ..user = User.fromJson(api.user)
          ..isUnlocked = true
          ..showWelcome = true;
        await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: state),
            ChangeNotifierProvider(create: (_) => TabNav()),
          ],
          child: const MaterialApp(home: HomeView()),
        ));
        await tester.pump(const Duration(seconds: 1));

        expect(find.byKey(const Key('welcome-card')), findsOneWidget);
        expect(find.text('Welcome, Jane!'), findsOneWidget);

        await tester.tap(find.byKey(const Key('welcome-dismiss')));
        await tester.pump(const Duration(seconds: 3)); // let the confetti finish
        expect(find.byKey(const Key('welcome-card')), findsNothing);
        expect(state.showWelcome, isFalse);
      }, () => api.client);
    });
  });
}
