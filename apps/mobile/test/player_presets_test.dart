import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transpose_mobile/player_presets.dart';

void main() {
  setUp(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty(),
  );
  test('presets validate finite ranges and valid AB before restoring', () {
    final data = _preset('one').toJson();
    expect(PlayerPreset.parse(data), isNotNull);
    for (final invalid in <Map<String, Object?>>[
      {...data, 'pitch': double.nan},
      {...data, 'speed': 0},
      {...data, 'aMs': 2000, 'bMs': 1000},
      {...data, 'aMs': 1000, 'bMs': 1100},
      {...data, 'aMs': null, 'bMs': null, 'loop': true},
      {...data, 'name': ''},
      {...data, 'positionMs': -1},
    ]) {
      expect(PlayerPreset.parse(invalid), isNull);
    }
  });
  test('YouTube presets preserve 0.25x and 2x speeds', () {
    final data = _preset('video').toJson();
    for (final speed in [.25, 2.0]) {
      expect(PlayerPreset.parse({...data, 'speed': speed})?.speed, speed);
    }
    expect(PlayerPreset.parse({...data, 'speed': .2}), isNull);
    expect(PlayerPreset.parse({...data, 'speed': 2.1}), isNull);
    expect(
      PlayerPreset.parse({...data, 'youtube': false, 'speed': .25}),
      isNull,
    );
  });
  test(
    'serialized writes survive re-creation without losing either collection',
    () async {
      final store = PlayerPresetStore();
      await Future.wait([
        store.save(_preset('one')),
        store.save(_preset('two')),
        store.save(_preset('stage'), setlist: true),
      ]);
      final reopened = PlayerPresetStore();
      expect((await reopened.list()).map((p) => p.id), ['one', 'two']);
      expect((await reopened.list(setlist: true)).single.id, 'stage');
    },
  );
  test('corrupt storage is reported, not silently replaced', () async {
    final prefs = SharedPreferencesAsync();
    await prefs.setString('transpono.player.collections.v1', '{broken');
    final store = PlayerPresetStore(preferences: prefs);
    await expectLater(store.save(_preset('one')), throwsFormatException);
    expect(await prefs.getString('transpono.player.collections.v1'), '{broken');
  });
  test(
    'invalid individual entries are skipped without hiding valid entries',
    () async {
      final prefs = SharedPreferencesAsync();
      await prefs.setString(
        'transpono.player.collections.v1',
        jsonEncode({
          'presets': [
            {'bad': true},
            _preset('valid').toJson(),
          ],
        }),
      );
      expect(
        (await PlayerPresetStore(preferences: prefs).list()).single.id,
        'valid',
      );
      await PlayerPresetStore(preferences: prefs).save(_preset('new'));
      final raw = jsonDecode(
        (await prefs.getString('transpono.player.collections.v1'))!,
      );
      expect(raw['presets'].first, {'bad': true});
    },
  );
  test('wrong collection schema never overwrites saved data', () async {
    final prefs = SharedPreferencesAsync();
    for (final raw in ['[]', '{"presets": "broken"}']) {
      await prefs.setString('transpono.player.collections.v1', raw);
      await expectLater(
        PlayerPresetStore(preferences: prefs).save(_preset('new')),
        throwsFormatException,
      );
      expect(await prefs.getString('transpono.player.collections.v1'), raw);
    }
  });
  test(
    'rename and delete persist without touching the other collection',
    () async {
      final store = PlayerPresetStore();
      await store.save(_preset('one'));
      await store.save(_preset('two'));
      await store.save(_preset('stage'), setlist: true);
      await store.rename('one', '  Novo nome  ');
      await store.delete('two');
      final reopened = PlayerPresetStore();
      expect((await reopened.list()).single.name, 'Novo nome');
      expect((await reopened.list(setlist: true)).single.name, 'My stage');
      await expectLater(store.rename('one', '  '), throwsArgumentError);
      await expectLater(store.delete('missing'), throwsStateError);
      expect((await reopened.list()).single.name, 'Novo nome');
    },
  );
  test('reorder preserves invalid records and unknown metadata', () async {
    final prefs = SharedPreferencesAsync();
    final one = {..._preset('one').toJson(), 'futureField': 'preserved'};
    await prefs.setString(
      'transpono.player.collections.v1',
      jsonEncode({
        'setlist': [
          one,
          {'unreadable': true},
          _preset('two').toJson(),
        ],
        'futureCollection': ['kept'],
      }),
    );
    final store = PlayerPresetStore(preferences: prefs);
    await store.reorder(['two', 'one'], setlist: true);
    await store.rename('one', 'Renamed', setlist: true);
    final raw = jsonDecode(
      (await prefs.getString('transpono.player.collections.v1'))!,
    );
    expect(raw['setlist'][0]['id'], 'two');
    expect(raw['setlist'][1], {'unreadable': true});
    expect(raw['setlist'][2]['futureField'], 'preserved');
    expect(raw['futureCollection'], ['kept']);
    expect((await store.list(setlist: true)).map((item) => item.id), [
      'two',
      'one',
    ]);
  });
  test(
    'stale and duplicate reorder requests do not overwrite the collection',
    () async {
      final store = PlayerPresetStore();
      await store.save(_preset('one'), setlist: true);
      await store.save(_preset('two'), setlist: true);
      for (final ids in [
        ['one'],
        ['one', 'one'],
        ['one', 'missing'],
      ]) {
        await expectLater(store.reorder(ids, setlist: true), throwsStateError);
      }
      await expectLater(
        store.save(_preset('one'), setlist: true),
        throwsStateError,
      );
      expect((await store.list(setlist: true)).map((item) => item.id), [
        'one',
        'two',
      ]);
    },
  );
  test(
    'read-modify-write serialization also covers separate store instances',
    () async {
      final first = PlayerPresetStore(), second = PlayerPresetStore();
      await first.save(_preset('one'));
      await Future.wait([
        first.rename('one', 'Renamed'),
        second.save(_preset('two')),
        second.save(_preset('stage'), setlist: true),
      ]);
      expect((await first.list()).map((item) => item.name), [
        'Renamed',
        'My two',
      ]);
      expect((await first.list(setlist: true)).single.id, 'stage');
    },
  );
  test(
    'all edits reject corrupted collection without replacing raw data',
    () async {
      final prefs = SharedPreferencesAsync();
      final store = PlayerPresetStore(preferences: prefs);
      await prefs.setString('transpono.player.collections.v1', '{broken');
      for (final operation in <Future<void> Function()>[
        () => store.rename('one', 'Name'),
        () => store.delete('one'),
        () => store.reorder(['one']),
      ]) {
        await expectLater(operation(), throwsFormatException);
        expect(
          await prefs.getString('transpono.player.collections.v1'),
          '{broken',
        );
      }
    },
  );
}

PlayerPreset _preset(String id) => PlayerPreset(
  id: id,
  name: 'My $id',
  title: 'Song',
  sourceId: 'video-id',
  locator: 'aqz-KE-bpKQ',
  youtube: true,
  pitch: -2,
  speed: .85,
  positionMs: 1000,
  aMs: 1000,
  bMs: 4000,
  loop: true,
);
