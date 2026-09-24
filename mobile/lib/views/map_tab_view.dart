import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/models.dart';
import '../services/location_tracker.dart';
import '../theme/app_theme.dart';
import '../util/journey.dart';
import '../util/time.dart';
import '../widgets/map_kit.dart';
import '../widgets/ui.dart';
import 'documents_view.dart' show walletColors, walletGreen, walletIcon;
import 'sharing_sheets.dart' show showSharingConsentSheet;

/// Staff-only: everyone who is sharing their location, on one map. Search for
/// someone, tap a person to fly to them, and see at a glance which documents
/// they have on file (types only — staff can never open a document).
class MapTabView extends StatefulWidget {
  const MapTabView({super.key});

  @override
  State<MapTabView> createState() => _MapTabViewState();
}

class _MapTabViewState extends State<MapTabView> with TickerProviderStateMixin, AnimatedMapCamera {
  final _map = MapController();
  @override
  MapController get mapController => _map;

  final _sheet = DraggableScrollableController();
  final _search = TextEditingController();
  Timer? _autoRefresh;
  String? _selectedId;
  int _lastFitCount = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppState>().refreshPeople();
    });
    // Keep the picture current without anyone having to pull to refresh.
    _autoRefresh = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) context.read<AppState>().refreshPeople();
    });
  }

  @override
  void dispose() {
    _autoRefresh?.cancel();
    _search.dispose();
    _sheet.dispose();
    disposeCamera();
    _map.dispose();
    super.dispose();
  }

  EdgeInsets get _fitPadding => EdgeInsets.fromLTRB(50, 190, 50, 260 + MediaQuery.paddingOf(context).bottom);

  static Color ringFor(Recency r) => switch (r) {
        Recency.activeNow => Brand.green,
        Recency.recent => Brand.amber,
        Recency.stale => Colors.white38,
      };

  DateTime _seen(UserLocation p) => DateTime.tryParse(p.reportedAt)?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0);

  void _select(UserLocation p) {
    HapticFeedback.selectionClick();
    setState(() => _selectedId = p.userId);
    flyTo(LatLng(p.latitude, p.longitude), 16.5);
    if (_sheet.isAttached) {
      _sheet.animateTo(0.42, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final now = DateTime.now();
    final query = _search.text.trim().toLowerCase();

    final everyone = [...app.locations]..sort((a, b) => _seen(b).compareTo(_seen(a)));
    final people = query.isEmpty ? everyone : everyone.where((p) => p.name.toLowerCase().contains(query)).toList();
    final activeNow = everyone.where((p) => recencyOf(_seen(p), now: now) == Recency.activeNow).length;
    final selected = everyone.where((p) => p.userId == _selectedId).firstOrNull;

    if (mapReady && everyone.length != _lastFitCount) {
      _lastFitCount = everyone.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && selected == null && everyone.isNotEmpty) {
          flyToFit([for (final p in everyone) LatLng(p.latitude, p.longitude)], padding: _fitPadding);
        }
      });
    }

    final safeTop = MediaQuery.paddingOf(context).top;

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, box) {
          final minSize = ((kNavBarClearance + 74) / box.maxHeight).clamp(0.1, 0.4);
          return Stack(
            children: [
              FlutterMap(
                mapController: _map,
                options: MapOptions(
                  initialCenter: everyone.isEmpty ? savannah : LatLng(everyone.first.latitude, everyone.first.longitude),
                  initialZoom: everyone.isEmpty ? 12.5 : 14,
                  minZoom: 3,
                  maxZoom: 19,
                  backgroundColor: const Color(0xFF0E1115),
                  onMapReady: () {
                    mapReady = true;
                    if (everyone.isNotEmpty) {
                      _lastFitCount = everyone.length;
                      flyToFit([for (final p in everyone) LatLng(p.latitude, p.longitude)], padding: _fitPadding);
                    }
                  },
                  onTap: (_, _) {
                    if (_selectedId != null) setState(() => _selectedId = null);
                  },
                ),
                children: [
                  const AppTileLayer(),
                  MarkerLayer(
                    markers: [
                      for (final p in people)
                        Marker(
                          point: LatLng(p.latitude, p.longitude),
                          width: p.userId == _selectedId ? 170 : 96,
                          height: p.userId == _selectedId ? 112 : 64,
                          alignment: Alignment.topCenter,
                          child: GestureDetector(
                            key: Key('person-${p.userId}'),
                            onTap: () => _select(p),
                            child: PersonMarker(
                              name: p.name,
                              ring: ringFor(recencyOf(_seen(p), now: now)),
                              selected: p.userId == _selectedId,
                              isStaff: p.isStaffPerson,
                              isSelf: p.userId == app.user?.id,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),

              // Search + summary
              Positioned(
                top: safeTop + 10,
                left: 14,
                right: 14,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GlassPanel(
                      radius: 28,
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: TextField(
                        key: const Key('people-search'),
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Search people',
                          filled: false,
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: query.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.close_rounded),
                                  onPressed: () => setState(_search.clear),
                                ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _GlassChip(icon: Icons.groups_rounded, label: '${everyone.length} ${everyone.length == 1 ? 'person' : 'people'}'),
                          const SizedBox(width: 8),
                          _GlassChip(icon: Icons.circle, iconColor: Brand.green, iconSize: 10, label: '$activeNow active now'),
                          const SizedBox(width: 8),
                          _ShareToggleChip(sharing: app.consent?.granted == true),
                        ],
                      ),
                    ),
                    ListenableBuilder(
                      listenable: app.locationTracker,
                      builder: (context, _) {
                        final tracker = app.locationTracker;
                        if (app.consent?.granted != true) return const SizedBox.shrink();
                        // A staff member never sees their own pin among
                        // "everyone" (they already know where they are), so
                        // this is the only place they can confirm their own
                        // sharing is actually working, not just turned on.
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: tracker.lastError != null ? _LocationErrorBanner(tracker: tracker) : _SelfSharingStatus(tracker: tracker),
                        );
                      },
                    ),
                    const Padding(padding: EdgeInsets.only(left: 12, top: 6), child: MapCredit()),
                  ],
                ),
              ),

              // Controls
              Positioned(
                right: 14,
                top: safeTop + 130,
                child: Column(
                  children: [
                    GlassIconButton(
                      icon: Icons.zoom_out_map_rounded,
                      tooltip: 'Show everyone',
                      onPressed: () {
                        setState(() => _selectedId = null);
                        flyToFit([for (final p in everyone) LatLng(p.latitude, p.longitude)], padding: _fitPadding);
                      },
                    ),
                    const SizedBox(height: 10),
                    GlassIconButton(
                      icon: Icons.refresh_rounded,
                      tooltip: 'Refresh',
                      onPressed: () => context.read<AppState>().refreshPeople(),
                    ),
                  ],
                ),
              ),

              // Pull-up list
              DraggableScrollableSheet(
                controller: _sheet,
                initialChildSize: minSize + 0.14,
                minChildSize: minSize,
                maxChildSize: 0.88,
                snap: true,
                snapSizes: [minSize + 0.14, 0.6],
                builder: (context, scroll) => _PeopleSheet(
                  scroll: scroll,
                  people: people,
                  total: everyone.length,
                  selected: selected,
                  now: now,
                  documentsOnFile: app.documentsOnFile,
                  selfId: app.user?.id,
                  onSelect: _select,
                  onClearSelection: () => setState(() => _selectedId = null),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _GlassChip extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final double iconSize;
  final String label;
  const _GlassChip({required this.icon, this.iconColor, this.iconSize = 16, required this.label});

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      radius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: iconSize, color: iconColor ?? Colors.white70),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        ],
      ),
    );
  }
}

