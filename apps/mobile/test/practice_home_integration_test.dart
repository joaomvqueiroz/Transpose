import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transpose_mobile/loop_observation.dart';
import 'package:transpose_mobile/main_player_controller.dart';
import 'package:transpose_mobile/player_presets.dart';
import 'package:transpose_mobile/practice_controller.dart';
import 'package:transpose_mobile/practice_progression_card.dart';
import 'package:transpose_mobile/practice_session.dart';
import 'package:transpose_mobile/session_snapshot.dart';
import 'package:transpose_mobile/studio_visual_app.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.pump();
    if (key.startsWith('visualTab') &&
        find.byKey(Key(key)).evaluate().isEmpty) {
      await tester.tap(find.byKey(const Key('visualPlayerMenu')));
      await tester.pumpAndSettle();
    }
    final target = find.byKey(Key(key));
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pump();
  }

  PracticeController practice(WidgetTester tester) => tester
      .widget<PracticeProgressionCard>(find.byType(PracticeProgressionCard))
      .controller;

  void background(WidgetTester tester) {
    // Match the lifecycle notifications delivered when Android hides the app.
    for (final state in <AppLifecycleState>[
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
  }

  void foreground(WidgetTester tester) {
    final binding = tester.binding;
    if (binding.lifecycleState == AppLifecycleState.paused) {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    }
    if (binding.lifecycleState == AppLifecycleState.hidden) {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    }
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }

  Future<void> mount(
    WidgetTester tester,
    _Player player, {
    _Store? store,
  }) async {
    foreground(tester);
    await tester.pumpWidget(
      StudioVisualApp(playerController: player, recoveryRepository: store),
    );
    await tester.pumpAndSettle();
    await tap(tester, 'visualTabpractice');
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester, _Player player) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    player.dispose();
  }

  testWidgets(
    'home keeps the same practice session across player and fullscreen',
    (tester) async {
      final player = _Player();
      await mount(tester, player);
      final original = practice(tester);
      await tap(tester, 'practicePlanStart');
      await tester.pumpAndSettle();
      expect(original.running, isTrue);
      expect(player.playing, isTrue);
      player.completeLoop();
      await tester.pump();
      expect(original.totalRepetitions, 1);
      final id = original.snapshot!.id;

      await tap(tester, 'visualTabplayer');
      expect(find.byType(PracticeProgressionCard), findsNothing);
      player.completeLoop();
      await tester.pump();
      expect(original.totalRepetitions, 2);
      await tap(tester, 'visualPlayerMenu');
      await tester.dragFrom(const Offset(400, 500), const Offset(0, -300));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Tela cheia').last);
      await tester.tap(find.text('Tela cheia').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('visualFullscreenSurface')), findsOneWidget);
      player.completeLoop();
      await tester.pumpAndSettle();
      expect(original.currentPercent, 65);
      expect(original.totalRepetitions, 3);
      await tap(tester, 'visualFullscreenBack');
      await tester.pumpAndSettle();
      await tap(tester, 'visualTabpractice');
      expect(identical(practice(tester), original), isTrue);
      expect(original.snapshot!.id, id);
      expect(find.text('65% · Etapa 2/9'), findsOneWidget);
      expect(find.text('Total reproduzido: 3 voltas'), findsOneWidget);
      expect(player.playCalls, 2); // Initial step and one confirmed transition.
      expect(tester.takeException(), isNull);
      await unmount(tester, player);
    },
  );

  testWidgets(
    'background pauses practice away from its tab and never auto resumes',
    (tester) async {
      addTearDown(() => foreground(tester));
      final player = _Player();
      await mount(tester, player);
      final controller = practice(tester);
      await tap(tester, 'practicePlanStart');
      await tester.pumpAndSettle();
      player.completeLoop();
      await tester.pump();
      await tap(tester, 'visualTabplayer');
      background(tester);
      await tester.pumpAndSettle();
      expect(controller.status, PracticeStatus.paused);
      expect(player.playing, isFalse);
      final plays = player.playCalls;
      // Even a late adapter counter must not credit a paused session.
      player.completeLoop();
      await tester.pump(const Duration(seconds: 30));
      foreground(tester);
      await tester.pumpAndSettle();
      expect(player.playCalls, plays);
      expect(player.playing, isFalse);
      expect(controller.status, PracticeStatus.paused);
      expect(controller.totalRepetitions, 1);
      await tap(tester, 'visualTabpractice');
      expect(find.text('Treino pausado'), findsOneWidget);
      expect(find.text('Total reproduzido: 1 voltas'), findsOneWidget);
      await tap(tester, 'practicePlanResume');
      await tester.pumpAndSettle();
      expect(player.playCalls, plays + 1);
      expect(controller.totalRepetitions, 1);
      expect(player.position, player.markerA);
      expect(tester.takeException(), isNull);
      await unmount(tester, player);
    },
  );

  testWidgets(
    'background during preparation cancels pending play at home level',
    (tester) async {
      addTearDown(() => foreground(tester));
      final player = _Player()..seekGate = Completer<void>();
      await mount(tester, player);
      final controller = practice(tester);
      await tap(tester, 'practicePlanStart');
      expect(controller.busy, isTrue);
      background(tester);
      await tester.pump();
      player.seekGate!.complete();
      await tester.pumpAndSettle();
      expect(controller.status, PracticeStatus.paused);
      expect(controller.busy, isFalse);
      expect(player.playCalls, 0);
      expect(player.playing, isFalse);
      foreground(tester);
      await tester.pumpAndSettle();
      expect(player.playCalls, 0);
      expect(player.playing, isFalse);
      expect(controller.status, PracticeStatus.paused);
      expect(tester.takeException(), isNull);
      await unmount(tester, player);
    },
  );

  testWidgets('home saves confirmed practice progress and restores it paused', (
    tester,
  ) async {
    final store = _Store();
    final first = _Player();
    await mount(tester, first, store: store);
    await tap(tester, 'practicePlanStart');
    await tester.pumpAndSettle();
    first.completeLoop();
    await tester.pumpAndSettle();
    expect(store.saved?.practice?.totalRepetitions, 1);
    first.completeLoop();
    await tester.pumpAndSettle();
    expect(store.saved?.practice?.totalRepetitions, 2);
    expect(store.saved?.practice?.currentPercent, 60);
    expect(store.saved?.screen, 'practice');
    final savedId = store.saved!.practice!.id;
    await unmount(tester, first);

    final second = _Player();
    await tester.pumpWidget(
      StudioVisualApp(playerController: second, recoveryRepository: store),
    );
    await tester.pumpAndSettle();
    expect(second.restoreCalls, 1);
    expect(second.playCalls, 0);
    expect(second.playing, isFalse);
    expect(find.byKey(const Key('visualScrollpractice')), findsOneWidget);
    final restored = practice(tester);
    expect(restored.status, PracticeStatus.paused);
    expect(restored.totalRepetitions, 2);
    expect(restored.snapshot?.id, savedId);
    expect(find.byKey(const Key('practicePlanResume')), findsOneWidget);
    expect(find.text('Total reproduzido: 2 voltas'), findsOneWidget);
    await tap(tester, 'practicePlanResume');
    await tester.pumpAndSettle();
    expect(second.playCalls, 1);
    expect(restored.totalRepetitions, 2);
    second.completeLoop();
    await tester.pumpAndSettle();
    expect(restored.currentPercent, 65);
    expect(restored.totalRepetitions, 3);
    expect(tester.takeException(), isNull);
    await unmount(tester, second);
  });
}

