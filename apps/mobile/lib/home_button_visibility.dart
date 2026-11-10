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

/// The floating "back to the start screen" button hides in these cases.
bool get hideHomeButton =>
    pageInputFocused.value ||
    adjustmentsCoverScreen.value ||
    pictureInPictureShown.value ||
    pageUnmutePrompt.value;
