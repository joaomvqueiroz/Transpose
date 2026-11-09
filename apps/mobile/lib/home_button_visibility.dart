import 'package:flutter/foundation.dart';

/// The page's text field (the YouTube search bar) has the focus.
final ValueNotifier<bool> pageInputFocused = ValueNotifier<bool>(false);

/// The studio's adjustments are fully up, covering the video.
final ValueNotifier<bool> adjustmentsCoverScreen = ValueNotifier<bool>(false);

/// The user last scrolled the page down (reading on): the floating "Abrir
/// ajustes" shrinks to a small arrow; scrolling up brings it back in full.
final ValueNotifier<bool> pageScrolledDown = ValueNotifier<bool>(false);

/// The floating "back to the start screen" button hides in both cases.
bool get hideHomeButton =>
    pageInputFocused.value || adjustmentsCoverScreen.value;
