import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum StudioAppearanceMode { dark, light, glass }

class StudioAppearance {
  const StudioAppearance({
    this.mode = StudioAppearanceMode.dark,
    this.apple = false,
    this.noteColors = const {},
  });

  final StudioAppearanceMode mode;

  /// The "Apple" design: on top of the glass colours ([mode] is then
  /// [StudioAppearanceMode.glass]) the adjustments are a floating sheet of
  /// glass with a grabber and three heights, and no close button.
  final bool apple;
  final Map<int, Color> noteColors;

  StudioAppearance copyWith({
    StudioAppearanceMode? mode,
    bool? apple,
    Map<int, Color>? noteColors,
  }) => StudioAppearance(
    mode: mode ?? this.mode,
    apple: apple ?? this.apple,
    noteColors: noteColors ?? this.noteColors,
  );
}

class StudioAppearanceStore {
  StudioAppearanceStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const _key = 'transpono.appearance.v1';
  final SharedPreferencesAsync _preferences;

  Future<StudioAppearance> read() async {
    final raw = await _preferences.getString(_key);
    if (raw == null) return const StudioAppearance();
    try {
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic>) return const StudioAppearance();
      final mode = StudioAppearanceMode.values.firstWhere(
        (item) => item.name == data['mode'],
        orElse: () => StudioAppearanceMode.dark,
      );
      final colors = <int, Color>{};
      final encoded = data['noteColors'];
      if (encoded is Map) {
        for (final entry in encoded.entries) {
          final index = int.tryParse(entry.key.toString());
          final value = entry.value;
          if (index != null && index >= 0 && index < 12 && value is int) {
            colors[index] = Color(value);
          }
        }
      }
      return StudioAppearance(
        mode: mode,
        apple: data['apple'] == true && mode == StudioAppearanceMode.glass,
        noteColors: colors,
      );
    } on Object {
      return const StudioAppearance();
    }
  }

  Future<void> save(StudioAppearance value) => _preferences.setString(
    _key,
    jsonEncode({
      'mode': value.mode.name,
      'apple': value.apple,
      'noteColors': value.noteColors.map(
        (index, color) => MapEntry('$index', color.toARGB32()),
      ),
    }),
  );
}
