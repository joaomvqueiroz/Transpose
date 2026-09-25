import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transpose_mobile/player_panel_model.dart';
import 'package:transpose_mobile/player_presets.dart';
import 'package:transpose_mobile/stage_panel.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  testWidgets('same media presets retain the selected entry after remount', (
    tester,
  ) async {
    final store = _Store([_preset('one'), _preset('two'), _preset('three')]);
    String? applied;
    Future<void> mount() => tester.pumpWidget(
      _page(
        store: store,
        selected: 'two',
        onApply: (preset) async {
          applied = preset.id;
          return true;
        },
      ),
    );
    await mount();
    await tester.pumpAndSettle();
    expect(find.text('SETLIST · 2 DE 3'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await mount();
    await tester.pumpAndSettle();
    expect(find.text('SETLIST · 2 DE 3'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('visualStageNext')));
    await tester.tap(find.byKey(const Key('visualStageNext')));
    await tester.pumpAndSettle();
    expect(applied, 'three');
    expect(find.text('SETLIST · 3 DE 3'), findsOneWidget);
  });

  testWidgets('a slow old read never replaces a newer setlist', (tester) async {
    final stale = Completer<List<PlayerPreset>>();
    final fresh = Completer<List<PlayerPreset>>();
    final store = _DelayedStore([stale, fresh]);
    await tester.pumpWidget(_page(store: store));
    await tester.pump();
    await tester.pumpWidget(_page(store: store, revision: 1));
    await tester.pump();
    fresh.complete([_preset('one'), _preset('two')]);
    await tester.pumpAndSettle();
    expect(find.text('SETLIST · 1 DE 2'), findsOneWidget);
    stale.complete([_preset('old')]);
    await tester.pumpAndSettle();
    expect(find.text('SETLIST · 1 DE 2'), findsOneWidget);
    expect(find.text('SETLIST · 1 DE 1'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Widget _page({
  required PlayerPresetStore store,
  String? selected,
  int revision = 0,
  Future<bool> Function(PlayerPreset)? onApply,
}) => MaterialApp(
  home: Scaffold(
    body: StagePanel(
      model: _Model(),
      store: store,
      sourceKey: 'local:file:///same.wav',
      selectedPresetId: selected,
      revision: revision,
      onApply: onApply ?? (_) async => true,
      onCollections: () {},
      onAdd: () {},
      onTool: (_) {},
    ),
  ),
);

class _Store extends PlayerPresetStore {
  _Store(this.items);
  final List<PlayerPreset> items;
  @override
  Future<List<PlayerPreset>> list({bool setlist = false}) async => items;
}

class _DelayedStore extends PlayerPresetStore {
  _DelayedStore(this.pending);
  final List<Completer<List<PlayerPreset>>> pending;
  var next = 0;
  @override
  Future<List<PlayerPreset>> list({bool setlist = false}) =>
      pending[next++].future;
}

PlayerPreset _preset(String id) => PlayerPreset(
  id: id,
  name: 'Preset $id',
  title: 'Same song',
  sourceId: 'same',
  locator: 'file:///same.wav',
  youtube: false,
  pitch: id == 'one' ? 0 : 2,
  speed: 1,
  positionMs: 0,
);

class _Model extends PlayerPanelModel {
  @override
  bool get loaded => true;
  @override
  bool get playing => false;
  @override
  bool get busy => false;
  @override
  bool get canPitch => true;
  @override
  bool get canSpeed => true;
  @override
  bool get canLoop => true;
  @override
  bool get muted => false;
  @override
  String get title => 'Same song';
  @override
  String get sourceLabel => 'Local';
  @override
  String? get message => null;
  @override
  Duration get position => Duration.zero;
  @override
  Duration get duration => const Duration(minutes: 3);
  @override
  double get pitch => 2;
  @override
  double get speed => 1;
  @override
  Duration? get markerA => null;
  @override
  Duration? get markerB => null;
  @override
  bool get loopEnabled => false;
  @override
  Future<void> playPause() async {}
  @override
  Future<void> seek(Duration value) async {}
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
