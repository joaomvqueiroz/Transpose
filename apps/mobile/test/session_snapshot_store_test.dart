import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:transpose_mobile/player_presets.dart';
import 'package:transpose_mobile/practice_session.dart';
import 'package:transpose_mobile/session_snapshot_store.dart';

SessionSnapshot snapshot(int position) => SessionSnapshot(
  media: PlayerPreset(
    id: 'session-song',
    name: 'Sessão',
    title: 'Song',
    sourceId: 'file-1',
    locator: 'file:///music/song.mp3',
    youtube: false,
    pitch: -2,
    speed: 0.8,
    positionMs: position,
    aMs: 2000,
    bMs: 6000,
    loop: true,
  ),
  savedAt: DateTime.utc(2026, 9, 25).add(Duration(milliseconds: position)),
);

void main() {
  sqfliteFfiInit();
  late Directory temporary;
  late String path;
  late SessionSnapshotStore store;
  SessionSnapshotStore createStore() => SessionSnapshotStore(
    databaseFactory: databaseFactoryFfi,
    databasePath: path,
  );
  Future<void> edit(Future<void> Function(Database db) action) async {
    await store.close();
    final db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    try {
      await action(db);
    } finally {
      await db.close();
    }
    store = createStore();
  }

  Future<Map<String, String>> payloads() async {
    final db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    try {
      return {
        for (final row in await db.query('session_snapshots'))
          row['slot'] as String: row['payload'] as String,
      };
    } finally {
      await db.close();
    }
  }

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp(
      'transpono_snapshot_test_',
    );
    path = '${temporary.path}/session.sqlite';
    store = createStore();
  });
  tearDown(() async {
    await store.close();
    await temporary.delete(recursive: true);
  });

  test(
    'empty store is quiet and first save survives closing/reopening',
    () async {
      final empty = await store.read();
      expect(empty.snapshot, isNull);
      expect(empty.warning, isNull);
      expect(empty.writeBlocked, isFalse);
      await store.save(snapshot(1000));
      await store.close();
      store = createStore();
      final result = await store.read();
      expect(result.snapshot!.toJson(), snapshot(1000).toJson());
      expect(result.fromPrevious, isFalse);
      expect((await payloads()).keys, ['current']);
    },
  );

  test(
    'two generations retained in commit order including concurrent saves',
    () async {
      await Future.wait([
        store.save(snapshot(1000)),
        store.save(snapshot(2000)),
        store.save(snapshot(3000)),
      ]);
      final raw = await payloads();
      expect(raw.length, 2);
      expect(
        SessionSnapshot.parse(jsonDecode(raw['current']!))!.media.positionMs,
        3000,
      );
      expect(
        SessionSnapshot.parse(jsonDecode(raw['previous']!))!.media.positionMs,
        2000,
      );
      expect((await store.read()).snapshot!.media.positionMs, 3000);
    },
  );

  test(
    'v1 payload migrates on the next confirmed v2 save without erasing media',
    () async {
      await store.save(snapshot(3000));
      final legacy = snapshot(3000).toJson()
        ..['snapshotVersion'] = 1
        ..remove('practice');
      await edit((db) async {
        await db.update('session_snapshots', {'payload': jsonEncode(legacy)});
      });
      final before = await payloads();
      final recovered = await store.read();
      expect(recovered.writeBlocked, isFalse);
      expect(recovered.snapshot!.practice, isNull);
      expect(recovered.snapshot!.media.positionMs, 3000);
      expect(
        await payloads(),
        before,
        reason: 'Reading is not a write migration.',
      );
      final progress = PracticeProgress(
        id: 'practice-on-disk',
        sourceKey: 'local:${recovered.snapshot!.media.locator}',
        aMs: 2000,
        bMs: 6000,
        plan: const PracticePlan(),
        currentPercent: 80,
        stepRepetitions: 1,
        totalRepetitions: 13,
        status: PracticeStatus.running,
      );
      await store.save(
        SessionSnapshot(
          media: recovered.snapshot!.media,
          savedAt: DateTime.utc(2026, 9, 25, 12),
          practice: progress,
        ),
      );
      await store.close();
      store = createStore();
      final result = await store.read();
      expect(result.snapshot!.practice!.toJson(), progress.toJson());
      expect(result.snapshot!.practice!.status, PracticeStatus.paused);
      expect(
        result.snapshot!.media.toJson(),
        recovered.snapshot!.media.toJson(),
      );
      final raw = await payloads();
      expect(jsonDecode(raw['current']!)['snapshotVersion'], 2);
      expect(raw['previous'], before['current']);
    },
  );

  test(
    'bad optional practice keeps the current media instead of falling back',
    () async {
      await store.save(snapshot(1000));
      await store.save(snapshot(3000));
      final invalidPractice = snapshot(3000).toJson()
        ..['practice'] = {'version': 999, 'current': 'broken'};
      await edit((db) async {
        await db.update(
          'session_snapshots',
          {'payload': jsonEncode(invalidPractice)},
          where: 'slot = ?',
          whereArgs: ['current'],
        );
      });
      final before = await payloads();
      final result = await store.read();
      expect(result.writeBlocked, isFalse);
      expect(result.fromPrevious, isFalse);
      expect(result.snapshot!.practice, isNull);
      expect(result.snapshot!.media.positionMs, 3000);
      expect(await payloads(), before);
    },
  );

  test(
    'corrupt current falls back without mutating either saved record',
    () async {
      await store.save(snapshot(1000));
      await store.save(snapshot(2000));
      await edit((db) async {
        await db.update(
          'session_snapshots',
          {'payload': '{partial'},
          where: 'slot = ?',
          whereArgs: ['current'],
        );
      });
      final before = await payloads();
      final result = await store.read();
      expect(result.snapshot!.media.positionMs, 1000);
      expect(result.fromPrevious, isTrue);
      expect(result.warning, isNotNull);
      expect(await payloads(), before);
      await store.save(snapshot(3000));
      expect((await payloads())['previous'], before['previous']);
      expect((await store.read()).snapshot!.media.positionMs, 3000);
    },
  );

  test(
    'malformed media falls back and absent current still uses previous',
    () async {
      await store.save(snapshot(1000));
      await store.save(snapshot(2000));
      final bad = snapshot(2000).toJson();
      (bad['media']! as Map<String, Object?>)['pitch'] = 99;
      await edit((db) async {
        await db.update(
          'session_snapshots',
          {'payload': jsonEncode(bad)},
          where: 'slot = ?',
          whereArgs: ['current'],
        );
      });
      expect((await store.read()).fromPrevious, isTrue);
      await edit((db) async {
        await db.delete(
          'session_snapshots',
          where: 'slot = ?',
          whereArgs: ['current'],
        );
      });
      expect((await store.read()).snapshot!.media.positionMs, 1000);
    },
  );

  test(
    'two malformed records warn but reads preserve the original values',
    () async {
      await store.save(snapshot(1000));
      await store.save(snapshot(2000));
      await edit((db) async {
        await db.update('session_snapshots', {'payload': 'broken'});
      });
      final before = await payloads();
      final result = await store.read();
      expect(result.snapshot, isNull);
      expect(result.warning, isNotNull);
      expect(await payloads(), before);
    },
  );

  for (final slot in ['current', 'previous']) {
    test(
      'future $slot schema blocks fallback write and explicit clear',
      () async {
        await store.save(snapshot(1000));
        await store.save(snapshot(2000));
        final future = snapshot(3000).toJson()
          ..['snapshotVersion'] = SessionSnapshot.version + 1;
        await edit((db) async {
          await db.update(
            'session_snapshots',
            {'payload': jsonEncode(future)},
            where: 'slot = ?',
            whereArgs: [slot],
          );
        });
        final before = await payloads();
        final result = await store.read();
        expect(result.snapshot, isNull);
        expect(result.writeBlocked, isTrue);
        expect(store.writeBlocked, isTrue);
        await expectLater(store.save(snapshot(4000)), throwsStateError);
        await expectLater(store.clear(), throwsStateError);
        expect(await payloads(), before);
      },
    );
  }

  test('save detects a future record even if read was never called', () async {
    await store.save(snapshot(1000));
    final future = snapshot(3000).toJson()
      ..['snapshotVersion'] = SessionSnapshot.version + 1;
    await edit((db) async {
      await db.update('session_snapshots', {'payload': jsonEncode(future)});
    });
    final before = await payloads();
    await expectLater(store.save(snapshot(4000)), throwsStateError);
    expect(await payloads(), before);
  });

  test('future SQLite schema does not downgrade or erase data', () async {
    await store.save(snapshot(1000));
    await edit((db) => db.setVersion(2));
    final before = await File(path).readAsBytes();
    final result = await store.read();
    expect(result.writeBlocked, isTrue);
    expect(result.warning, contains('versão mais recente'));
    await expectLater(store.save(snapshot(2000)), throwsStateError);
    expect(await File(path).readAsBytes(), before);
  });

  test(
    'corrupt database file is left untouched and autosave fails closed',
    () async {
      final bytes = utf8.encode('Not a database. Keep this for recovery.');
      await File(path).writeAsBytes(bytes, flush: true);
      final result = await store.read();
      expect(result.snapshot, isNull);
      expect(result.writeBlocked, isTrue);
      await expectLater(store.save(snapshot(2000)), throwsStateError);
      expect(await File(path).readAsBytes(), bytes);
    },
  );

  test(
    'transaction failure rolls back both current and previous changes',
    () async {
      await store.save(snapshot(1000));
      await store.save(snapshot(2000));
      await edit(
        (db) => db.execute('''
      CREATE TRIGGER reject_current BEFORE INSERT ON session_snapshots
      WHEN NEW.slot = 'current'
      BEGIN SELECT RAISE(ABORT, 'simulated storage failure'); END
    '''),
      );
      final before = await payloads();
      await expectLater(
        store.save(snapshot(3000)),
        throwsA(isA<DatabaseException>()),
      );
      expect(await payloads(), before);
      await edit((db) => db.execute('DROP TRIGGER reject_current'));
      await store.save(snapshot(4000));
      expect((await store.read()).snapshot!.media.positionMs, 4000);
    },
  );

  test(
    'invalid new snapshot is rejected before touching saved values',
    () async {
      await store.save(snapshot(1000));
      final before = await payloads();
      final bad = SessionSnapshot(
        media: snapshot(1000).media,
        savedAt: DateTime.now(),
        screen: 'missing',
      );
      await expectLater(store.save(bad), throwsArgumentError);
      expect(await payloads(), before);
    },
  );

  test(
    'explicit clear removes snapshots only and the store remains reusable',
    () async {
      await store.save(snapshot(1000));
      await store.save(snapshot(2000));
      await store.clear();
      expect((await store.read()).snapshot, isNull);
      expect(await File(path).exists(), isTrue);
      await store.save(snapshot(3000));
      expect((await store.read()).snapshot!.media.positionMs, 3000);
    },
  );

  test(
    'close drains pending saves and rejects operations submitted afterward',
    () async {
      final saving = store.save(snapshot(1000));
      final closing = store.close();
      await expectLater(store.save(snapshot(2000)), throwsStateError);
      await saving;
      await closing;
      store = createStore();
      expect((await store.read()).snapshot!.media.positionMs, 1000);
    },
  );
}
