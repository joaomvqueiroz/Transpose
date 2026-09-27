import 'package:flutter/material.dart';

/// Stitch-inspired monochrome controls scoped to the four adjustments tabs.
/// The embedded YouTube page keeps its own visual styling.
ThemeData studioColumnTheme(ThemeData base) {
  const muted = Color(0xFFA1A1AA);
  const control = Color(0xFF2A2A2C);
  const controlBorder = Color(0xFF444447);
  const panel = Color(0xFF1B1B1D);
  final scheme = base.colorScheme.copyWith(
    primary: Colors.white,
    onPrimary: const Color(0xFF161618),
    primaryContainer: const Color(0xFF353437),
    onPrimaryContainer: Colors.white,
    secondary: const Color(0xFFC6C6CF),
    onSecondary: const Color(0xFF1B1B1D),
    secondaryContainer: control,
    onSecondaryContainer: Colors.white,
    surface: panel,
    onSurface: const Color(0xFFF4F4F5),
    outline: controlBorder,
  );
  return base.copyWith(
    colorScheme: scheme,
    cardColor: panel,
    cardTheme: const CardThemeData(
      color: panel,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        side: BorderSide(color: Color(0xFF353537)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        disabledForegroundColor: muted,
        backgroundColor: control,
        disabledBackgroundColor: const Color(0xFF202022),
        side: const BorderSide(color: controlBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        disabledForegroundColor: muted,
        backgroundColor: const Color(0xFF232326),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        foregroundColor: const Color(0xFF161618),
        backgroundColor: Colors.white,
        disabledBackgroundColor: control,
        disabledForegroundColor: muted,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
    ),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: const Color(0xFFE6E6E9),
      inactiveTrackColor: const Color(0xFF414145),
      thumbColor: Colors.white,
      overlayColor: const Color(0x33FFFFFF),
      valueIndicatorColor: control,
      valueIndicatorTextStyle: const TextStyle(color: Colors.white),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? const Color(0xFF161618)
            : muted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Colors.white
            : const Color(0xFF353538),
      ),
    ),
  );
}
