import 'package:flutter/material.dart';

/// Cores do protótipo aprovado (vermelho da marca + grafite).
class LeoColors {
  static const red = Color(0xFFDA2A32);
  static const ink = Color(0xFF17181C);
  static const inkSoft = Color(0xFF24262C);
  static const inkLine = Color(0xFF3A3D45);
  static const ground = Color(0xFFF4F4F1);
  static const surface = Color(0xFFFFFFFF);
  static const muted = Color(0xFF5B5E66);
  static const text2 = Color(0xFF3F4249);
  static const line = Color(0xFFE2E2DD);
  static const field = Color(0xFFC9CBC3);
  static const segment = Color(0xFFE6E6E0);
  static const okBg = Color(0xFF24372D);
  static const okFg = Color(0xFF8FE0B2);
  static const offBg = Color(0xFF3A2A2C);
  static const offFg = Color(0xFFF2A3A7);
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: LeoColors.red,
      primary: LeoColors.red,
      onPrimary: Colors.white,
      surface: LeoColors.surface,
    ),
    scaffoldBackgroundColor: LeoColors.ground,
  );
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: const BorderSide(color: LeoColors.field),
  );
  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: LeoColors.ground,
      foregroundColor: LeoColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        color: LeoColors.ink,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: LeoColors.ink, width: 1.5),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.white : null,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? LeoColors.ink : null,
      ),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: LeoColors.ink,
      thumbColor: LeoColors.ink,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: LeoColors.segment,
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
