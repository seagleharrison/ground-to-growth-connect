import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ground_to_growth_connect/app_state.dart';
import 'package:ground_to_growth_connect/models/models.dart';
import 'package:ground_to_growth_connect/views/settings_view.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'support/fake_api.dart';

// A real 1x1 PNG, so the avatar can actually decode it.
const _tinyPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

Future<AppState> _pumpSettings(WidgetTester tester, FakeApi api) async {
  FlutterSecureStorage.setMockInitialValues({'auth_token': 'tok'});
  final state = AppState()
    ..user = User.fromJson(api.user)
    ..isUnlocked = true;
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
        theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange, brightness: Brightness.dark)),
        home: const SettingsView(),
      ),
    ),
  );
  await tester.pump();
  return state;
}

Future<void> _openEditor(WidgetTester tester) async {
  await tester.tap(find.text('Edit'));
  await tester.pumpAndSettle();
}

String _fieldText(WidgetTester tester, int index) =>
    tester.widget<TextField>(find.byType(TextField).at(index)).controller!.text;

bool _saveEnabled(WidgetTester tester) =>
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save changes')).onPressed != null;

void _withFakeApi(String description, Future<void> Function(WidgetTester tester, FakeApi api) body) {
  testWidgets(description, (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final api = FakeApi();
    await http.runWithClient(() => body(tester, api), () => api.client);
  });
}

void main() {
  _withFakeApi('Settings shows the profile card, and Edit opens the editor pre-filled', (tester, api) async {
    await _pumpSettings(tester, api);

    expect(find.text('Jane Doe'), findsOneWidget);
    expect(find.text('Person we serve'), findsOneWidget, reason: 'friendly account type, not "homeless"');
    expect(find.text('Female'), findsOneWidget);

    await _openEditor(tester);
    expect(find.text('Edit profile'), findsOneWidget);
    expect(_fieldText(tester, 0), 'Jane Doe');
    expect(_fieldText(tester, 1), 'jane@example.org');
    expect(_fieldText(tester, 2), '912-555-0100');
    expect(find.text('Account type can only be changed by Ground to Growth staff.'), findsOneWidget);
  });

  _withFakeApi('Save stays disabled until something changes, and a blank name is blocked', (tester, api) async {
    await _pumpSettings(tester, api);
    await _openEditor(tester);

    expect(_saveEnabled(tester), isFalse, reason: 'nothing changed yet');

    await tester.enterText(find.byType(TextField).at(0), 'Jane Q. Doe');
    await tester.pump();
    expect(_saveEnabled(tester), isTrue);

    await tester.enterText(find.byType(TextField).at(0), '   ');
    await tester.pump();
    expect(_saveEnabled(tester), isFalse, reason: 'a blank name must not be savable');
    expect(find.text("Your name can't be blank"), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), 'Jane Doe');
    await tester.pump();
    expect(_saveEnabled(tester), isFalse, reason: 'back to the original value means no change');
  });

  _withFakeApi('Editing name, email, phone and gender saves and updates Settings', (tester, api) async {
    final state = await _pumpSettings(tester, api);
    await _openEditor(tester);

    await tester.enterText(find.byType(TextField).at(0), '  Janet Q. Doe ');
    await tester.enterText(find.byType(TextField).at(1), ''); // clear email
    await tester.enterText(find.byType(TextField).at(2), '912-555-0199');
    await tester.tap(find.byType(DropdownButtonFormField<Gender?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Non-binary').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
    await tester.pumpAndSettle();

    expect(api.patchBodies.single, {
      'name': 'Janet Q. Doe',
      'email': '',
      'phone': '912-555-0199',
      'gender': 'nonbinary',
    });

    // Back on Settings, showing the new details and confirming the save.
    expect(find.text('Edit profile'), findsNothing);
    expect(find.text('Profile saved'), findsOneWidget);
    expect(find.text('Janet Q. Doe'), findsOneWidget);
    expect(find.text('912-555-0199'), findsOneWidget);
    expect(find.text('Non-binary'), findsOneWidget);
    expect(find.text('jane@example.org'), findsNothing, reason: 'cleared email should disappear');
    expect(state.user!.name, 'Janet Q. Doe');
  });

  _withFakeApi('Choosing "Not specified" clears the gender on the server', (tester, api) async {
    await _pumpSettings(tester, api);
    await _openEditor(tester);

    await tester.tap(find.byType(DropdownButtonFormField<Gender?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not specified').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
    await tester.pumpAndSettle();

    expect(api.patchBodies.single['gender'], '');
    expect(api.user['gender'], isNull);
    expect(find.text('Female'), findsNothing);
  });

  _withFakeApi('A server error is shown and the editor stays open with the edits intact', (tester, api) async {
    api.failProfileUpdateWith = 'name cannot be empty';
    await _pumpSettings(tester, api);
    await _openEditor(tester);

    await tester.enterText(find.byType(TextField).at(0), 'Someone Else');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
    await tester.pumpAndSettle();

    expect(find.text('Edit profile'), findsOneWidget, reason: 'must not close on failure');
    expect(find.textContaining('name cannot be empty'), findsOneWidget);
    expect(_fieldText(tester, 0), 'Someone Else', reason: "the person's typing must not be lost");
  });

  _withFakeApi('Adding, then removing, a profile picture', (tester, api) async {
    final png = base64Decode(_tinyPng);
    final file = File('${Directory.systemTemp.path}/profile_test_${DateTime.now().microsecondsSinceEpoch}.png');
    await tester.runAsync(() => file.writeAsBytes(png));
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });

    // Stand in for the system photo picker: it hands back the file path.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/image_picker'),
      (call) async => call.method == 'pickImage' ? file.path : null,
    );
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/image_picker'), null));

    final state = await _pumpSettings(tester, api);
    await _openEditor(tester);
    expect(find.text('Add a photo'), findsOneWidget);
    expect(state.profilePictureBytes, isNull);

    await tester.tap(find.text('Add a photo'));
    await tester.pumpAndSettle();
    expect(find.text('Remove photo'), findsNothing, reason: 'nothing to remove yet');
    await tester.tap(find.text('Choose from photos'));
    // Reading the picked file is real disk I/O, which the test clock can't
    // advance, so give it real time and let the app react in between.
    for (var i = 0; i < 20 && api.pictureBase64 == null; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(api.pictureMime, 'image/png');
    expect(base64Decode(api.pictureBase64!), png, reason: 'the exact picture bytes are uploaded');
    expect(state.user!.hasProfilePicture, isTrue);
    expect(state.profilePictureBytes, png);
    expect(find.text('Change photo'), findsOneWidget);

    await tester.tap(find.text('Change photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove photo'));
    await tester.pumpAndSettle();

    expect(api.pictureBase64, isNull);
    expect(state.user!.hasProfilePicture, isFalse);
    expect(state.profilePictureBytes, isNull);
    expect(find.text('Add a photo'), findsOneWidget);
  });
}
