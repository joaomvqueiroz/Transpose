import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transpose_mobile/chord_sheet.dart';
import 'package:transpose_mobile/player_chord_sheet.dart';
import 'package:transpose_mobile/player_panel_model.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  Future<void> tap(WidgetTester tester, String key) async {
    final target = find.byKey(Key(key));
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  String displayed(WidgetTester tester) => tester
      .widget<SelectableText>(find.byKey(const Key('playerChordText')))
      .textSpan!
      .toPlainText();

  test('UTF-8 import keeps alignment, accents and normalized newlines', () {
    expect(
      decodePlayerChordFile(
        utf8.encode('\uFEFFC   G\r\nCanção de estudo\rAm  F\n'),
      ),
      'C   G\nCanção de estudo\nAm  F\n',
    );
    expect(() => decodePlayerChordFile([0xff, 0xfe, 0]), throwsFormatException);
    expect(
      () => decodePlayerChordFile(utf8.encode('   \n')),
      throwsFormatException,
    );
    expect(
      () => decodePlayerChordFile(utf8.encode('C\u0000')),
      throwsFormatException,
    );
    expect(
      () => decodePlayerChordFile(List.filled(40001, 65)),
      throwsFormatException,
    );
    expect(() => validatePlayerChordText('C' * 10001), throwsFormatException);
    expect(() => validatePlayerChordText('C\n' * 500), throwsFormatException);
  });

  test('only chord rows transpose; lyric words and spacing are preserved', () {
    expect(
      transposePlayerChordText('C   G/B  Am7 | F\nA música começa\n[Verso]', 2),
      'D   A/C# Bm7 | G\nA música começa\n[Verso]',
    );
  });

  test('transposition keeps start columns, section labels and explicit inline chords', () {
    const original =
        'C       G/B     Am7\nUma letra original\n[Intro] C     F (2x)';
    final changed = transposePlayerChordText(original, 1).split('\n');
    expect(changed[0].indexOf('C#'), 0);
    expect(changed[0].indexOf('G#/C'), 8);
    expect(changed[0].indexOf('A#m7'), 16);
    expect(changed[1], 'Uma letra original');
    expect(changed[2], '[Intro] C#    F# (2x)');
    expect(
      transposePlayerChordText('[C]Uma [G/B]letra [Verso]', 2),
      '[D]Uma [A/C#]letra [Verso]',
    );
    expect(transposePlayerChordText('C|G', 1), 'C#|G#');
    expect(transposePlayerChordText(original, 12), original);
  });

  testWidgets(
    'cifra pitch is independently saved and never changes audio pitch',
    (tester) async {
      final key = GlobalKey<PlayerChordSheetState>();
      final model = _DelayedPitch();
      final store = ChordSheetStore();
      await store.save(
        'song',
        const ChordSheet(notes: 'C       G/B\nLetra original'),
      );
      await tester.pumpWidget(_app(key, model, store, 'song'));
      await tester.pumpAndSettle();
      await tap(tester, 'playerChordPitchUp');
      expect(displayed(tester), startsWith('C#      G#/C'));
      expect(model.requested, isNull);
      expect((await store.read('song')).followAudio, isFalse);
      await tap(tester, 'playerChordPitchUp');
      expect(model.pitch, 0);
      expect(displayed(tester), startsWith('D       A/C#'));
      expect((await store.read('song')).notes, 'C       G/B\nLetra original');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_app(key, model, store, 'song'));
      await tester.pumpAndSettle();
      expect(displayed(tester), startsWith('D       A/C#'));
      await tap(tester, 'playerChordPitchReset');
      expect(displayed(tester), 'C       G/B\nLetra original');
      expect(model.pitch, 0, reason: 'Reset cifra must not change the audio');
      expect(find.text('Tom da cifra'), findsOneWidget);
      unawaited(model.changePitch(2));
      await tester.pump();
      model.acknowledge();
      await tester.pumpAndSettle();
      expect(model.pitch, 2);
      expect(
        displayed(tester),
        startsWith('C'),
        reason: 'Unlinked cifra keeps its key while the video pitch changes.',
      );
    },
  );

  testWidgets('unsupported audio can still transpose the chord independently', (
    tester,
  ) async {
    final model = _Model()..canPitch = false;
    final store = ChordSheetStore()
      ..temporarySheet = const ChordSheet(notes: 'Am  F');
    await tester.pumpWidget(
      _app(GlobalKey<PlayerChordSheetState>(), model, store, ''),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('playerChordPitchUp')))
          .onPressed,
      isNotNull,
    );
    expect(find.byKey(const Key('playerChordVideoPitchUp')), findsNothing);
    await tap(tester, 'playerChordPitchUp');
    expect(displayed(tester), 'A#m F#');
    expect(model.pitch, 0);
  });

  testWidgets('wide chord lines fit or wrap without horizontal clipping', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = ChordSheetStore();
    await store.save('moderate', ChordSheet(notes: 'C${' ' * 20}G'));
    await tester.pumpWidget(
      _app(GlobalKey<PlayerChordSheetState>(), _Model(), store, 'moderate'),
    );
    await tester.pumpAndSettle();
    final text = find.byKey(const Key('playerChordText'));
    expect(tester.widget<SelectableText>(text).style!.fontSize, lessThan(15));
    expect(find.byKey(const Key('playerChordHorizontalScroll')), findsNothing);

    await store.save('long', ChordSheet(notes: 'C${' ' * 100}G'));
    await tester.pumpWidget(
      _app(GlobalKey<PlayerChordSheetState>(), _Model(), store, 'long'),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<SelectableText>(text).style!.fontSize, 11);
    expect(find.byKey(const Key('playerChordHorizontalScroll')), findsNothing);
    expect(find.byKey(const Key('playerChordScrollHint')), findsNothing);
    expect(tester.getSize(text).width, lessThan(320));
    expect(tester.getSize(text).height, greaterThan(30));
    expect(displayed(tester), 'C${' ' * 100}G');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'empty source has no automatic example and keeps edits only in session',
    (tester) async {
      final key = GlobalKey<PlayerChordSheetState>();
      final store = _RecordingStore();
      await tester.pumpWidget(_app(key, _Model(), store, ''));
      await tester.pumpAndSettle();
      expect(find.text('Cifra de exemplo'), findsNothing);
      expect(displayed(tester), isEmpty);
      unawaited(key.currentState!.choose());
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('playerChordInput')),
        'Dm   G\nMinha letra',
      );
      await tap(tester, 'playerChordSave');
      expect(displayed(tester), 'Dm   G\nMinha letra');
      expect(store.savedSources, isEmpty);
      expect(store.readSources, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'temporary text survives viewer navigation within the same store',
    (tester) async {
      final key = GlobalKey<PlayerChordSheetState>();
      final model = _Model();
      final store = _RecordingStore();
      await tester.pumpWidget(_app(key, model, store, ''));
      await tester.pumpAndSettle();
      unawaited(key.currentState!.choose());
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('playerChordInput')),
        'Am   F\nMeu rascunho temporário',
      );
      await tap(tester, 'playerChordSave');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(key.currentState, isNull);

      await tester.pumpWidget(_app(key, model, store, ''));
      await tester.pumpAndSettle();
      expect(displayed(tester), 'Am   F\nMeu rascunho temporário');
      expect(find.text('Minha cifra'), findsOneWidget);
      expect(store.readSources, isEmpty);
      expect(store.savedSources, isEmpty);
      expect(ChordSheetStore().temporarySheet.notes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('save persists text per source and preserves synchronized cues', (
    tester,
  ) async {
    final model = _Model();
    final key = GlobalKey<PlayerChordSheetState>();
    final store = ChordSheetStore();
    await store.save(
      'one',
      const ChordSheet(timeline: '00:00 C\n00:08 G', notes: 'C   G\nOriginal'),
    );
    await tester.pumpWidget(_app(key, model, store, 'one'));
    await tester.pumpAndSettle();
    unawaited(key.currentState!.choose());
    await tester.pumpAndSettle();
    // Simulate edits elsewhere while this editor is open.
    await store.save(
      'one',
      const ChordSheet(timeline: '00:00 Am\n00:09 F', notes: 'C   G\nOriginal'),
    );
    await tester.enterText(
      find.byKey(const Key('playerChordInput')),
      'C   G\nA minha letra',
    );
    await tap(tester, 'playerChordSave');
    final saved = await ChordSheetStore().read('one');
    expect(saved.timeline, '00:00 Am\n00:09 F');
    expect(saved.notes, 'C   G\nA minha letra');
    await model.changePitch(2);
    await tester.pump();
    expect(displayed(tester), 'C   G\nA minha letra');
    expect((await store.read('one')).notes, 'C   G\nA minha letra');
    expect((await store.read('two')).notes, isEmpty);
  });

  testWidgets('cancel, example and hide never overwrite saved text', (
    tester,
  ) async {
    final key = GlobalKey<PlayerChordSheetState>();
    final store = ChordSheetStore();
    await store.save('one', const ChordSheet(notes: 'Am  F'));
    await tester.pumpWidget(_app(key, _Model(), store, 'one'));
    await tester.pumpAndSettle();
    unawaited(key.currentState!.choose());
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('playerChordInput')),
      'Texto não guardado',
    );
    await tap(tester, 'playerChordCancel');
    expect(displayed(tester), 'Am  F');
    unawaited(key.currentState!.choose());
    await tester.pumpAndSettle();
    await tap(tester, 'playerChordExample');
    expect(find.text('Cifra de exemplo'), findsOneWidget);
    expect((await store.read('one')).notes, 'Am  F');
    unawaited(key.currentState!.choose());
    await tester.pumpAndSettle();
    await tap(tester, 'playerChordHide');
    expect(find.byKey(const Key('playerChordSheet')), findsNothing);
    unawaited(key.currentState!.choose());
    await tester.pumpAndSettle();
    await tap(tester, 'playerChordSave');
    expect(displayed(tester), 'Am  F');
    expect((await store.read('one')).notes, 'Am  F');
  });

  testWidgets(
    'import is previewed before saving; picker cancel/error preserve text',
    (tester) async {
      final originalPicker = FilePickerPlatform.instance;
      final picker = _Picker();
      FilePickerPlatform.instance = picker;
      addTearDown(() => FilePickerPlatform.instance = originalPicker);
      final key = GlobalKey<PlayerChordSheetState>();
      final store = ChordSheetStore();
      await store.save('one', const ChordSheet(notes: 'C   G'));
      await tester.pumpWidget(_app(key, _Model(), store, 'one'));
      await tester.pumpAndSettle();
      unawaited(key.currentState!.choose());
      await tester.pumpAndSettle();
      await tap(tester, 'playerChordImport');
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('playerChordInput')))
            .controller!
            .text,
        'C   G',
      );
      picker.file = _Picked(utf8.encode('Dm   G\r\nCanção'));
      await tap(tester, 'playerChordImport');
      expect((await store.read('one')).notes, 'C   G');
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('playerChordInput')))
            .controller!
            .text,
        'Dm   G\nCanção',
      );
      picker.file = _Picked([0xff]);
      await tap(tester, 'playerChordImport');
      expect(
        find.text('Guarde a cifra como texto UTF-8 (.txt).'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('playerChordInput')))
            .controller!
            .text,
        'Dm   G\nCanção',
      );
      await tap(tester, 'playerChordSave');
      expect((await store.read('one')).notes, 'Dm   G\nCanção');
    },
  );

  testWidgets('late source read cannot replace current source text', (
    tester,
  ) async {
    final key = GlobalKey<PlayerChordSheetState>();
    final model = _Model();
    final store = _DelayedStore();
    await tester.pumpWidget(_app(key, model, store, 'one'));
    await tester.pumpWidget(_app(key, model, store, 'two'));
    await tester.pumpAndSettle();
    expect(displayed(tester), 'Dm   G');
    store.first.complete(const ChordSheet(notes: 'C   F'));
    await tester.pumpAndSettle();
    expect(displayed(tester), 'Dm   G');
  });

  testWidgets(
    'changing source while editing refuses applying text to either song',
    (tester) async {
      final key = GlobalKey<PlayerChordSheetState>();
      final model = _Model();
      final store = ChordSheetStore();
      await store.save('one', const ChordSheet(notes: 'C   G'));
      await store.save('two', const ChordSheet(notes: 'Dm   G'));
      await tester.pumpWidget(_app(key, model, store, 'one'));
      await tester.pumpAndSettle();
      unawaited(key.currentState!.choose());
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('playerChordInput')),
        'F   G',
      );
      await tester.pumpWidget(_app(key, model, store, 'two'));
      await tester.pumpAndSettle();
      await tap(tester, 'playerChordSave');
      expect(find.textContaining('A música mudou.'), findsOneWidget);
      expect((await store.read('one')).notes, 'C   G');
      expect((await store.read('two')).notes, 'Dm   G');
      await tap(tester, 'playerChordCancel');
      expect(displayed(tester), 'Dm   G');
      expect(tester.takeException(), isNull);
    },
  );
}

