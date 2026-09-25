/// The single authoritative lifecycle state for one media session.
///
/// UI code must derive presentation from this value instead of maintaining
/// independent `isPlaying`, `isPaused`, or `isBuffering` flags.
enum PlayerState {
  idle,
  loading,
  ready,
  playing,
  paused,
  buffering,
  interrupted,
  error,
  ended;

  /// Stable diagnostic name matching `STATE_MACHINES.md`.
  String get code => name.toUpperCase();
}
