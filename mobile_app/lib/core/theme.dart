import 'package:flutter/material.dart';

/// Brand colours sampled from the Smart System logo.
class AppColors {
  static const Color indigo = Color(0xFF2E3192); // "SMART SYSTEM" wordmark
  static const Color blue = Color(0xFF4478B5); // cloud gradient (middle)
  static const Color cyan = Color(0xFF59BAD5); // cloud gradient (light)
  static const Color navy = Color(0xFF1B1D4F);

  static const Color background = Color(0xFFF4F6FB);
  static const Color surface = Colors.white;
  static const Color border = Color(0xFFE3E7F0);
  static const Color text = Color(0xFF1A1C3A);
  static const Color muted = Color(0xFF6B7280);
  static const Color subtle = Color(0xFF9CA3AF);

  static const Color success = Color(0xFF15803D);
  static const Color successBg = Color(0xFFDCFCE7);
  static const Color warning = Color(0xFFB45309);
  static const Color warningBg = Color(0xFFFEF3C7);
  static const Color danger = Color(0xFFDC2626);
  static const Color dangerBg = Color(0xFFFEE2E2);
  static const Color info = Color(0xFF1D4ED8);
  static const Color infoBg = Color(0xFFDBEAFE);
  static const Color indigoBg = Color(0xFFE8E9F7);
  static const Color cyanBg = Color(0xFFE0F4FA);
  static const Color greyBg = Color(0xFFF1F3F7);

  static const Color shadow = Color(0x142E3192); // indigo @ 8%
  static const Color overlayWhite20 = Color(0x33FFFFFF);
  static const Color overlayWhite12 = Color(0x1FFFFFFF);
  static const Color overlayWhite70 = Color(0xB3FFFFFF);

  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [indigo, blue, cyan],
    stops: [0.0, 0.62, 1.0],
  );
}

class AppTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.indigo,
      primary: AppColors.indigo,
      secondary: AppColors.blue,
      tertiary: AppColors.cyan,
      surface: AppColors.surface,
      error: AppColors.danger,
      brightness: Brightness.light,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      splashFactory: InkRipple.splashFactory,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.text,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.text,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.indigo,
          foregroundColor: Colors.white,
          minimumSize: const Size(64, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.indigo,
          minimumSize: const Size(64, 48),
          side: const BorderSide(color: AppColors.border, width: 1.4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.indigo,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.indigo,
        foregroundColor: Colors.white,
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      dividerColor: AppColors.border,
    );
  }
}
