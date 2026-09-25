import 'dart:async';

import 'media_source.dart';

/// Prepared media owned by exactly one player session.
///
/// An adapter must make [release] safe after a successful load and retryable
/// if release itself fails. It must clean up partial resources if loading
/// throws.
abstract interface class LoadedMedia {
  /// Confirmed duration from the decoder, when available.
  Duration? get duration;

  /// Most recent timeline position reported by the adapter.
  Duration get position;

  /// Emits once for each natural completion of non-looping media.
  /// Explicit pause, seek, unload and decoder failures must not emit here.
  Stream<void> get endEvents;

  /// Completes only when this resource has started output.
  ///
  /// A failed start must leave the resource stopped or report a fatal failure
  /// that can be released safely.
  Future<void> play();

  /// Completes only when output has stopped and position is preserved.
  Future<void> pause();

  /// Requests a timeline jump and returns the position acknowledged by the
  /// adapter. Implementations must not silently clamp an out-of-range target.
  Future<Duration> seek(Duration position);

  /// Stops output and releases decoder, file and platform resources.
  Future<void> release();
}

/// Optional adapter capability for externally confirmed, safety-related pauses.
///
/// Each event means the adapter has stopped output and withdrawn any automatic
/// resume intent (for example after audio focus loss or headphone removal).
/// Ordinary buffering, explicit Pause and end-of-media must not emit here.
abstract interface class InterruptedLoadedMedia implements LoadedMedia {
  Stream<void> get interruptionEvents;
}

/// Playback was safely refused/cancelled by an interruption, not a fatal decoder
/// error. The loaded resource remains usable after another explicit Play.
final class MediaPlaybackInterrupted implements Exception {
  const MediaPlaybackInterrupted();
}

/// Boundary between Player Core and a concrete media playback stack.
///
/// The implementation is selected after ADR-012. This contract performs no
/// audio processing and has no dependency on Flutter or native SDKs. A
/// successful load returns a prepared, non-playing resource: loading must
/// never start audio on its own.
abstract interface class MediaLoader {
  Future<LoadedMedia> load(MediaSource source);
}
