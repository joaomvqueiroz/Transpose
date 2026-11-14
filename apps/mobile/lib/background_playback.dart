import 'package:flutter/services.dart';

/// The song in the background: on Android a media notification and the
/// lock-screen controls, like Spotify's own app (BackgroundPlaybackService.kt);
/// on the iPhone the lock screen, Control Center and headphone buttons
/// (TransponoBackground in AppDelegate.swift). Taps on them, and headphones
/// being unplugged ("pause"), come back to [onAction].
class BackgroundPlayback {
  static const MethodChannel _channel = MethodChannel('transpono/background');

  static String? _lastKey;
  static DateTime _lastSent = DateTime.fromMillisecondsSinceEpoch(0);
  static bool _shown = false;

  /// "play", "pause", "next", "previous" or "seek:" followed by milliseconds.
  static void listen(void Function(String action) onAction) {
    _owner = onAction;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'action' && call.arguments is String) {
        onAction(call.arguments as String);
      }
    });
  }

  static void Function(String action)? _owner;

  /// Stops listening, only if [onAction] is still the one listening: when
  /// the source changes the new studio starts listening before the old one
  /// is closed, and the old one used to switch the new one's controls off.
  static void unlisten([void Function(String action)? onAction]) {
    if (onAction != null && _owner != onAction) return;
    _owner = null;
    _channel.setMethodCallHandler(null);
  }

  /// Sent when the song or play/pause changes, and every few seconds for
  /// the position.
  static Future<void> update({
    required String title,
    required String artist,
    required bool playing,
    required Duration position,
    required Duration duration,
    double speed = 1,
  }) async {
    final String key = '$title|$artist|$playing|$speed';
    final DateTime now = DateTime.now();
    if (key == _lastKey && now.difference(_lastSent).inSeconds < 5) return;
    if (!_shown && !playing) return;
    _lastKey = key;
    _lastSent = now;
    _shown = true;
    try {
      await _channel.invokeMethod<void>('update', {
        'title': title,
        'artist': artist,
        'playing': playing,
        'position': position.inMilliseconds,
        'duration': duration.inMilliseconds,
        'speed': speed,
      });
    } on Object {
      // No notification on this system: the song still plays.
    }
  }

  static Future<void> stop() async {
    if (!_shown) return;
    _shown = false;
    _lastKey = null;
    try {
      await _channel.invokeMethod<void>('stop');
    } on Object {
      // Nothing shown.
    }
  }
}
