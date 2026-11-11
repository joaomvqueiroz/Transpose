import 'package:flutter/foundation.dart';

/// The page's text field (the YouTube search bar) has the focus.
final ValueNotifier<bool> pageInputFocused = ValueNotifier<bool>(false);

/// The studio's adjustments are fully up, covering the video.
final ValueNotifier<bool> adjustmentsCoverScreen = ValueNotifier<bool>(false);

/// The user last scrolled the page down (reading on): the floating "Abrir
/// ajustes" shrinks to a small arrow; scrolling up brings it back in full.
final ValueNotifier<bool> pageScrolledDown = ValueNotifier<bool>(false);

/// Android's picture-in-picture window is open (the studio shows only the
/// video). Mirrors `inPictureInPicture` (picture_in_picture.dart).
final ValueNotifier<bool> pictureInPictureShown = ValueNotifier<bool>(false);

/// YouTube shows its "Toque para ativar o som" button over the video (a muted
/// start): the start-screen button sits in the same corner and gives way.
final ValueNotifier<bool> pageUnmutePrompt = ValueNotifier<bool>(false);

/// Where the YouTube site's own bars are, so the app's buttons sit inside
/// them like in the YouTube app: [pivot] is the centre of the bottom bar's tab
/// row, measured up from the bottom of the page (null: no bar with a free
/// middle slot); [topFree] says the top bar shows the logo and the search
/// icon, with room for the start-screen button next to it; [pivotX] is the
/// free slot's centre from the left (null: the middle of the page); [hidden]
/// says both bars slid away because the page was scrolled down, and the app's
/// buttons go with them; [topRight] from
/// the right edge (the width taken by the site's own icons).
typedef YouTubeBars = ({
  double? pivot,
  double? pivotX,
  bool topFree,
  double topRight,
  bool hidden,
  bool topAway,
  bool homeInPage,
  bool searching,
  bool shorts,
  bool music,
  String avatar,
  String tab,
  bool dark,
});

/// iPhone with the system's glass (iOS 26): the bottom bar is drawn natively
/// above the page (glass_bar.dart); the page's own bar and the app's Flutter
/// buttons in it stay out of sight.
final ValueNotifier<bool> nativeGlassBar = ValueNotifier<bool>(false);

/// The home-screen search widget was tapped: the YouTube page opens its
/// search field as soon as it is ready (set back to false when done).
final ValueNotifier<bool> pendingPageSearch = ValueNotifier<bool>(false);

/// Taps on the start-screen icon the page draws in its own top bar
/// ([YouTubeBars.homeInPage]): each one adds one.
final ValueNotifier<int> pageHomeRequests = ValueNotifier<int>(0);

/// YouTube Music's song tabs (A seguir, Letra, ...) under its player, drawn
/// by the app: their names, which can be opened, and the opened one (-1:
/// none, the player shows).
typedef SongTabs = ({List<String> labels, List<bool> enabled, int selected});

final ValueNotifier<SongTabs?> musicSongTabs = ValueNotifier<SongTabs?>(null);

SongTabs? songTabsFromState(Object? raw) {
  if (raw is! Map) return null;
  final Object? labels = raw['labels'];
  if (labels is! List || labels.isEmpty || labels.length > 8) return null;
  final List<String> names = [
    for (final Object? label in labels) label is String ? label : '',
  ];
  final Object? enabled = raw['enabled'];
  final Object? selected = raw['selected'];
  return (
    labels: names,
    enabled: [
      for (int i = 0; i < names.length; i++)
        !(enabled is List && i < enabled.length && enabled[i] == false),
    ],
    selected: selected is num && selected >= 0 && selected < names.length
        ? selected.toInt()
        : -1,
  );
}

bool sameSongTabs(SongTabs? a, SongTabs? b) => a == null || b == null
    ? a == b
    : a.selected == b.selected &&
          listEquals(a.labels, b.labels) &&
          listEquals(a.enabled, b.enabled);

final ValueNotifier<YouTubeBars?> pageYouTubeBars = ValueNotifier<YouTubeBars?>(
  null,
);

YouTubeBars? youTubeBarsFromState(Object? raw) {
  if (raw is! Map) return null;
  final Object? pivot = raw['pivot'];
  return (
    pivot: pivot is num && pivot.isFinite && pivot > 0 && pivot < 400
        ? pivot.toDouble()
        : null,
    pivotX: switch (raw['pivotX']) {
      final num x when x.isFinite && x > 0 && x < 4000 => x.toDouble(),
      _ => null,
    },
    topFree: raw['topFree'] == true,
    hidden: raw['hidden'] == true,
    topAway: raw['topAway'] == true,
    homeInPage: raw['homeInPage'] == true,
    searching: raw['searching'] == true,
    shorts: raw['shorts'] == true,
    music: raw['music'] == true,
    tab: switch (raw['tab']) {
      final String tab => tab,
      _ => '',
    },
    avatar: switch (raw['avatar']) {
      final String url when url.startsWith('https://') => url,
      _ => '',
    },
    topRight: switch (raw['topRight']) {
      final num right when right.isFinite && right >= 0 && right < 300 =>
        right.toDouble(),
      _ => 48,
    },
    dark: raw['dark'] != false,
  );
}

/// The page itself (Spotify's own bars) carries the button that opens the
/// adjustments: the app's wide "Abrir ajustes" stays out of the way.
final ValueNotifier<bool> pageDrawsAdjustButton = ValueNotifier<bool>(false);

/// The page itself shows the start-screen button in its top bar.
final ValueNotifier<bool> pageDrawsHomeButton = ValueNotifier<bool>(false);

/// Spotify's open player (the song's own screen) is up.
final ValueNotifier<bool> spotifyPlayerOpen = ValueNotifier<bool>(false);

/// Where Spotify's open player ends on its page, in the screen's own
/// pixels from the page's top (null without it): below it, down to the
/// screen's bottom, the page is black.
final ValueNotifier<double?> spotifyPlayerBottom = ValueNotifier<double?>(null);

/// The finger pulling Spotify's player up to show the adjustments under it:
/// how far it moved since the last call (positive: up), and when it lets go
/// its speed (positive: up). Set by the studio; called by the Spotify page.
void Function(double dy)? spotifyPullDrag;
void Function(double velocity)? spotifyPullEnd;

/// The page's own adjustments button was tapped (a counter).
final ValueNotifier<int> pageAdjustRequests = ValueNotifier<int>(0);

/// The floating "back to the start screen" button hides in these cases.
bool get hideHomeButton =>
    pageDrawsHomeButton.value ||
    pageInputFocused.value ||
    adjustmentsCoverScreen.value ||
    pictureInPictureShown.value ||
    pageUnmutePrompt.value ||
    pageYouTubeBars.value?.hidden == true ||
    // The top bar it sits in scrolled out of sight.
    pageYouTubeBars.value?.topAway == true;
