import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:transpose_mobile/loop_observation.dart';
import 'package:transpose_mobile/main_player_controller.dart';
import 'package:transpose_mobile/practice_controller.dart';
import 'package:transpose_mobile/practice_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Player player;
  late PracticeController practice;

  setUp(() {
    player = _Player();
    practice = PracticeController(player);
  });
  tearDown(() async {
    practice.dispose();
    player.dispose();
  });

  test(
    'start prepares the existing player and baseline without invented loops',
    () async {
      expect(practice.status, PracticeStatus.notStarted);
      expect(practice.hasSession, isFalse);
      expect(practice.snapshot, isNull);
      await practice.start(const PracticePlan());
      expect(practice.running, isTrue);
      expect(practice.currentPercent, 60);
      expect(practice.stepRepetitions, 0);
      expect(practice.totalRepetitions, 0);
      expect(player.commands, <String>[
        'pause',
        'loop',
        'speed:0.6',
        'seek:2000',
        'play',
      ]);
      for (var i = 0; i < 20; i++) {
        player.emit(position: Duration(milliseconds: 2000 + i * 40));
      }
      expect(practice.totalRepetitions, 0);
    },
  );

  test('confirmed repetitions advance once and finish only after target repetitions', () async {
    await practice.start(
      const PracticePlan(
        startPercent: 60,
        targetPercent: 65,
        incrementPercent: 5,
        repetitionsPerStep: 2,
      ),
    );
    player.emit(count: 1);
    expect(practice.stepRepetitions, 1);
    expect(practice.totalRepetitions, 1);
    player.emit(count: 1);
    expect(practice.totalRepetitions, 1);
    player.emit(count: 2);
    await _settle();
    expect(practice.currentPercent, 65);
    expect(practice.stepNumber, 2);
    expect(practice.stepRepetitions, 0);
    expect(practice.totalRepetitions, 2);
    expect(practice.running, isTrue);
    expect(player.speeds, <double>[.6, .65]);
    player.emit(count: 1);
    expect(practice.status, PracticeStatus.running);
    player.emit(count: 2);
    await _settle();
    expect(practice.status, PracticeStatus.completed);
    expect(practice.totalRepetitions, 4);
    expect(player.playing, isFalse);
    expect(player.speeds, <double>[.6, .65]);
    player.emit(count: 20);
    expect(practice.totalRepetitions, 4);
  });

  test('short final increment clamps to target and still requires full repetitions', () async {
    await practice.start(
      const PracticePlan(
        startPercent: 60,
        targetPercent: 67,
        incrementPercent: 5,
        repetitionsPerStep: 1,
      ),
    );
    player.emit(count: 1);
    await _settle();
    player.emit(count: 1);
    await _settle();
    expect(practice.currentPercent, 67);
    expect(practice.status, PracticeStatus.running);
    expect(practice.totalRepetitions, 2);
    player.emit(count: 1);
    await _settle();
    expect(practice.status, PracticeStatus.completed);
    expect(player.speeds, <double>[.6, .65, .67]);
  });

  test('seek epoch change pauses progression; explicit resume restarts pending cycle at A', () async {
    await practice.start(const PracticePlan());
    player.emit(count: 1);
    final epoch = player.epoch;
    player.emit(
      epoch: epoch + 1,
      count: 0,
      position: const Duration(milliseconds: 3700),
    );
    expect(practice.status, PracticeStatus.paused);
    expect(practice.totalRepetitions, 1);
    expect(practice.stepRepetitions, 1);
    player.emit(count: 7);
    expect(practice.totalRepetitions, 1);
    await practice.resume();
    expect(practice.running, isTrue);
    expect(player.position, const Duration(seconds: 2));
    expect(practice.stepRepetitions, 1);
    player.emit(count: 1);
    expect(practice.stepRepetitions, 2);
    expect(practice.totalRepetitions, 2);
  });

  test(
    'counter rollback also suspends instead of inventing repetitions',
    () async {
      await practice.start(const PracticePlan());
      player.emit(count: 1);
      player.emit(count: 0);
      expect(practice.status, PracticeStatus.paused);
      expect(practice.totalRepetitions, 1);
    },
  );

  test(
    'manual speed change pauses automation without overwriting the user value',
    () async {
      await practice.start(const PracticePlan());
      await player.changeSpeed(.9);
      expect(practice.status, PracticeStatus.paused);
      expect(player.speed, .9);
      player.emit(count: 8);
      expect(practice.totalRepetitions, 0);
      await practice.resume();
      expect(player.speed, .6);
      expect(practice.running, isTrue);
    },
  );

  test('manual loop disable pauses progression', () async {
    await practice.start(const PracticePlan());
    await player.toggleLoop();
    expect(practice.status, PracticeStatus.paused);
    expect(player.loopEnabled, isFalse);
    await practice.resume();
    expect(player.loopEnabled, isTrue);
    expect(practice.running, isTrue);
  });

  test('source or marker change aborts the old plan', () async {
    await practice.start(const PracticePlan());
    player.source = 'local:file:///different.wav';
    player.emit();
    expect(practice.status, PracticeStatus.aborted);
    expect(practice.canResume, isFalse);
    expect(practice.snapshot, isNull);
    await practice.start(const PracticePlan());
    player.a = const Duration(seconds: 3);
    player.emit();
    expect(practice.status, PracticeStatus.aborted);
  });

  test('playback interruption cannot automatically resume training', () async {
    await practice.start(const PracticePlan());
    player.emit(count: 1);
    player.emit(playing: false);
    final playCalls = player.playCalls;
    expect(practice.status, PracticeStatus.paused);
    player.emit(playing: true, count: 8);
    expect(practice.status, PracticeStatus.paused);
    expect(practice.totalRepetitions, 1);
    expect(player.playCalls, playCalls);
    await practice.resume();
    expect(practice.running, isTrue);
  });

  test(
    'unavailable observations suspend and buffering alone creates no counts',
    () async {
      await practice.start(const PracticePlan());
      player.emit(ready: false);
      expect(practice.running, isTrue);
      expect(practice.totalRepetitions, 0);
      player.emit(ready: true);
      player.telemetry = false;
      player.emit();
      expect(practice.status, PracticeStatus.paused);
      expect(practice.canResume, isFalse);
    },
  );

  test('muting suspends progression and prevents new training', () async {
    await practice.start(const PracticePlan());
    player.isMuted = true;
    player.emit(count: 1);
    expect(practice.status, PracticeStatus.paused);
    expect(practice.totalRepetitions, 0);
    expect(practice.canStart, isFalse);
  });

  test(
    'pause while speed preparation is pending cancels later autoplay',
    () async {
      player.speedGate = Completer<void>();
      final starting = practice.start(const PracticePlan());
      await _settle();
      expect(practice.busy, isTrue);
      expect(practice.snapshot, isNull);
      await practice.pause();
      player.speedGate!.complete();
      await starting;
      expect(practice.busy, isFalse);
      expect(practice.status, PracticeStatus.paused);
      expect(player.playCalls, 0);
      expect(player.playing, isFalse);
    },
  );

  test(
    'stop while preparation is pending never starts late playback',
    () async {
      player.speedGate = Completer<void>();
      final starting = practice.start(const PracticePlan());
      await _settle();
      await practice.stop();
      player.speedGate!.complete();
      await starting;
      expect(practice.status, PracticeStatus.aborted);
      expect(practice.snapshot, isNull);
      expect(player.playCalls, 0);
    },
  );

  test(
    'external player pause during delayed preparation prevents autoplay',
    () async {
      player.speedGate = Completer<void>();
      final starting = practice.start(const PracticePlan());
      await _settle();
      expect(practice.busy, isTrue);
      await player.externalPause();
      expect(player.manualControlRevision, 1);
      player.speedGate!.complete();
      await starting;
      expect(practice.status, PracticeStatus.paused);
      expect(practice.busy, isFalse);
      expect(player.playCalls, 0);
      expect(player.playing, isFalse);
    },
  );

  test('external control during delayed preparation cancels later automatic commands', () async {
    player.speedGate = Completer<void>();
    final starting = practice.start(const PracticePlan());
    await _settle();
    player.externalControlIntent();
    player.speedGate!.complete();
    await starting;
    expect(practice.status, PracticeStatus.paused);
    expect(
      player.commands.where((command) => command.startsWith('seek:')),
      isEmpty,
    );
    expect(player.playCalls, 0);
    expect(practice.totalRepetitions, 0);
  });

  test(
    'native interruption during preparation prevents a later automatic play',
    () async {
      player.speedGate = Completer<void>();
      final starting = practice.start(const PracticePlan());
      await _settle();
      expect(practice.busy, isTrue);
      player.externalInterruption();
      expect(player.manualControlRevision, 0);
      expect(player.interruptionRevision, 1);
      player.speedGate!.complete();
      await starting;
      expect(practice.status, PracticeStatus.paused);
      expect(practice.busy, isFalse);
      expect(player.playCalls, 0);
      expect(player.playing, isFalse);
      expect(practice.totalRepetitions, 0);
      player.emit(ready: true);
      expect(practice.status, PracticeStatus.paused);
      expect(player.playCalls, 0);
      await practice.resume();
      expect(practice.running, isTrue);
      expect(player.playCalls, 1);
    },
  );

  test('loss of confirmed-loop capability during preparation leaves training paused', () async {
    player.speedGate = Completer<void>();
    final starting = practice.start(const PracticePlan());
    await _settle();
    player.telemetry = false;
    player.emit();
    player.speedGate!.complete();
    await starting;
    expect(practice.status, PracticeStatus.paused);
    expect(player.playCalls, 0);
    expect(practice.canResume, isFalse);
    player.telemetry = true;
    player.emit();
    expect(practice.status, PracticeStatus.paused);
    expect(player.playCalls, 0);
    await practice.resume();
    expect(practice.running, isTrue);
    expect(player.playCalls, 1);
  });

  testWidgets(
    'readiness wait does not play before confirmation and respects external pause',
    (tester) async {
      player.ready = false;
      final starting = practice.start(const PracticePlan());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(practice.busy, isTrue);
      expect(player.playCalls, 0);
      await player.externalPause();
      player.emit(ready: true);
      await tester.pump(const Duration(milliseconds: 250));
      await starting;
      expect(practice.status, PracticeStatus.paused);
      expect(player.playCalls, 0);
    },
  );

  testWidgets(
    'confirmed readiness finishes preparation without fabricated progress',
    (tester) async {
      player.ready = false;
      final starting = practice.start(const PracticePlan());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(practice.busy, isTrue);
      expect(player.playCalls, 0);
      player.emit(ready: true);
      await tester.pump(const Duration(milliseconds: 250));
      await starting;
      expect(practice.running, isTrue);
      expect(player.playCalls, 1);
      expect(practice.totalRepetitions, 0);
    },
  );

  test(
    'unconfirmed speed, loop, seek and play all leave training paused',
    () async {
      for (final failure in <String>['speed', 'loop', 'seek', 'play']) {
        player.failure = failure;
        await practice.start(const PracticePlan());
        expect(practice.status, PracticeStatus.paused, reason: failure);
        expect(player.playing, isFalse, reason: failure);
        expect(practice.totalRepetitions, 0, reason: failure);
        player.failure = null;
        await practice.stop();
        player.loop = false;
        player.currentSpeed = 1;
        player.currentPosition = const Duration(seconds: 3);
      }
    },
  );

  test('load/source loss during preparation aborts without playing', () async {
    player.speedGate = Completer<void>();
    final starting = practice.start(const PracticePlan());
    await _settle();
    player.isLoaded = false;
    player.emit();
    player.speedGate!.complete();
    await starting;
    expect(practice.status, PracticeStatus.aborted);
    expect(practice.snapshot, isNull);
    expect(player.playCalls, 0);
  });

  test(
    'snapshot roundtrip restores paused and only resume starts output',
    () async {
      await practice.start(const PracticePlan());
      player.emit(count: 1);
      final saved = PracticeProgress.parse(practice.snapshot!.toJson())!;
      await practice.pause();
      practice.dispose();
      practice = PracticeController(player);
      final playCalls = player.playCalls;
      practice.restore(saved);
      expect(practice.status, PracticeStatus.paused);
      expect(practice.currentPercent, 60);
      expect(practice.stepRepetitions, 1);
      expect(practice.totalRepetitions, 1);
      expect(player.playCalls, playCalls);
      expect(player.playing, isFalse);
      await practice.resume();
      expect(practice.running, isTrue);
      expect(practice.totalRepetitions, 1);
      expect(player.playCalls, playCalls + 1);
    },
  );

  test(
    'restore ignores another source or range and retains completed status',
    () async {
      practice.restore(_saved(source: 'local:file:///other.wav'));
      expect(practice.hasSession, isFalse);
      practice.restore(_saved(aMs: 2500));
      expect(practice.hasSession, isFalse);
      practice.restore(
        _saved(
          current: 100,
          step: 3,
          total: 27,
          status: PracticeStatus.completed,
        ),
      );
      expect(practice.status, PracticeStatus.completed);
      expect(practice.canResume, isFalse);
      expect(player.playCalls, 0);
    },
  );

  test(
    'an aborted saved plan cannot become a resumable training session',
    () async {
      practice.restore(_saved(status: PracticeStatus.aborted));
      expect(practice.status, isNot(PracticeStatus.paused));
      expect(practice.canResume, isFalse);
      await practice.resume();
      expect(player.commands, isEmpty);
      expect(player.playCalls, 0);
    },
  );

  test(
    'a paused plan cannot resume onto a different source or range',
    () async {
      await practice.start(const PracticePlan());
      player.emit(count: 1);
      await practice.pause();
      final commandCount = player.commands.length;
      player.source = 'local:file:///other.wav';
      player.emit(count: 99);
      expect(practice.status, PracticeStatus.aborted);
      expect(practice.canResume, isFalse);
      expect(practice.snapshot, isNull);
      await practice.resume();
      expect(player.commands.length, commandCount);
      expect(practice.totalRepetitions, 1);
      player.source = 'local:file:///practice.wav';
      player.a = const Duration(milliseconds: 2500);
      player.emit();
      expect(practice.canResume, isFalse);
      await practice.resume();
      expect(player.commands.length, commandCount);
      player.a = const Duration(seconds: 2);
      player.emit();
      expect(practice.canResume, isFalse);
      expect(player.commands.length, commandCount);
      await practice.resume();
      expect(practice.running, isFalse);
      expect(practice.totalRepetitions, 1);
      await practice.start(const PracticePlan());
      expect(practice.running, isTrue);
      expect(practice.totalRepetitions, 0);
      expect(player.position, const Duration(seconds: 2));
    },
  );

  test('missed boundaries do not skip speeds or attribute old loops to a new speed', () async {
    await practice.start(const PracticePlan(repetitionsPerStep: 2));
    player.emit(count: 5);
    await _settle();
    expect(practice.totalRepetitions, 5);
    expect(practice.stepRepetitions, 2);
    expect(practice.currentPercent, 60);
    expect(practice.status, PracticeStatus.paused);
    expect(player.playing, isFalse);
    expect(player.speeds, <double>[.6]);
    await practice.resume();
    expect(practice.currentPercent, 65);
    expect(practice.stepRepetitions, 0);
    expect(practice.totalRepetitions, 5);
    expect(player.speeds, <double>[.6, .65]);
  });

  test(
    'skip advances without adding repetitions and cannot fake completion',
    () async {
      await practice.start(const PracticePlan(targetPercent: 65));
      await practice.skipStep();
      expect(practice.currentPercent, 65);
      expect(practice.totalRepetitions, 0);
      final playCalls = player.playCalls;
      await practice.skipStep();
      expect(practice.status, PracticeStatus.running);
      expect(practice.currentPercent, 65);
      expect(player.playCalls, playCalls);
      expect(practice.totalRepetitions, 0);
    },
  );

  test('stop and explicit restart reset progress but preserve player settings on stop', () async {
    await practice.start(const PracticePlan());
    player.emit(count: 1);
    await practice.stop();
    expect(practice.status, PracticeStatus.aborted);
    expect(player.speed, .6);
    expect(player.loopEnabled, isTrue);
    expect(player.markerA, const Duration(seconds: 2));
    expect(player.playing, isFalse);
    await practice.start(const PracticePlan(startPercent: 80));
    expect(practice.running, isTrue);
    expect(practice.currentPercent, 80);
    expect(practice.totalRepetitions, 0);
    expect(practice.stepRepetitions, 0);
  });

  test(
    'invalid plan or unsupported source does not issue player commands',
    () async {
      await practice.start(const PracticePlan(incrementPercent: 0));
      expect(player.commands, isEmpty);
      player.telemetry = false;
      await practice.start(const PracticePlan());
      expect(player.commands, isEmpty);
      expect(practice.hasSession, isFalse);
      expect(practice.unavailableReason, isNotNull);
    },
  );
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

