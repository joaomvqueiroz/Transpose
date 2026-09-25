import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'main_player_controller.dart';
import 'practice_session.dart';

/// Coordinates the existing player; it never owns audio or counts wall time.
class PracticeController extends ChangeNotifier {
  PracticeController(this.player) {
    player.addListener(_observe);
  }
  final MainPlayerController player;
  PracticePlan _plan = const PracticePlan();
  PracticeStatus _status = PracticeStatus.notStarted;
  String? _id, _sourceKey, _message;
  int _aMs = 0, _bMs = 0, _current = 60, _step = 0, _total = 0;
  int? _epoch, _seen;
  int _generation = 0;
  int _preparationRevision = 0;
  int _preparationInterruption = 0;
  bool _preparing = false, _disposed = false;

  PracticePlan get plan => _plan;
  PracticeStatus get status => _status;
  int get currentPercent => _current;
  int get stepRepetitions => _step;
  int get totalRepetitions => _total;
  bool get busy => _preparing;
  bool get running => _status == PracticeStatus.running;
  bool get hasSession => _id != null;
  String? get message => _message;
  bool get _sameRange =>
      player.sourceKey == _sourceKey &&
      player.markerA?.inMilliseconds == _aMs &&
      player.markerB?.inMilliseconds == _bMs;
  String? get unavailableReason {
    if (!player.loaded) return 'Escolha uma música e marque A e B.';
    if (player.loopObservation == null) {
      return 'A fonte atual ainda não confirma voltas completas. O treino manual continua disponível.';
    }
    if (!player.canSpeed || !player.canLoop) {
      return 'Aguarde uma fonte com velocidade e loop disponíveis.';
    }
    if (player.muted) return 'Ative o som no player antes de iniciar o treino.';
    if (player.markerA == null ||
        player.markerB == null ||
        player.markerB! - player.markerA! < const Duration(milliseconds: 250)) {
      return 'Marque A e B com pelo menos 0,25 s entre eles.';
    }
    return null;
  }

  bool get canStart =>
      !_disposed && !busy && !player.busy && unavailableReason == null;
  bool get canResume =>
      canStart && _status == PracticeStatus.paused && _sameRange;
  int get stepNumber =>
      ((_current - _plan.startPercent) / _plan.incrementPercent).ceil() + 1;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _baseline() {
    final o = player.loopObservation;
    _epoch = o?.epoch;
    _seen = o?.count;
  }

  bool _active(int generation) =>
      !_disposed &&
      generation == _generation &&
      _sameRange &&
      player.manualControlRevision == _preparationRevision &&
      player.interruptionRevision == _preparationInterruption &&
      player.loopObservation != null;

  Future<void> start(PracticePlan plan) async {
    if (!canStart || !plan.valid) return;
    _plan = plan;
    _id = 'practice-${DateTime.now().microsecondsSinceEpoch}';
    _sourceKey = player.sourceKey;
    _aMs = player.markerA!.inMilliseconds;
    _bMs = player.markerB!.inMilliseconds;
    _step = 0;
    _total = 0;
    _current = plan.startPercent;
    await _prepare(_current, resetStep: true);
  }

