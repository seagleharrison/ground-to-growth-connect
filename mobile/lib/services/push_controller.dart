import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'push_service.dart';
import 'secure_storage_service.dart';

enum PushStatus { unknown, unavailable, notDetermined, denied, enabled }

/// Notifications for this phone: whether they're on, asking at a good moment,
/// telling the server which phone to alert, and turning a tapped notification
/// into "open this screen".
///
/// Alerts never carry message text or names (a lock screen can be read by
/// anyone nearby); they only say that something needs attention.
class PushController extends ChangeNotifier {
  final PushService service;
  PushController({PushService? service}) : service = service ?? PushService();

  PushStatus status = PushStatus.unknown;
  String? _token;
  bool _promptDismissed = false;
  bool _started = false;

  /// What the person tapped, waiting for the screen to open it.
  Map<String, String>? pendingTap;

  /// How long "Not now" keeps the offer away.
  static const dismissFor = Duration(days: 7);

  /// Debug builds register with Apple's sandbox, TestFlight and App Store
  /// builds with production.
  static String get environment => kReleaseMode ? 'production' : 'sandbox';

  /// Show the "turn on notifications" offer.
  bool get shouldOffer => status == PushStatus.notDetermined && !_promptDismissed;

  /// Starts listening for taps and, if the person already allowed
  /// notifications, quietly registers this phone. Never shows the system prompt.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    service.listenForTaps(_onTap);
    final launch = await service.takeLaunchTap();
    if (launch != null && launch.isNotEmpty) _onTap(launch);

    final dismissedAt = await SecureStorageService.loadPushPromptDismissedAt();
    _promptDismissed = dismissedAt != null && DateTime.now().difference(dismissedAt) < dismissFor;
    await refresh(ask: false);
  }

  void _onTap(Map<String, String> data) {
    pendingTap = data;
    notifyListeners();
  }

  Map<String, String>? takeTap() {
    final tap = pendingTap;
    pendingTap = null;
    return tap;
  }

  /// [ask] true shows Apple's permission prompt if it hasn't been answered.
  Future<void> refresh({required bool ask}) async {
    final result = await service.register(ask: ask);
    switch (result.status) {
      case 'authorized':
        status = PushStatus.enabled;
        final token = result.token;
        if (token != null) {
          _token = token;
          try {
            await ApiClient.shared.registerPushToken(token, environment);
          } catch (_) {
            // Try again next time the app opens.
          }
        }
      case 'denied':
        status = PushStatus.denied;
      case 'notDetermined':
        status = PushStatus.notDetermined;
      default:
        status = PushStatus.unavailable;
    }
    notifyListeners();
  }

  /// The person tapped "Turn on".
  Future<void> enable() => refresh(ask: true);

  Future<void> dismissPrompt() async {
    _promptDismissed = true;
    notifyListeners();
    await SecureStorageService.savePushPromptDismissedAt(DateTime.now());
  }

  Future<void> openSettings() => service.openSettings();

  Future<void> setBadge(int count) => service.setBadge(count);

  /// On sign-out: stop alerts for this phone *before* the session is cleared,
  /// so the next person who signs in on it isn't sent the last person's alerts.
  Future<void> unregister() async {
    final token = _token;
    if (token != null) {
      try {
        await ApiClient.shared.unregisterPushToken(token);
      } catch (_) {}
    }
    // Sign-out never waits on the phone just to clear the badge.
    unawaited(service.setBadge(0));
  }

  void clearPrivate() {
    _token = null;
    _started = false;
    pendingTap = null;
    status = PushStatus.unknown;
    notifyListeners();
  }
}
