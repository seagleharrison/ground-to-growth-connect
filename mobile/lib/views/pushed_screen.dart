import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A screen opened on top of the tabs (from Settings or Home) with a visible
/// back arrow, so nobody is left wondering how to get out.
class PushedScreen extends StatelessWidget {
  final String title;
  final Widget child;
  const PushedScreen({super.key, required this.title, required this.child});

  static Future<void> open(BuildContext context, {required String title, required Widget child}) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => PushedScreen(title: title, child: child)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Brand.background,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: child,
    );
  }
}
