import 'package:flutter/foundation.dart';

/// The page's text field (the YouTube search bar) has the focus.
final ValueNotifier<bool> pageInputFocused = ValueNotifier<bool>(false);

/// The studio's adjustments are fully up, covering the video.
final ValueNotifier<bool> adjustmentsCoverScreen = ValueNotifier<bool>(false);

/// The floating "back to the start screen" button hides in both cases.
bool get hideHomeButton =>
    pageInputFocused.value || adjustmentsCoverScreen.value;
