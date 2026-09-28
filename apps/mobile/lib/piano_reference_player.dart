import 'package:audioplayers/audioplayers.dart';

/// Plays recorded piano notes bundled with the app; it never synthesizes a beep.
abstract class PianoReferencePlayer {
  Future<void> play(String note);
  Future<void> stop();
  Future<void> dispose();
}

class SampledPianoReferencePlayer implements PianoReferencePlayer {
  AudioPlayer? _player;

  static const notes = {'E2', 'A2', 'D3', 'G3', 'B3', 'E4'};

  AudioPlayer _createPlayer() {
    final player = AudioPlayer();
    // A one-shot reference needs no per-frame playback-position callbacks.
    player.positionUpdater = TimerPositionUpdater(
      getPosition: player.getCurrentPosition,
      interval: const Duration(milliseconds: 250),
    );
    return player;
  }

  @override
  Future<void> play(String note) async {
    if (!notes.contains(note)) throw ArgumentError.value(note, 'note');
    final player = _player ??= _createPlayer();
    await player.stop();
    await player.play(
      AssetSource('piano/$note.wav'),
      volume: .7,
      mode: PlayerMode.lowLatency,
    );
  }

  @override
  Future<void> stop() async {
    await _player?.stop();
  }

  @override
  Future<void> dispose() async {
    await _player?.dispose();
    _player = null;
  }
}