/// Staff can share their own location with each other, the same as
/// participants share theirs with staff. Tapping it while off opens the
/// consent sheet; while on, it turns sharing off right away.
class _ShareToggleChip extends StatelessWidget {
  final bool sharing;
  const _ShareToggleChip({required this.sharing});

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      key: const Key('share-my-location-chip'),
      onTap: () {
        if (sharing) {
          context.read<AppState>().revokeConsent();
        } else {
          showSharingConsentSheet(context, forStaff: true);
        }
      },
      child: GlassPanel(
        radius: 20,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (sharing)
              const PulseDot(color: Brand.green, size: 8)
            else
              const Icon(Icons.location_on_outlined, size: 16, color: Colors.white70),
            const SizedBox(width: 6),
            Text(
              sharing ? 'Sharing' : 'Share my location',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: sharing ? Brand.green : Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when this staff member turned sharing on but it isn't actually
/// reaching the server — most often a permission the phone won't ask about
/// again, so this offers the direct way to fix it rather than just a message.
class _LocationErrorBanner extends StatelessWidget {
  final LocationTracker tracker;
  const _LocationErrorBanner({required this.tracker});

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      radius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, size: 18, color: Brand.amber),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tracker.lastError!, style: const TextStyle(color: Brand.amber, fontSize: 13, height: 1.3)),
                if (tracker.permissionBlocked)
                  TextButton(
                    key: const Key('open-location-settings-map'),
                    onPressed: tracker.openSettings,
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft, minimumSize: const Size(0, 32)),
                    child: const Text('Open Settings', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SelfSharingStatus extends StatelessWidget {
  final LocationTracker tracker;
  const _SelfSharingStatus({required this.tracker});

  @override
  Widget build(BuildContext context) {
    final last = tracker.lastReportAt;
    final stale = last != null && isStaleCheckIn(last);
    final color = stale ? Brand.amber : Brand.green;
    return GlassPanel(
      radius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(stale ? Icons.warning_amber_rounded : Icons.check_circle_rounded, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              last == null ? 'Sharing on — waiting for your first check-in…' : 'Sharing on — your last check-in was ${timeAgo(last)}',
              key: const Key('self-sharing-status'),
              style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _PeopleSheet extends StatelessWidget {
  final ScrollController scroll;
  final List<UserLocation> people;
  final int total;
  final UserLocation? selected;
  final DateTime now;
  final Map<String, Set<DocumentType>> documentsOnFile;
  final String? selfId;
  final ValueChanged<UserLocation> onSelect;
  final VoidCallback onClearSelection;

  const _PeopleSheet({
    required this.scroll,
    required this.people,
    required this.total,
    required this.selected,
    required this.now,
    required this.documentsOnFile,
    required this.selfId,
    required this.onSelect,
    required this.onClearSelection,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Brand.surface.withValues(alpha: 0.97),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: ListView(
        controller: scroll,
        padding: EdgeInsets.fromLTRB(16, 10, 16, kNavBarClearance + 16),
        children: [
          Center(child: Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(3)))),
          const SizedBox(height: 14),
          Row(
            children: [
              Text('People sharing', style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              Text('$total', style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          const Row(
            children: [
              _Legend(Brand.green, 'Active now'),
              SizedBox(width: 14),
              _Legend(Brand.amber, 'Within 2 h'),
              SizedBox(width: 14),
              _Legend(Colors.white38, 'Earlier'),
            ],
          ),
          const SizedBox(height: 14),
          if (selected != null) ...[
            _PersonCard(
              person: selected!,
              now: now,
              types: documentsOnFile[selected!.userId] ?? const {},
              isSelf: selected!.userId == selfId,
              onClose: onClearSelection,
            ),
            const SizedBox(height: 14),
          ],
          if (people.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 30),
              child: Column(
                children: [
                  const Icon(Icons.location_searching_rounded, size: 40, color: Colors.white38),
                  const SizedBox(height: 12),
                  Text(
                    total == 0 ? 'No one is sharing yet' : 'No one matches that search',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    total == 0 ? 'People show up here once they turn on location sharing.' : 'Try a different name.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white54),
                  ),
                ],
              ),
            ),
          for (final p in people)
            if (p.userId != selected?.userId)
              _PersonRow(
                person: p,
                now: now,
                types: documentsOnFile[p.userId] ?? const {},
                isSelf: p.userId == selfId,
                onTap: () => onSelect(p),
              ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend(this.color, this.label);

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
        ],
      );
}

class _PersonRow extends StatelessWidget {
  final UserLocation person;
  final DateTime now;
  final Set<DocumentType> types;
  final bool isSelf;
  final VoidCallback onTap;

  const _PersonRow({required this.person, required this.now, required this.types, this.isSelf = false, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final seen = DateTime.tryParse(person.reportedAt)?.toLocal() ?? now;
    final ring = _MapTabViewState.ringFor(recencyOf(seen, now: now));
    return PressableScale(
      onTap: onTap,
      child: Container(
        key: Key('row-${person.userId}'),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Brand.surfaceHigh, borderRadius: BorderRadius.circular(20)),
        child: Row(
          children: [
            _Avatar(name: person.name, ring: ring),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(child: Text(person.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16), overflow: TextOverflow.ellipsis)),
                      if (isSelf) ...[
                        const SizedBox(width: 6),
                        const Pill(key: Key('you-pill'), label: 'You', color: Brand.orange),
                      ],
                      if (person.isStaffPerson) ...[
                        const SizedBox(width: 6),
                        const Pill(key: Key('staff-pill'), label: 'Staff', color: Brand.blue),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text('Seen ${timeAgo(seen, now: now)}', style: TextStyle(color: ring, fontSize: 13)),
                ],
              ),
            ),
            _DocDots(types: types),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String name;
  final Color ring;
  const _Avatar({required this.name, required this.ring});

  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final initials = parts.isEmpty
        ? '?'
        : parts.length == 1
            ? parts.first.characters.first.toUpperCase()
            : (parts.first.characters.first + parts.last.characters.first).toUpperCase();
    return Container(
      width: 46,
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Brand.surface,
        border: Border.all(color: ring, width: 3),
      ),
      child: Text(initials, style: const TextStyle(fontWeight: FontWeight.w800)),
    );
  }
}

/// Three little cards showing which of the core documents are on file.
class _DocDots extends StatelessWidget {
  final Set<DocumentType> types;
  const _DocDots({required this.types});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final t in DocumentType.coreChecklist)
          Container(
            key: Key('doc-${t.wireValue}-${types.contains(t)}'),
            width: 26,
            height: 26,
            margin: const EdgeInsets.only(left: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              gradient: types.contains(t) ? LinearGradient(colors: walletColors(t)) : null,
              color: types.contains(t) ? null : Colors.white10,
            ),
            child: Icon(walletIcon(t), size: 15, color: types.contains(t) ? Colors.white : Colors.white24),
          ),
      ],
    );
  }
}

class _PersonCard extends StatelessWidget {
  final UserLocation person;
  final DateTime now;
  final Set<DocumentType> types;
  final bool isSelf;
  final VoidCallback onClose;

  const _PersonCard({required this.person, required this.now, required this.types, this.isSelf = false, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final seen = DateTime.tryParse(person.reportedAt)?.toLocal() ?? now;
    final ring = _MapTabViewState.ringFor(recencyOf(seen, now: now));
    final missing = [for (final t in DocumentType.coreChecklist) if (!types.contains(t)) t];

    return Container(
      key: const Key('person-card'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Brand.surfaceHigh,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: ring.withValues(alpha: 0.6), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Avatar(name: person.name, ring: ring),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(child: Text(person.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19), overflow: TextOverflow.ellipsis)),
                        if (isSelf) ...[
                          const SizedBox(width: 8),
                          const Pill(key: Key('you-pill'), label: 'You', color: Brand.orange),
                        ],
                        if (person.isStaffPerson) ...[
                          const SizedBox(width: 8),
                          const Pill(key: Key('staff-pill'), label: 'Staff', color: Brand.blue),
                        ],
                      ],
                    ),
                    Text(
                      'Seen ${timeAgo(seen, now: now)} · ${clockTime(seen)}',
                      style: TextStyle(color: ring, fontSize: 13),
                    ),
                  ],
                ),
              ),
              IconButton(onPressed: onClose, icon: const Icon(Icons.close_rounded, color: Colors.white54)),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Location is approximate (rounded to about 200 meters).',
            style: TextStyle(color: Colors.white54, fontSize: 12.5),
          ),
          const SizedBox(height: 14),
          const Text('DOCUMENTS ON FILE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1, color: Colors.white54)),
          const SizedBox(height: 8),
          for (final t in DocumentType.coreChecklist)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: types.contains(t) ? walletGreen : Colors.transparent,
                      border: types.contains(t) ? null : Border.all(color: Colors.white30, width: 2),
                    ),
                    child: types.contains(t) ? const Icon(Icons.check_rounded, size: 16, color: Colors.white) : null,
                  ),
                  const SizedBox(width: 12),
                  Text(t.label, style: TextStyle(color: types.contains(t) ? Colors.white : Colors.white60)),
                ],
              ),
            ),
          if (missing.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              missing.length == 3
                  ? 'Nothing on file yet — a good thing to help with.'
                  : 'Still needs: ${missing.map((t) => t.label.toLowerCase()).join(', ')}.',
              style: const TextStyle(color: Brand.amber, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}
