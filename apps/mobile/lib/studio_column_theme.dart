import 'package:flutter/material.dart';

import 'studio_appearance.dart';

/// Stitch-inspired monochrome controls scoped to the four adjustments tabs.
/// The embedded YouTube page keeps its own visual styling.
ThemeData studioColumnTheme(
  ThemeData base, {
  StudioAppearanceMode mode = StudioAppearanceMode.dark,
}) {
  final ThemeData theme = _studioColumnTheme(base, mode: mode);
  if (!studioSpotifySkin) return theme;
  // Spotify: its buttons are translucent white pills or outlined circles,
  // never dark blocks; its chips white when chosen.
  final Color fill = skinChip;
  return theme.copyWith(
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        disabledForegroundColor: const Color(0x80FFFFFF),
        backgroundColor: fill,
        disabledBackgroundColor: const Color(0x0DFFFFFF),
        side: BorderSide.none,
        shape: studioYouTubeSkin
            ? const StadiumBorder()
            : const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: fill,
        shape: const StadiumBorder(),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        foregroundColor: skinChipOnInk,
        backgroundColor: skinChipOn,
        disabledBackgroundColor: fill,
        shape: const StadiumBorder(),
      ),
    ),
    chipTheme: theme.chipTheme.copyWith(
      backgroundColor: fill,
      selectedColor: skinChipOn,
      side: BorderSide.none,
      shape: skinChipShape,
      labelStyle: const TextStyle(color: Colors.white),
      secondaryLabelStyle: const TextStyle(color: Colors.black),
      checkmarkColor: Colors.black,
    ),
    sliderTheme: theme.sliderTheme.copyWith(
      activeTrackColor: skinAccent,
      inactiveTrackColor: const Color(0x33FFFFFF),
      thumbColor: skinAccent,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? skinSwitch
            : const Color(0x4DFFFFFF),
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
  );
}

ThemeData _studioColumnTheme(
  ThemeData base, {
  StudioAppearanceMode mode = StudioAppearanceMode.dark,
}) {
  if (base.brightness == Brightness.light) {
    const ink = Color(0xFF193244);
    const panel = Color(0xFFFFFFFF);
    const border = Color(0xFFB7C4D2);
    final scheme = base.colorScheme.copyWith(
      primary: ink,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFDCEBF3),
      onPrimaryContainer: ink,
      secondaryContainer: const Color(0xFFE8EEF4),
      onSecondaryContainer: ink,
      surface: panel,
      onSurface: const Color(0xFF182636),
      outline: border,
    );
    return base.copyWith(
      colorScheme: scheme,
      cardColor: panel,
      cardTheme: const CardThemeData(
        color: panel,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(24)),
          side: BorderSide(color: border),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          backgroundColor: const Color(0xFFE8EEF4),
          side: const BorderSide(color: border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: ink),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: ink,
        ),
      ),
      sliderTheme: base.sliderTheme.copyWith(
        activeTrackColor: ink,
        inactiveTrackColor: border,
        thumbColor: ink,
      ),
    );
  }
  const muted = Color(0xFFA1A1AA);
  final control = mode == StudioAppearanceMode.glass
      ? const Color(0x2EFFFFFF)
      : const Color(0xFF2A2A2C);
  const controlBorder = Color(0xFF444447);
  final panel = mode == StudioAppearanceMode.glass
      ? const Color(0x991B222B)
      : const Color(0xFF1B1B1D);
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
    cardTheme: CardThemeData(
      color: panel,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(24)),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        disabledForegroundColor: muted,
        backgroundColor: const Color(0xFF232326),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        foregroundColor: const Color(0xFF161618),
        backgroundColor: Colors.white,
        disabledBackgroundColor: control,
        disabledForegroundColor: muted,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
