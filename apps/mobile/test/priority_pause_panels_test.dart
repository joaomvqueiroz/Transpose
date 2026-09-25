import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transpose_mobile/chord_sheet.dart';
import 'package:transpose_mobile/main_player_panel.dart';
import 'package:transpose_mobile/player_panel_model.dart';
import 'package:transpose_mobile/player_presets.dart';
import 'package:transpose_mobile/practice_panel.dart';
import 'package:transpose_mobile/stage_panel.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  final panels = <(String, String, String?, Widget Function(_BusyModel))>[
    (
      'main',
      'visualPlayerPlay',
      null,
      (model) => SingleChildScrollView(
        child: MainPlayerPanel(
          model: model,
          media: const SizedBox(),
          onFullscreen: () {},
          onSearch: () {},
          onOpenFile: () {},
          onTool: (_) {},
        ),
      ),
    ),
    (
      'fullscreen',
      'visualFullscreenPlay',
      'visualFullscreenLock',
      (model) => MainPlayerFullscreen(
        model: model,
        media: const SizedBox(),
        onExit: () {},
      ),
    ),
    (
      'practice',
      'visualPracticePause',
      null,
      (model) => SingleChildScrollView(
        child: PracticePanel(
          model: model,
          onOpenPlayer: () {},
          onSaveLoop: () {},
          onOpenLoops: () {},
          onMetronome: () {},
        ),
      ),
    ),
    (
      'stage',
      'visualStageExecute',
      'visualStageLock',
      (model) => StagePanel(
        model: model,
        store: _Presets(),
        sourceKey: 'youtube:aqz-KE-bpKQ',
        onApply: (_) async => false,
        onCollections: () {},
        onAdd: () {},
        onTool: (_) {},
      ),
    ),
    (
      'chords',
      'chordsPlay',
      null,
      (model) => ChordsPanel(
        model: model,
        sourceKey: 'youtube:aqz-KE-bpKQ',
        store: _Chords(),
        onOpenPlayer: () {},
      ),
    ),
  ];

  for (final panel in panels) {
    testWidgets('${panel.$1} permits priority Pause but not Play while busy', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1000, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final model = _BusyModel();
      addTearDown(model.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(body: panel.$4(model)),
        ),
      );
      await tester.pump();
      final transport = find.byKey(Key(panel.$2));
      await tester.ensureVisible(transport);
      expect(_enabled(tester, transport), isTrue);
      await tester.tap(transport);
      await tester.pump();
      expect(model.playing, isFalse);
      expect(model.calls, 1);
      expect(
        model.busy,
        isTrue,
        reason: 'The pending audio adjustment is not complete',
      );
      expect(model.pitchPending, isTrue);
      expect(
        _enabled(tester, transport),
        isFalse,
        reason: 'Busy state must not enable Play',
      );

      model
        ..playing = true
        ..muted = true
        ..update();
      await tester.pump();
      expect(
        _enabled(tester, transport),
        isFalse,
        reason: 'Unmute/Play is not a priority Pause',
      );
      model
        ..loaded = false
        ..muted = false
        ..update();
      await tester.pump();
      expect(_enabled(tester, transport), isFalse);

      if (panel.$3 case final lockKey?) {
        model
          ..loaded = true
          ..update();
        await tester.pump();
        expect(_enabled(tester, transport), isTrue);
        final lock = find.byKey(Key(lockKey));
        await tester.ensureVisible(lock);
        await tester.tap(lock);
        await tester.pump();
        expect(
          _enabled(tester, transport),
          isFalse,
          reason: 'Explicit touch lock still applies',
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}

bool _enabled(WidgetTester tester, Finder finder) {
  final widget = tester.widget(finder);
  return widget is IconButton
      ? widget.onPressed != null
      : (widget as ButtonStyleButton).onPressed != null;
}

class _Presets extends PlayerPresetStore {
  @override
  Future<List<PlayerPreset>> list({bool setlist = false}) async => [];
}

class _Chords extends ChordSheetStore {
  @override
  Future<ChordSheet> read(String source) async => const ChordSheet();
}

class _BusyModel extends PlayerPanelModel {
  int calls = 0;
  @override
  bool loaded = true;
  @override
  bool playing = true;
  @override
  bool busy = true;
  @override
  bool pitchPending = true;
  @override
  bool muted = false;
  @override
  bool get canPitch => true;
  @override
  bool get canSpeed => true;
  @override
  bool get canLoop => true;
  @override
  String get title => 'Pending audio adjustment';
  @override
  String get sourceLabel => 'YouTube';
  @override
  String? get message => null;
  @override
  Duration get position => const Duration(seconds: 20);
  @override
  Duration get duration => const Duration(minutes: 3);
  @override
  double get pitch => 0;
  @override
  double get speed => 1;
  @override
  Duration? get markerA => null;
  @override
  Duration? get markerB => null;
  @override
  bool get loopEnabled => false;
  void update() => notifyListeners();
  @override
  Future<void> playPause() async {
    calls++;
    playing = !playing;
    update();
  }

  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> changePitch(double value) async {}
  @override
  Future<void> changeSpeed(double value) async {}
  @override
  Future<void> markA() async {}
  @override
  Future<void> markB() async {}
  @override
  Future<void> toggleLoop() async {}
  @override
  Future<void> clearLoop() async {}
  @override
  Future<void> resetProcessing() async {}
}
