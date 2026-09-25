import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:transpose_mobile/main_player_controller.dart';
import 'package:transpose_mobile/player_presets.dart';
import 'package:transpose_mobile/practice_session.dart';
import 'package:transpose_mobile/session_recovery_controller.dart';
import 'package:transpose_mobile/session_snapshot.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'local startup restores saved adjustments and presentation paused',
    () async {
      final stored = _snapshot(
        _media(position: 15000, loop: true),
        screen: 'stage',
      );
      final harness = _Harness(result: SessionRecoveryResult(snapshot: stored));
      addTearDown(harness.close);

      await harness.recovery.initialize();
      await harness.recovery.flush();

      expect(harness.player.restored, [stored.media]);
      expect(harness.player.playing, isFalse);
      expect(harness.player.playCalls, 0);
      expect(harness.player.current!.positionMs, 15000);
      expect(harness.player.current!.loop, isTrue);
      expect(harness.restored, [stored]);
      expect(harness.recovery.pending, isNull);
      expect(harness.recovery.restorationMilliseconds, isNonNegative);
      expect(harness.recovery.message, contains('reproduzir'));
    },
  );

  test(
    'YouTube startup is metadata only until an explicit restore action',
    () async {
      final stored = _snapshot(_media(youtube: true));
      final harness = _Harness(result: SessionRecoveryResult(snapshot: stored));
      addTearDown(harness.close);

      await harness.recovery.initialize();
      await harness.recovery.flush();

      expect(harness.recovery.pending, same(stored));
      expect(harness.player.restored, isEmpty);
      expect(harness.player.openCalls, 0);
      expect(harness.player.playCalls, 0);
      expect(harness.repository.saved, isEmpty);

      await harness.recovery.restorePending();
      expect(harness.player.restored, [stored.media]);
      expect(harness.player.playing, isFalse);
      expect(harness.player.playCalls, 0);
      expect(harness.recovery.pending, isNull);
    },
  );

  test('pending source and DSP intentions are never committed', () async {
    final harness = _Harness();
    addTearDown(harness.close);
    await harness.recovery.initialize();

    harness.player.update(_media(pitch: 1));
    await harness.recovery.flush();
    expect(harness.repository.saved.last.media.pitch, 1);

    harness.player.update(_media(pitch: 6), busy: true);
    await harness.recovery.flush();
    expect(harness.repository.saved.last.media.pitch, 1);
    harness.player.update(_media(pitch: 6), pitchPending: true);
    await harness.recovery.flush();
    expect(harness.repository.saved.last.media.pitch, 1);

    harness.player.update(_media(pitch: 6));
    await harness.recovery.flush();
    expect(harness.repository.saved.last.media.pitch, 6);
    expect(harness.repository.saved.map((s) => s.media.pitch), [1, 6]);
  });

  test(
    'unsettled practice transitions retain the last confirmed snapshot',
    () async {
      final harness = _Harness();
      addTearDown(harness.close);
      await harness.recovery.initialize();
      harness.presentation = SessionPresentation(practice: _progress());
      harness.player.update(_media(position: 12000));
      await harness.recovery.flush();
      expect(harness.repository.saved.single.practice!.currentPercent, 75);

      harness.presentation = SessionPresentation(
        settled: false,
        practice: _progress(current: 80, step: 0, total: 8),
      );
      harness.player.update(_media(position: 10000, pitch: 3));
      harness.recovery.presentationChanged();
      await harness.recovery.flush();
      expect(harness.repository.saved.length, 1);
      expect(harness.repository.saved.last.media.pitch, 2);
      expect(harness.repository.saved.last.media.positionMs, 12000);

      harness.presentation = SessionPresentation(
        practice: _progress(current: 80, step: 0, total: 8),
      );
      harness.recovery.presentationChanged();
      await harness.recovery.flush();
      expect(harness.repository.saved.length, 2);
      expect(harness.repository.saved.last.media.pitch, 3);
      expect(harness.repository.saved.last.media.positionMs, 10000);
      expect(harness.repository.saved.last.practice!.currentPercent, 80);
    },
  );

  test(
    'an unsettled initial presentation does not create a partial snapshot',
    () async {
      final harness = _Harness();
      addTearDown(harness.close);
      harness.presentation = SessionPresentation(
        settled: false,
        practice: _progress(),
      );
      harness.player.update(_media());
      await harness.recovery.initialize();
      await harness.recovery.flush();
      expect(harness.repository.saved, isEmpty);
      harness.presentation = SessionPresentation(practice: _progress());
      harness.recovery.presentationChanged();
      await harness.recovery.flush();
      expect(harness.repository.saved.length, 1);
      expect(harness.repository.saved.single.practice!.totalRepetitions, 6);
    },
  );

  testWidgets(
    'practice progress commits immediately during continuous playback',
    (tester) async {
      final harness = _Harness(positionInterval: const Duration(seconds: 5));
      try {
        await harness.recovery.initialize();
        harness.presentation = SessionPresentation(practice: _progress());
        harness.player.update(_media(position: 12000), playing: true);
        await tester.pump();
        expect(harness.repository.saved.length, 1);
        harness.player.update(_media(position: 13000), playing: true);
        await tester.pump(const Duration(milliseconds: 100));
        expect(harness.repository.saved.length, 1);

        harness.presentation = SessionPresentation(
          practice: _progress(step: 1, total: 7),
        );
        harness.recovery.presentationChanged();
        await tester.pump();
        expect(harness.repository.saved.length, 2);
        expect(harness.repository.saved.last.practice!.totalRepetitions, 7);
        expect(harness.repository.saved.last.practice!.stepRepetitions, 1);
        expect(harness.repository.saved.last.media.positionMs, 13000);
        expect(
          harness.repository.saved.last.practiceSessionId,
          'practice-session',
        );
        expect(harness.repository.saved.last.practiceCurrent, .75);
        expect(harness.repository.saved.last.practiceTarget, .85);

        harness.recovery.presentationChanged();
        await tester.pump();
        expect(
          harness.repository.saved.length,
          2,
          reason: 'Same progress is deduplicated.',
        );
        harness.presentation = const SessionPresentation();
        harness.recovery.presentationChanged();
        await tester.pump();
        expect(harness.repository.saved.length, 3);
        expect(harness.repository.saved.last.practice, isNull);
      } finally {
        final closing = harness.close();
        await tester.pump();
        await closing;
      }
    },
  );

  testWidgets(
    'entering a pending operation checkpoints the last acknowledged position',
    (tester) async {
      final harness = _Harness();
      try {
        await harness.recovery.initialize();
        harness.player.update(_media(position: 0), playing: true);
        await tester.pump();
        harness.player.update(_media(position: 1000), playing: true);
        await tester.pump(const Duration(milliseconds: 100));
        expect(harness.repository.saved.map((s) => s.media.positionMs), [0]);

        // 9000 is an unacknowledged seek target. A crash here may restore 1000,
        // never the requested target or an arbitrarily old five-second snapshot.
        harness.player.update(
          _media(position: 9000),
          playing: true,
          busy: true,
        );
        await tester.pump();
        expect(harness.repository.saved.map((s) => s.media.positionMs), [
          0,
          1000,
        ]);
        await harness.recovery.flush();
        expect(harness.repository.saved.last.media.positionMs, 1000);
      } finally {
        // Close while this test's FakeAsync zone can still drain its Future
        // chain. Async addTearDown runs after that zone stops pumping.
        final closing = harness.close();
        await tester.pump();
        await closing;
      }
    },
  );

  testWidgets(
    'position saving is throttled during continuous playback and immediate on pause',
    (tester) async {
      final harness = _Harness(positionInterval: const Duration(seconds: 5));
      try {
        await harness.recovery.initialize();

        harness.player.update(_media(position: 0), playing: true);
        await tester.pump();
        expect(harness.repository.saved.map((s) => s.media.positionMs), [0]);
        harness.player.update(_media(position: 1000), playing: true);
        await tester.pump(const Duration(seconds: 2));
        harness.player.update(_media(position: 3000), playing: true);
        await tester.pump(const Duration(seconds: 2));
        harness.player.update(_media(position: 4000), playing: true);
        expect(harness.repository.saved.length, 1);
        await tester.pump(const Duration(seconds: 1));
        expect(harness.repository.saved.map((s) => s.media.positionMs), [
          0,
          4000,
        ]);

        harness.player.update(_media(position: 4200), playing: true);
        harness.player.update(_media(position: 4500));
        await tester.pump();
        expect(harness.repository.saved.last.media.positionMs, 4500);
        final count = harness.repository.saved.length;
        await tester.pump(const Duration(seconds: 10));
        expect(harness.repository.saved.length, count);
      } finally {
        final closing = harness.close();
        await tester.pump();
        await closing;
      }
    },
  );

  test(
    'identical acknowledgements are deduplicated but navigation is saved',
    () async {
      final harness = _Harness();
      addTearDown(harness.close);
      await harness.recovery.initialize();
      harness.player.update(_media(position: 5000));
      await harness.recovery.flush();
      harness.player.update(_media(position: 5000));
      await harness.recovery.flush();
      expect(harness.repository.saved.length, 1);

      harness.presentation = const SessionPresentation(
        screen: 'chords',
        fullscreen: true,
        activePresetId: 'saved-1',
      );
      harness.recovery.presentationChanged();
      await harness.recovery.flush();
      expect(harness.repository.saved.length, 2);
      expect(harness.repository.saved.last.screen, 'chords');
      expect(harness.repository.saved.last.fullscreen, isTrue);
      expect(harness.repository.saved.last.activePresetId, 'saved-1');
    },
  );

  test(
    'save failure pauses autosave and retry commits the newest confirmed state',
    () async {
      final harness = _Harness();
      addTearDown(harness.close);
      await harness.recovery.initialize();
      harness.repository.failSaves = true;
      harness.player.update(_media(pitch: 2));
      await harness.recovery.flush();
      expect(harness.recovery.saveFailed, isTrue);
      expect(harness.repository.saved, isEmpty);
      expect(harness.recovery.message, contains('Não foi possível guardar'));

      harness.player.update(_media(pitch: 4));
      await harness.recovery.flush();
      expect(harness.repository.saveCalls, 1);
      harness.repository.failSaves = false;
      await harness.recovery.retrySave();
      expect(harness.repository.readCalls, 2);
      expect(harness.recovery.saveFailed, isFalse);
      expect(harness.repository.saved.single.media.pitch, 4);
    },
  );

  test(
    'read failure preserves storage and retry rechecks before saving',
    () async {
      final harness = _Harness();
      addTearDown(harness.close);
      harness.repository.failReads = true;
      await harness.recovery.initialize();
      expect(harness.recovery.saveFailed, isTrue);
      expect(harness.recovery.message, contains('ler'));
      harness.player.update(_media());
      await harness.recovery.flush();
      expect(harness.repository.saveCalls, 0);
      expect(harness.repository.clearCalls, 0);

      harness.repository.failReads = false;
      await harness.recovery.retrySave();
      expect(harness.recovery.saveFailed, isFalse);
      expect(harness.repository.readCalls, 2);
      expect(harness.repository.saved.length, 1);
      expect(harness.repository.clearCalls, 0);
    },
  );

  test(
    'failed source restoration retains its snapshot and permits retry',
    () async {
      final stored = _snapshot(_media());
      final harness = _Harness(result: SessionRecoveryResult(snapshot: stored));
      addTearDown(harness.close);
      harness.player.restoreSucceeds = false;
      await harness.recovery.initialize();
      await harness.recovery.flush();
      expect(harness.recovery.pending, same(stored));
      expect(harness.repository.saved, isEmpty);
      expect(harness.repository.clearCalls, 0);
      expect(harness.restored, isEmpty);

      harness.player.restoreSucceeds = true;
      await harness.recovery.restorePending();
      expect(harness.recovery.pending, isNull);
      expect(harness.restored, [stored]);
      expect(harness.player.restored.length, 2);
    },
  );

  test('dismiss after failed restore preserves saved snapshot and actionable notice', () async {
    final stored = _snapshot(_media(pitch: 2));
    final harness = _Harness(result: SessionRecoveryResult(snapshot: stored));
    addTearDown(harness.close);
    harness.player.restoreSucceeds = false;
    await harness.recovery.initialize();

    // Loading can succeed before a subsequent adjustment fails. This partial
    // player is not permission to overwrite the original recoverable values.
    harness.player.update(_media(pitch: 0, position: 1000));
    harness.recovery.dismissNotice();
    await harness.recovery.flush();
    expect(harness.recovery.pending, same(stored));
    expect(harness.recovery.message, isNotNull);
    expect(harness.recovery.message, isNotEmpty);
    expect(harness.repository.saved, isEmpty);
    expect(harness.repository.clearCalls, 0);

    harness.player.update(_media(pitch: 1, position: 1500));
    await harness.recovery.flush();
    expect(harness.repository.saved, isEmpty);
    expect(harness.recovery.pending, same(stored));
  });

  test(
    'explicitly using the current confirmed session releases recovery hold',
    () async {
      final stored = _snapshot(_media(pitch: 2));
      final harness = _Harness(result: SessionRecoveryResult(snapshot: stored));
      addTearDown(harness.close);
      harness.player.restoreSucceeds = false;
      await harness.recovery.initialize();
      harness.player.update(_media(pitch: 0, position: 1000));
      await harness.recovery.flush();
      expect(harness.repository.saved, isEmpty);

      harness.recovery.useCurrentSession();
      await harness.recovery.flush();
      expect(harness.recovery.pending, isNull);
      expect(harness.repository.saved.single.media.pitch, 0);
      expect(harness.repository.saved.single.media.positionMs, 1000);
      expect(harness.repository.clearCalls, 0);
      expect(harness.player.playCalls, 0);

      harness.player.update(_media(pitch: 1, position: 2000));
      await harness.recovery.flush();
      expect(harness.repository.saved.map((s) => s.media.pitch), [0, 1]);
      expect(harness.repository.saved.last.media.positionMs, 2000);
    },
  );

  test(
    'using the current session refuses unacknowledged player state',
    () async {
      final stored = _snapshot(_media());
      final harness = _Harness(result: SessionRecoveryResult(snapshot: stored));
      addTearDown(harness.close);
      harness.player.restoreSucceeds = false;
      await harness.recovery.initialize();
      harness.player.update(_media(pitch: 7), busy: true);
      harness.recovery.useCurrentSession();
      await harness.recovery.flush();
      expect(harness.recovery.pending, same(stored));
      expect(harness.repository.saved, isEmpty);
      expect(harness.repository.clearCalls, 0);

      harness.player.update(_media(pitch: 7), pitchPending: true);
      harness.recovery.useCurrentSession();
      await harness.recovery.flush();
      expect(harness.recovery.pending, same(stored));
      expect(harness.repository.saved, isEmpty);
    },
  );

  test(
    'user source selection takes precedence over slow startup storage',
    () async {
      final stored = _snapshot(_media(source: 'old'));
      final harness = _Harness(result: SessionRecoveryResult(snapshot: stored));
      addTearDown(harness.close);
      final gate = Completer<SessionRecoveryResult>();
      harness.repository.readGate = gate;
      final initializing = harness.recovery.initialize();
      harness.recovery.beginUserSource();
      harness.player.update(_media(source: 'new'));
      gate.complete(SessionRecoveryResult(snapshot: stored));
      await initializing;
      await harness.recovery.flush();

      expect(harness.player.restored, isEmpty);
      expect(harness.recovery.pending, isNull);
      expect(harness.repository.saved.last.media.sourceId, 'new');
      expect(harness.restored, isEmpty);
    },
  );

  test('new user source cancels an in-flight restoration callback', () async {
    final stored = _snapshot(_media(source: 'old'));
    final harness = _Harness(result: SessionRecoveryResult(snapshot: stored));
    addTearDown(harness.close);
    final gate = Completer<void>();
    harness.player.restoreGate = gate;
    final initializing = harness.recovery.initialize();
    await Future<void>.delayed(Duration.zero);
    expect(harness.recovery.restoring, isTrue);
    harness.recovery.beginUserSource();
    harness.player.update(_media(source: 'new'));
    gate.complete();
    await initializing;
    await harness.recovery.flush();
    expect(harness.player.pauseCalls, 1);
    expect(harness.restored, isEmpty);
    expect(harness.recovery.pending, isNull);
    expect(harness.repository.saved.last.media.sourceId, 'new');
  });

  test(
    'close during pending read never restores or notifies disposed listeners',
    () async {
      final harness = _Harness();
      final gate = Completer<SessionRecoveryResult>();
      harness.repository.readGate = gate;
      final initializing = harness.recovery.initialize();
      final closing = harness.recovery.close();
      gate.complete(SessionRecoveryResult(snapshot: _snapshot(_media())));
      await closing;
      await initializing;

      expect(harness.player.restored, isEmpty);
      expect(harness.restored, isEmpty);
      expect(harness.repository.saved, isEmpty);
      expect(harness.repository.closeCalls, 1);
      harness.player.dispose();
    },
  );

  test(
    'future-format protection blocks writes and retry without deleting data',
    () async {
      final harness = _Harness(
        result: const SessionRecoveryResult(
          writeBlocked: true,
          warning: 'Atualize o app.',
        ),
      );
      addTearDown(harness.close);
      await harness.recovery.initialize();
      expect(harness.recovery.writeBlocked, isTrue);
      harness.recovery.beginUserSource();
      harness.player.update(_media());
      await harness.recovery.flush();
      await harness.recovery.retrySave();
      expect(harness.repository.readCalls, 1);
      expect(harness.repository.saveCalls, 0);
      expect(harness.repository.clearCalls, 0);
    },
  );
}

