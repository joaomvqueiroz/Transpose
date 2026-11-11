import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'home_button_visibility.dart';

/// iPhone (iOS 26): the bottom bar over the YouTube pages is the system's own
/// glass, drawn natively above the page (SceneDelegate.swift, channel
/// `transpono/glass_bar`). Nothing happens on other platforms or systems.
abstract final class GlassBar {
  static const MethodChannel _channel = MethodChannel('transpono/glass_bar');
  static void Function(String name)? _onTap;
  static String? _sent;
  static bool _asked = false;

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Asks once whether the system has the glass; sets [nativeGlassBar].
  static Future<void> checkAvailable() async {
    if (!_supported || _asked) return;
    _asked = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'tap' && call.arguments is String) {
        _onTap?.call(call.arguments as String);
      }
      return null;
    });
    try {
      nativeGlassBar.value =
          await _channel.invokeMethod<bool>('available') ?? false;
    } on Object {
      nativeGlassBar.value = false;
    }
  }

  static void attach(void Function(String name) onTap) => _onTap = onTap;

  /// Whether [onTap] is the one the bar talks to now (a page that is leaving
  /// must not hide a bar the next page already took over).
  static bool isAttached(void Function(String name) onTap) => _onTap == onTap;

  static void detach(void Function(String name) onTap) {
    if (_onTap == onTap) _onTap = null;
  }

  /// The icons the system has no symbol for (PNG, 3x): name → bytes.
  static Future<void> setIcons(Map<String, Uint8List> icons) async {
    if (!nativeGlassBar.value) return;
    try {
      await _channel.invokeMethod<void>('icons', icons);
    } on Object {
      // The bar keeps the system's stand-in symbol.
    }
  }

  /// Shakes one of the bar's buttons: "not now".
  static void shake(String name) {
    if (!nativeGlassBar.value) return;
    unawaited(
      _channel.invokeMethod<void>('shake', name).catchError((Object _) {}),
    );
  }

  static void update({
    required bool visible,
    String selected = '',
    String avatar = '',
    bool dark = true,
    bool music = false,
  }) {
    if (!nativeGlassBar.value) return;
    final String state = '$visible|$selected|$avatar|$dark|$music';
    if (state == _sent) return;
    _sent = state;
    unawaited(
      _channel
          .invokeMethod<void>('update', <String, Object>{
            'visible': visible,
            'selected': selected,
            'avatar': avatar,
            'dark': dark,
            // YouTube Music: the second and fourth buttons are "explore"
            // and the library (still named "shorts" and "you" on the wire).
            'music': music,
          })
          .catchError((Object _) {}),
    );
  }
}
