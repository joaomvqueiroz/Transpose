import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A widget shortcut asked for a listening source: "source:youtube",
/// "source:youtubeMusic", "source:soundCloud", "source:spotify" or "search".
/// The first screen (source picker) acts on it and sets it back to null.
final ValueNotifier<String?> widgetSourceRequest = ValueNotifier<String?>(null);

bool isWidgetSourceAction(String action) =>
    action == 'search' || action.startsWith('source:');

/// Mirrors acknowledged player state into Android launchers. Widget actions
/// always open the app; YouTube never plays from an invisible background view.
class HomeWidgetBridge {
  HomeWidgetBridge({required this.onAction});

  static const _channel = MethodChannel('transpose/home_widgets');

  /// The action the app was opened with, when it was not a source shortcut:
  /// kept for the studio, which is created after the first screen.
  static String? _launchAction;
  static bool _launchTaken = false;

  /// Source shortcuts work with or without a studio on screen: the first
  /// screen calls this once, and again whenever a studio's bridge goes away.
  static bool _sourcesWanted = false;

  static Future<void> listenForSources() async {
    _sourcesWanted = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'action' || call.arguments is! String) return;
      final action = call.arguments as String;
      if (isWidgetSourceAction(action)) {
        widgetSourceRequest.value = action;
      } else {
        _launchAction = action;
      }
    });
    if (_launchTaken) return;
    _launchTaken = true;
    try {
      final action = await _channel.invokeMethod<String>('takeAction');
      if (action == null) return;
      if (isWidgetSourceAction(action)) {
        widgetSourceRequest.value = action;
      } else {
        _launchAction = action;
      }
    } on MissingPluginException {
      // iOS and widget tests do not use Android home widgets.
    }
  }

  final void Function(String action) onAction;
  Timer? _pending;
  Map<String, Object?>? _state;
  String? _sent;
  DateTime? _lastSent;
  bool _sending = false;
  bool _disposed = false;
  bool _missingPlugin = false;

  Future<void> initialize() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'action' && call.arguments is String) {
        _dispatch(call.arguments as String);
      }
    });
    final launch = _launchAction;
    _launchAction = null;
    if (launch != null) onAction(launch);
    try {
      final action = await _channel.invokeMethod<String>('takeAction');
      _launchTaken = true;
      if (action != null) _dispatch(action);
    } on MissingPluginException {
      // iOS and widget tests do not use Android home widgets.
    }
  }

  void _dispatch(String action) {
    if (isWidgetSourceAction(action)) {
      widgetSourceRequest.value = action;
    } else {
      onAction(action);
    }
  }

  void schedule(Map<String, Object?> state) {
    if (_disposed || _missingPlugin) return;
    _state = state;
    final encoded = jsonEncode(state);
    if (encoded == _sent) return;
    if (_lastSent == null ||
        DateTime.now().difference(_lastSent!) >= const Duration(seconds: 2)) {
      _pending?.cancel();
      _pending = null;
      unawaited(_send());
    } else {
      _pending ??= Timer(const Duration(seconds: 2), () {
        _pending = null;
        unawaited(_send());
      });
    }
  }

  Future<void> _send() async {
    if (_disposed || _missingPlugin) return;
    if (_sending) {
      _schedulePending();
      return;
    }
    final state = _state;
    if (state == null) return;
    final encoded = jsonEncode(state);
    if (encoded == _sent) return;
    _sending = true;
    var delivered = false;
    try {
      await _channel.invokeMethod<void>('update', state);
      _sent = encoded;
      _lastSent = DateTime.now();
      delivered = true;
    } on MissingPluginException {
      // No Android widget provider on this platform.
      _missingPlugin = true;
    } on PlatformException {
      // A later player snapshot can retry after a transient Android failure.
    } finally {
      _sending = false;
      if (delivered &&
          !_disposed &&
          !_missingPlugin &&
          _state != null &&
          jsonEncode(_state) != _sent) {
        _schedulePending();
      }
    }
  }

  void _schedulePending() {
    _pending ??= Timer(const Duration(seconds: 2), () {
      _pending = null;
      unawaited(_send());
    });
  }

  void dispose() {
    _disposed = true;
    _pending?.cancel();
    _channel.setMethodCallHandler(null);
    if (_sourcesWanted) unawaited(listenForSources());
  }
}
