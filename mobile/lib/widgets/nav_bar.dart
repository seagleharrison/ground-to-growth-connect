import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

class NavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  const NavItem(this.icon, this.selectedIcon, this.label);
}

/// A frosted bottom bar that runs edge to edge — flush with the sides and the
/// bottom of the screen, including under the home indicator — so nothing shows
/// around it. Every tab keeps its label visible: icons alone are easy to
/// misread, and this app is for everyone.
class BottomNavBar extends StatelessWidget {
  final List<NavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const BottomNavBar({super.key, required this.items, required this.selectedIndex, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Brand.background.withValues(alpha: 0.88),
            border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: Row(
                children: [
                  for (final (i, item) in items.indexed)
                    Expanded(
                      child: _NavButton(
                        item: item,
                        selected: i == selectedIndex,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onSelected(i);
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final NavItem item;
  final bool selected;
  final VoidCallback onTap;

  const _NavButton({required this.item, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: selected ? Brand.orange.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: selected ? 1.12 : 1,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutBack,
              child: Icon(
                selected ? item.selectedIcon : item.icon,
                size: 25,
                color: selected ? Brand.orange : Colors.white60,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? Brand.orange : Colors.white60,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
