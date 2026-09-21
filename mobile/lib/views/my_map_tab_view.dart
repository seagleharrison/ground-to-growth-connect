import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/models.dart';

class _DayGroup {
  final String key; // yyyy-MM-dd, UTC
  final List<MyLocationReport> reports; // sorted ascending by reportedAt
  _DayGroup({required this.key, required this.reports});

  /// The most recent point that day — used as the collapsed dot's position.
  LatLng get anchor {
    final last = reports.last;
    return LatLng(last.latitude, last.longitude);
  }
}

/// A participant's own map: one dot per day, never other participants'
/// locations. Tapping a day's dot reveals that day's movement trail — the
/// sequence of points reported that day, connected in order. Direct
/// equivalent of the native app's MyMapTabView.swift.
class MyMapTabView extends StatefulWidget {
  const MyMapTabView({super.key});

  @override
  State<MyMapTabView> createState() => _MyMapTabViewState();
}

class _MyMapTabViewState extends State<MyMapTabView> {
  final _mapController = MapController();
  String? _selectedDay;
  bool _fitted = false;

  List<_DayGroup> _days(List<MyLocationReport> reports) {
    final byDay = <String, List<MyLocationReport>>{};
    for (final r in reports) {
      final key = r.reportedAt.substring(0, 10); // yyyy-MM-dd prefix, already UTC (Z-suffixed ISO8601)
      (byDay[key] ??= []).add(r);
    }
    final groups = byDay.entries.map((e) {
      final sorted = [...e.value]..sort((a, b) => a.reportedAt.compareTo(b.reportedAt));
      return _DayGroup(key: e.key, reports: sorted);
    }).toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return groups;
  }

  String _dayLabel(String key) {
    final date = DateTime.tryParse('${key}T00:00:00Z');
    if (date == null) return key;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec' // ignore: unnecessary_string_escapes
    ];
    return '${months[date.month - 1]} ${date.day}';
  }

  String _timeLabel(String iso) {
    final date = DateTime.tryParse(iso)?.toLocal();
    if (date == null) return '';
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour < 12 ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final days = _days(app.myLocations);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Map'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => context.read<AppState>().refreshMyLocations(),
          ),
        ],
      ),
      body: days.isEmpty
          ? const _EmptyMap()
          : RefreshIndicator(
              onRefresh: () => context.read<AppState>().refreshMyLocations(),
              child: Column(
                children: [
                  if (_selectedDay != null) _buildBanner(days),
                  Expanded(child: _buildMap(days)),
                ],
              ),
            ),
    );
  }

  Widget _buildBanner(List<_DayGroup> days) {
    final group = days.firstWhere((d) => d.key == _selectedDay, orElse: () => days.first);
    final count = group.reports.length;
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Text(
            '${_dayLabel(group.key)} · $count report${count == 1 ? '' : 's'}',
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          const Spacer(),
          TextButton(
            onPressed: () => setState(() {
              _selectedDay = null;
              _fitted = false;
            }),
            child: const Text('Show all days'),
          ),
        ],
      ),
    );
  }

  Widget _buildMap(List<_DayGroup> days) {
    final selected = _selectedDay == null ? null : days.firstWhere((d) => d.key == _selectedDay, orElse: () => days.first);

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: days.first.anchor,
        initialZoom: 13,
        onMapReady: () => _fitToAnchors(days.map((d) => d.anchor)),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.harrison.groundtogrowth',
        ),
        if (selected != null)
          PolylineLayer(
            polylines: [
              Polyline(
                points: [for (final r in selected.reports) LatLng(r.latitude, r.longitude)],
                color: Colors.blue,
                strokeWidth: 3,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            if (selected != null)
              for (final (index, r) in selected.reports.indexed)
                Marker(
                  point: LatLng(r.latitude, r.longitude),
                  width: index == selected.reports.length - 1 ? 22 : 16,
                  height: index == selected.reports.length - 1 ? 22 : 16,
                  child: Tooltip(
                    message: _timeLabel(r.reportedAt),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                )
            else
              for (final group in days)
                Marker(
                  point: group.anchor,
                  width: 90,
                  height: 60,
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _selectedDay = group.key;
                      _fitted = false;
                    }),
                    child: Column(
                      children: [
                        Icon(Icons.circle, color: Theme.of(context).colorScheme.primary, size: 22),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            _dayLabel(group.key),
                            style: const TextStyle(color: Colors.white, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ],
    );
  }

  void _fitToAnchors(Iterable<LatLng> points) {
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
}

class _EmptyMap extends StatelessWidget {
  const _EmptyMap();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.navigation_outlined, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text('No locations yet', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Your reported locations appear here once you grant consent and the app sends its first update.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
