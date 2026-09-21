import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../data/help_content.dart';
import '../util/journey.dart' show haversineMeters;
import 'api_client.dart';
import 'secure_storage_service.dart';

/// Where the person's location stands for the "near you" list.
enum NearbyStatus { unknown, needsPermission, denied, ready, unavailable }

/// A gentle heads-up when the person isn't where the local places are.
enum RegionNotice { none, outsideGeorgia, farFromSavannah }

class NearbyPlace {
  final HelpPlace place;
  final double? distanceMeters; // null until we know where the person is
  const NearbyPlace(this.place, this.distanceMeters);
}

/// Keeps the Resources tab current, and works out what's near the person.
///
/// * Content comes from the server each time the tab is opened (a cheap "any
///   news?" check), is remembered for offline use, and falls back to the copy
///   bundled in the app.
/// * Location stays on the phone: it is used to sort places by distance and
///   is never sent anywhere.
class ResourcesController extends ChangeNotifier {
  HelpContent? content;
  bool isRefreshing = false;

  /// True when the last attempt to reach the server failed and we're showing
  /// the copy we already had.
  bool offline = false;
  DateTime? lastCheckedAt;
  String? _etag;
  Future<void>? _loading;

  NearbyStatus nearbyStatus = NearbyStatus.unknown;
  LatLng? position;

  /// Lets tests supply a position (or none) instead of asking the phone.
  @visibleForTesting
  static Future<({NearbyStatus status, LatLng? position})> Function({required bool ask})? debugLocator;

  /// Georgia, roughly. Used only to say "these places are in Georgia".
  static const _georgiaSouth = 30.35, _georgiaNorth = 35.0, _georgiaWest = -85.61, _georgiaEast = -80.84;
  static const farFromPlacesMeters = 80000.0;

  static const staleAfter = Duration(minutes: 15);

  /// Tests use this to start from known content without reading assets from disk.
  @visibleForTesting
  void debugPreload(HelpContent preloaded) {
    content = preloaded;
    _loading = Future.value();
  }

  /// Loads what we already have: the last copy from the server, or the bundled one.
  Future<void> ensureLoaded() => _loading ??= _loadLocal();

  Future<void> _loadLocal() async {
    try {
      final cached = await SecureStorageService.loadResourcesCache();
      if (cached != null) {
        content = HelpContent.fromRaw(cached.json);
        _etag = cached.etag;
      }
    } catch (_) {
      content = null; // a damaged cache is just ignored
      _etag = null;
    }
    if (content == null) {
      try {
        content = await HelpContent.loadBundled();
      } catch (_) {}
    }
    notifyListeners();
  }

  /// Asks the server whether the content changed and, if so, takes the new copy.
  Future<void> refresh() async {
    if (isRefreshing) return;
    isRefreshing = true;
    notifyListeners();
    try {
      await ensureLoaded();
      final result = await ApiClient.shared.fetchResources(etag: _etag);
      if (result.status == 200 && result.body != null) {
        // Parse before keeping it: a bad response must never replace good content.
        final fresh = HelpContent.fromRaw(result.body!);
        content = fresh;
        _etag = result.etag;
        await SecureStorageService.saveResourcesCache(json: result.body!, etag: result.etag);
        offline = false;
        lastCheckedAt = DateTime.now();
      } else if (result.status == 304) {
        offline = false;
        lastCheckedAt = DateTime.now();
      } else {
        offline = true;
      }
    } catch (_) {
      offline = true;
    }
    isRefreshing = false;
    notifyListeners();
  }

  /// Called when the app comes back to the front: re-check if it's been a while.
  Future<void> refreshIfStale() async {
    final last = lastCheckedAt;
    if (last == null || DateTime.now().difference(last) > staleAfter) await refresh();
  }

  /// Works out where the person is so places can be sorted by distance. With
  /// [ask] false it only uses location the person has already allowed, so
  /// opening the tab never triggers a surprise permission prompt.
  Future<void> locate({bool ask = false}) async {
    final override = debugLocator;
    if (override != null) {
      final r = await override(ask: ask);
      nearbyStatus = r.status;
      position = r.position;
      notifyListeners();
      return;
    }
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && ask) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.deniedForever) {
        nearbyStatus = NearbyStatus.denied;
      } else if (permission == LocationPermission.denied) {
        nearbyStatus = ask ? NearbyStatus.denied : NearbyStatus.needsPermission;
      } else {
        final p = await Geolocator.getLastKnownPosition() ??
            await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 10)),
            );
        position = LatLng(p.latitude, p.longitude);
        nearbyStatus = NearbyStatus.ready;
      }
    } catch (_) {
      nearbyStatus = NearbyStatus.unavailable;
    }
    notifyListeners();
  }

  /// The places, nearest first when we know where the person is.
  List<NearbyPlace> get nearby {
    final places = content?.places ?? const <HelpPlace>[];
    final here = position;
    if (here == null) return [for (final p in places) NearbyPlace(p, null)];
    final withDistance = [
      for (final p in places) NearbyPlace(p, haversineMeters(here, LatLng(p.lat, p.lng))),
    ]..sort((a, b) => a.distanceMeters!.compareTo(b.distanceMeters!));
    return withDistance;
  }

  RegionNotice get regionNotice {
    final here = position;
    final places = nearby;
    if (here == null || places.isEmpty) return RegionNotice.none;
    final inGeorgia = here.latitude >= _georgiaSouth &&
        here.latitude <= _georgiaNorth &&
        here.longitude >= _georgiaWest &&
        here.longitude <= _georgiaEast;
    if (!inGeorgia) return RegionNotice.outsideGeorgia;
    if (places.first.distanceMeters! > farFromPlacesMeters) return RegionNotice.farFromSavannah;
    return RegionNotice.none;
  }
}
