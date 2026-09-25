import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transpose_mobile/main_player_panel.dart';
import 'package:transpose_mobile/player_panel_model.dart';

void main() {
  Future<void> tap(WidgetTester tester, String key) async {
    final Finder target = find.byKey(Key(key));
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pump();
  }

  testWidgets('principal controls operate the supplied shared model', (
    WidgetTester tester,
  ) async {
    final _Model model = _Model();
    final List<String> tools = <String>[];
    int fullscreen = 0;
    await tester.pumpWidget(
      _app(
        MainPlayerPanel(
          model: model,
          media: const ColoredBox(color: Colors.black),
          onFullscreen: () => fullscreen++,
          onSearch: () {},
          onOpenFile: () {},
          onTool: tools.add,
        ),
      ),
    );

    await tap(tester, 'visualPlayerFullscreen');
    expect(fullscreen, 1);
    await tap(tester, 'visualPlayerPitchUp');
    expect(model.pitch, 1);
    expect(find.text('+1'), findsOneWidget);
    await tap(tester, 'visualPlayerPitchDown');
    expect(model.pitch, 0);
    await tap(tester, 'visualPlayerPitchUp');
    await tap(tester, 'visualPlayerPitchReset');
    expect(model.pitch, 0);

    for (final (String, double) preset in <(String, double)>[
      ('075', .75),
      ('085', .85),
      ('100', 1),
    ]) {
      await tap(tester, 'visualPlayerSpeed${preset.$1}');
      expect(model.speed, preset.$2);
    }

    await tap(tester, 'visualPlayerMarkA');
    expect(model.markerA, const Duration(seconds: 20));
    model.position = const Duration(seconds: 40);
    await tap(tester, 'visualPlayerMarkB');
    expect(model.markerB, const Duration(seconds: 40));
    await tap(tester, 'visualPlayerLoopToggle');
    expect(model.loopEnabled, isTrue);
    await tap(tester, 'visualPlayerClearLoop');
    expect(model.markerA, isNull);
    expect(model.markerB, isNull);

    await tap(tester, 'visualPlayerBack10');
    expect(model.position, const Duration(seconds: 30));
    await tap(tester, 'visualPlayerForward10');
    expect(model.position, const Duration(seconds: 40));
    await tap(tester, 'visualPlayerPlay');
    expect(model.playing, isTrue);
    await tap(tester, 'visualPlayerStudyTools');
    for (final String tool in <String>[
      'metronome',
      'chords',
      'tuner',
      'save',
    ]) {
      await tap(tester, 'visualPlayerTool_$tool');
    }
    await tap(tester, 'visualPlayerAdvancedTools');
    expect(tools, <String>['metronome', 'chords', 'tuner', 'save', 'advanced']);
    await tap(tester, 'visualPlayerDismissTip');
    expect(find.byKey(const Key('visualPlayerDismissTip')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('seek and speed sliders send final drag intentions', (
    WidgetTester tester,
  ) async {
    final _Model model = _Model();
    await tester.pumpWidget(
      _app(
        MainPlayerPanel(
          model: model,
          media: const SizedBox(),
          onFullscreen: () {},
          onSearch: () {},
          onOpenFile: () {},
          onTool: (_) {},
        ),
      ),
    );
    final Finder seek = find.byKey(const Key('visualPlayerSeek'));
    await tester.ensureVisible(seek);
    await tester.drag(seek, const Offset(150, 0));
    await tester.pump();
    expect(model.position, greaterThan(const Duration(seconds: 20)));
    final Finder speed = find.byKey(const Key('visualPlayerSpeed'));
    await tester.ensureVisible(speed);
    await tester.drag(speed, const Offset(90, 0));
    await tester.pump();
    expect(model.speed, greaterThan(1));
  });

  testWidgets('empty and unsupported sources do not expose fake capabilities', (
    WidgetTester tester,
  ) async {
    final _Model model = _Model()..loaded = false;
    int search = 0;
    int file = 0;
    await tester.pumpWidget(
      _app(
        MainPlayerPanel(
          model: model,
          media: const SizedBox(),
          onFullscreen: () {},
          onSearch: () => search++,
          onOpenFile: () => file++,
          onTool: (_) {},
        ),
      ),
    );
    await tap(tester, 'visualPlayerEmptySearch');
    await tap(tester, 'visualPlayerEmptyFile');
    expect(search, 1);
    expect(file, 1);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('visualPlayerPlay')))
          .onPressed,
      isNull,
    );
    model
      ..loaded = true
      ..canPitch = false
      ..canSpeed = false
      ..canLoop = false
      ..update();
    await tester.pump();
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('visualPlayerPitchUp')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<Slider>(find.byKey(const Key('visualPlayerSpeed')))
          .onChanged,
      isNull,
    );
    expect(
      find.textContaining('não está disponível nesta fonte.'),
      findsNWidgets(3),
    );
  });

  testWidgets('fullscreen lock blocks native controls and media until held', (
    WidgetTester tester,
  ) async {
    final _Model model = _Model();
    int mediaTaps = 0;
    int exit = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: MainPlayerFullscreen(
            model: model,
            media: GestureDetector(
              key: const Key('testMedia'),
              behavior: HitTestBehavior.opaque,
              onTap: () => mediaTaps++,
              child: const ColoredBox(color: Colors.blue),
            ),
            onExit: () => exit++,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('testMedia')));
    expect(mediaTaps, 1);
    await tap(tester, 'visualFullscreenLock');
    await tester.tap(find.byKey(const Key('testMedia')), warnIfMissed: false);
    expect(mediaTaps, 1);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('visualFullscreenPlay')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('visualFullscreenLock')));
    await tester.pump();
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('visualFullscreenPlay')))
          .onPressed,
      isNull,
    );
    await tester.longPress(find.byKey(const Key('visualFullscreenLock')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('testMedia')));
    expect(mediaTaps, 2);
    await tap(tester, 'visualFullscreenPlay');
    expect(model.playing, isTrue);
    await tap(tester, 'visualFullscreenBack');
    expect(exit, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow display and enlarged text retain reachable controls', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final _Model model = _Model();
    await tester.pumpWidget(
      _app(
        MainPlayerPanel(
          model: model,
          media: const SizedBox(),
          onFullscreen: () {},
          onSearch: () {},
          onOpenFile: () {},
          onTool: (_) {},
        ),
        textScale: 2,
      ),
    );
    await tap(tester, 'visualPlayerStudyTools');
    await tester.ensureVisible(
      find.byKey(const Key('visualPlayerAdvancedTools')),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(640, 320);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: MainPlayerFullscreen(
            model: model,
            media: const SizedBox(),
            onExit: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

Widget _app(Widget panel, {double textScale = 1}) => MaterialApp(
  theme: ThemeData.dark(),
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: SingleChildScrollView(child: panel),
    ),
  ),
);

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
  String title = 'Test song';
  @override
  String sourceLabel = 'Local';
  @override
  String? message;
  @override
  Duration position = const Duration(seconds: 20);
  @override
  Duration duration = const Duration(minutes: 3);
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

  void update() => notifyListeners();

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
    markerA = markerB = null;
    loopEnabled = false;
    notifyListeners();
  }

  @override
  Future<void> resetProcessing() async {
    pitch = 0;
    speed = 1;
    notifyListeners();
  }
}
