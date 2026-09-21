import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';

/// Staff-only map: every consented participant's latest location. Direct
/// equivalent of the native app's MapTabView.swift.
class MapTabView extends StatefulWidget {
  const MapTabView({super.key});

  @override
  State<MapTabView> createState() => _MapTabViewState();
}

class _MapTabViewState extends State<MapTabView> {
  final _mapController = MapController();
  bool _fitted = false;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final locations = app.locations;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Map'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => context.read<AppState>().refreshLocations(),
          ),
        ],
      ),
      body: locations.isEmpty
          ? const _EmptyMap(
              title: 'No locations yet',
              subtitle: 'Locations appear here once consented users report in.',
            )
          : RefreshIndicator(
              onRefresh: () => context.read<AppState>().refreshLocations(),
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: LatLng(locations.first.latitude, locations.first.longitude),
                  initialZoom: 13,
                  onMapReady: () => _fitToMarkers(locations.map((l) => LatLng(l.latitude, l.longitude))),
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.harrison.groundtogrowth',
                  ),
                  MarkerLayer(
                    markers: [
                      for (final loc in locations)
                        Marker(
                          point: LatLng(loc.latitude, loc.longitude),
                          width: 120,
                          height: 60,
                          child: _PinLabel(label: loc.name),
                        ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  void _fitToMarkers(Iterable<LatLng> points) {
    if (points.isEmpty || _fitted) return;
    _fitted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (points.length == 1) {
        _mapController.move(points.first, 14);
      } else {
        _mapController.fitCamera(
          CameraFit.coordinates(coordinates: points.toList(), padding: const EdgeInsets.all(48)),
        );
      }
    });
  }

  @override
  void didUpdateWidget(covariant MapTabView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _fitted = false;
  }
}

class _PinLabel extends StatelessWidget {
  final String label;
  const _PinLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(Icons.location_on, color: Theme.of(context).colorScheme.primary, size: 32),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 11)),
        ),
      ],
    );
  }
}

class _EmptyMap extends StatelessWidget {
  final String title;
  final String subtitle;
  const _EmptyMap({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.map_outlined, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(subtitle, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
