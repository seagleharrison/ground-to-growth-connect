import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../nav.dart';
import '../theme/app_theme.dart';
import '../util/journey.dart';
import '../util/time.dart';
import '../widgets/map_kit.dart';
import '../widgets/ui.dart';

/// A participant's own map — never anyone else's. One glowing dot per day; pick
/// a day to see the route you took, tap a stop for its details, or press play
/// to watch the day unfold.
class MyMapTabView extends StatefulWidget {
  const MyMapTabView({super.key});

  @override
  State<MyMapTabView> createState() => _MyMapTabViewState();
}

class _MyMapTabViewState extends State<MyMapTabView> with TickerProviderStateMixin, AnimatedMapCamera {
  final _map = MapController();
  @override
  MapController get mapController => _map;

  String? _selectedDayKey;
  JourneyRange _range = JourneyRange.all;
  int? _selectedStop;
  LatLng? _me;
  int _lastFitDays = -1;

  late final AnimationController _replay = AnimationController(vsync: this, duration: const Duration(seconds: 6))
    ..addListener(_onReplayTick)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) setState(() {});
    });

  @override
  void dispose() {
    _replay.dispose();
    disposeCamera();
    _map.dispose();
    super.dispose();
  }

  void _onReplayTick() {
    if (!mounted) return;
    final day = _dayFor(_days);
    if (day != null && mapReady && _replay.isAnimating) {
      _map.move(pointAlong(day.points, _replay.value), _map.camera.zoom);
    }
    setState(() {});
  }

  List<JourneyDay> _days = [];

  JourneyDay? _dayFor(List<JourneyDay> days) {
    for (final d in days) {
      if (d.key == _selectedDayKey) return d;
    }
    return null;
  }

  EdgeInsets get _fitPadding => EdgeInsets.fromLTRB(50, 120, 50, 330 + MediaQuery.paddingOf(context).bottom);

  void _selectDay(JourneyDay day) {
    _replay
      ..stop()
      ..value = 0;
    setState(() {
      _selectedDayKey = day.key;
      _selectedStop = null;
    });
    flyToFit(day.points, padding: _fitPadding);
  }

  /// Shows every day in a stretch of time (all, the past week, this month).
  void _selectRange(JourneyRange range) {
    _replay
      ..stop()
      ..value = 0;
    setState(() {
      _range = range;
      _selectedDayKey = null;
      _selectedStop = null;
    });
    final visible = filterByRange(_days, range, DateTime.now());
    flyToFit([for (final d in visible) ...d.points], padding: _fitPadding);
  }

  void _togglePlay(JourneyDay day) {
    if (_replay.isAnimating) {
      _replay.stop();
      setState(() {});
      return;
    }
    if (_replay.value >= 1) _replay.value = 0;
    _replay.duration = Duration(milliseconds: (3000 + day.stops * 900).clamp(4000, 14000));
    setState(() => _selectedStop = null);
    if (mapReady && _map.camera.zoom < 14.5) flyTo(pointAlong(day.points, _replay.value), 15);
    _replay.forward();
  }

  Future<void> _locateMe() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        messenger.showSnackBar(const SnackBar(content: Text('Allow location access in Settings to see yourself on the map.')));
        return;
      }
      final p = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      final here = LatLng(p.latitude, p.longitude);
      setState(() => _me = here);
      flyTo(here, 16);
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text("Couldn't find your location right now.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    _days = groupByLocalDay(app.myLocations);
    final days = _days;
    final selected = _dayFor(days);
    // With no single day picked, the map shows whichever stretch of time is chosen.
    final visible = filterByRange(days, _range, DateTime.now());

    // Frame all the days the first time data shows up, and again when more arrive.
    if (mapReady && days.length != _lastFitDays) {
      _lastFitDays = days.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && selected == null && visible.isNotEmpty) {
          flyToFit([for (final d in visible) ...d.points], padding: _fitPadding);
        }
      });
    }

    final safeTop = MediaQuery.paddingOf(context).top;
    final safeBottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: days.isEmpty ? savannah : days.last.anchor,
              initialZoom: days.isEmpty ? 12.5 : 14,
              minZoom: 3,
              maxZoom: 19,
              backgroundColor: const Color(0xFF0E1115),
              onMapReady: () {
                mapReady = true;
                if (days.isNotEmpty) {
                  _lastFitDays = days.length;
                  flyToFit([for (final d in days) ...d.points], padding: _fitPadding);
                }
              },
              onTap: (_, _) {
                if (_selectedStop != null) setState(() => _selectedStop = null);
              },
            ),
            children: [
              const AppTileLayer(),
              if (selected != null) ..._routeLayers(selected),
              MarkerLayer(markers: _markers(selected == null ? visible : days, selected)),
            ],
          ),

          // Day picker
          Positioned(
            top: safeTop + 10,
            left: 14,
            right: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GlassPanel(
                  radius: 28,
                  padding: const EdgeInsets.all(6),
                  child: SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final r in JourneyRange.values)
                          _DayChip(
                            key: Key('chip-${r.name}'),
                            label: r.label,
                            selected: selected == null && _range == r,
                            onTap: () => _selectRange(r),
                          ),
                        for (final d in days.reversed)
                          _DayChip(
                            key: Key('chip-${d.key}'),
                            label: dayLabel(d.date),
                            count: d.stops,
                            selected: selected?.key == d.key,
                            onTap: () => _selectDay(d),
                          ),
                      ],
                    ),
                  ),
                ),
                const Padding(padding: EdgeInsets.only(left: 12, top: 6), child: MapCredit()),
              ],
            ),
          ),

          // Map controls
          Positioned(
            right: 14,
            top: safeTop + 92,
            child: Column(
              children: [
                GlassIconButton(
                  icon: Icons.zoom_out_map_rounded,
                  tooltip: 'Show everything',
                  onPressed: () => flyToFit(selected?.points ?? [for (final d in visible) ...d.points], padding: _fitPadding),
                ),
                const SizedBox(height: 10),
                GlassIconButton(icon: Icons.my_location_rounded, tooltip: 'Where I am now', onPressed: _locateMe, active: _me != null),
                const SizedBox(height: 10),
                GlassIconButton(
                  icon: Icons.refresh_rounded,
                  tooltip: 'Refresh',
                  onPressed: () => context.read<AppState>().refreshMyLocations(),
                ),
              ],
            ),
          ),

          // Bottom panel
          Positioned(
            left: 14,
            right: 14,
            bottom: safeBottom + 100,
            child: FadeSlideIn(
              key: ValueKey('panel-${selected?.key}-${_range.name}-${days.isEmpty}'),
              offset: 24,
              child: GlassPanel(
                padding: const EdgeInsets.all(18),
                child: days.isEmpty
                    ? _emptyPanel(context)
                    : selected == null
                        ? _overviewPanel(visible)
                        : _dayPanel(selected),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // MARK: map layers

  List<Widget> _routeLayers(JourneyDay day) {
    final t = _replay.value;
    final playing = t > 0;
    return [
      PolylineLayer(
        polylines: [
          Polyline(points: day.points, strokeWidth: 14, color: Brand.orange.withValues(alpha: 0.14), strokeCap: StrokeCap.round, strokeJoin: StrokeJoin.round),
          if (!playing)
            Polyline(
              points: day.points,
              strokeWidth: 4.5,
              color: Brand.orange,
              gradientColors: const [Brand.green, Brand.orange],
              strokeCap: StrokeCap.round,
              strokeJoin: StrokeJoin.round,
            )
          else ...[
            Polyline(
              points: day.points,
              strokeWidth: 3,
              color: Colors.white38,
              pattern: const StrokePattern.dotted(),
            ),
            Polyline(
              points: pathUntil(day.points, t),
              strokeWidth: 5.5,
              color: Brand.orange,
              gradientColors: const [Brand.green, Brand.orange],
              strokeCap: StrokeCap.round,
              strokeJoin: StrokeJoin.round,
            ),
          ],
        ],
      ),
    ];
  }

  List<Marker> _markers(List<JourneyDay> days, JourneyDay? selected) {
    final markers = <Marker>[];

    if (selected == null) {
      // Overview: one glowing dot per day.
      for (final d in days) {
        markers.add(Marker(
          point: d.anchor,
          width: 110,
          height: 70,
          child: GestureDetector(
            key: Key('day-dot-${d.key}'),
            onTap: () => _selectDay(d),
            child: Column(
              children: [
                const GlowDot(color: Brand.orange, size: 26),
                const SizedBox(height: 4),
                _MapLabel('${dayLabel(d.date)} · ${d.stops}'),
              ],
            ),
          ),
        ));
      }
    } else {
      // Other days stay visible as quiet dots, so you can hop to them.
      for (final d in days.where((d) => d.key != selected.key)) {
        markers.add(Marker(
          point: d.anchor,
          width: 30,
          height: 30,
          child: GestureDetector(
            onTap: () => _selectDay(d),
            child: Center(
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white38, border: Border.all(color: Colors.white70, width: 2)),
              ),
            ),
          ),
        ));
      }

      for (final (i, point) in selected.points.indexed) {
        final isFirst = i == 0;
        final isLast = i == selected.stops - 1;
        final isSelected = _selectedStop == i;
        final color = isLast ? Brand.orange : (isFirst ? Brand.green : Brand.surfaceHigh);
        markers.add(Marker(
          point: point,
          width: 64,
          height: 64,
          child: GestureDetector(
            key: Key('stop-$i'),
            onTap: () {
              setState(() => _selectedStop = i);
              flyTo(point, _map.camera.zoom < 15 ? 15.5 : _map.camera.zoom);
            },
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutBack,
                child: GlowDot(
                  color: isSelected ? Brand.blue : color,
                  size: isSelected ? 38 : (isLast || isFirst ? 30 : 26),
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(
                      fontSize: isSelected ? 15 : 12,
                      fontWeight: FontWeight.w800,
                      color: (isLast || isFirst || isSelected) ? const Color(0xFF1B1004) : Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ));
      }

      if (_replay.value > 0) {
        markers.add(Marker(
          point: pointAlong(selected.points, _replay.value),
          width: 60,
          height: 60,
          child: const IgnorePointer(child: Center(child: PulseDot(color: Brand.blue, size: 18))),
        ));
      }
    }

    if (_me != null) {
      markers.add(Marker(
        point: _me!,
        width: 60,
        height: 60,
        child: const IgnorePointer(child: Center(child: PulseDot(color: Brand.blue, size: 14))),
      ));
    }
    return markers;
  }

  // MARK: panels

  Widget _emptyPanel(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: Brand.orange.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.route_rounded, color: Brand.orange),
            ),
            const SizedBox(width: 14),
            const Expanded(child: Text('Your journey will show up here', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
          ],
        ),
        const SizedBox(height: 10),
        const Text(
          'Once location sharing is on, each check-in is added to this map so you can look back at where you have been.',
          style: TextStyle(color: Colors.white70, height: 1.4),
        ),
        const SizedBox(height: 14),
        OutlinedButton(
          onPressed: () => context.read<TabNav>().go(AppTab.home),
          child: const Text('Go to Home to turn on sharing'),
        ),
      ],
    );
  }

  Widget _overviewPanel(List<JourneyDay> days) {
    if (days.isEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_range.label, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text(
            'No check-ins in this stretch of time. Pick another one above, or tap a day.',
            key: Key('range-empty'),
            style: TextStyle(color: Colors.white70, height: 1.4),
          ),
        ],
      );
    }
    final checkIns = days.fold<int>(0, (a, d) => a + d.stops);
    final distance = days.fold<double>(0, (a, d) => a + d.distanceMeters);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_range == JourneyRange.all ? 'Your journey' : _range.label, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text('Tap a day above, or a glowing dot, to see where you went.', style: TextStyle(color: Colors.white60)),
        const SizedBox(height: 14),
        Row(
          children: [
            _Stat(Icons.calendar_today_rounded, '${days.length}', days.length == 1 ? 'day' : 'days'),
            _Stat(Icons.place_rounded, '$checkIns', 'check-ins'),
            _Stat(Icons.straighten_rounded, formatDistance(distance), 'covered'),
          ],
        ),
      ],
    );
  }

  Widget _dayPanel(JourneyDay day) {
    final stop = _selectedStop;
    final t = _replay.value;
    final nearest = day.stops <= 1 ? 0 : (t * (day.stops - 1)).round();
    final accuracy = stop == null ? null : day.reports[stop].accuracyMeters;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(fullDate(day.date), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(
                    stop == null
                        ? '${clockTime(day.first)} to ${clockTime(day.last)}'
                        : 'Stop ${stop + 1} of ${day.stops} · ${clockTime(day.times[stop])}${accuracy != null ? ' · about ${accuracy.round()} m' : ''}',
                    style: TextStyle(color: stop == null ? Colors.white60 : Brand.blue, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            if (stop != null)
              IconButton(
                tooltip: 'Close',
                onPressed: () => setState(() => _selectedStop = null),
                icon: const Icon(Icons.close_rounded, color: Colors.white54),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            _Stat(Icons.place_rounded, '${day.stops}', day.stops == 1 ? 'stop' : 'stops'),
            _Stat(Icons.straighten_rounded, formatDistance(day.distanceMeters), 'traveled'),
            _Stat(Icons.schedule_rounded, _duration(day.last.difference(day.first)), 'span'),
          ],
        ),
        if (day.stops > 1) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              PressableScale(
                onTap: () => _togglePlay(day),
                child: Container(
                  key: const Key('replay-button'),
                  width: 46,
                  height: 46,
                  decoration: const BoxDecoration(shape: BoxShape.circle, gradient: Brand.heroGradient),
                  child: Icon(
                    _replay.isAnimating ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: const Color(0xFF3A1D00),
                    size: 28,
                  ),
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 5,
                    activeTrackColor: Brand.orange,
                    inactiveTrackColor: Colors.white12,
                    thumbColor: Brand.orange,
                    overlayColor: Brand.orange.withValues(alpha: 0.15),
                  ),
                  child: Slider(
                    key: const Key('replay-slider'),
                    value: t.clamp(0, 1),
                    onChangeStart: (_) => _replay.stop(),
                    onChanged: (v) {
                      _replay.value = v;
                      if (mapReady) _map.move(pointAlong(day.points, v), _map.camera.zoom);
                    },
                  ),
                ),
              ),
              SizedBox(
                width: 62,
                child: Text(
                  t <= 0 ? 'Replay' : clockTime(day.times[nearest]),
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  String _duration(Duration d) {
    if (d.inMinutes < 1) return '—';
    if (d.inHours < 1) return '${d.inMinutes} min';
    final m = d.inMinutes % 60;
    return m == 0 ? '${d.inHours} h' : '${d.inHours} h $m m';
  }
}

class _DayChip extends StatelessWidget {
  final String label;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  const _DayChip({super.key, required this.label, this.count, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      pressedScale: 0.94,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: selected ? Brand.heroGradient : null,
          color: selected ? null : Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Text(
          count == null ? label : '$label · $count',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: selected ? const Color(0xFF3A1D00) : Colors.white,
          ),
        ),
      ),
    );
  }
}

class _MapLabel extends StatelessWidget {
  final String text;
  const _MapLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.72), borderRadius: BorderRadius.circular(12)),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  const _Stat(this.icon, this.value, this.label);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 18, color: Brand.orange),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
