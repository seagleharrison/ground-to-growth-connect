import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

/// Brand colors and the one dark theme the whole app uses. Everything visual
/// (cards, buttons, maps) pulls from here so the app looks like one thing.
class Brand {
  Brand._();

  static const orange = Color(0xFFFFB578);
  static const orangeDeep = Color(0xFFFF8A3D);
  static const green = Color(0xFF34C759);
  static const blue = Color(0xFF4DA3FF);
  static const amber = Color(0xFFFFC94D);
  static const red = Color(0xFFFF6B5E);

  // Neutral charcoal — no warm/brown tint. Orange is only ever an accent.
  static const background = Color(0xFF0B0D11);
  static const surface = Color(0xFF15181E);
  static const surfaceHigh = Color(0xFF1F232B);
  static const outline = Color(0xFF2C313B);

  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [orange, orangeDeep],
  );
}

ThemeData buildAppTheme() {
  // Built from a neutral dark scheme rather than seeded from orange, so no
  // Material default (chips, menus, dialogs) picks up a brown tint.
  final scheme = const ColorScheme.dark().copyWith(
    primary: Brand.orange,
    onPrimary: const Color(0xFF3A1D00),
    primaryContainer: Brand.surfaceHigh,
    onPrimaryContainer: Brand.orange,
    secondary: Brand.blue,
    secondaryContainer: Brand.surfaceHigh,
    onSecondaryContainer: Colors.white,
    surface: Brand.surface,
    onSurface: Colors.white,
    onSurfaceVariant: Colors.white60,
    surfaceContainerLowest: Brand.background,
    surfaceContainerLow: Brand.surface,
    surfaceContainer: Brand.surface,
    surfaceContainerHigh: Brand.surfaceHigh,
    surfaceContainerHighest: Brand.surfaceHigh,
    outline: Brand.outline,
    outlineVariant: Brand.outline,
    error: Brand.red,
  );

  final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: Brightness.dark);
  final text = base.textTheme;

  return base.copyWith(
    scaffoldBackgroundColor: Brand.background,
    textTheme: text.copyWith(
      headlineLarge: text.headlineLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.8),
      headlineMedium: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.6),
      headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Brand.surfaceHigh,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Brand.orange, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Brand.red, width: 1.5),
      ),
      labelStyle: const TextStyle(color: Colors.white60),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: text.labelLarge?.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        side: const BorderSide(color: Brand.outline, width: 1.5),
        textStyle: text.labelLarge?.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Brand.surfaceHigh,
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Brand.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    dividerTheme: const DividerThemeData(color: Brand.outline, space: 1),
    chipTheme: ChipThemeData(
      backgroundColor: Brand.surfaceHigh,
      selectedColor: Brand.orange.withValues(alpha: 0.22),
      side: const BorderSide(color: Brand.outline),
      labelStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      checkmarkColor: Brand.orange,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Brand.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
    }),
  );
}
