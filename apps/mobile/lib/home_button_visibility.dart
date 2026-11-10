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
  String avatar,
  bool dark,
});

/// The home-screen search widget was tapped: the YouTube page opens its
/// search field as soon as it is ready (set back to false when done).
final ValueNotifier<bool> pendingPageSearch = ValueNotifier<bool>(false);

/// Taps on the start-screen icon the page draws in its own top bar
/// ([YouTubeBars.homeInPage]): each one adds one.
final ValueNotifier<int> pageHomeRequests = ValueNotifier<int>(0);

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

/// The floating "back to the start screen" button hides in these cases.
bool get hideHomeButton =>
    pageInputFocused.value ||
    adjustmentsCoverScreen.value ||
    pictureInPictureShown.value ||
    pageUnmutePrompt.value ||
    pageYouTubeBars.value?.hidden == true ||
    // The top bar it sits in scrolled out of sight.
    pageYouTubeBars.value?.topAway == true;
