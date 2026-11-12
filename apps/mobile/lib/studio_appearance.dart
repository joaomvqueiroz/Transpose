import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum StudioAppearanceMode { dark, light, glass }

/// The glass themes' cards are drawn darker ("Médio"). Set by
/// the studio from [StudioAppearance.darkPanels] before it builds its cards,
/// so that every card picks it up without being told one by one.
bool studioGlassDarkPanels = false;

class StudioAppearance {
  const StudioAppearance({
    this.mode = StudioAppearanceMode.dark,
    this.apple = false,
    this.darkPanels = false,
    this.native = false,
    this.noteColors = const {},
  });

  /// "Nativo": on YouTube the adjustments wear the YouTube app's own look.
  final bool native;

  final StudioAppearanceMode mode;

  /// The "Apple" design: on top of the glass colours ([mode] is then
  /// [StudioAppearanceMode.glass]) the adjustments are a floating sheet of
  /// glass with a grabber and three heights, and no close button.
  final bool apple;

  /// The mixed themes: the glass background stays as it is and the cards
  /// over it are darker. It is "Médio" (glass and dark).
  final bool darkPanels;
  final Map<int, Color> noteColors;

  StudioAppearance copyWith({
    StudioAppearanceMode? mode,
    bool? apple,
    bool? darkPanels,
    bool? native,
    Map<int, Color>? noteColors,
  }) => StudioAppearance(
    native: native ?? this.native,
    mode: mode ?? this.mode,
    apple: apple ?? this.apple,
    darkPanels: darkPanels ?? this.darkPanels,
    noteColors: noteColors ?? this.noteColors,
  );
}

class StudioAppearanceStore {
  StudioAppearanceStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const _key = 'transpono.appearance.v1';
  final SharedPreferencesAsync _preferences;

  /// The theme the app starts with: "Escuro", the dark glass.
  static const StudioAppearance standard = StudioAppearance(
    mode: StudioAppearanceMode.glass,
  );

  Future<StudioAppearance> read() async {
    final raw = await _preferences.getString(_key);
    if (raw == null) return standard;
    try {
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic>) return standard;
      // The old opaque dark theme is gone: it opens as the new "Escuro".
      final mode = data['mode'] == StudioAppearanceMode.light.name
          ? StudioAppearanceMode.light
          : StudioAppearanceMode.glass;
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
        // "Misto 2" is gone: a saved one opens as "Médio".
        apple:
            data['apple'] == true &&
            data['darkPanels'] != true &&
            mode == StudioAppearanceMode.glass,
        darkPanels:
            data['darkPanels'] == true && mode == StudioAppearanceMode.glass,
        native: data['native'] == true,
        noteColors: colors,
      );
    } on Object {
      return standard;
    }
  }

  Future<void> save(StudioAppearance value) => _preferences.setString(
    _key,
    jsonEncode({
      'mode': value.mode.name,
      'apple': value.apple,
      'darkPanels': value.darkPanels,
      'native': value.native,
      'noteColors': value.noteColors.map(
        (index, color) => MapEntry('$index', color.toARGB32()),
      ),
    }),
  );
}

/// On Spotify the adjustments wear Spotify's own look (its Encore tokens, read
/// from open.spotify.com): the colour of the song's cover fading into
/// #121212, flat translucent cards with 16 px corners, white text, green
/// accents. Set by the studio while Spotify is the source.
bool studioSpotifySkin = false;

/// The now-playing colour Spotify draws behind the song (from its cover).
Color spotifyTint = const Color(0xFF121212);

/// Spotify's own palette.
const Color spotifyBase = Color(0xFF121212);
const Color spotifyGreen = Color(0xFF1ED760);
const Color spotifyCard = Color(0x14FFFFFF);
const Color spotifySubdued = Color(0xFFB3B3B3);

/// Where Spotify's own gradient behind the song ends, at its bottom.
Color spotifyTintEnd = const Color(0xFF121212);

/// The sheet behind the cards: the cover's colour, darkened as Spotify does.
/// It is the colour of the page's last line, so the two meet seamlessly.
Color get spotifySheetColor => spotifyTintEnd;

/// With [studioSpotifySkin], the page skin is YouTube's ("Nativo") rather
/// than Spotify's: the same flat layout in the YouTube app's colours.
bool studioYouTubeSkin = false;

/// Spotify is the source (whatever the theme).
bool studioSpotifySource = false;

/// YouTube Music is the source: one page with the player, and the
/// adjustments come up from under it as the page is scrolled (as on
/// Spotify), whatever the theme.
bool studioMusicSource = false;

/// YouTube and YouTube Music in "Nativo": their adjustments are Spotify's
/// own panel (the flat Spotify look of [studioSpotifySkin], coming up from
/// under the player), in YouTube's red where Spotify has its green.
bool studioRedAccent = false;

/// The red YouTube uses for its own accents.
const Color youtubeRed = Color(0xFFFF0033);

/// Spotify's green, or YouTube's red with [studioRedAccent].
Color get skinGreen => studioRedAccent ? youtubeRed : spotifyGreen;

/// Text and icons over [skinGreen]: black on Spotify's green, white on
/// YouTube's red.
Color get skinGreenInk => studioRedAccent ? Colors.white : Colors.black;

/// The skins' palette: Spotify's, or the YouTube app's.
Color get skinChip =>
    studioYouTubeSkin ? const Color(0xFF272727) : const Color(0x1AFFFFFF);
Color get skinChipOn =>
    studioYouTubeSkin ? const Color(0xFFF1F1F1) : const Color(0xFFFFFFFF);
Color get skinChipOnInk =>
    studioYouTubeSkin ? const Color(0xFF0F0F0F) : const Color(0xFF000000);
Color get skinAccent =>
    studioYouTubeSkin ? const Color(0xFFFF0033) : skinGreen;
Color get skinSwitch =>
    studioYouTubeSkin ? const Color(0xFF3EA6FF) : skinGreen;
Color get skinSubdued =>
    studioYouTubeSkin ? const Color(0xFFAAAAAA) : const Color(0xBFFFFFFF);
Color get skinCard => studioYouTubeSkin ? const Color(0x00000000) : spotifyCard;
const Color youtubeBase = Color(0xFF0F0F0F);
OutlinedBorder get skinChipShape => studioYouTubeSkin
    ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
    : const StadiumBorder();

/// A section's title: Spotify's small capitals, or YouTube's bold line.
Text skinLabel(String text, {Key? key}) => Text(
  studioYouTubeSkin ? text : text.toUpperCase(),
  key: key,
  maxLines: 1,
  overflow: TextOverflow.ellipsis,
  style: studioYouTubeSkin
      ? const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: Color(0xFFF1F1F1),
        )
      : const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: .96,
          color: Color(0xBFFFFFFF),
        ),
);

/// The fill and the border of the small cards that are not drawn with the
/// panel gradient (the practice tools): the same glass as the big cards.
Color studioGlassToolFill() => studioSpotifySkin
    ? skinCard
    : studioGlassDarkPanels
    ? const Color(0xAD181C23)
    : const Color(0xC70E1116);

Color studioGlassToolBorder() => studioSpotifySkin
    ? const Color(0x00000000)
    : studioGlassDarkPanels
    ? const Color(0x55E4F8FF)
    : const Color(0x44E4F8FF);
