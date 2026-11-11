import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:youtube_native_audio/youtube_native_audio.dart';

import 'youtube_browser.dart';

enum NativeFollowStatus { idle, loading, ready, failed }

/// iPhone-only: plays the current YouTube video's audio natively and keeps it
/// following the (muted) web player. The web player stays the clock, so
/// YouTube's own controls, seeking, loops and speed keep working; only pitch
/// and effects are rendered natively.
class NativeYouTubeAudioFollower {
  NativeYouTubeAudioFollower({
    required this.setWebMuted,
    required this.onChanged,
    YouTubeNativeAudio? audio,
  }) : _audio = audio ?? YouTubeNativeAudio();

  /// Effects the native graph renders. Chorus has no native equivalent.
  static const Set<String> nativeActions = {
    'pitch',
    'bass',
    'mid',
    'treble',
    'gain',
    'reverb',
    'delay',
    'feedback',
  };

  /// Allowed drift between the web clock and the native clock while playing.
  static const double driftSeconds = 0.35;

  final YouTubeNativeAudio _audio;
  final Future<void> Function(bool muted) setWebMuted;
  final VoidCallback onChanged;

  NativeFollowStatus _status = NativeFollowStatus.idle;
  NativeFollowStatus get status => _status;
  NativeAudioSettings _settings = const NativeAudioSettings();
  NativeAudioSettings get settings => _settings;
  String _videoId = '';
  String _message = '';
  int _generation = 0;
  bool _syncing = false;
  bool _webMuted = false;
  bool _disposed = false;

  bool handles(String action) =>
      nativeActions.contains(action) &&
      _videoId.isNotEmpty &&
      _status != NativeFollowStatus.failed;

  Future<void> command(String action, num value) async {
    _settings = _settings.withValue(action, value.toDouble());
    if (_status == NativeFollowStatus.ready) await _audio.configure(_settings);
    _changed();
  }

  /// Native values replace what the web bridge could not apply.
  YouTubeMediaState overlay(YouTubeMediaState media) {
    if (_videoId.isEmpty || media.videoId != _videoId) return media;
    switch (_status) {
      case NativeFollowStatus.idle:
        return media;
      case NativeFollowStatus.loading:
        return media.copyWith(
          pitch: _settings.pitch,
          pitchStatus: 'idle',
          pitchMessage: _message,
          audioEffects: _settings.effects,
        );
      case NativeFollowStatus.ready:
        return media.copyWith(
          muted: false,
          pitch: _settings.pitch,
          pitchStatus: 'active',
          pitchMessage: _message,
          audioEffects: _settings.effects,
        );
      case NativeFollowStatus.failed:
        return media.copyWith(pitchMessage: _message);
    }
  }

  Future<void> sync(YouTubeMediaState media) async {
    if (_disposed || _syncing) return;
    _syncing = true;
    try {
      final String id = media.hasVideo ? media.videoId : '';
      if (id != _videoId) await _switchTo(id);
      if (_status != NativeFollowStatus.ready) return;
      final NativeAudioState native = await _audio.state();
      if (media.isAd) {
        // Ads play through YouTube's own audio; the track resumes afterwards.
        if (native.playing) await _audio.pause();
        await _mute(false);
        return;
      }
      if (!media.muted || !_webMuted) await _mute(true);
      if ((media.speed - _settings.rate).abs() > 0.001) {
        _settings = _settings.withValue('rate', media.speed);
        await _audio.configure(_settings);
      }
      if (media.playing) {
        if (!native.playing) {
          await _audio.play(media.position);
        } else if ((native.position - media.position).abs() > driftSeconds) {
          await _audio.seek(media.position);
        }
      } else if (native.playing) {
        await _audio.pause();
      }
    } on Object {
      if (!_disposed && _status == NativeFollowStatus.ready) {
        await _fail('O áudio nativo parou. A usar o som do YouTube.');
      }
    } finally {
      _syncing = false;
    }
  }

  Future<void> _switchTo(String id) async {
    final int generation = ++_generation;
    _videoId = id;
    _status = NativeFollowStatus.idle;
    _message = '';
    await _audio.stop();
    await _mute(false);
    if (id.isEmpty) {
      _changed();
      return;
    }
    _status = NativeFollowStatus.loading;
    _message = 'A preparar o áudio nativo…';
    _changed();
    unawaited(() async {
      try {
        await _audio.load(id);
        if (_disposed || generation != _generation) return;
        await _audio.configure(_settings);
        _status = NativeFollowStatus.ready;
        _message = 'Tom e efeitos pelo áudio nativo';
      } on Object {
        if (_disposed || generation != _generation) return;
        _status = NativeFollowStatus.failed;
        _message = 'Áudio nativo indisponível para este vídeo. A usar o som do YouTube.';
      }
      _changed();
    }());
  }

  Future<void> _fail(String message) async {
    _status = NativeFollowStatus.failed;
    _message = message;
    try {
      await _audio.stop();
    } on Object {
      // Already stopped.
    }
    await _mute(false);
    _changed();
  }

  Future<void> _mute(bool muted) async {
    if (_webMuted == muted && muted == false) return;
    _webMuted = muted;
    try {
      await setWebMuted(muted);
    } on Object {
      // A navigation replaced the page; the next sync re-applies.
    }
  }

  void _changed() {
    if (!_disposed) onChanged();
  }

  void dispose() {
    _disposed = true;
    _generation++;
    unawaited(_audio.stop().catchError((Object _) {}));
  }
}
