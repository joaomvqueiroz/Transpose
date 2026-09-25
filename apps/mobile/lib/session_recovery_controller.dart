import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'main_player_controller.dart';
import 'practice_session.dart';
import 'session_snapshot.dart';

class SessionPresentation {
  const SessionPresentation({
    this.screen = 'player',
    this.fullscreen = false,
    this.activePresetId,
    this.practice,
    this.settled = true,
  });
  final String screen;
  final bool fullscreen;
  final String? activePresetId;
  final PracticeProgress? practice;
  // Multi-command practice transitions cannot be captured halfway through.
  final bool settled;
}

/// Saves acknowledged player state, not UI intentions or a future Play command.
/// Online startup is metadata-only until an explicit restore action.
class SessionRecoveryController extends ChangeNotifier {
  SessionRecoveryController({
    required this.player,
    required this.repository,
    required this.presentation,
    required this.onRestored,
    this.positionInterval = const Duration(seconds: 5),
  }) {
    player.addListener(_changed);
  }
  final MainPlayerController player;
  final SessionSnapshotRepository repository;
  final SessionPresentation Function() presentation;
  final ValueChanged<SessionSnapshot> onRestored;
  final Duration positionInterval;
  bool _initialized = false, _initializing = false, _restoring = false;
  bool _closed = false,
      _closing = false,
      _writeBlocked = false,
      _saveFailed = false;
  bool _ignoreStartup = false, _holdAutosave = false;
  bool _attemptedRestore = false;
  int _generation = 0;
  Timer? _positionTimer;
  Future<void> _tail = Future<void>.value();
  SessionSnapshot? _pending, _latest;
  String? _message, _queuedIdentity, _semanticIdentity;
  bool? _lastPlaying;
  final String _sessionId = 'session-${DateTime.now().microsecondsSinceEpoch}';
  int? restorationMilliseconds;

  bool get initializing => _initializing;
  bool get restoring => _restoring;
  bool get saveFailed => _saveFailed;
  bool get writeBlocked => _writeBlocked;
  SessionSnapshot? get pending => _pending;
  String? get message => _message;
  bool get canDismiss => _pending == null || !_attemptedRestore || _restoring;
  bool get canUseCurrent =>
      _pending != null &&
      !_restoring &&
      player.snapshot('Sessão atual') != null;

  void _notify() {
    if (!_closed && !_closing) notifyListeners();
  }

  Future<void> initialize() async {
    if (_closed || _closing || _initialized || _initializing) return;
    _initializing = true;
    _message = 'A procurar a última sessão…';
    _notify();
    try {
      final result = await repository.read();
      if (_closed || _closing) return;
      _writeBlocked = result.writeBlocked || repository.writeBlocked;
      _initialized = true;
      _initializing = false;
      if (_ignoreStartup) {
        _message = result.warning;
        _changed();
      } else if (result.snapshot == null) {
        _message = result.warning;
      } else {
        _pending = result.snapshot;
        _holdAutosave = true;
        if (_pending!.media.youtube) {
          _message =
              'Última sessão: ${_pending!.media.title}. Abra o vídeo quando quiser; nada foi reproduzido.';
          if (result.fromPrevious) {
            _message = 'Recuperada a cópia anterior. $_message';
          }
        } else {
          await _restore(_pending!, fromPrevious: result.fromPrevious);
        }
      }
    } on Object {
      if (!_closed && !_closing) {
        _initialized = true;
        _initializing = false;
        _saveFailed = true;
        _message = 'Não foi possível ler a última sessão. Os dados foram preservados; pode continuar a usar o player.';
      }
    }
    _notify();
    _changed();
  }

  Future<void> restorePending() async {
    final snapshot = _pending;
    if (snapshot != null && !_restoring && !_closed && !_closing) {
      await _restore(snapshot);
    }
  }

  Future<void> _restore(
    SessionSnapshot snapshot, {
    bool fromPrevious = false,
  }) async {
    final generation = ++_generation;
    _attemptedRestore = true;
    _restoring = true;
    _holdAutosave = true;
    _message = 'A recuperar ${snapshot.media.title}…';
    _notify();
    final watch = Stopwatch()..start();
    try {
      await player.restore(snapshot.media);
      if (_closed || _closing || generation != _generation) return;
      restorationMilliseconds = watch.elapsedMilliseconds;
      if (player.lastRestoreSucceeded) {
        _pending = null;
        _message = fromPrevious
            ? 'Sessão recuperada pela cópia anterior · reprodução pausada.'
            : 'Sessão recuperada · toque em reproduzir para continuar.';
        onRestored(snapshot);
        _holdAutosave = false;
      } else {
        _message = snapshot.media.youtube
            ? 'Não foi possível recuperar o vídeo. Os ajustes continuam guardados; tente novamente ou escolha outra música.'
            : 'Não foi possível abrir o ficheiro guardado. Os ajustes foram preservados; volte a selecionar o ficheiro ou tente novamente.';
      }
    } on Object {
      if (!_closed && !_closing && generation == _generation) {
        _message = 'Não foi possível recuperar a sessão. Os ajustes guardados continuam disponíveis.';
      }
    } finally {
      if (!_closed && !_closing && generation == _generation) {
        _restoring = false;
        _notify();
        _changed();
      }
    }
  }