PlayerPreset _media({
  String source = 'song',
  bool youtube = false,
  int position = 23000,
  double pitch = 2,
  bool loop = false,
}) => PlayerPreset(
  id: 'preset-$source',
  name: 'Treino',
  title: 'Música $source',
  sourceId: youtube ? 'abcdefghijk' : source,
  locator: youtube ? 'abcdefghijk' : 'file:///C:/private/$source.wav',
  youtube: youtube,
  pitch: pitch,
  speed: .75,
  positionMs: position,
  aMs: 10000,
  bMs: 20000,
  loop: loop,
);

PracticeProgress _progress({int current = 75, int step = 0, int total = 6}) =>
    PracticeProgress(
      id: 'practice-session',
      sourceKey: 'local:file:///C:/private/song.wav',
      aMs: 10000,
      bMs: 20000,
      plan: const PracticePlan(
        startPercent: 60,
        targetPercent: 85,
        incrementPercent: 5,
        repetitionsPerStep: 2,
      ),
      currentPercent: current,
      stepRepetitions: step,
      totalRepetitions: total,
      status: PracticeStatus.running,
    );

SessionSnapshot _snapshot(PlayerPreset media, {String screen = 'player'}) =>
    SessionSnapshot(
      media: media,
      savedAt: DateTime.utc(2026, 9, 25),
      sessionId: 'previous-session',
      screen: screen,
      fullscreen: true,
      activePresetId: 'saved-1',
    );

