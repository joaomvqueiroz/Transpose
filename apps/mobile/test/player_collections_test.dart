import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transpose_mobile/player_collections.dart';
import 'package:transpose_mobile/player_presets.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('empty collection explains how to save a real source', (
    tester,
  ) async {
    await _open(tester, PlayerPresetStore());
    expect(find.textContaining('Ainda não há predefinições'), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets(
    'rename persists, empty name disabled, remove needs confirmation',
    (tester) async {
      final store = PlayerPresetStore();
      await store.save(_preset('one'));
      await _open(tester, store);
      expect(find.textContaining('YouTube · +2 st · 0.85×'), findsOneWidget);
      expect(find.textContaining('A/B 0:01–0:04 (ligado)'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('collectionMenu-one')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Renomear'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('collectionRenameInput')),
        ' ',
      );
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('collectionConfirmRename')),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(
        find.byKey(const Key('collectionRenameInput')),
        'Meu ensaio',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('collectionConfirmRename')));
      await tester.pumpAndSettle();
      expect((await store.list()).single.name, 'Meu ensaio');
      expect(find.text('Meu ensaio'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('collectionMenu-one')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remover'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect((await store.list()).length, 1);
      await tester.tap(find.byKey(const ValueKey('collectionMenu-one')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remover'));
      await tester.pumpAndSettle();
      expect(find.textContaining('não será apagado'), findsOneWidget);
      await tester.tap(find.byKey(const Key('collectionConfirmDelete')));
      await tester.pumpAndSettle();
      expect(await store.list(), isEmpty);
      expect(find.textContaining('Ainda não há predefinições'), findsOneWidget);
    },
  );

  testWidgets(
    'setlist shows thumbnail, short title and a compact options menu',
    (tester) async {
      final store = PlayerPresetStore();
      await store.save(_preset('one'), setlist: true);
      await store.save(_preset('two'), setlist: true);
      await _open(tester, store, setlist: true);
      expect(
        find.byKey(const ValueKey('setlistThumbnail-one')),
        findsOneWidget,
      );
      expect(find.text('Song'), findsNWidgets(2));
      expect(find.byKey(const ValueKey('collectionMenu-one')), findsOneWidget);
      expect(find.byKey(const ValueKey('collectionDown-one')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('collectionMenu-one')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('setlistMoveDown')));
      await tester.pumpAndSettle();
      expect(
        (await PlayerPresetStore().list(setlist: true)).map((item) => item.id),
        ['two', 'one'],
      );
      await tester.longPress(find.byKey(const ValueKey('collectionOpen-two')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('setlistMoveUp')), findsNothing);
      expect(find.byKey(const Key('setlistMoveDown')), findsOneWidget);
    },
  );

  testWidgets('embedded setlist header is a quarter shorter', (tester) async {
    final store = PlayerPresetStore();
    await store.save(_preset('one'), setlist: true);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerCollectionsPage(
            store: store,
            setlist: true,
            embedded: true,
            onApply: (_) async {},
            onAdd: () async {},
            onPrevious: () {},
            onNext: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const Key('setlistHeader'))).height,
      closeTo(58, 1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('applying delegates to existing player then closes this page', (
    tester,
  ) async {
    final store = PlayerPresetStore();
    await store.save(_preset('one'));
    PlayerPreset? selected;
    await _open(tester, store, onApply: (item) async => selected = item);
    await tester.tap(find.byKey(const ValueKey('collectionOpen-one')));
    await tester.pumpAndSettle();
    expect(selected?.id, 'one');
    expect(find.byType(PlayerCollectionsPage), findsNothing);
    expect(find.text('Abrir coleção'), findsOneWidget);
  });

  testWidgets('failed restore remains on the collection with honest error', (
    tester,
  ) async {
    final store = PlayerPresetStore();
    await store.save(_preset('one'));
    await _open(
      tester,
      store,
      onApply: (_) async => throw StateError('Ficheiro indisponível'),
    );
    await tester.tap(find.byKey(const ValueKey('collectionOpen-one')));
    await tester.pumpAndSettle();
    expect(find.byType(PlayerCollectionsPage), findsOneWidget);
    expect(find.textContaining('Ficheiro indisponível'), findsOneWidget);
  });

  testWidgets(
    'narrow screen and large text remain scrollable without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = PlayerPresetStore();
      await store.save(_preset('one'), setlist: true);
      await _open(tester, store, setlist: true, scale: 2);
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(ListView).first, const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _open(
  WidgetTester tester,
  PlayerPresetStore store, {
  bool setlist = false,
  double scale = 1,
  Future<void> Function(PlayerPreset)? onApply,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (context) => PlayerCollectionsPage(
                  store: store,
                  setlist: setlist,
                  onApply: onApply ?? (_) async {},
                ),
              ),
            ),
            child: const Text('Abrir coleção'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Abrir coleção'));
  await tester.pumpAndSettle();
}

PlayerPreset _preset(String id) => PlayerPreset(
  id: id,
  name: 'My $id',
  title: 'Song',
  sourceId: 'video-id',
  locator: 'aqz-KE-bpKQ',
  youtube: true,
  pitch: 2,
  speed: .85,
  positionMs: 1000,
  aMs: 1000,
  bMs: 4000,
  loop: true,
);
