import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/models.dart';
import '../nav.dart';
import '../services/location_tracker.dart';
import '../theme/app_theme.dart';
import '../widgets/nav_bar.dart';
import 'analytics_view.dart';
import 'documents_view.dart';
import 'home_view.dart';
import 'map_tab_view.dart';
import 'my_map_tab_view.dart';
import 'resources_view.dart';
import 'settings_view.dart';

/// Participants get Home, their own Map, Documents, Resources and Me; staff get the
/// everyone-Map and Me; admins also get Analytics. The bar runs along the bottom.
class MainTabView extends StatefulWidget {
  const MainTabView({super.key});

  @override
  State<MainTabView> createState() => _MainTabViewState();
}

class _MainTabViewState extends State<MainTabView> {
  bool _offeredLocationUpgradesThisLaunch = false;

  /// The moment someone lands in the app with sharing on but something about
  /// their location setup is worse than it could be, offer the fix directly
  /// rather than waiting for them to notice a banner — this is what actually
  /// made check-ins go stale for a tester whose phone sat locked for hours.
  /// Only asked once per app launch either way, so it never turns into
  /// nagging, and the two nudges never stack on top of each other.
  void _maybeOfferLocationUpgrades(AppState app) {
    if (_offeredLocationUpgradesThisLaunch) return;
    final tracker = app.locationTracker;
    if (app.consent?.granted != true) return;
    final needsAlways = tracker.canUpgradeToAlways && !tracker.alwaysNudgeDismissed;
    final needsPrecise = tracker.canUpgradeToPrecise && !tracker.preciseNudgeDismissed;
    if (!needsAlways && !needsPrecise) return;
    _offeredLocationUpgradesThisLaunch = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (needsAlways) await _showAlwaysDialog(tracker);
      if (!mounted) return;
      if (needsPrecise) await _showPreciseDialog(tracker);
    });
  }

  Future<void> _showAlwaysDialog(LocationTracker tracker) async {
    final turnOn = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Keep sharing while your phone is locked?'),
        content: const Text(
          'Right now we can only see your location while the app is open. Choosing '
          '"Always Allow" for Location in Settings lets us check in every 15 minutes '
          "even when your phone is locked or in your pocket.",
        ),
        actions: [
          TextButton(
            key: const Key('always-nudge-not-now'),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          TextButton(
            key: const Key('always-nudge-open-settings'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Turn On'),
          ),
        ],
      ),
    );
    tracker.dismissAlwaysNudge();
    if (turnOn == true) await tracker.openSettings();
  }

  Future<void> _showPreciseDialog(LocationTracker tracker) async {
    final turnOn = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Make your location more accurate?'),
        content: const Text(
          'Precise Location is turned off for this app, so your spot on the map could '
          'be off by a mile or more. Turning it on in Settings gives our outreach team '
          'your exact location instead of just a general area.',
        ),
        actions: [
          TextButton(
            key: const Key('precise-nudge-not-now'),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          TextButton(
            key: const Key('precise-nudge-open-settings'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Turn On'),
          ),
        ],
      ),
    );
    tracker.dismissPreciseNudge();
    if (turnOn == true) await tracker.openSettings();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    // What to show follows the current view: an admin's own, or the preview they picked.
    final view = context.select<AppState, AppView>((a) => a.currentView);
    final previewing = context.select<AppState, bool>((a) => a.isPreviewing);
    final notice = context.select<AppState, String?>((a) => a.previewNotice);
    final isStaff = view != AppView.participant;
    final isAdmin = view == AppView.admin;
    final nav = context.watch<TabNav>();

    if (notice != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        final app = context.read<AppState>();
        if (app.previewNotice == null) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(app.previewNotice!)));
        app.clearPreviewNotice();
      });
    }

    return ListenableBuilder(
      listenable: app.locationTracker,
      builder: (context, _) {
        _maybeOfferLocationUpgrades(app);
        return _buildScaffold(context, app: app, isStaff: isStaff, isAdmin: isAdmin, previewing: previewing, view: view, nav: nav);
      },
    );
  }

  Widget _buildScaffold(
    BuildContext context, {
    required AppState app,
    required bool isStaff,
    required bool isAdmin,
    required bool previewing,
    required AppView view,
    required TabNav nav,
  }) {
    final tabs = <({AppTab tab, NavItem item, Widget view})>[
      if (!isStaff)
        (
          tab: AppTab.home,
          item: const NavItem(Icons.home_outlined, Icons.home_rounded, 'Home'),
          view: const HomeView(),
        ),
      (
        tab: AppTab.map,
        item: const NavItem(Icons.map_outlined, Icons.map_rounded, 'Map'),
        view: isStaff ? const MapTabView() : const MyMapTabView(),
      ),
      if (!isStaff)
        (
          tab: AppTab.documents,
          item: const NavItem(Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded, 'Documents'),
          view: const DocumentsView(),
        ),
      if (!isStaff)
        (
          tab: AppTab.resources,
          item: const NavItem(Icons.menu_book_outlined, Icons.menu_book_rounded, 'Resources'),
          view: const ResourcesView(),
        ),
      // Organization-wide numbers are for admin accounts only.
      if (isAdmin)
        (
          tab: AppTab.analytics,
          item: const NavItem(Icons.insights_outlined, Icons.insights_rounded, 'Analytics'),
          view: const AnalyticsView(),
        ),
      (
        tab: AppTab.me,
        item: const NavItem(Icons.person_outline_rounded, Icons.person_rounded, 'Me'),
        view: const SettingsView(),
      ),
    ];

    var index = tabs.indexWhere((t) => t.tab == nav.current);
    if (index < 0) index = 0;

    return Scaffold(
      extendBody: true,
      body: Column(
        children: [
          if (previewing) _PreviewBanner(view: view, onExit: () => context.read<AppState>().viewAs(AppView.admin)),
          Expanded(
            // The banner already covers the status bar, so the screens below don't leave room for it again.
            child: MediaQuery.removePadding(
              context: context,
              removeTop: previewing,
              child: Stack(
                children: [
                  IndexedStack(index: index, children: [for (final t in tabs) t.view]),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: BottomNavBar(
                      items: [for (final t in tabs) t.item],
                      selectedIndex: index,
                      onSelected: (i) => nav.go(tabs[i].tab),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Always visible while an admin is previewing, so it's never unclear that this
/// isn't their own view, and there's a one-tap way back.
class _PreviewBanner extends StatelessWidget {
  final AppView view;
  final VoidCallback onExit;
  const _PreviewBanner({required this.view, required this.onExit});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('preview-banner'),
      width: double.infinity,
      color: Brand.amber,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
          child: Row(
            children: [
              const Icon(Icons.visibility_rounded, size: 18, color: Color(0xFF3A2A00)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Previewing as ${view.label}',
                  style: const TextStyle(color: Color(0xFF3A2A00), fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ),
              TextButton(
                key: const Key('exit-preview'),
                onPressed: onExit,
                style: TextButton.styleFrom(foregroundColor: const Color(0xFF3A2A00)),
                child: const Text('Exit preview', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
