import 'package:flutter/foundation.dart';

enum AppTab { home, map, documents, me }

/// Which tab is showing. Shared so any screen can send the person somewhere
/// else in the app ("Add your documents" on Home jumps to the Documents tab).
class TabNav extends ChangeNotifier {
  AppTab current;
  TabNav({this.current = AppTab.home});

  void go(AppTab tab) {
    if (tab == current) return;
    current = tab;
    notifyListeners();
  }
}
