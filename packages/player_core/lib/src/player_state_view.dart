import 'player_state.dart';

/// Read-only player state exposed to presentation code.
///
/// The driver that accepts backend confirmations is intentionally not part of
/// the package's public facade. This prevents widgets from optimistically
/// forcing playback states such as [PlayerState.playing].
abstract interface class PlayerStateView {
  PlayerState get state;

  Stream<PlayerState> get states;
}