PracticeProgress _saved({
  String source = 'local:file:///practice.wav',
  int aMs = 2000,
  int current = 65,
  int step = 1,
  int total = 4,
  PracticeStatus status = PracticeStatus.paused,
}) => PracticeProgress(
  id: 'saved-practice',
  sourceKey: source,
  aMs: aMs,
  bMs: 4000,
  plan: const PracticePlan(),
  currentPercent: current,
  stepRepetitions: step,
  totalRepetitions: total,
  status: status,
);

class _Player extends MainPlayerController {
  bool isLoaded = true, isPlaying = false, isBusy = false, isMuted = false;
  bool telemetry = true, ready = true, nativePlaying = false, loop = false;
  int epoch = 1, count = 0, playCalls = 0;
  int manualRevision = 0, nativeInterruptionRevision = 0;
  double currentSpeed = 1;
  String source = 'local:file:///practice.wav';
  String? failure;
  Duration currentPosition = const Duration(seconds: 3);
  Duration? a = const Duration(seconds: 2), b = const Duration(seconds: 4);
  Completer<void>? speedGate;
  final commands = <String>[];
  final speeds = <double>[];

  @override
  bool get loaded => isLoaded;
  @override
  int get manualControlRevision => manualRevision;
  @override
  int get interruptionRevision => nativeInterruptionRevision;
  @override
  bool get playing => isPlaying;
  @override
  bool get busy => isBusy;
  @override
  bool get muted => isMuted;
  @override
  bool get canSpeed => isLoaded;
  @override
  bool get canLoop => isLoaded;
  @override
  bool get pitchPending => false;
  @override
  String get sourceKey => isLoaded ? source : '';
  @override
  Duration? get markerA => a;
  @override
  Duration? get markerB => b;
  @override
  Duration get position => currentPosition;
  @override
  double get speed => currentSpeed;
  @override
  bool get loopEnabled => loop;
  @override
  LoopObservation? get loopObservation => !telemetry
      ? null
      : LoopObservation(
          epoch: epoch,
          count: count,
          ready: ready,
          playing: nativePlaying,
        );

