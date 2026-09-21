import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../nav.dart';
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
class MainTabView extends StatelessWidget {
  const MainTabView({super.key});

  @override
  Widget build(BuildContext context) {
    final isStaff = context.select<AppState, bool>((a) => a.user?.isStaff == true);
    final isAdmin = context.select<AppState, bool>((a) => a.user?.isAdmin == true);
    final nav = context.watch<TabNav>();

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
      body: Stack(
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
    );
  }
}
