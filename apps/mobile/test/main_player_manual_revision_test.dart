import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:transpose_mobile/main_player_controller.dart';
import 'package:transpose_mobile/media/local_player_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Local local;
  late MainPlayerController player;
  setUp(() {
    local = _Local();
    player = MainPlayerController(local: local);
  });
  tearDown(() => player.dispose());

  test(
    'external intents advance revision at enqueue time, not completion',
    () async {
      local.speedGate = Completer<void>();
      final initial = player.manualControlRevision;
      final changing = player.changeSpeed(.7);
      expect(player.manualControlRevision, initial + 1);
      await Future<void>.delayed(Duration.zero);
      expect(local.speedCalls, 1);
      final seeking = player.seek(const Duration(seconds: 3));
      expect(player.manualControlRevision, initial + 2);
      expect(local.seekCalls, 0);
      local.speedGate!.complete();
      await Future.wait<void>(<Future<void>>[changing, seeking]);
      expect(player.manualControlRevision, initial + 2);
      expect(local.seekCalls, 1);
    },
  );

  test('automatic commands do not advance the user intent revision', () async {
    final initial = player.manualControlRevision;
    await player.automatedCommand(() => player.changeSpeed(.6));
    await player.automatedCommand(player.pause);
    await player.automatedCommand(
      () => player.seek(const Duration(seconds: 2)),
    );
    expect(player.manualControlRevision, initial);
    expect(local.currentSpeed, .6);
    expect(local.pauseCalls, 1);
    expect(local.currentPosition, const Duration(seconds: 2));
  });

  test('a pending automated Future never hides an external pause', () async {
    local.speedGate = Completer<void>();
    final initial = player.manualControlRevision;
    final changing = player.automatedCommand(() => player.changeSpeed(.6));
    await Future<void>.delayed(Duration.zero);
    expect(player.manualControlRevision, initial);
    await player.pause();
    expect(player.manualControlRevision, initial + 1);
    expect(local.pauseCalls, 1);
    local.speedGate!.complete();
    await changing;
    expect(player.manualControlRevision, initial + 1);
  });

  test(
    'a pending automated Future never hides another queued user command',
    () async {
      local.speedGate = Completer<void>();
      final initial = player.manualControlRevision;
      final changing = player.automatedCommand(() => player.changeSpeed(.6));
      final manualSeek = player.seek(const Duration(seconds: 3));
      expect(player.manualControlRevision, initial + 1);
      local.speedGate!.complete();
      await Future.wait<void>(<Future<void>>[changing, manualSeek]);
      expect(player.manualControlRevision, initial + 1);
      expect(local.currentPosition, const Duration(seconds: 3));
    },
  );

  test('automation scope ends before async callback continuation', () async {
    final gate = Completer<void>();
    final initial = player.manualControlRevision;
    final delayed = player.automatedCommand(() async {
      await gate.future;
      await player.changeSpeed(.7);
    });
    expect(player.manualControlRevision, initial);
    gate.complete();
    await delayed;
    expect(player.manualControlRevision, initial + 1);
  });

  test(
    'failed automated callback cannot leave automation suppression enabled',
    () async {
      await expectLater(
        Future<void>.sync(
          () => player.automatedCommand(() => throw StateError('failed')),
        ),
        throwsStateError,
      );
      final initial = player.manualControlRevision;
      await player.pause();
      expect(player.manualControlRevision, initial + 1);
    },
  );
}

class _Local extends LocalPlayerController {
  Completer<void>? speedGate;
  double currentSpeed = 1;
  Duration currentPosition = Duration.zero;
  int speedCalls = 0, pauseCalls = 0, seekCalls = 0;

  @override
  bool get loaded => true;
  @override
  bool get canSpeed => true;
  @override
  bool get busy => false;
  @override
  Duration get duration => const Duration(seconds: 60);
  @override
  Duration get position => currentPosition;
  @override
  double get speed => currentSpeed;

  @override
  Future<void> changeSpeed(double value) async {
    speedCalls++;
    await speedGate?.future;
    currentSpeed = value;
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    notifyListeners();
  }

  @override
  Future<void> seek(Duration target) async {
    seekCalls++;
    currentPosition = target;
    notifyListeners();
  }
}
