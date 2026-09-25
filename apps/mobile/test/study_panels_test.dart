import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transpose_mobile/chord_sheet.dart';
import 'package:transpose_mobile/player_panel_model.dart';
import 'package:transpose_mobile/player_presets.dart';
import 'package:transpose_mobile/stage_panel.dart';

class _Model extends PlayerPanelModel {
  @override
  bool loaded = true;
  @override
  bool playing = false;
  @override
  bool busy = false;
  @override
  bool canPitch = true;
  @override
  bool canSpeed = true;
  @override
  bool canLoop = true;
  @override
  bool muted = false;
  @override
  String title = 'Música real';
  @override
  String sourceLabel = 'Local';
  @override
  String? message;
  @override
  Duration position = Duration.zero;
  @override
  Duration duration = const Duration(minutes: 3);
  @override
  double pitch = 2;
  @override
  double speed = 1;
  @override
  Duration? markerA;
  @override
  Duration? markerB;
  @override
  bool loopEnabled = false;
  @override
  Future<void> playPause() async {
    playing = !playing;
    notifyListeners();
  }

  @override
  Future<void> seek(Duration value) async {
    position = value;
    notifyListeners();
  }

  @override
  Future<void> changePitch(double value) async {
    pitch = value;
    notifyListeners();
  }

  @override
  Future<void> changeSpeed(double value) async {
    speed = value;
    notifyListeners();
  }

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

PlayerPreset _preset(String id) => PlayerPreset(
  id: id,
  name: 'Faixa $id',
  title: 'Música $id',
  sourceId: id,
  locator: 'file:///$id.wav',
  youtube: false,
  pitch: 0,
  speed: 1,
  positionMs: 0,
);

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  Future<void> tap(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  test('manual cue timestamps validate order and locate current chord', () {
    final cues = parseChordCues('00:02 C\n00:08.25 Am7\n01:16 G/B');
    expect(cues[1].milliseconds, 8250);
    expect(currentChordIndex(cues, Duration.zero), -1);
    expect(currentChordIndex(cues, const Duration(seconds: 9)), 1);
    expect(() => parseChordCues('00:08 C\n00:08 D'), throwsFormatException);
    expect(() => parseChordCues('00:60 C'), throwsFormatException);
    expect(() => parseChordCues('Am G F'), throwsFormatException);
  });
  test('chord sheets persist original chords and notes per source', () async {
    final store = ChordSheetStore();
    await store.save(
      'youtube:one',
      const ChordSheet(timeline: '00:00 C\n00:08 Am', notes: 'Verso suave'),
    );
    expect((await ChordSheetStore().read('youtube:one')).notes, 'Verso suave');
    expect((await store.read('local:two')).timeline, isEmpty);
    await expectLater(
      store.save('youtube:one', const ChordSheet(timeline: 'invalid')),
      throwsFormatException,
    );
    expect((await store.read('youtube:one')).timeline, contains('00:08 Am'));
  });
  testWidgets('chords follow real pitch, seek and save editable sheet', (
    tester,
  ) async {
    final model = _Model();
    final store = ChordSheetStore();
    await store.save(
      'local:test',
      const ChordSheet(timeline: '00:00 C\n00:08 Am', notes: 'Nota inicial'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChordsPanel(
            model: model,
            sourceKey: 'local:test',
            store: store,
            onOpenPlayer: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('D'), findsWidgets);
    expect(find.text('Bm'), findsWidgets);
    await tap(tester, 'chordCue1');
    expect(model.position, const Duration(seconds: 8));
    await tap(tester, 'chordsPlay');
    expect(model.playing, isTrue);
    await tap(tester, 'chordsEdit');
    await tester.enterText(
      find.byKey(const Key('chordsTimelineInput')),
      '00:00 F\n00:09 G',
    );
    await tester.enterText(
      find.byKey(const Key('chordsNotesInput')),
      'Minha nota',
    );
    await tap(tester, 'chordsSave');
    expect((await store.read('local:test')).notes, 'Minha nota');
    expect((await store.read('local:test')).timeline, contains('00:00 F'));
    await tap(tester, 'chordsEdit');
    await tester.enterText(
      find.byKey(const Key('chordsNotesInput')),
      'Ainda por guardar',
    );
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('Descartar alterações?'), findsOneWidget);
    await tester.tap(find.text('Continuar a editar'));
    await tester.pumpAndSettle();
    expect(find.text('Ainda por guardar'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Descartar'));
    await tester.pumpAndSettle();
    expect((await store.read('local:test')).notes, 'Minha nota');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'stage uses shared transport and setlist, lock prevents changes',
    (tester) async {
      final model = _Model();
      final store = PlayerPresetStore();
      await store.save(_preset('1'), setlist: true);
      await store.save(_preset('2'), setlist: true);
      String? chosen;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StagePanel(
              model: model,
              store: store,
              sourceKey: 'local:file:///1.wav',
              onApply: (p) async {
                chosen = p.id;
                return true;
              },
              onCollections: () {},
              onAdd: () {},
              onTool: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('SETLIST · 1 DE 2'), findsOneWidget);
      await tap(tester, 'visualStagePitchUp');
      expect(model.pitch, 3);
      await tap(tester, 'visualStageExecute');
      expect(model.playing, isTrue);
      await tap(tester, 'visualStageNext');
      expect(chosen, '2');
      await tap(tester, 'visualStageLock');
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('visualStagePitchUp')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('visualStageExecute')))
            .onPressed,
        isNull,
      );
      await tap(tester, 'visualStageLock');
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('visualStageExecute')))
            .onPressed,
        isNull,
      );
      await tester.longPress(find.byKey(const Key('visualStageLock')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('visualStageExecute')))
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('stage failure keeps selected song and exposes retry message', (
    tester,
  ) async {
    final store = PlayerPresetStore();
    await store.save(_preset('1'), setlist: true);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StagePanel(
            model: _Model()..loaded = false,
            store: store,
            sourceKey: '',
            onApply: (_) async => false,
            onCollections: () {},
            onAdd: () {},
            onTool: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tap(tester, 'visualStageNext');
    expect(find.textContaining('Não foi possível preparar'), findsOneWidget);
    expect(find.text('SETLIST · 1 MÚSICAS'), findsOneWidget);
  });
  for (final size in [const Size(320, 700), const Size(844, 390)]) {
    testWidgets('study panels fit $size with text scaling 2', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final model = _Model();
      for (final panel in <Widget>[
        StagePanel(
          model: model,
          store: PlayerPresetStore(),
          sourceKey: '',
          onApply: (_) async => true,
          onCollections: () {},
          onAdd: () {},
          onTool: (_) {},
        ),
        ChordsPanel(
          model: model,
          sourceKey: '',
          store: ChordSheetStore(),
          onOpenPlayer: () {},
        ),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: const TextScaler.linear(2),
              ),
              child: Scaffold(body: panel),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  }
}
