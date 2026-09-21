import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens web links and phone calls. Kept in one place so a failure (no
/// browser, no phone app) always ends with a plain message instead of nothing.
class Launch {
  Launch._();

  /// Lets tests see what would have been opened without leaving the app.
  @visibleForTesting
  static Future<bool> Function(Uri uri)? debugOverride;

  static Future<bool> _open(Uri uri) {
    final override = debugOverride;
    if (override != null) return override(uri);
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static Future<void> link(BuildContext context, String url) async {
    final messenger = ScaffoldMessenger.of(context);
    var ok = false;
    try {
      ok = await _open(Uri.parse(url));
    } catch (_) {}
    if (!ok) {
      messenger.showSnackBar(SnackBar(content: Text("Couldn't open that page. The address is $url")));
    }
  }

  /// A map link to get somewhere: Apple Maps on iPhones, Google Maps elsewhere.
  static String directionsUrl(double lat, double lng) => defaultTargetPlatform == TargetPlatform.iOS
      ? 'https://maps.apple.com/?daddr=$lat,$lng&dirflg=d'
      : 'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng';

  static Future<void> call(BuildContext context, String dial, String display) async {
    final messenger = ScaffoldMessenger.of(context);
    var ok = false;
    try {
      ok = await _open(Uri(scheme: 'tel', path: dial));
    } catch (_) {}
    if (!ok) {
      messenger.showSnackBar(SnackBar(content: Text("Couldn't start the call. The number is $display")));
    }
  }
}