  void emit({
    int? count,
    int? epoch,
    bool? ready,
    bool? playing,
    Duration? position,
  }) {
    if (count != null) this.count = count;
    if (epoch != null) this.epoch = epoch;
    if (ready != null) this.ready = ready;
    if (playing != null) {
      isPlaying = playing;
      nativePlaying = playing;
    }
    if (position != null) currentPosition = position;
    notifyListeners();
  }

  void externalControlIntent() {
    manualRevision++;
    emit();
  }

  Future<void> externalPause() async {
    externalControlIntent();
    await pause();
  }

  void externalInterruption() {
    nativeInterruptionRevision++;
    emit(playing: false);
  }

  @override
  Future<void> pause() async {
    commands.add('pause');
    emit(playing: false);
  }

  @override
  Future<void> toggleLoop() async {
    commands.add('loop');
    if (failure == 'loop') return;
    loop = !loop;
    emit(epoch: epoch + 1, count: 0);
  }

  @override
  Future<void> changeSpeed(double value) async {
    commands.add('speed:$value');
    speeds.add(value);
    await speedGate?.future;
    if (failure == 'speed') return;
    currentSpeed = value;
    emit();
  }

  @override
  Future<void> seek(Duration position) async {
    commands.add('seek:${position.inMilliseconds}');
    if (failure == 'seek') return;
    emit(epoch: epoch + 1, count: 0, position: position);
  }

  @override
  Future<void> playPause() async {
    commands.add('play');
    playCalls++;
    if (failure == 'play') return;
    emit(playing: !isPlaying);
  }
}
