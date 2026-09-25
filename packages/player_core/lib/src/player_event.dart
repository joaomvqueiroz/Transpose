/// Confirmed facts that can advance [PlayerStateMachine].
///
/// `play` and `pause` are confirmations from the future playback adapter, not
/// optimistic UI intents. The application/controller layer owns that mapping.
enum PlayerEvent {
  load,
  loadOk,
  loadFail,
  play,
  pause,
  bufferEmpty,
  bufferReady,
  seek,
  seekValid,
  interruptionBegin,
  interruptionEnd,
  endOfMedia,
  fatalError,
  unload;

  /// Stable diagnostic name matching `STATE_MACHINES.md`.
  String get code => switch (this) {
        PlayerEvent.load => 'LOAD',
        PlayerEvent.loadOk => 'LOAD_OK',
        PlayerEvent.loadFail => 'LOAD_FAIL',
        PlayerEvent.play => 'PLAY',
        PlayerEvent.pause => 'PAUSE',
        PlayerEvent.bufferEmpty => 'BUFFER_EMPTY',
        PlayerEvent.bufferReady => 'BUFFER_READY',
        PlayerEvent.seek => 'SEEK',
        PlayerEvent.seekValid => 'SEEK_VALID',
        PlayerEvent.interruptionBegin => 'INTERRUPTION_BEGIN',
        PlayerEvent.interruptionEnd => 'INTERRUPTION_END',
        PlayerEvent.endOfMedia => 'END_OF_MEDIA',
        PlayerEvent.fatalError => 'FATAL_ERROR',
        PlayerEvent.unload => 'UNLOAD',
      };
}
