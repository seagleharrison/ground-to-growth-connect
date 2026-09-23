import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../models/models.dart';
import 'api_client.dart';
import 'secure_storage_service.dart';

/// Direct equivalent of the native app's LocationTracker.swift: reports an
/// approximate location every 15 minutes while consent is granted, using
/// geolocator's position stream instead of CLLocationManager directly.
class LocationTracker extends ChangeNotifier {
  static const reportInterval = Duration(minutes: 15);

  bool isTracking = false;
  DateTime? lastReportAt;
  String? lastError;
  LocationPermission authorizationStatus = LocationPermission.denied;

  /// True once iOS/Android has refused permission outright (rather than just
  /// not having been asked yet). On iOS especially, the system only shows its
  /// own permission dialog the first time; asking again silently does
  /// nothing, so the only way forward from here is the Settings app —
  /// [openSettings] takes them straight there instead of just saying so.
  bool permissionBlocked = false;

  /// Lets tests stand in for the real "open Settings" action, which needs a device.
  @visibleForTesting
  static Future<bool> Function()? debugOpenSettings;

  Future<void> openSettings() async {
    final override = debugOpenSettings;
    if (override != null) {
      await override();
      return;
    }
    await Geolocator.openAppSettings();
  }

  bool _consentGranted = false;
  DateTime? _lastSentAt;
  bool _pendingReport = false;
  StreamSubscription<Position>? _positionSub;

  Future<void> updateConsent({required bool granted}) async {
    _consentGranted = granted;
    if (granted) {
      await _startIfAuthorized();
    } else {
      _stopTracking();
    }
  }

  Future<void> requestPermission() async {
    authorizationStatus = await Geolocator.requestPermission();
    notifyListeners();
  }

  Future<void> _startIfAuthorized() async {
    if (!_consentGranted) {
      _stopTracking();
      return;
    }

    if (!await Geolocator.isLocationServiceEnabled()) {
      lastError = 'Location services are turned off on this phone. Turn them on in Settings to share your location.';
      permissionBlocked = true;
      notifyListeners();
      return;
    }

    // "denied" here means not yet asked (or restricted by the device); only
    // that case is worth asking about — the OS shows its own dialog once,
    // ever, and a real refusal comes back as deniedForever, not denied again.
    var status = await Geolocator.checkPermission();
    if (status == LocationPermission.denied) {
      status = await Geolocator.requestPermission();
    }
    authorizationStatus = status;

    switch (status) {
      case LocationPermission.always:
      case LocationPermission.whileInUse:
        permissionBlocked = false;
        _beginUpdates();
      case LocationPermission.denied:
      case LocationPermission.deniedForever:
        _stopTracking();
        // Asking again from here on would do nothing (deniedForever is a real
        // refusal; a lingering denied means the device itself restricts it) —
        // either way, Settings is the only path left.
        permissionBlocked = true;
        lastError = "Location permission was turned off for this app. Turn it back on in your phone's Settings to keep sharing your location.";
      case LocationPermission.unableToDetermine:
        break;
    }
    notifyListeners();
  }

  void _beginUpdates() {
    isTracking = true;
    lastError = null;
    _positionSub?.cancel();
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: 100,
      ),
    ).listen(
      (position) => _reportIfNeeded(position),
      onError: (Object e) {
        // Permission can be pulled out from under an already-running session
        // (e.g. turned off in Settings mid-day) — this is what actually
        // happened in the field: iOS's own "kCLErrorDomain error 1" surfaced
        // here as a PermissionDeniedException, not through the checks above.
        if (e is PermissionDeniedException) permissionBlocked = true;
        lastError = friendlyLocationError(e);
        notifyListeners();
      },
    );
    Geolocator.getCurrentPosition().then((p) => _reportIfNeeded(p, force: _lastSentAt == null));
    notifyListeners();
  }

  void _stopTracking() {
    _positionSub?.cancel();
    _positionSub = null;
    isTracking = false;
    notifyListeners();
  }

  Future<void> _reportIfNeeded(Position position, {bool force = false}) async {
    if (!_consentGranted) return;
    if (await SecureStorageService.loadToken() == null) return;

    final now = DateTime.now();
    if (!force && _lastSentAt != null && now.difference(_lastSentAt!) < reportInterval - const Duration(seconds: 5)) {
      return;
    }
    if (_pendingReport) return;

    final previousSentAt = _lastSentAt;
    _pendingReport = true;
    _lastSentAt = now;

    final payload = LocationReportPayload(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyMeters: position.accuracy >= 0 ? position.accuracy : null,
      reportedAt: now.toUtc().toIso8601String(),
    );

    try {
      final report = await ApiClient.shared.postLocation(payload);
      lastReportAt = DateTime.tryParse(report.reportedAt) ?? now;
      lastError = null;
    } catch (e) {
      // Roll back so the next update can retry this interval.
      _lastSentAt = previousSentAt;
      lastError = e is GgcException ? e.message : friendlyLocationError(e);
    } finally {
      _pendingReport = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    super.dispose();
  }
}

/// Turns whatever the location plugin throws into something a person would
/// want to read. The plugin's own exceptions sometimes carry the raw text an
/// iPhone or Android gives it (e.g. "kCLErrorDomain error 1"), which means
/// nothing to someone who isn't a developer — this replaces it outright
/// rather than showing it.
String friendlyLocationError(Object e) {
  if (e is LocationServiceDisabledException) {
    return 'Location services are turned off on this phone. Turn them on in Settings to share your location.';
  }
  if (e is PermissionDeniedException) {
    return "Location permission was turned off for this app. Turn it back on in your phone's Settings to keep sharing your location.";
  }
  return "Couldn't get your location just now. We'll keep trying.";
}
