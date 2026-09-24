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

  /// True while sharing works, but only because the app is open or was
  /// recently backgrounded — "While Using" access doesn't wake the app once
  /// it's been locked/backgrounded for a while, so check-ins silently stop.
  /// "Always" access is what makes the 15-minute promise hold when a phone
  /// stays locked for hours (confirmed in the field: a tester's check-ins
  /// ran fine, then stopped for 17+ hours the moment the phone was left
  /// locked).
  bool get canUpgradeToAlways => authorizationStatus == LocationPermission.whileInUse;

  /// Dismissing the "turn on Always" nudge only lasts this app session — it
  /// isn't nagging forever, but it also isn't gone forever, since it matters.
  bool alwaysNudgeDismissed = false;

  void dismissAlwaysNudge() {
    alwaysNudgeDismissed = true;
    notifyListeners();
  }

  /// iOS's separate "Precise Location" toggle — independent of Always/While
  /// Using. Starts as [precise] rather than [reduced] so a fresh tracker
  /// doesn't flash a false nudge before its first real check completes.
  LocationAccuracyStatus accuracyStatus = LocationAccuracyStatus.precise;

  /// True when someone has turned Precise Location off for this app — check-ins
  /// still happen, but each one can be off by a mile or more, which matters a
  /// lot for outreach trying to actually find someone.
  bool get canUpgradeToPrecise => accuracyStatus == LocationAccuracyStatus.reduced;

  bool preciseNudgeDismissed = false;

  void dismissPreciseNudge() {
    preciseNudgeDismissed = true;
    notifyListeners();
  }

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
  Timer? _periodicTimer;

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

  /// Re-checks permission and location-services state without waiting for
  /// consent to be toggled off and back on — needed when someone comes back
  /// from the Settings app, since nothing else notices a change made there.
  Future<void> refreshAuthorizationStatus() => _startIfAuthorized();

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
        accuracyStatus = await Geolocator.getLocationAccuracy();
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
      locationSettings: _platformLocationSettings(),
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

    // Whether or not the device is moving, check in on schedule: this is
    // what makes "every 15 minutes" actually true, not just "every 15
    // minutes if you happen to also be walking around".
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(reportInterval, (_) => _periodicCheckIn());
    notifyListeners();
  }

  Future<void> _periodicCheckIn() async {
    if (!_consentGranted) return;
    try {
      final position = await Geolocator.getCurrentPosition();
      await _reportIfNeeded(position, force: true);
    } catch (e) {
      lastError = friendlyLocationError(e);
      notifyListeners();
    }
  }

  void _stopTracking() {
    _positionSub?.cancel();
    _positionSub = null;
    _periodicTimer?.cancel();
    _periodicTimer = null;
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
    _periodicTimer?.cancel();
    super.dispose();
  }
}

/// The distance filter alone only reports when someone actually moves
/// 100m+, and the periodic timer only fires while the app process is
/// actually alive — on iOS, neither one matters if the OS suspends the app
/// the moment it's backgrounded. `AppleSettings.allowBackgroundLocationUpdates`
/// is what actually keeps it running: without it, even "Always" permission
/// still gets suspended in the background (confirmed the hard way — a
/// tester's check-ins worked once, then stopped for 17+ hours the moment his
/// phone sat locked, because this flag was never being set).
LocationSettings _platformLocationSettings() {
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    return AppleSettings(
      accuracy: LocationAccuracy.medium,
      distanceFilter: 100,
      allowBackgroundLocationUpdates: true,
      // Otherwise iOS pauses updates exactly when someone stops moving —
      // the one case this app most needs to keep reporting through.
      pauseLocationUpdatesAutomatically: false,
      // The honest signal that something is still watching in the
      // background, matching the consent this app already asks for.
      showBackgroundLocationIndicator: true,
    );
  }
  // Android background delivery needs its own foreground-service setup,
  // which hasn't been built yet — plain settings are correct until it is.
  return const LocationSettings(accuracy: LocationAccuracy.medium, distanceFilter: 100);
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
