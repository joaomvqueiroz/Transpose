import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transpose_mobile/chord_sheet.dart';
import 'package:transpose_mobile/main_player_panel.dart';
import 'package:transpose_mobile/player_panel_model.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  Future<void> tap(WidgetTester tester, String key) async {
    final Finder target = find.byKey(Key(key));
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  testWidgets('video and first chord lines fit together in portrait', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = ChordSheetStore();
    await store.save(
      'song',
      const ChordSheet(
        notes: 'C       G/B\nLetra original\nAm      F',
        sourceTitle: 'Exercício original',
        sourceUrl: 'https://www.cifras.com.br/cifra/teste/exercicio',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          appBar: AppBar(title: const Text('Transpono')),
          bottomNavigationBar: const SizedBox(height: 72),
          body: SingleChildScrollView(
            child: MainPlayerPanel(
              model: _Model(),
              media: const ColoredBox(color: Colors.black),
              mediaExtraHeight: 104,
              chordActive: true,
              sourceKey: 'song',
              chordStore: store,
              onFullscreen: () {},
              onSearch: () {},
              onOpenFile: () {},
              onTool: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final video = tester.getRect(
      find.byKey(const Key('visualPlayerMediaSurface')),
    );
    final text = tester.getRect(find.byKey(const Key('playerChordText')));
    expect(video.top, greaterThanOrEqualTo(56));
    expect(
      text.top + 48,
      lessThanOrEqualTo(708),
      reason:
          'Video and at least two chord/lyric lines must fit without pinning',
    );
    expect(find.byKey(const Key('visualPlayerSeek')), findsNothing);
    await tester.tap(find.byKey(const Key('visualPlayerSettings')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('visualPlayerSeek')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('arrow opens and closes the control deck directly below video', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        MainPlayerPanel(
          model: _Model(),
          media: const ColoredBox(color: Colors.black),
          onFullscreen: () {},
          onSearch: () {},
          onOpenFile: () {},
          onTool: (_) {},
        ),
      ),
    );
    final toggle = find.byKey(const Key('visualPlayerControlsToggle'));
    expect(find.byKey(const Key('visualPlayerPitchUp')), findsNothing);
    expect(
      find.descendant(
        of: toggle,
        matching: find.byIcon(Icons.keyboard_arrow_up),
      ),
      findsOneWidget,
    );
    await tap(tester, 'visualPlayerControlsToggle');
    expect(find.byKey(const Key('visualPlayerPitchUp')), findsOneWidget);
    expect(
      find.descendant(
        of: toggle,
        matching: find.byIcon(Icons.keyboard_arrow_down),
      ),
      findsOneWidget,
    );
    final video = tester.getRect(
      find.byKey(const Key('visualPlayerMediaSurface')),
    );
    final arrow = tester.getRect(toggle);
    final pitch = tester.getRect(
      find.byKey(const Key('visualPlayerPitchValue')),
    );
    final sources = tester.getRect(
      find.byKey(const Key('visualPlayerEmptyFile')),
    );
    expect(arrow.top, greaterThanOrEqualTo(video.bottom));
    expect(pitch.top, greaterThan(arrow.bottom));
    expect(pitch.bottom, lessThan(sources.top));
    await tap(tester, 'visualPlayerControlsToggle');
    expect(find.byKey(const Key('visualPlayerPitchUp')), findsNothing);
  });

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

    expect(find.text('Test song'), findsNothing);
    expect(find.text('Local'), findsNothing);
    expect(find.byKey(const Key('visualPlayerSeek')), findsNothing);

    await tap(tester, 'visualPlayerMediaSurface');
    await tap(tester, 'visualPlayerFullscreen');
    expect(fullscreen, 1);
    expect(find.byKey(const Key('visualPlayerPitchUp')), findsNothing);
    await tap(tester, 'visualPlayerControlsToggle');
    expect(find.byKey(const Key('visualPlayerPitchUp')), findsOneWidget);
    expect(find.byKey(const Key('visualPlayerSettingsSheet')), findsNothing);
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

    await tap(tester, 'visualPlayerMediaSurface');
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
      expect(find.byKey(const Key('visualPlayerSettingsSheet')), findsNothing);
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
    expect(seek, findsNothing);
    await tap(tester, 'visualPlayerMediaSurface');
    await tester.ensureVisible(seek);
    await tester.drag(seek, const Offset(150, 0));
    await tester.pump();
    expect(model.position, greaterThan(const Duration(seconds: 20)));
    await tap(tester, 'visualPlayerControlsToggle');
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
    expect(find.byKey(const Key('visualPlayerPlay')), findsNothing);
    await tap(tester, 'visualPlayerMediaSurface');
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
    await tap(tester, 'visualPlayerEmptySearch');
    await tap(tester, 'visualPlayerEmptyFile');
    expect(search, 2, reason: 'A loaded source must still be replaceable');
    expect(file, 2);
    await tap(tester, 'visualPlayerControlsToggle');
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
    model
      ..canPitch = true
      ..canSpeed = true
      ..canLoop = true
      ..update();
    await tester.pump();
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('visualPlayerPitchUp')))
          .onPressed,
      isNotNull,
      reason: 'Inline controls must follow current model capabilities',
    );
    expect(
      tester
          .widget<Slider>(find.byKey(const Key('visualPlayerSpeed')))
          .onChanged,
      isNotNull,
    );
    expect(
      find.textContaining('não está disponível nesta fonte.'),
      findsNothing,
    );
  });

  testWidgets('Cifra toggles cards into the video without resetting audio', (
    tester,
  ) async {
    final model = _Model();
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
    expect(find.byKey(const Key('playerChordSheet')), findsNothing);
    expect(find.byKey(const Key('visualPlayerPitchUp')), findsNothing);
    await tap(tester, 'visualPlayerControlsToggle');
    expect(find.byKey(const Key('visualPlayerPitchUp')), findsOneWidget);
    await tap(tester, 'visualPlayerPitchUp');
    await tap(tester, 'visualPlayerSpeed085');
    await tap(tester, 'visualPlayerChordPicker');
    expect(find.byKey(const Key('visualPlayerPitchUp')), findsNothing);
    expect(find.byKey(const Key('playerChordSheet')), findsOneWidget);
    expect(find.text('Cifra de exemplo'), findsNothing);
    final videoBeforeSettings = tester.getRect(
      find.byKey(const Key('visualPlayerMediaSurface')),
    );
    final chordAction = tester.getRect(
      find.byKey(const Key('visualPlayerChordPicker')),
    );
    final chordSheet = tester.getRect(
      find.byKey(const Key('playerChordSheet')),
    );
    expect(chordAction.top, greaterThanOrEqualTo(videoBeforeSettings.bottom));
    expect(chordSheet.top, greaterThanOrEqualTo(chordAction.bottom));
    await tap(tester, 'visualPlayerSettings');
    final video = tester.getRect(
      find.byKey(const Key('visualPlayerMediaSurface')),
    );
    final settings = tester.getRect(
      find.byKey(const Key('visualPlayerSettingsSheet')),
    );
    expect(settings, video);
    await tap(tester, 'visualPlayerPitchUp');
    expect(model.pitch, 2);
    await tester.pump(const Duration(seconds: 3));
    expect(find.byKey(const Key('visualPlayerSettingsSheet')), findsOneWidget);
    await tap(tester, 'visualPlayerSettingsClose');
    await tap(tester, 'visualPlayerChordPicker');
    expect(find.byKey(const Key('playerChordSheet')), findsNothing);
    expect(find.byKey(const Key('visualPlayerPitchUp')), findsNothing);
    await tap(tester, 'visualPlayerControlsToggle');
    expect(find.byKey(const Key('visualPlayerPitchUp')), findsOneWidget);
    expect(model.pitch, 2);
    expect(model.speed, .85);
    expect(tester.takeException(), isNull);
  });

  testWidgets('video transport appears on touch for exactly two seconds', (
    WidgetTester tester,
  ) async {
    final _Model model = _Model();
    int mediaTaps = 0;
    await tester.pumpWidget(
      _app(
        MainPlayerPanel(
          model: model,
          media: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => mediaTaps++,
            child: const ColoredBox(color: Colors.black),
          ),
          onFullscreen: () {},
          onSearch: () {},
          onOpenFile: () {},
          onTool: (_) {},
        ),
      ),
    );
    final Finder surface = find.byKey(const Key('visualPlayerMediaSurface'));
    final Finder play = find.byKey(const Key('visualPlayerPlay'));
    expect(play, findsNothing);
    await tester.tap(surface);
    await tester.pump();
    expect(
      mediaTaps,
      1,
      reason: 'Hidden controls preserve native media touches',
    );
    expect(play, findsOneWidget);
    final Rect mediaBounds = tester.getRect(surface);
    for (final String key in <String>[
      'visualPlayerBack10',
      'visualPlayerPlay',
      'visualPlayerForward10',
    ]) {
      final Rect bounds = tester.getRect(find.byKey(Key(key)));
      expect(bounds.left, greaterThanOrEqualTo(mediaBounds.left));
      expect(bounds.right, lessThanOrEqualTo(mediaBounds.right));
      expect(bounds.top, greaterThanOrEqualTo(mediaBounds.top));
      expect(bounds.bottom, lessThanOrEqualTo(mediaBounds.bottom));
    }
    await tester.pump(const Duration(milliseconds: 1999));
    expect(play, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    expect(play, findsNothing);

    await tester.tap(surface);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.tap(play);
    await tester.pump();
    expect(model.playing, isTrue);
    expect(
      mediaTaps,
      2,
      reason: 'Overlay buttons do not activate native media',
    );
    await tester.pump(const Duration(milliseconds: 1500));
    expect(
      play,
      findsOneWidget,
      reason: 'A control touch restarts the timeout',
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(play, findsNothing);

    await tester.tap(surface);
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    expect(
      tester.takeException(),
      isNull,
      reason: 'Disposal cancels the timer',
    );
  });

  testWidgets('fullscreen lock blocks native controls and media until held', (
    WidgetTester tester,
  ) async {
    final _Model model = _Model();
    int mediaTaps = 0;
    int nativeTouchEvents = 0;
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
            onNativeMediaTouch: () => nativeTouchEvents++,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('testMedia')));
    expect(mediaTaps, 1);
    expect(nativeTouchEvents, 1);
    await tap(tester, 'visualFullscreenLock');
    await tester.tap(find.byKey(const Key('testMedia')), warnIfMissed: false);
    expect(nativeTouchEvents, 1);
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
    await tap(tester, 'visualPlayerMediaSurface');
    final Rect media = tester.getRect(
      find.byKey(const Key('visualPlayerMediaSurface')),
    );
    final Rect forward = tester.getRect(
      find.byKey(const Key('visualPlayerForward10')),
    );
    expect(forward.right, lessThanOrEqualTo(media.right));
    await tap(tester, 'visualPlayerControlsToggle');
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
  builder: (BuildContext context, Widget? child) => MediaQuery(
    data: MediaQuery.of(context)
        .copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: Scaffold(body: SingleChildScrollView(child: panel)),
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
