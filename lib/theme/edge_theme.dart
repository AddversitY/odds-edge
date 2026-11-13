import 'package:flutter/material.dart';

/// Night-ledger ink with a chartreuse mark. Green, amber, and coral
/// are reserved for the value check, not for the wordmark.
class EdgeColors {
  static const background = Color(0xFF100E0C);
  static const surface = Color(0xFF1B1814);
  static const surfaceHigh = Color(0xFF28231D);
  static const border = Color(0xFF3A332B);
  static const text = Color(0xFFF7F2E9);
  static const textSecondary = Color(0xFFC9BBA9);
  static const textTertiary = Color(0xFF8F8274);
  static const accent = Color(0xFFD6F25C);
  static const good = Color(0xFF3DDB9A);
  static const warn = Color(0xFFE6B15A);
  static const bad = Color(0xFFFF6E5A);
  static const onAccent = Color(0xFF17140A);
}

class EdgeFont {
  static const sans = 'Outfit';
  static const display = 'Fraunces';
}

/// Four sizes, used everywhere: 34, 22, 17, 15.
class EdgeType {
  static const display = TextStyle(
    fontFamily: EdgeFont.display,
    fontSize: 34,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.8,
    height: 1.05,
    color: EdgeColors.text,
  );
  static const title = TextStyle(
    fontFamily: EdgeFont.sans,
    fontSize: 22,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.4,
    height: 1.2,
    color: EdgeColors.text,
  );
  static const body = TextStyle(
    fontFamily: EdgeFont.sans,
    fontSize: 17,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: EdgeColors.text,
  );
  static const label = TextStyle(
    fontFamily: EdgeFont.sans,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: EdgeColors.textSecondary,
  );
  static const number = TextStyle(
    fontFamily: EdgeFont.display,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.6,
    fontFeatures: [FontFeature.tabularFigures()],
    color: EdgeColors.text,
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
    fontFamily: EdgeFont.sans,
    fontFamilyFallback: const ['Segoe UI', 'sans-serif'],
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
        borderRadius: BorderRadius.all(Radius.circular(18)),
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
