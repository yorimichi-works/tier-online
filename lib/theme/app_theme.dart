import 'package:flutter/material.dart';

abstract final class AppColors {
  static const background = Color(0xFF0D0D0F);
  static const card = Color(0xFF17171B);
  static const elevated = Color(0xFF202025);
  static const outline = Color(0xFF34343D);
  static const purple = Color(0xFF8B7CFF);
  static const cyan = Color(0xFF5AC8D8);
}

/// Local CJK coverage first, followed by platform fonts for uncommon glyphs.
///
/// Both local subsets contain all strings shipped by the app. The Japanese
/// subset also contains the Joyo Kanji set and the Korean subset contains all
/// modern Hangul syllables. Platform fallbacks remain available for arbitrary
/// mixed-language user content and uncommon CJK variants.
const appFontFamilyFallback = <String>[
  'TierNotoSansJP',
  'TierNotoSansKR',
  'Noto Sans',
  'Noto Sans JP',
  'Noto Sans KR',
  'Noto Sans TC',
  'PingFang TC',
  'Microsoft JhengHei',
  'Yu Gothic',
  'YuGothic',
  'Yu Gothic UI',
  'Hiragino Kaku Gothic ProN',
  'Meiryo',
  'Apple SD Gothic Neo',
  'Malgun Gothic',
  'Arial',
  'Helvetica',
  'sans-serif',
];

ThemeData buildAppTheme() => buildDarkAppTheme();

ThemeData buildDarkAppTheme() {
  const scheme = ColorScheme.dark(
    primary: AppColors.purple,
    secondary: AppColors.cyan,
    surface: AppColors.card,
    onSurface: Color(0xFFF4F4F7),
    onSurfaceVariant: Color(0xFFA7A7B3),
    outline: AppColors.outline,
    error: Color(0xFFFF7180),
    onError: Color(0xFF2B0007),
    errorContainer: Color(0xFF4A1821),
    onErrorContainer: Color(0xFFFFE8EC),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    fontFamilyFallback: appFontFamilyFallback,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      color: AppColors.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.outline),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      backgroundColor: AppColors.card,
      indicatorColor: AppColors.purple.withValues(alpha: .2),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.elevated,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.purple, width: 1.4),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.elevated,
      contentTextStyle: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w700,
      ),
      actionTextColor: AppColors.cyan,
      closeIconColor: Colors.white,
    ),
  );
}

ThemeData buildLightAppTheme() {
  const scheme = ColorScheme.light(
    primary: Color(0xFF6558D9),
    secondary: Color(0xFF187887),
    surface: Colors.white,
    surfaceContainerHigh: Color(0xFFECEEF3),
    onSurface: Color(0xFF1A1B20),
    onSurfaceVariant: Color(0xFF626672),
    outline: Color(0xFFCCD0DA),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFFF5F6F9),
    fontFamilyFallback: appFontFamilyFallback,
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFFF5F6F9),
      foregroundColor: Color(0xFF1A1B20),
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFCCD0DA)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      backgroundColor: Colors.white,
      indicatorColor: const Color(0xFF6558D9).withValues(alpha: .16),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFECEEF3),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFCCD0DA)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFCCD0DA)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF6558D9), width: 1.4),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Color(0xFF292A31),
      contentTextStyle: TextStyle(color: Colors.white),
    ),
  );
}