class _Harness {
  _Harness({
    SessionRecoveryResult result = const SessionRecoveryResult(),
    Duration positionInterval = const Duration(seconds: 5),
  }) {
    repository.result = result;
    recovery = SessionRecoveryController(
      player: player,
      repository: repository,
      presentation: () => presentation,
      onRestored: restored.add,
      positionInterval: positionInterval,
    );
  }
  final player = _Player();
  final repository = _Repository();
  final restored = <SessionSnapshot>[];
  SessionPresentation presentation = const SessionPresentation();
  late final SessionRecoveryController recovery;
  Future<void> close() async {
    await recovery.close();
    player.dispose();
  }
}

class _Repository extends SessionSnapshotRepository {
  SessionRecoveryResult result = const SessionRecoveryResult();
  Completer<SessionRecoveryResult>? readGate;
  final saved = <SessionSnapshot>[];
  var readCalls = 0, saveCalls = 0, clearCalls = 0, closeCalls = 0;
  bool failReads = false, failSaves = false;

  @override
  Future<SessionRecoveryResult> read() async {
    readCalls++;
    if (failReads) throw StateError('Read failure');
    return readGate?.future ?? result;
  }

  @override
  Future<void> save(SessionSnapshot snapshot) async {
    saveCalls++;
    if (failSaves) throw StateError('No space left');
    saved.add(snapshot);
  }

