/// Individual operations a [MediaSource] may support.
enum MediaCapability {
  seek,
  backgroundPlayback,
  pitchShift,
  timeStretch,
  cache,
  export,
  preciseLoop,
}

/// Immutable, typed capability set for a media source.
///
/// Processing support is intentionally granular: pitch and time-stretch can be
/// enabled independently, and [canProcessAudio] is derived so it cannot drift
/// from those two facts.
final class MediaCapabilities {
  MediaCapabilities({
    this.canSeek = false,
    this.canBackgroundPlay = false,
    this.canPitchShift = false,
    this.canTimeStretch = false,
    this.canCache = false,
    this.canExport = false,
    this.canLoopPrecisely = false,
  }) {
    if (canLoopPrecisely && !canSeek) {
      throw ArgumentError(
        'precise looping requires seeking',
        'canLoopPrecisely',
      );
    }
  }

  /// Source-level capabilities for an authorized local media file.
  ///
  /// Runtime support will later be the intersection of these capabilities and
  /// the selected player/audio adapter. `cache` is false because the source is
  /// already local; `export` remains false until an explicit export policy is
  /// implemented.
  static final MediaCapabilities localFile = MediaCapabilities(
    canSeek: true,
    canBackgroundPlay: true,
    canPitchShift: true,
    canTimeStretch: true,
    canLoopPrecisely: true,
  );

  static final MediaCapabilities none = MediaCapabilities();

  final bool canSeek;
  final bool canBackgroundPlay;
  final bool canPitchShift;
  final bool canTimeStretch;
  final bool canCache;
  final bool canExport;
  final bool canLoopPrecisely;

  bool get canProcessAudio => canPitchShift || canTimeStretch;

  bool supports(MediaCapability capability) => switch (capability) {
        MediaCapability.seek => canSeek,
        MediaCapability.backgroundPlayback => canBackgroundPlay,
        MediaCapability.pitchShift => canPitchShift,
        MediaCapability.timeStretch => canTimeStretch,
        MediaCapability.cache => canCache,
        MediaCapability.export => canExport,
        MediaCapability.preciseLoop => canLoopPrecisely,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaCapabilities &&
          canSeek == other.canSeek &&
          canBackgroundPlay == other.canBackgroundPlay &&
          canPitchShift == other.canPitchShift &&
          canTimeStretch == other.canTimeStretch &&
          canCache == other.canCache &&
          canExport == other.canExport &&
          canLoopPrecisely == other.canLoopPrecisely;

  @override
  int get hashCode => Object.hash(
        canSeek,
        canBackgroundPlay,
        canPitchShift,
        canTimeStretch,
        canCache,
        canExport,
        canLoopPrecisely,
      );

  @override
  String toString() => 'MediaCapabilities('
      'seek: $canSeek, '
      'background: $canBackgroundPlay, '
      'pitch: $canPitchShift, '
      'timeStretch: $canTimeStretch, '
      'cache: $canCache, '
      'export: $canExport, '
      'preciseLoop: $canLoopPrecisely)';
}
