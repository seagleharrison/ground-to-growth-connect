import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../theme/app_theme.dart';

/// Savannah, GA — where the map starts when there's nothing to show yet.
const savannah = LatLng(32.0809, -81.0912);

/// Turns the (light, colourful) OpenStreetMap tiles into a calm, neutral dark
/// grey map: convert to brightness, invert it, and tint very slightly blue.
/// Land ends up close to the app's own background, water and parks a shade
/// lighter, roads darkest, and labels turn light — a quiet backdrop so the
/// orange and green markers are what the eye finds. (Tinting the original
/// colours instead turned the land brown.)
const _neutralDarkMatrix = <double>[
  -0.1913, -0.6437, -0.0650, 0, 233.5, //
  -0.2020, -0.6794, -0.0686, 0, 247.3,
  -0.2233, -0.7510, -0.0758, 0, 275.8,
  0, 0, 0, 1, 0,
];

Widget naturalDarkTileBuilder(BuildContext context, Widget tile, TileImage image) =>
    ColorFiltered(colorFilter: const ColorFilter.matrix(_neutralDarkMatrix), child: tile);

/// OpenStreetMap tiles, restyled dark so the map matches the rest of the app.
class AppTileLayer extends StatelessWidget {
  const AppTileLayer({super.key});

  @override
  Widget build(BuildContext context) {
    return TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.harrison.groundtogrowth',
      tileBuilder: naturalDarkTileBuilder,
      // Phone screens pack 2-3 pixels into every point, so plain 256px tiles get
      // stretched and look soft. On those screens, load the next zoom level and
      // draw it at half size: street names and outlines stay crisp.
      retinaMode: RetinaMode.isHighDensity(context),
      // Keep a wider ring of tiles loaded so panning doesn't reveal blank squares.
      panBuffer: 2,
    );
  }
}

/// The small credit OpenStreetMap asks for.
class MapCredit extends StatelessWidget {
  const MapCredit({super.key});

  @override
  Widget build(BuildContext context) {
    return const Text('© OpenStreetMap contributors', style: TextStyle(fontSize: 9.5, color: Colors.white38));
  }
}

/// Smooth camera moves ("flying" to a place) instead of jumping there.
mixin AnimatedMapCamera<T extends StatefulWidget> on State<T>, TickerProviderStateMixin<T> {
  MapController get mapController;

  /// Set true from the map's onMapReady; the camera can't be read before that.
  bool mapReady = false;
  AnimationController? _flight;

  void flyTo(LatLng destination, double zoom, {Duration duration = const Duration(milliseconds: 750)}) {
    if (!mapReady) return;
    _flight?.dispose();
    final camera = mapController.camera;
    final lat = Tween(begin: camera.center.latitude, end: destination.latitude);
    final lng = Tween(begin: camera.center.longitude, end: destination.longitude);
    final z = Tween(begin: camera.zoom, end: zoom);
    final controller = AnimationController(vsync: this, duration: duration);
    _flight = controller;
    final curve = CurvedAnimation(parent: controller, curve: Curves.easeInOutCubic);
    controller.addListener(() {
      if (!mounted) return;
      mapController.move(LatLng(lat.evaluate(curve), lng.evaluate(curve)), z.evaluate(curve));
    });
    controller.forward();
  }

  /// Flies to a view that fits every point, with room for overlays.
  void flyToFit(List<LatLng> points, {EdgeInsets padding = const EdgeInsets.all(60), double maxZoom = 16.5}) {
    if (!mapReady || points.isEmpty) return;
    if (points.length == 1) {
      flyTo(points.first, 15.5);
      return;
    }
    final fitted = CameraFit.coordinates(coordinates: points, padding: padding, maxZoom: maxZoom)
        .fit(mapController.camera);
    flyTo(fitted.center, fitted.zoom);
  }

  void disposeCamera() => _flight?.dispose();
}

/// A dot with a soft glow, for path stops and "you are here".
class GlowDot extends StatelessWidget {
  final Color color;
  final double size;
  final Widget? child;
  const GlowDot({super.key, required this.color, this.size = 22, this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.65), blurRadius: 14, spreadRadius: 1)],
      ),
      child: child,
    );
  }
}

/// A person on the staff map: initials in a ring coloured by how recently
/// they were seen, with their name underneath when selected.
class PersonMarker extends StatelessWidget {
  final String name;
  final Color ring;
  final bool selected;
  final bool isStaff;
  final bool isSelf;
  const PersonMarker({super.key, required this.name, required this.ring, required this.selected, this.isStaff = false, this.isSelf = false});

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final size = selected ? 52.0 : 40.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutBack,
              width: size,
              height: size,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Brand.surfaceHigh,
                border: Border.all(color: ring, width: selected ? 4 : 3),
                boxShadow: [BoxShadow(color: ring.withValues(alpha: 0.6), blurRadius: selected ? 22 : 12)],
              ),
              child: Text(
                _initials,
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: selected ? 18 : 14, color: Colors.white),
              ),
            ),
            // A small badge marks a colleague sharing their own location, so
            // staff never confuse a teammate's pin for a participant's.
            if (isStaff)
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  key: const Key('staff-badge'),
                  width: 18,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Brand.blue,
                    border: Border.all(color: Brand.background, width: 2),
                  ),
                  child: const Icon(Icons.shield_rounded, size: 10, color: Colors.white),
                ),
              ),
          ],
        ),
        if (selected)
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(12)),
            child: Text(isSelf ? '$name (You)' : name, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
      ],
    );
  }
}