  @override
  Future<void> clear() async => clearCalls++;
  @override
  Future<void> close() async => closeCalls++;
}

class _Player extends MainPlayerController {
  PlayerPreset? current;
  final restored = <PlayerPreset>[];
  Completer<void>? restoreGate;
  bool restoreSucceeds = true, _lastRestore = false;
  bool _playing = false, _busy = false, _pitchPending = false;
  int _pauseVersion = 0;
  var pauseCalls = 0, playCalls = 0, openCalls = 0;

  @override
  bool get playing => _playing;
  @override
  bool get loaded => current != null;
  @override
  bool get busy => _busy;
  @override
  bool get pitchPending => _pitchPending;
  @override
  bool get lastRestoreSucceeded => _lastRestore;

  void update(
    PlayerPreset media, {
    bool playing = false,
    bool busy = false,
    bool pitchPending = false,
  }) {
    current = media;
    _playing = playing;
    _busy = busy;
    _pitchPending = pitchPending;
    notifyListeners();
  }

  @override
  PlayerPreset? snapshot(String name) =>
      busy || pitchPending ? null : current?.renamed(name);

  @override
  Future<void> restore(PlayerPreset preset) async {
    restored.add(preset);
    final version = _pauseVersion;
    await restoreGate?.future;
    _lastRestore = restoreSucceeds && version == _pauseVersion;
    if (_lastRestore) update(preset);
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    _pauseVersion++;
    _playing = false;
    notifyListeners();
  }

  @override
  Future<void> playPause() async {
    playCalls++;
    _playing = !_playing;
    notifyListeners();
  }

  @override
  Future<void> openYouTube() async => openCalls++;
}