Widget _app(
  GlobalKey<PlayerChordSheetState> key,
  PlayerPanelModel model,
  ChordSheetStore store,
  String source,
) => MaterialApp(
  theme: ThemeData.dark(),
  home: Scaffold(
    body: SingleChildScrollView(
      child: PlayerChordSheet(
        key: key,
        model: model,
        sourceKey: source,
        store: store,
      ),
    ),
  ),
);

class _RecordingStore extends ChordSheetStore {
  final savedSources = <String>[];
  final readSources = <String>[];
  @override
  Future<ChordSheet> read(String source) async {
    readSources.add(source);
    return const ChordSheet();
  }

  @override
  Future<void> save(String source, ChordSheet sheet) async =>
      savedSources.add(source);
}

class _DelayedStore extends ChordSheetStore {
  final first = Completer<ChordSheet>();
  @override
  Future<ChordSheet> read(String source) async =>
      source == 'one' ? first.future : const ChordSheet(notes: 'Dm   G');
}

class _Picker extends FilePickerPlatform {
  PlatformFile? file;
  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => file;
}

final class _Picked extends PlatformFile {
  _Picked(List<int> bytes) : bytes = Uint8List.fromList(bytes);
  final Uint8List bytes;
  @override
  String get name => 'cifra.txt';
  @override
  Uri get uri => Uri.file('C:/test/cifra.txt');
  @override
  Never get xFile => throw UnimplementedError();
  @override
  int? lengthSync() => bytes.length;
  @override
  Future<int?> length() async => bytes.length;
  @override
  Future<Uint8List> readAsBytes() async => bytes;
  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(bytes);
}

class _Model extends PlayerPanelModel {
  @override
  bool get loaded => true;
  @override
  bool get busy => false;
  @override
  bool canPitch = true;
  @override
  String get title => 'Música de estudo';
  @override
  double pitch = 0;
  @override
  Future<void> changePitch(double value) async {
    pitch = value;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DelayedPitch extends _Model {
  double? requested;
  Completer<void>? pending;
  @override
  Future<void> changePitch(double value) {
    requested = value;
    pending = Completer<void>();
    return pending!.future;
  }

  void acknowledge() {
    pitch = requested!;
    notifyListeners();
    pending!.complete();
  }
}
