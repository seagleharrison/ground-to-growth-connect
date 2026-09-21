import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import 'consent_view.dart';
import 'documents_view.dart';
import 'map_tab_view.dart';
import 'my_map_tab_view.dart';
import 'settings_view.dart';

/// Direct equivalent of the native app's MainTabView in SettingsView.swift:
/// staff get the everyone-map; participants get Share, their own map, and
/// Documents. Settings is common to both.
class MainTabView extends StatefulWidget {
  const MainTabView({super.key});

  @override
  State<MainTabView> createState() => _MainTabViewState();
}

class _MainTabViewState extends State<MainTabView> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final isStaff = app.user?.isStaff == true;

    final tabs = <({String label, IconData icon, Widget view})>[
      if (isStaff) (label: 'Map', icon: Icons.map, view: const MapTabView()),
      if (!isStaff) (label: 'Share', icon: Icons.location_on, view: const ConsentView()),
      if (!isStaff) (label: 'Map', icon: Icons.map, view: const MyMapTabView()),
      if (!isStaff) (label: 'Documents', icon: Icons.lock_outline, view: const DocumentsView()),
      (label: 'Settings', icon: Icons.settings, view: const SettingsView()),
    ];

    final index = _index.clamp(0, tabs.length - 1);

    return Scaffold(
      body: IndexedStack(
        index: index,
        children: [for (final t in tabs) t.view],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final t in tabs) NavigationDestination(icon: Icon(t.icon), label: t.label),
        ],
      ),
    );
  }
}
