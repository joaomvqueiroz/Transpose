import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transpose_mobile/player_panel_model.dart';
import 'package:transpose_mobile/practice_panel.dart';

void main() {
  Future<void> tap(WidgetTester tester, String key) async {
    final target = find.byKey(Key(key));
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pump();
  }

  Widget app(_Model model, {List<String>? actions, double scale = 1}) =>
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: PracticePanel(
                model: model,
                onOpenPlayer: () => actions?.add('player'),
                onSaveLoop: () => actions?.add('save'),
                onOpenLoops: () => actions?.add('saved'),
                onMetronome: () => actions?.add('metronome'),
                onEditLoop: () => actions?.add('edit'),
              ),
            ),
          ),
        ),
      );

  testWidgets('practice uses current shared A/B and player controls', (
    tester,
  ) async {
    final model = _Model();
    final actions = <String>[];
    await tester.pumpWidget(app(model, actions: actions));
    expect(find.text('Trecho de teste'), findsOneWidget);
    expect(find.textContaining('Treino manual'), findsOneWidget);
    await tap(tester, 'visualPracticeMarkA');
    model.position = const Duration(seconds: 25);
    await tap(tester, 'visualPracticeMarkB');
    expect(find.text('0:10 — 0:25'), findsOneWidget);
    await tap(tester, 'practiceLoopToggle');
    expect(model.loopEnabled, isTrue);
    await tap(tester, 'practiceReturnA');
    expect(model.position, const Duration(seconds: 10));
    await tap(tester, 'practiceEditLoop');
    await tap(tester, 'visualPracticeSaveLoop');
    await tap(tester, 'practiceSavedLoops');
    await tap(tester, 'practiceMetronome');
    expect(actions, <String>['edit', 'save', 'saved', 'metronome']);
    await tap(tester, 'visualPracticePause');
    expect(model.playing, isTrue);
    await tap(tester, 'visualPracticePause');
    expect(model.playing, isFalse);
    await tap(tester, 'practiceClearLoop');
    expect(model.markerA, isNull);
    expect(model.markerB, isNull);
    expect(model.loopEnabled, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('speed steps and sliders adjust actual engine intentions', (
    tester,
  ) async {
    final model = _Model();
    await tester.pumpWidget(app(model));
    await tap(tester, 'visualPracticeMinus');
    expect(model.speed, .95);
    await tap(tester, 'visualPracticePlus');
    expect(model.speed, 1);
    final slider = find.byKey(const Key('practiceSpeed'));
    await tester.ensureVisible(slider);
    await tester.drag(slider, const Offset(-180, 0));
    await tester.pump();
    expect(model.speed, lessThan(1));
    await tap(tester, 'practiceOriginalSpeed');
    expect(model.speed, 1);
    final seek = find.byKey(const Key('practiceSeek'));
    await tester.ensureVisible(seek);
    await tester.drag(seek, const Offset(200, 0));
    await tester.pump();
    expect(model.position, greaterThan(const Duration(seconds: 10)));
  });

  testWidgets('empty source leaves navigation usable and actions disabled', (
    tester,
  ) async {
    final model = _Model()..loaded = false;
    final actions = <String>[];
    await tester.pumpWidget(app(model, actions: actions));
    await tap(tester, 'practiceOpenPlayer');
    await tap(tester, 'practiceSavedLoops');
    expect(actions, <String>['player', 'saved']);
    for (final key in <String>[
      'visualPracticeMarkA',
      'visualPracticeMarkB',
      'visualPracticePause',
      'visualPracticeMinus',
      'visualPracticePlus',
      'visualPracticeSaveLoop',
    ]) {
      final button = tester.widget<ButtonStyleButton>(find.byKey(Key(key)));
      expect(button.onPressed, isNull, reason: key);
    }
  });

  testWidgets('unsupported source and busy state cannot send loop or speed', (
    tester,
  ) async {
    final model = _Model()..supported = false;
    await tester.pumpWidget(app(model));
    expect(find.text('A fonte atual não permite loop.'), findsOneWidget);
    expect(
      tester.widget<Slider>(find.byKey(const Key('practiceSpeed'))).onChanged,
      isNull,
    );
    model
      ..supported = true
      ..busy = true;
    model.notifyListeners();
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('visualPracticePause')))
          .onPressed,
      isNull,
    );
    expect(
      tester.widget<Slider>(find.byKey(const Key('practiceSeek'))).onChanged,
      isNull,
    );
  });

  testWidgets(
    'manual speed is not advanced by elapsed time or a backwards seek',
    (tester) async {
      final model = _Model()
        ..playing = true
        ..loopEnabled = true
        ..markerA = const Duration(seconds: 10)
        ..markerB = const Duration(seconds: 25)
        ..speed = .75;
      await tester.pumpWidget(app(model));
      model.position = const Duration(seconds: 24);
      model.notifyListeners();
      await tester.pump(const Duration(seconds: 20));
      model.position = const Duration(seconds: 10);
      model.notifyListeners();
      await tester.pump(const Duration(minutes: 10));
      expect(model.speed, .75);
      expect(find.text('75%'), findsOneWidget);
    },
  );

  testWidgets('practice fits narrow screen and large text without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(_Model(), scale: 2));
    await tap(tester, 'practiceMetronome');
    expect(tester.takeException(), isNull);
  });
}

class _Model extends PlayerPanelModel {
  @override
  bool loaded = true;
  @override
  bool busy = false;
  @override
  bool playing = false;
  bool supported = true;
  @override
  bool get canLoop => loaded && supported;
  @override
  bool get canPitch => loaded && supported;
  @override
  bool get canSpeed => loaded && supported;
  @override
  bool get muted => false;
  @override
  String get title => 'Trecho de teste';
  @override
  String get sourceLabel => 'Áudio de teste';
  @override
  String? get message => null;
  @override
  Duration position = const Duration(seconds: 10);
  @override
  Duration get duration => const Duration(minutes: 2);
  @override
  double pitch = 0;
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
  Future<void> changeSpeed(double value) async {
    speed = value;
    notifyListeners();
  }

  @override
  Future<void> markA() async {
    markerA = position;
    notifyListeners();
  }

  @override
  Future<void> markB() async {
    markerB = position;
    notifyListeners();
  }

  @override
  Future<void> toggleLoop() async {
    loopEnabled = !loopEnabled;
    notifyListeners();
  }

  @override
  Future<void> clearLoop() async {
    markerA = null;
    markerB = null;
    loopEnabled = false;
    notifyListeners();
  }

  @override
  Future<void> changePitch(double value) async {}
  @override
  Future<void> resetProcessing() async {}
}
