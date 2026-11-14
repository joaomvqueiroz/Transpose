import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'player_presets.dart';

/// The song playing a moment ago (video, place, tone, speed, A–B), kept so
/// it can be continued after the app was closed — by the user, by Android
/// in the background, or by a crash.
class LastSong {
  LastSong({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;
  static const String _key = 'transpono.lastSong';

  /// Keeps [song] for the studio opened at [place] (the site's host).
  Future<void> remember(PlayerPreset song, String place) =>
      _preferences.setString(
        _key,
        jsonEncode(<String, Object?>{
          'song': song.toJson(),
          'place': place,
          'at': DateTime.now().millisecondsSinceEpoch,
        }),
      );

  /// The song kept for [place], if it is recent enough.
  Future<PlayerPreset?> read(
    String place, {
    Duration maxAge = const Duration(hours: 12),
  }) async {
    try {
      final String? raw = await _preferences.getString(_key);
      if (raw == null) return null;
      final Object? value = jsonDecode(raw);
      if (value is! Map<String, dynamic> || value['place'] != place) {
        return null;
      }
      final Object? at = value['at'];
      if (at is! int ||
          DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(at)) >
              maxAge) {
        return null;
      }
      return PlayerPreset.parse(value['song']);
    } on Object {
      return null;
    }
  }

  Future<void> forget() => _preferences.remove(_key);
}
