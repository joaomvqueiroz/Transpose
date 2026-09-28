import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

/// Mirrors acknowledged player state into Android launchers. Widget actions
/// always open the app; YouTube never plays from an invisible background view.
class HomeWidgetBridge {
  HomeWidgetBridge({required this.onAction});

  static const _channel = MethodChannel('transpose/home_widgets');
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
        onAction(call.arguments as String);
      }
    });
    try {
      final action = await _channel.invokeMethod<String>('takeAction');
      if (action != null) onAction(action);
    } on MissingPluginException {
      // iOS and widget tests do not use Android home widgets.
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
  }
}
