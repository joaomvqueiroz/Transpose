import 'dart:convert';
import 'dart:io';

import 'package:sqflite/sqflite.dart';

import 'session_snapshot.dart';

export 'session_snapshot.dart';

/// Two small records in a single SQLite transaction: the current snapshot and
/// its previous *validated* predecessor. User presets remain a separate store.
class SessionSnapshotStore extends SessionSnapshotRepository {
  SessionSnapshotStore({DatabaseFactory? databaseFactory, String? databasePath})
    : _factoryOverride = databaseFactory,
      _pathOverride = databasePath;

  static const databaseName = 'transpono_session.sqlite';
  static const _databaseVersion = 1;
  static const _table = 'session_snapshots';
  final DatabaseFactory? _factoryOverride;
  final String? _pathOverride;
  Database? _database;
  Future<void> _tail = Future<void>.value();
  bool _closed = false;
  String? _blockedReason;

  @override
  bool get writeBlocked => _blockedReason != null;

  Future<T> _serial<T>(Future<T> Function() operation) {
    if (_closed) {
      return Future<T>.error(StateError('Recovery store is closed.'));
    }
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> _checkDatabase(Database db) async {
    final schema = await db.getVersion();
    if (schema > _databaseVersion) {
      throw UnsupportedSessionSnapshotVersion(schema);
    }
    final integrity = await db.rawQuery('PRAGMA quick_check');
    if (integrity.length != 1 || integrity.single.values.single != 'ok') {
      throw const FormatException('A base de recuperação está danificada.');
    }
  }

  Future<Database> _open() async {
    if (_database != null) return _database!;
    if (writeBlocked) throw StateError(_blockedReason!);
    final factory = _factoryOverride ?? databaseFactory;
    final path =
        _pathOverride ?? '${await factory.getDatabasesPath()}/$databaseName';
    try {
      if (await factory.databaseExists(path)) {
        Database? probe;
        try {
          // Android's default writable-open corruption handler can delete the
          // file. sqflite's read-only handler explicitly does not. Verify before
          // opening writable, and never delete/recreate on a failed check.
          probe = await factory.openDatabase(
            path,
            options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
          );
          await _checkDatabase(probe);
        } on DatabaseException catch (error) {
          if (!error.isReadOnlyError()) rethrow;
          // A valid hot rollback journal needs writable recovery after process
          // death. Preserve the complete on-disk input first; if native recovery
          // fails, even its corruption handler cannot destroy this evidence.
          await probe?.close();
          probe = null;
          await _preserveInterruptedDatabase(path);
        } finally {
          await probe?.close();
        }
      }
      _database = await factory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: _databaseVersion,
          singleInstance: false,
          onConfigure: (db) async {
            await _checkDatabase(db);
            await db.execute('PRAGMA synchronous = FULL');
          },
          onCreate: (db, _) => db.execute('''
            CREATE TABLE $_table (
              slot TEXT PRIMARY KEY CHECK (slot IN ('current', 'previous')),
              payload TEXT NOT NULL
            )
          '''),
          onDowngrade: (db, oldVersion, _) =>
              throw UnsupportedSessionSnapshotVersion(oldVersion),
        ),
      );
      return _database!;
    } catch (error) {
      _blockedReason = error is UnsupportedSessionSnapshotVersion
          ? error.toString()
          : 'Não foi possível abrir a recuperação. Os dados existentes foram '
                'preservados; a gravação automática está suspensa. Verifique '
                'o armazenamento e reinicie o app para tentar novamente.';
      rethrow;
    }
  }

  Future<void> _preserveInterruptedDatabase(String path) async {
    if (path == inMemoryDatabasePath) return;
    final backup = Directory(
      '$path.interrupted-${DateTime.now().microsecondsSinceEpoch}',
    );
    await backup.create();
    for (final suffix in ['', '-journal', '-wal', '-shm']) {
      final file = File('$path$suffix');
      if (await file.exists()) {
        await file.copy('${backup.path}/$databaseName$suffix');
      }
    }
    // Retain this exceptional backup for deliberate recovery, including when
    // SQLite can repair the original; never silently remove user recovery data.
  }

  Future<Map<String, String>> _payloads(DatabaseExecutor db) async {
    final rows = await db.query(_table, columns: ['slot', 'payload']);
    return {
      for (final row in rows) row['slot'] as String: row['payload'] as String,
    };
  }

  SessionSnapshot? _parse(String? raw) {
    if (raw == null) return null;
    try {
      return SessionSnapshot.parse(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }

  SessionRecoveryResult _recover(Map<String, String> data) {
    SessionSnapshot? current, previous;
    var future = false;
    for (final slot in ['current', 'previous']) {
      try {
        final value = _parse(data[slot]);
        if (slot == 'current') {
          current = value;
        } else {
          previous = value;
        }
      } on UnsupportedSessionSnapshotVersion catch (error) {
        future = true;
        _blockedReason = error.toString();
      }
    }
    if (future) {
      // Even a valid older sibling must not downgrade a future-version session.
      return SessionRecoveryResult(warning: _blockedReason, writeBlocked: true);
    }
    if (current != null) return SessionRecoveryResult(snapshot: current);
    if (previous != null) {
      return SessionRecoveryResult(
        snapshot: previous,
        fromPrevious: true,
        warning:
            'A sessão mais recente estava incompleta. '
            'Foi recuperada a última cópia válida.',
      );
    }
    return SessionRecoveryResult(
      warning: data.isEmpty
          ? null
          : 'A sessão guardada não pôde ser recuperada. '
                'As predefinições e os ficheiros de música não foram alterados.',
    );
  }

  @override
  Future<SessionRecoveryResult> read() => _serial(() async {
    if (writeBlocked) {
      return SessionRecoveryResult(warning: _blockedReason, writeBlocked: true);
    }
    try {
      final db = await _open();
      return _recover(await _payloads(db));
    } catch (_) {
      _blockedReason ??=
          'Não foi possível ler a recuperação. '
          'Os dados foram preservados; a gravação automática está suspensa.';
      return SessionRecoveryResult(warning: _blockedReason, writeBlocked: true);
    }
  });

  @override
  Future<void> save(SessionSnapshot snapshot) => _serial(() async {
    if (writeBlocked) throw StateError(_blockedReason!);
    final json = snapshot.toJson();
    if (SessionSnapshot.parse(json) == null) {
      throw ArgumentError('A sessão a guardar é inválida.');
    }
    final encoded = jsonEncode(json);
    final db = await _open();
    await db.transaction((txn) async {
      final data = await _payloads(txn);
      final recovered = _recover(data);
      if (recovered.writeBlocked) throw StateError(_blockedReason!);
      // Invalid current records must never displace the last known good copy.
      // Copy the original JSON so compatible unknown fields are not erased.
      if (_parse(data['current']) != null) {
        await txn.insert(_table, {
          'slot': 'previous',
          'payload': data['current'],
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await txn.insert(_table, {
        'slot': 'current',
        'payload': encoded,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  });

  @override
  Future<void> clear() => _serial(() async {
    if (writeBlocked) throw StateError(_blockedReason!);
    final db = await _open();
    await db.transaction((txn) async {
      final recovered = _recover(await _payloads(txn));
      if (recovered.writeBlocked) throw StateError(_blockedReason!);
      await txn.delete(_table);
    });
  });

  @override
  Future<void> close() {
    if (_closed) return _tail;
    _closed = true;
    final result = _tail.then((_) async {
      await _database?.close();
      _database = null;
    });
    _tail = result;
    return result;
  }
}
