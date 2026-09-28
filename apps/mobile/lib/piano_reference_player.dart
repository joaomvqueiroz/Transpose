import 'package:audioplayers/audioplayers.dart';

/// Plays recorded piano notes bundled with the app; it never synthesizes a beep.
abstract class PianoReferencePlayer {
  Future<void> play(String note);
  Future<void> stop();
  Future<void> dispose();
}

class SampledPianoReferencePlayer implements PianoReferencePlayer {
  AudioPlayer? _player;
  Future<void> _pending = Future<void>.value();
  int _generation = 0;
  bool _disposed = false;

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

  Future<void> _enqueue(Future<void> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.catchError((Object _) {});
    return result;
  }

  @override
  Future<void> play(String note) {
    if (!notes.contains(note)) throw ArgumentError.value(note, 'note');
    if (_disposed) throw StateError('O piano já foi fechado.');
    final generation = ++_generation;
    return _enqueue(() async {
      if (generation != _generation) return;
      final player = _player ??= _createPlayer();
      await player.stop();
      if (generation != _generation) return;
      await player.play(
        AssetSource('piano/$note.wav'),
        volume: .7,
        mode: PlayerMode.lowLatency,
      );
      if (generation != _generation) await player.stop();
    });
  }

  @override
  Future<void> stop() {
    ++_generation;
    return _enqueue(() async {
      await _player?.stop();
    });
  }

  @override
  Future<void> dispose() {
    _disposed = true;
    ++_generation;
    return _enqueue(() async {
      await _player?.dispose();
      _player = null;
    });
  }
}
