import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'home_button_visibility.dart';

/// The app is shown in Android's picture-in-picture window: the studio then
/// draws only the video.
final ValueNotifier<bool> inPictureInPicture = ValueNotifier<bool>(false);

/// Android picture-in-picture (MainActivity, channel `transpono/pip`): while a
/// YouTube video plays, leaving the app keeps it in the system's small
/// window. Nothing happens on other platforms.
abstract final class PictureInPicture {
  static const MethodChannel _channel = MethodChannel('transpono/pip');
  static bool _listening = false;
  static bool? _playing;

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static void _listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'pipChanged') {
        inPictureInPicture.value = call.arguments == true;
        pictureInPictureShown.value = inPictureInPicture.value;
      }
      return null;
    });
  }

  /// Tells Android whether leaving the app should open the small window.
  static Future<void> setVideoPlaying(bool playing) async {
    if (!_supported) return;
    _listen();
    if (_playing == playing) return;
    _playing = playing;
    try {
      await _channel.invokeMethod<void>('setVideoPlaying', playing);
    } on Object {
      // Older app builds without the channel: nothing to do.
    }
  }
}