  /// Call before a user chooses another source/preset, never for position ticks.
  /// Taking a new explicit action takes precedence over slow startup recovery.
  void beginUserSource() {
    if (_closed || _closing) return;
    _ignoreStartup = true;
    _generation++;
    if (_restoring) unawaited(player.pause());
    _restoring = false;
    _pending = null;
    _attemptedRestore = false;
    _holdAutosave = false;
    _message = _writeBlocked
        ? 'Gravação automática suspensa para preservar os dados existentes.'
        : _saveFailed
        ? _message
        : null;
    _notify();
  }

  void dismissNotice() {
    if (_closed || _closing) return;
    if (_restoring || _initializing) {
      _ignoreStartup = true;
      _generation++;
      if (_restoring) unawaited(player.pause());
      _restoring = false;
    }
    if (_pending != null && _attemptedRestore) {
      // A cancelled restore may have prepared only part of the source. Do not
      // hide suspended autosave or silently adopt that partial state.
      _message = 'Recuperação interrompida. Tente novamente, escolha outra música ou use explicitamente a sessão atual.';
      _notify();
      return;
    }
    // Dismiss is not deletion. An unopened saved session remains on disk.
    _pending = null;
    _message = null;
    _notify();
  }

  Future<void> useCurrentSession() async {
    if (_closed || _closing || !canUseCurrent) return;
    beginUserSource();
    _changed();
    await flush();
  }

  SessionSnapshot? _capture() {
    final ui = presentation();
    if (!ui.settled) return null;
    final media = player.snapshot('Sessão em curso');
    if (media == null) return null;
    return SessionSnapshot(
      media: media,
      savedAt: DateTime.now().toUtc(),
      sessionId: _sessionId,
      screen: ui.screen,
      fullscreen: ui.fullscreen,
      activePresetId: ui.activePresetId,
      practice: ui.practice,
    );
  }

  String _identity(SessionSnapshot snapshot, {bool position = true}) {
    final m = Map<String, Object?>.of(snapshot.media.toJson())
      ..remove('id')
      ..remove('name');
    if (!position) m.remove('positionMs');
    return jsonEncode([
      m,
      snapshot.screen,
      snapshot.fullscreen,
      snapshot.activePresetId,
      snapshot.practice?.toJson(),
    ]);
  }

  /// UI navigation is part of the useful session; fullscreen will not reopen
  /// automatically, even though the previous layout is recorded for diagnosis.
  void presentationChanged() => _changed();

  void _changed() {
    if (_closed ||
        _closing ||
        !_initialized ||
        _initializing ||
        _restoring ||
        _holdAutosave ||
        _writeBlocked ||
        _saveFailed) {
      return;
    }
    final candidate = _capture();
    if (candidate == null) {
      // Save the last acknowledged position before seek/source/DSP work; never
      // replace it with the unacknowledged target of that operation.
      if (_latest != null) unawaited(_enqueue(_latest!));
      return;
    }
    _latest = candidate;
    final signature = _identity(candidate, position: false);
    final immediate =
        signature != _semanticIdentity ||
        (_lastPlaying == true && !player.playing);
    _semanticIdentity = signature;
    _lastPlaying = player.playing;
    if (immediate || !player.playing) {
      _positionTimer?.cancel();
      _positionTimer = null;
      unawaited(_enqueue(candidate));
    } else {
      // Throttle, not trailing debounce: continuous playback must still save.
      _positionTimer ??= Timer(positionInterval, () {
        _positionTimer = null;
        if (!_closed && !_closing) unawaited(flush());
      });
    }
  }

  Future<void> _enqueue(SessionSnapshot snapshot) {
    final identity = _identity(snapshot);
    if (_queuedIdentity == identity) return _tail;
    _queuedIdentity = identity;
    final task = _tail.then((_) async {
      if (_closed || _writeBlocked || _saveFailed) return;
      try {
        await repository.save(snapshot);
      } on Object {
        _queuedIdentity = null;
        _writeBlocked = repository.writeBlocked;
        _saveFailed = true;
        _message = _writeBlocked
            ? 'Gravação automática suspensa. Os dados existentes foram preservados.'
            : 'Não foi possível guardar a sessão. Verifique o espaço disponível e tente guardar novamente.';
        _notify();
      }
    });
    _tail = task;
    return task;
  }

  Future<void> flush() async {
    _positionTimer?.cancel();
    _positionTimer = null;
    if (_closed ||
        _closing ||
        !_initialized ||
        _initializing ||
        _restoring ||
        _holdAutosave ||
        _writeBlocked ||
        _saveFailed) {
      await _tail;
      return;
    }
    final candidate = _capture() ?? _latest;
    if (candidate != null) await _enqueue(candidate);
    await _tail;
  }

  Future<void> retrySave() async {
    if (_closed || _closing || _writeBlocked) return;
    try {
      // Recheck format before allowing a write after a read/storage error.
      final result = await repository.read();
      if (_closed || _closing) return;
      _writeBlocked = result.writeBlocked || repository.writeBlocked;
      if (_writeBlocked) {
        _message = result.warning;
        _notify();
        return;
      }
      _saveFailed = false;
      _queuedIdentity = null;
      _message = null;
      await flush();
      if (!_saveFailed) _message = 'Gravação automática disponível.';
    } on Object {
      _message = 'O armazenamento ainda não está disponível. Os dados foram preservados.';
    }
    _notify();
  }

  Future<void> close() async {
    if (_closed || _closing) return;
    // Capture before asynchronous disposal of the shared player.
    final saving = flush();
    _closing = true;
    _generation++;
    player.removeListener(_changed);
    _positionTimer?.cancel();
    await saving;
    _closed = true;
    await repository.close();
    super.dispose();
  }
}