class _Store extends SessionSnapshotRepository {
  SessionSnapshot? saved;
  @override
  Future<SessionRecoveryResult> read() async =>
      SessionRecoveryResult(snapshot: saved);
  @override
  Future<void> save(SessionSnapshot snapshot) async {
    // Use the production serialization contract, not an in-memory playing intent.
    saved = SessionSnapshot.parse(snapshot.toJson());
  }

  @override
  Future<void> clear() async {
    saved = null;
  }

  @override
  Future<void> close() async {}
}

class _Player extends MainPlayerController {
  bool _playing = false, _loop = true, _restored = false;
  double _speed = 1;
  Duration _position = const Duration(seconds: 2);
  int _count = 0, _epoch = 1;
  int playCalls = 0, restoreCalls = 0;
  Completer<void>? seekGate;
  @override
  bool get loaded => true;
  @override
  bool get playing => _playing;
  @override
  bool get busy => false;
  @override
  bool get pitchPending => false;
  @override
  bool get canPitch => true;
  @override
  bool get canSpeed => true;
  @override
  bool get canSeek => true;
  @override
  bool get canLoop => true;
  @override
  bool get muted => false;
  @override
  double get speed => _speed;
  @override
  double get pitch => 0;
  @override
  bool get loopEnabled => _loop;
  @override
  Duration get position => _position;
  @override
  Duration get duration => const Duration(seconds: 20);
  @override
  Duration? get markerA => const Duration(seconds: 2);
  @override
  Duration? get markerB => const Duration(seconds: 6);
  @override
  String get sourceKey => 'local:file:///qa/practice.wav';
  @override
  String get title => 'Trecho de teste de integração';
  @override
  String? get message => null;
  @override
  LoopObservation get loopObservation => LoopObservation(
    epoch: _epoch,
    count: _count,
    ready: true,
    playing: _playing,
  );
  void completeLoop() {
    _count++;
    _position = markerA!;
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    _playing = false;
    notifyListeners();
  }

  @override
  Future<void> playPause() async {
    _playing = !_playing;
    if (_playing) playCalls++;
    notifyListeners();
  }

  @override
  Future<void> changeSpeed(double value) async {
    _speed = value;
    notifyListeners();
  }

  @override
  Future<void> seek(Duration value) async {
    await seekGate?.future;
    _position = value;
    _epoch++;
    _count = 0;
    notifyListeners();
  }

  @override
  Future<void> toggleLoop() async {
    _loop = !_loop;
    _epoch++;
    _count = 0;
    notifyListeners();
  }

  @override
  PlayerPreset snapshot(String name) => PlayerPreset(
    id: 'qa-practice',
    name: name,
    title: title,
    sourceId: 'qa-practice',
    locator: 'file:///qa/practice.wav',
    youtube: false,
    pitch: pitch,
    speed: speed,
    positionMs: position.inMilliseconds,
    aMs: markerA!.inMilliseconds,
    bMs: markerB!.inMilliseconds,
    loop: loopEnabled,
  );
  @override
  bool get lastRestoreSucceeded => _restored;
  @override
  Future<void> restore(PlayerPreset preset) async {
    restoreCalls++;
    _playing = false;
    _speed = preset.speed;
    _position = Duration(milliseconds: preset.positionMs);
    _loop = preset.loop;
    _restored = true;
    notifyListeners();
  }
}
