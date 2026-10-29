import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// White-based palette for Bingo Online. Typography and CJK font fallback are
/// shared with tier-online so both services look related when merged.
abstract final class BingoColors {
  static const background = Colors.white;
  static const surface = Color(0xFFF6F7FA);
  static const surfaceStrong = Color(0xFFEDEFF4);
  static const outline = Color(0xFFE1E4EB);
  static const ink = Color(0xFF1B1C22);
  static const inkMuted = Color(0xFF656B78);
  static const primary = Color(0xFFF2552C);
  static const primarySoft = Color(0xFFFFE9E2);
  static const gold = Color(0xFFFFB400);
  static const goldSoft = Color(0xFFFFF4D6);
  static const blue = Color(0xFF2F6BFF);
  static const blueSoft = Color(0xFFE6EEFF);
  static const marked = Color(0xFFFF7A50);
  static const line = Color(0xFFFFB400);
}

ThemeData buildBingoTheme() {
  const scheme = ColorScheme.light(
    primary: BingoColors.primary,
    onPrimary: Colors.white,
    primaryContainer: BingoColors.primarySoft,
    onPrimaryContainer: Color(0xFF5A1600),
    secondary: BingoColors.blue,
    secondaryContainer: BingoColors.blueSoft,
    tertiary: BingoColors.gold,
    surface: BingoColors.background,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: BingoColors.surface,
    surfaceContainer: BingoColors.surface,
    surfaceContainerHigh: BingoColors.surfaceStrong,
    onSurface: BingoColors.ink,
    onSurfaceVariant: BingoColors.inkMuted,
    outline: BingoColors.outline,
    outlineVariant: BingoColors.outline,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: scheme,
    fontFamilyFallback: appFontFamilyFallback,
  );
  return base.copyWith(
    scaffoldBackgroundColor: BingoColors.background,
    textTheme: base.textTheme.apply(
      bodyColor: BingoColors.ink,
      displayColor: BingoColors.ink,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: BingoColors.background,
      foregroundColor: BingoColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: BingoColors.outline),
      ),
    ),
    dividerTheme: const DividerThemeData(color: BingoColors.outline),
    navigationBarTheme: NavigationBarThemeData(
      height: 66,
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: BingoColors.primarySoft,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w800
              : FontWeight.w600,
        ),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: BingoColors.surface,
      side: const BorderSide(color: BingoColors.outline),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: BingoColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: BingoColors.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: BingoColors.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: BingoColors.primary, width: 1.6),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 44),
        side: const BorderSide(color: BingoColors.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: BingoColors.ink,
      contentTextStyle: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w700,
      ),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: BingoColors.ink,
      unselectedLabelColor: BingoColors.inkMuted,
      indicatorColor: BingoColors.primary,
      labelStyle: TextStyle(fontWeight: FontWeight.w800),
      dividerColor: BingoColors.outline,
    ),
  );
}
