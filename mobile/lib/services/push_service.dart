import 'dart:async';

import 'package:flutter/services.dart';

/// What the phone said when asked to register for notifications.
class PushRegistration {
  /// authorized | denied | notDetermined | failed | unavailable
  final String status;
  final String? token;
  const PushRegistration(this.status, [this.token]);
}

/// The Dart end of the iPhone's notification support (see AppDelegate.swift).
/// If there's no native side (tests, Android), every call quietly says
/// "unavailable" rather than failing.
class PushService {
  static const _channel = MethodChannel('g2g/push');

  void Function(Map<String, String> data)? _onTap;

  PushService() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onTap') _onTap?.call(_strings(call.arguments));
      return null;
    });
  }

  static Map<String, String> _strings(Object? raw) =>
      raw is Map ? {for (final e in raw.entries) '${e.key}': '${e.value}'} : <String, String>{};

  /// Called when someone taps a notification while the app is running.
  void listenForTaps(void Function(Map<String, String> data) onTap) => _onTap = onTap;

  /// The notification that opened the app, if it was closed when tapped.
  Future<Map<String, String>?> takeLaunchTap() async {
    try {
      final raw = await _channel.invokeMethod<Object?>('takeLaunchTap');
      return raw == null ? null : _strings(raw);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// With [ask] false this never shows the system prompt: it only registers if
  /// the person already said yes. With [ask] true it asks first.
  Future<PushRegistration> register({required bool ask}) async {
    try {
      final raw = await _channel
          .invokeMethod<Object?>('register', {'ask': ask})
          .timeout(const Duration(seconds: 20));
      final map = _strings(raw);
      return PushRegistration(map['status'] ?? 'failed', map['token']);
    } on MissingPluginException {
      return const PushRegistration('unavailable');
    } on PlatformException {
      return const PushRegistration('failed');
    } on TimeoutException {
      return const PushRegistration('failed');
    }
  }

  Future<void> setBadge(int count) async {
    try {
      await _channel.invokeMethod<void>('setBadge', {'count': count});
    } on MissingPluginException {
      // No native side here.
    } on PlatformException {
      // A badge isn't worth failing over.
    }
  }

  Future<void> openSettings() async {
    try {
      await _channel.invokeMethod<void>('openSettings');
    } on MissingPluginException {
      // No native side here.
    }
  }
}
