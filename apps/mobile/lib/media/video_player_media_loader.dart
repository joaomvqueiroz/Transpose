import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:player_core/player_core.dart';
import 'package:video_player/video_player.dart';

import 'native_audio_media_loader.dart';

/// Replaceable integration pilot, not the final DSP-capable playback decision.
///
/// Android uses the endorsed ExoPlayer/Media3 implementation; iOS uses AVPlayer.
/// The plugin acknowledges platform commands, not first acoustic output, so
/// AUD-001/002 still require instrumented device measurements.
final class VideoPlayerMediaLoader implements MediaLoader {
  VideoPlayerController? currentController;
  final NativeAudioMediaLoader _nativeAudio = NativeAudioMediaLoader();
  NativeAudioLoadedMedia? get currentAudio => _nativeAudio.currentAudio;

  @override
  Future<LoadedMedia> load(MediaSource source) async {
    if (source is! LocalFileSource) {
      throw UnsupportedError('Only local files are supported by this pilot.');
    }
    if (Platform.isAndroid &&
        (_isAudioName(source.displayName) ||
            _isAudioName(source.locator.path))) {
      currentController = null;
      return _nativeAudio.load(source);
    }
    final VideoPlayerController controller;
    if (source.locator.scheme == 'file') {
      controller = VideoPlayerController.file(File.fromUri(source.locator));
    } else if (source.locator.scheme == 'content' && Platform.isAndroid) {
      controller = VideoPlayerController.contentUri(source.locator);
    } else {
      throw UnsupportedError('This local locator is not supported.');
    }

    try {
      await controller.initialize();
      if (!controller.value.isInitialized || controller.value.hasError) {
        throw StateError('Media initialization failed.');
      }
      currentController = controller;
      return _VideoPlayerLoadedMedia(
        controller,
        onRelease: () {
          if (identical(currentController, controller)) {
            currentController = null;
          }
        },
      );
    } on Object {
      await controller.dispose();
      rethrow;
    }
  }

  bool _isAudioName(String name) {
    final String lower = name.toLowerCase();
    return <String>[
      '.wav',
      '.mp3',
      '.m4a',
      '.aac',
      '.flac',
      '.ogg',
      '.opus',
    ].any(lower.endsWith);
  }
}

final class _VideoPlayerLoadedMedia implements LoadedMedia {
  _VideoPlayerLoadedMedia(this._controller, {required this.onRelease}) {
    _controller.addListener(_onControllerChanged);
  }

  final VideoPlayerController _controller;
  final VoidCallback onRelease;
  final StreamController<void> _endController =
      StreamController<void>.broadcast(sync: true);
  bool _released = false;
  bool _completionNotified = false;

  @override
  Duration? get duration => _controller.value.duration;

  @override
  Duration get position => _controller.value.position;

  @override
  Stream<void> get endEvents => _endController.stream;

  void _onControllerChanged() {
    if (_released) return;
    final bool completed = _controller.value.isCompleted;
    if (!completed) {
      _completionNotified = false;
    } else if (!_completionNotified && !_controller.value.isLooping) {
      _completionNotified = true;
      _endController.add(null);
    }
  }

  @override
  Future<void> play() async {
    _requireActive();
    await _controller.play();
    if (_controller.value.hasError || !_controller.value.isPlaying) {
      throw StateError('Platform did not accept Play.');
    }
  }

  @override
  Future<void> pause() async {
    _requireActive();
    await _controller.pause();
    if (_controller.value.hasError || _controller.value.isPlaying) {
      throw StateError('Platform did not accept Pause.');
    }
  }

  @override
  Future<Duration> seek(Duration position) async {
    _requireActive();
    await _controller.seekTo(position);
    if (_controller.value.hasError) {
      throw StateError('Platform did not accept Seek.');
    }
    return _controller.value.position;
  }

  @override
  Future<void> release() async {
    if (_released) {
      return;
    }
    _controller.removeListener(_onControllerChanged);
    await _controller.dispose();
    _released = true;
    await _endController.close();
    onRelease();
  }

  void _requireActive() {
    if (_released) {
      throw StateError('Media has already been released.');
    }
  }
}
