import 'package:flutter/material.dart';

/// One dark theme for every screen. Neutral black, one blue accent,
/// and green / amber / red only for value.
class EdgeColors {
  static const background = Color(0xFF0B0B0D);
  static const surface = Color(0xFF1C1C1E);
  static const surfaceHigh = Color(0xFF2C2C2E);
  static const border = Color(0xFF3A3A3C);
  static const text = Color(0xFFF2F2F7);
  static const textSecondary = Color(0xFFAEAEB2);
  static const textTertiary = Color(0xFF8E8E93);
  static const accent = Color(0xFF0A84FF);
  static const good = Color(0xFF30D158);
  static const warn = Color(0xFFFFD60A);
  static const bad = Color(0xFFFF453A);
  static const onAccent = Color(0xFFFFFFFF);
}

/// Four sizes, used everywhere: 34, 22, 17, 15.
class EdgeType {
  static const display = TextStyle(
    fontSize: 34,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.6,
    height: 1.1,
    color: EdgeColors.text,
  );
  static const title = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    height: 1.2,
    color: EdgeColors.text,
  );
  static const body = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: EdgeColors.text,
  );
  static const label = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: EdgeColors.textSecondary,
  );
}

class EdgeSpace {
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const page = 20.0;
  static const radius = 16.0;
  static const tap = 48.0;
}

/// Kept so older call sites compile. Accent is chrome, not a value color.
const mint = EdgeColors.accent;
const panel = EdgeColors.surface;

ThemeData edgeTheme() {
  const scheme = ColorScheme.dark(
    primary: EdgeColors.accent,
    onPrimary: EdgeColors.onAccent,
    secondary: EdgeColors.accent,
    onSecondary: EdgeColors.onAccent,
    surface: EdgeColors.surface,
    onSurface: EdgeColors.text,
    error: EdgeColors.bad,
    onError: EdgeColors.onAccent,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: EdgeColors.background,
    colorScheme: scheme,
    fontFamily: 'Segoe UI',
    textTheme: const TextTheme(
      displayLarge: EdgeType.display,
      headlineMedium: EdgeType.title,
      titleLarge: EdgeType.title,
      titleMedium: EdgeType.body,
      bodyLarge: EdgeType.body,
      bodyMedium: EdgeType.body,
      bodySmall: EdgeType.label,
      labelLarge: EdgeType.label,
    ),
    iconTheme: const IconThemeData(color: EdgeColors.text, size: 22),
    dividerColor: EdgeColors.border,
    splashFactory: InkRipple.splashFactory,
    appBarTheme: const AppBarTheme(
      backgroundColor: EdgeColors.background,
      foregroundColor: EdgeColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: EdgeType.title,
    ),
    cardTheme: const CardThemeData(
      color: EdgeColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(EdgeSpace.radius)),
        side: BorderSide(color: EdgeColors.border),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: EdgeColors.accent,
      textColor: EdgeColors.text,
      titleTextStyle: EdgeType.body,
      subtitleTextStyle: EdgeType.label,
      minVerticalPadding: 12,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: EdgeColors.surfaceHigh,
      labelStyle: EdgeType.label,
      hintStyle: EdgeType.label,
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(color: EdgeColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(color: EdgeColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(color: EdgeColors.accent, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: EdgeColors.accent,
        foregroundColor: EdgeColors.onAccent,
        minimumSize: const Size(48, EdgeSpace.tap),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        textStyle: EdgeType.body.copyWith(fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: EdgeColors.accent,
        minimumSize: const Size(48, EdgeSpace.tap),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        textStyle: EdgeType.body.copyWith(fontWeight: FontWeight.w600),
        side: const BorderSide(color: EdgeColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: EdgeColors.accent,
        minimumSize: const Size(48, EdgeSpace.tap),
        textStyle: EdgeType.body.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: EdgeColors.surfaceHigh,
      selectedColor: EdgeColors.accent.withValues(alpha: .22),
      labelStyle: EdgeType.label.copyWith(color: EdgeColors.text),
      secondaryLabelStyle: EdgeType.label.copyWith(color: EdgeColors.accent),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      side: const BorderSide(color: EdgeColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: EdgeColors.accent,
      thumbColor: EdgeColors.accent,
      trackHeight: 4,
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 10),
      showValueIndicator: ShowValueIndicator.onDrag,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: EdgeColors.background,
      elevation: 0,
      height: 68,
      indicatorColor: EdgeColors.accent.withValues(alpha: .18),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return EdgeType.label.copyWith(
          fontSize: 13,
          color: selected ? EdgeColors.accent : EdgeColors.textSecondary,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? EdgeColors.accent : EdgeColors.textSecondary,
          size: 24,
        );
      }),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: EdgeColors.surface,
      titleTextStyle: EdgeType.title,
      contentTextStyle: EdgeType.body,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: EdgeColors.surfaceHigh,
      contentTextStyle: EdgeType.body,
      behavior: SnackBarBehavior.floating,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: EdgeColors.accent,
    ),
  );
}

Color valueColor(double? value) {
  if (value == null || value == 0) return EdgeColors.textSecondary;
  return value > 0 ? EdgeColors.good : EdgeColors.bad;
}
