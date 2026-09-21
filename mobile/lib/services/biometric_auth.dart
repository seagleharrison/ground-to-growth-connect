import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

/// Direct equivalent of the native app's BiometricAuth.swift: Face ID/Touch
/// ID with passcode fallback (not biometrics-only), so a device without
/// biometrics enrolled still has a way in via passcode.
class BiometricAuth {
  BiometricAuth._();
  static final _auth = LocalAuthentication();

  /// Lets automated tests stand in for the real Face ID / passcode prompt,
  /// which needs a device. Always null in the shipped app.
  @visibleForTesting
  static Future<bool> Function(String reason)? debugOverride;

  static Future<bool> authenticate(String reason) async {
    final override = debugOverride;
    if (override != null) return override(reason);

    try {
      final canCheck = await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
      if (!canCheck) {
        // Device has neither biometrics nor a passcode set up at all —
        // there is nothing to gate with, so don't lock the user out.
        return true;
      }
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(biometricOnly: false, stickyAuth: true),
      );
    } catch (_) {
      return false;
    }
  }
}
