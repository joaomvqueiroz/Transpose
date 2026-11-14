import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  /// A button of the small window was pressed: "play" (play or pause),
  /// "back" or "forward" (10 seconds).
  static void Function(String name)? onAction;

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static void _listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'pipChanged') {
        inPictureInPicture.value = call.arguments == true;
        pictureInPictureShown.value = inPictureInPicture.value;
      } else if (call.method == 'pipAction' && call.arguments is String) {
        onAction?.call(call.arguments as String);
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

/// iPhone, experimental (Ajustes → Mais): leaving the app shows the video
/// in the system's small window. The page copies the video's frames to the
/// app (only the playing video's page, only while this is on); the app
/// shows them in iOS's picture-in-picture. Off unless turned on.
final ValueNotifier<bool> iosSmallWindow = ValueNotifier<bool>(false);

abstract final class IosSmallWindow {
  static const String _key = 'transpono_ios_small_window';
  static bool _loaded = false;

  /// Whether this build can offer it (iPhone).
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static Future<void> load() async {
    if (_loaded || !supported) return;
    _loaded = true;
    try {
      iosSmallWindow.value =
          await SharedPreferencesAsync().getBool(_key) ?? false;
    } on Object {
      // No preferences: stays off.
    }
  }

  static void set(bool on) {
    iosSmallWindow.value = on;
    unawaited(
      SharedPreferencesAsync().setBool(_key, on).catchError((Object _) {}),
    );
  }
}