  Future<void> _prepare(int percent, {required bool resetStep}) async {
    if (_disposed || _preparing) return;
    final generation = ++_generation;
    _preparationRevision = player.manualControlRevision;
    _preparationInterruption = player.interruptionRevision;
    _preparing = true;
    _status = PracticeStatus.preparing;
    _message = 'A preparar $percent%…';
    _notify();
    try {
      await player.automatedCommand(player.pause);
      if (!_active(generation)) return;
      if (!player.loopEnabled) await player.automatedCommand(player.toggleLoop);
      if (!_active(generation)) return;
      await player.automatedCommand(() => player.changeSpeed(percent / 100));
      if (!_active(generation)) return;
      if (!player.loopEnabled || (player.speed - percent / 100).abs() > .0001) {
        throw StateError('Unconfirmed speed/loop');
      }
      await player.automatedCommand(
        () => player.seek(Duration(milliseconds: _aMs)),
      );
      if (!_active(generation)) return;
      // Readiness waits acknowledge preparation; they never count repetitions.
      final readyDeadline = DateTime.now().add(const Duration(seconds: 4));
      while (player.loopObservation?.ready != true &&
          DateTime.now().isBefore(readyDeadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        if (!_active(generation)) return;
      }
      if (player.loopObservation?.ready != true) {
        throw StateError('Playback not ready after seek');
      }
      if ((player.position.inMilliseconds - _aMs).abs() > 150) {
        throw StateError('Unconfirmed seek');
      }
      _current = percent;
      if (resetStep) _step = 0;
      _baseline();
      if (player.loopObservation == null) {
        throw StateError('Missing complete-loop telemetry');
      }
      if (!player.playing) await player.automatedCommand(player.playPause);
      if (!_active(generation)) return;
      if (!player.playing || player.muted) {
        throw StateError('Playback was not accepted');
      }
      _status = PracticeStatus.running;
      _message = null;
    } on Object {
      if (_active(generation)) {
        _status = PracticeStatus.paused;
        _message = 'O player não confirmou o ajuste. O treino ficou pausado; tente retomar.';
        await player.automatedCommand(player.pause);
      }
    } finally {
      _preparing = false;
      if (!_disposed) {
        if (!_sameRange && _id != null) {
          _status = PracticeStatus.aborted;
          _message = 'A música ou o trecho mudou. Inicie um novo plano.';
        } else if (generation == _generation &&
            _status == PracticeStatus.preparing) {
          _status = PracticeStatus.paused;
          _message = 'A preparação foi interrompida. Retome quando a fonte estiver pronta.';
        }
        _notify();
      }
    }
  }

  Future<void> pause() async {
    if (_disposed) return;
    _generation++;
    if (_id != null &&
        _status != PracticeStatus.completed &&
        _status != PracticeStatus.aborted) {
      _status = PracticeStatus.paused;
      _message =
          'Treino pausado. Retomar começa a volta pendente a partir de A.';
    }
    _baseline();
    _notify();
    await player.pause();
  }

  Future<void> resume() async {
    if (!canResume) return;
    if (_step >= _plan.repetitionsPerStep) {
      await skipStep();
      return;
    }
    await _prepare(_current, resetStep: false);
  }

  Future<void> skipStep() async {
    if (_disposed ||
        busy ||
        ![PracticeStatus.running, PracticeStatus.paused].contains(_status) ||
        !_sameRange ||
        !canStart) {
      return;
    }
    if (_current >= _plan.targetPercent) {
      _message =
          'Esta é a última etapa. Complete as voltas ou encerre o treino.';
      _notify();
      return;
    }
    await _prepare(
      math.min(_current + _plan.incrementPercent, _plan.targetPercent),
      resetStep: true,
    );
  }

  Future<void> stop() async {
    if (_disposed) return;
    _generation++;
    _status = PracticeStatus.aborted;
    _message = 'Treino encerrado. Tom, velocidade e A/B foram mantidos.';
    _baseline();
    _notify();
    await player.pause();
  }

  void _suspend(String reason) {
    _generation++;
    _status = PracticeStatus.paused;
    _message = reason;
    _baseline();
    _notify();
  }

  void _observe() {
    if (_disposed || _preparing) return;
    if (player.busy || player.pitchPending) return;
    if (hasSession && _status != PracticeStatus.aborted && !_sameRange) {
      _generation++;
      _status = PracticeStatus.aborted;
      _message = 'A música ou o trecho mudou. Inicie um novo plano.';
      _notify();
      return;
    }
    if (!running) return;
    final observation = player.loopObservation;
    if (observation == null) {
      _suspend(
        'Contagem indisponível ou fonte interrompida. Retome quando o vídeo/áudio estiver pronto.',
      );
      return;
    }
    if (!player.loopEnabled || (player.speed - _current / 100).abs() > .0001) {
      _suspend(
        'Ajuste manual detetado: a progressão automática está pausada. Retomar reaplica a etapa guardada.',
      );
      return;
    }
    if (_epoch != observation.epoch ||
        (_seen != null && observation.count < _seen!)) {
      _suspend(
        'A posição ou o loop mudou. Retome a partir de A quando quiser.',
      );
      return;
    }
    if (!player.playing || player.muted) {
      _suspend(
        'Reprodução pausada ou interrompida. O treino só retoma por sua ação.',
      );
      return;
    }
    if (!observation.ready || !observation.playing) {
      _baseline();
      return;
    }
    final delta = observation.count - (_seen ?? observation.count);
    _seen = observation.count;
    if (delta <= 0) return;
    final remaining = _plan.repetitionsPerStep - _step;
    _step += math.min(delta, remaining);
    _total += delta;
    if (_step < _plan.repetitionsPerStep) {
      _notify();
      return;
    }
    if (_current == _plan.targetPercent) {
      _status = PracticeStatus.completed;
      _generation++;
      _message = 'Plano concluído. Isto conta voltas reproduzidas, não avalia a sua execução.';
      _notify();
      unawaited(player.pause());
    } else if (delta > remaining) {
      _suspend(
        'Várias voltas chegaram juntas na mesma velocidade. Retome para preparar a próxima etapa.',
      );
      unawaited(player.pause());
    } else {
      // Make the completed step durable before preparation temporarily holds
      // recovery writes. A crash during the rate change can resume at next step.
      _notify();
      unawaited(
        _prepare(
          math.min(_current + _plan.incrementPercent, _plan.targetPercent),
          resetStep: true,
        ),
      );
    }
  }

  PracticeProgress? get snapshot {
    if (_id == null ||
        busy ||
        !_sameRange ||
        _status == PracticeStatus.aborted) {
      return null;
    }
    return PracticeProgress(
      id: _id!,
      sourceKey: _sourceKey!,
      aMs: _aMs,
      bMs: _bMs,
      plan: _plan,
      currentPercent: _current,
      stepRepetitions: _step,
      totalRepetitions: _total,
      status: _status,
    );
  }

  void restore(PracticeProgress? progress) {
    if (_disposed ||
        progress == null ||
        progress.status == PracticeStatus.aborted) {
      return;
    }
    if (player.sourceKey != progress.sourceKey ||
        player.markerA?.inMilliseconds != progress.aMs ||
        player.markerB?.inMilliseconds != progress.bMs) {
      return;
    }
    _generation++;
    _id = progress.id;
    _sourceKey = progress.sourceKey;
    _aMs = progress.aMs;
    _bMs = progress.bMs;
    _plan = progress.plan;
    _current = progress.currentPercent;
    _step = progress.stepRepetitions;
    _total = progress.totalRepetitions;
    _status = progress.status == PracticeStatus.completed
        ? PracticeStatus.completed
        : PracticeStatus.paused;
    _message = _status == PracticeStatus.completed
        ? 'Plano concluído recuperado, sem reprodução.'
        : 'Treino recuperado em pausa. Retomar reaplica $_current% e começa em A.';
    _baseline();
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    player.removeListener(_observe);
    super.dispose();
  }
}
