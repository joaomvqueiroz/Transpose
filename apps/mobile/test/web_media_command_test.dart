import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:transpose_mobile/web_media_command.dart';

void main() {
  for (final encoding in <String>['object', 'json', 'android']) {
    test('pending waits for done with $encoding result encoding', () async {
      int reads = 0;
      final bridge = _Bridge(
        onRead: (_) async {
          final result = ++reads == 1
              ? <String, dynamic>{'status': 'pending'}
              : <String, dynamic>{
                  'status': 'done',
                  'snapshot': {'playing': true, 'speed': 0.65},
                };
          return switch (encoding) {
            'json' => jsonEncode(result),
            'android' => jsonEncode(jsonEncode(result)),
            _ => result,
          };
        },
      );

      final state = await bridge.runner().execute(
        'speed',
        value: 0.65,
        isCurrent: () => true,
      );

      expect(reads, 2);
      expect(state, {'playing': true, 'speed': 0.65});
      expect(bridge.requests.values.single, {'action': 'speed', 'value': 0.65});
      expect(bridge.readIds.toSet(), {bridge.requests.keys.single});
      expect(bridge.idsFor('forgetCommand'), [bridge.requests.keys.single]);
      expect(bridge.idsFor('cancelCommand'), isEmpty);
    });
  }

  test('request serializes action safely and omits an absent value', () async {
    final bridge = _Bridge(
      onRead: (_) async => {'status': 'done', 'snapshot': <String, dynamic>{}},
    );
    const action = 'pause"; window.unrelated(); //';

    await bridge.runner().execute(action, isCurrent: () => true);

    expect(bridge.requests.values.single, {'action': action});
    expect(bridge.requests.values.single.containsKey('value'), isFalse);
  });

  test('error keeps the confirmed snapshot in a typed exception', () async {
    final snapshot = <String, dynamic>{'playing': false, 'speed': 1.0};
    final bridge = _Bridge(
      onRead: (_) async => jsonEncode({
        'status': 'error',
        'snapshot': snapshot,
        'error': 'private page diagnostics',
      }),
    );

    await expectLater(
      bridge.runner().execute('speed', value: 0.65, isCurrent: () => true),
      throwsA(
        isA<WebMediaCommandException>()
            .having((error) => error.snapshot, 'snapshot', snapshot)
            .having(
              (error) => error.toString(),
              'message',
              isNot(contains('private page diagnostics')),
            ),
      ),
    );
    expect(bridge.idsFor('forgetCommand'), [bridge.requests.keys.single]);
    expect(bridge.idsFor('cancelCommand'), isEmpty);
  });

  test('error without a valid snapshot still uses a typed exception', () async {
    final bridge = _Bridge(
      onRead: (_) async => {'status': 'error', 'snapshot': 'unavailable'},
    );

    await expectLater(
      bridge.runner().execute('play', isCurrent: () => true),
      throwsA(
        isA<WebMediaCommandException>().having(
          (error) => error.snapshot,
          'snapshot',
          isNull,
        ),
      ),
    );
  });

  test('cancelled before submission does not touch any document', () async {
    final bridge = _Bridge(
      onRead: (_) async => throw StateError('must not read'),
    );

    await expectLater(
      bridge.runner().execute('play', isCurrent: () => false),
      throwsA(isA<WebMediaCommandCancelled>()),
    );

    expect(bridge.scripts, isEmpty);
    expect(bridge.readIds, isEmpty);
  });

  test(
    'navigation during submission prevents reads and cleanup in new page',
    () async {
      bool current = true;
      final bridge = _Bridge(
        onRead: (_) async => throw StateError('must not read new document'),
        onSubmit: (script) async {
          if (script.contains('.dispatch(')) current = false;
        },
      );

      await expectLater(
        bridge.runner().execute('play', isCurrent: () => current),
        throwsA(isA<WebMediaCommandCancelled>()),
      );

      expect(bridge.requests, hasLength(1));
      expect(bridge.readIds, isEmpty);
      expect(bridge.idsFor('cancelCommand'), isEmpty);
      expect(bridge.idsFor('forgetCommand'), isEmpty);
    },
  );

  test(
    'navigation while awaiting a result rejects even a done snapshot',
    () async {
      bool current = true;
      final readStarted = Completer<void>();
      final reply = Completer<Object>();
      final bridge = _Bridge(
        onRead: (_) {
          readStarted.complete();
          return reply.future;
        },
      );
      final operation = bridge.runner().execute(
        'play',
        isCurrent: () => current,
      );
      final check = expectLater(
        operation,
        throwsA(isA<WebMediaCommandCancelled>()),
      );
      await readStarted.future;
      current = false;
      reply.complete({
        'status': 'done',
        'snapshot': {'playing': true},
      });
      await check;

      expect(bridge.readIds, hasLength(1));
      expect(bridge.idsFor('cancelCommand'), isEmpty);
      expect(bridge.idsFor('forgetCommand'), isEmpty);
    },
  );

  test(
    'navigation with pending result never polls or cleans new document',
    () async {
      bool current = true;
      final bridge = _Bridge(
        onRead: (_) async {
          current = false;
          return {'status': 'pending'};
        },
      );

      await expectLater(
        bridge.runner().execute('play', isCurrent: () => current),
        throwsA(isA<WebMediaCommandCancelled>()),
      );

      expect(bridge.readIds, hasLength(1));
      expect(bridge.idsFor('cancelCommand'), isEmpty);
      expect(bridge.idsFor('forgetCommand'), isEmpty);
    },
  );

  final invalidResults = <String, Object>{
    'missing': 'null',
    'malformed JSON': '{not valid json',
    'array': '[]',
    'number': 4,
    'unknown status': {'status': 'unknown'},
    'done without snapshot': {'status': 'done'},
    'done with invalid snapshot': {'status': 'done', 'snapshot': <Object>[]},
    'triple encoded': jsonEncode(
      jsonEncode(
        jsonEncode({
          'status': 'done',
          'snapshot': {'playing': true},
        }),
      ),
    ),
  };
  for (final entry in invalidResults.entries) {
    test('${entry.key} fails closed and cancels only its request', () async {
      final bridge = _Bridge(onRead: (_) async => entry.value);

      await expectLater(
        bridge.runner().execute('play', isCurrent: () => true),
        throwsA(isA<WebMediaCommandException>()),
      );

      final id = bridge.requests.keys.single;
      expect(bridge.idsFor('cancelCommand'), [id]);
      expect(bridge.idsFor('forgetCommand'), [id]);
    });
  }

  test(
    'pending result times out and cancels before forgetting the request',
    () async {
      final bridge = _Bridge(onRead: (_) async => {'status': 'pending'});
      final runner = bridge.runner(timeout: const Duration(milliseconds: 25));

      await _expectCommandTimeout(
        runner.execute('play', isCurrent: () => true),
      );

      expect(bridge.readIds, isNotEmpty);
      final id = bridge.requests.keys.single;
      expect(bridge.idsFor('cancelCommand'), [id]);
      expect(bridge.idsFor('forgetCommand'), [id]);
      expect(
        bridge.scripts.indexWhere(
          (script) => script.contains('cancelCommand('),
        ),
        lessThan(
          bridge.scripts.indexWhere(
            (script) => script.contains('forgetCommand('),
          ),
        ),
      );
    },
  );

  test('a never-completing submission cannot bypass the deadline', () async {
    final stalled = Completer<void>();
    final bridge = _Bridge(
      onRead: (_) async => throw StateError('submission never completed'),
      onSubmit: (script) {
        return script.contains('.dispatch(')
            ? stalled.future
            : Future<void>.value();
      },
    );

    await _expectCommandTimeout(
      bridge
          .runner(timeout: const Duration(milliseconds: 25))
          .execute('play', isCurrent: () => true),
    );

    expect(bridge.readIds, isEmpty);
    expect(bridge.idsFor('cancelCommand'), [bridge.requests.keys.single]);
    expect(bridge.idsFor('forgetCommand'), [bridge.requests.keys.single]);
  });

  test('a never-completing read cannot bypass the deadline', () async {
    final stalled = Completer<Object>();
    final bridge = _Bridge(onRead: (_) => stalled.future);

    await _expectCommandTimeout(
      bridge
          .runner(timeout: const Duration(milliseconds: 25))
          .execute('play', isCurrent: () => true),
    );

    expect(bridge.readIds, hasLength(1));
    expect(bridge.idsFor('cancelCommand'), [bridge.requests.keys.single]);
    expect(bridge.idsFor('forgetCommand'), [bridge.requests.keys.single]);
  });

  test('poll interval cannot extend the execution deadline', () async {
    final bridge = _Bridge(onRead: (_) async => {'status': 'pending'});

    await _expectCommandTimeout(
      bridge
          .runner(
            timeout: const Duration(milliseconds: 25),
            pollInterval: const Duration(seconds: 5),
          )
          .execute('play', isCurrent: () => true),
    );

    expect(bridge.readIds, hasLength(1));
  });

  test('cleanup failure cannot replace a successful snapshot', () async {
    final bridge = _Bridge(
      onRead: (_) async => {
        'status': 'done',
        'snapshot': {'playing': false},
      },
      onSubmit: (script) async {
        if (script.contains('forgetCommand(')) {
          throw StateError('page disappeared');
        }
      },
    );

    expect(await bridge.runner().execute('pause', isCurrent: () => true), {
      'playing': false,
    });
  });

  test('never-completing cleanup is bounded and preserves success', () async {
    final stalled = Completer<void>();
    final bridge = _Bridge(
      onRead: (_) async => {
        'status': 'done',
        'snapshot': {'playing': false},
      },
      onSubmit: (script) {
        return script.contains('forgetCommand(')
            ? stalled.future
            : Future<void>.value();
      },
    );

    expect(
      await bridge
          .runner()
          .execute('pause', isCurrent: () => true)
          .timeout(const Duration(seconds: 1)),
      {'playing': false},
    );
  });

  test(
    'never-completing cancellation is bounded and preserves timeout',
    () async {
      final stalled = Completer<void>();
      final bridge = _Bridge(
        onRead: (_) async => {'status': 'pending'},
        onSubmit: (script) {
          return script.contains('cancelCommand(')
              ? stalled.future
              : Future<void>.value();
        },
      );

      await _expectCommandTimeout(
        bridge
            .runner(timeout: const Duration(milliseconds: 25))
            .execute('play', isCurrent: () => true),
      );

      expect(bridge.idsFor('cancelCommand'), [bridge.requests.keys.single]);
      expect(bridge.idsFor('forgetCommand'), isEmpty);
    },
  );

  test('concurrent commands have distinct IDs and scoped cleanup', () async {
    final bothRead = Completer<void>();
    final replies = <String, Completer<Object>>{};
    final bridge = _Bridge(
      onRead: (id) {
        final reply = replies.putIfAbsent(id, Completer<Object>.new);
        if (replies.length == 2 && !bothRead.isCompleted) bothRead.complete();
        return reply.future;
      },
    );
    final runner = bridge.runner(timeout: const Duration(seconds: 2));
    final first = runner.execute('play', isCurrent: () => true);
    final second = runner.execute('pause', isCurrent: () => true);
    await bothRead.future;
    final firstId = bridge.requests.entries
        .firstWhere((entry) => entry.value['action'] == 'play')
        .key;
    final secondId = bridge.requests.entries
        .firstWhere((entry) => entry.value['action'] == 'pause')
        .key;
    expect(firstId, isNot(secondId));

    replies[secondId]!.complete({
      'status': 'done',
      'snapshot': {'playing': false},
    });
    expect(await second, {'playing': false});
    expect(bridge.idsFor('forgetCommand'), [secondId]);
    expect(bridge.idsFor('cancelCommand'), isEmpty);

    replies[firstId]!.complete({
      'status': 'done',
      'snapshot': {'playing': true},
    });
    expect(await first, {'playing': true});
    expect(bridge.idsFor('forgetCommand'), [secondId, firstId]);
    expect(bridge.idsFor('cancelCommand'), isEmpty);
  });

  test(
    'timeout cancels only the old command after a newer command completed',
    () async {
      final firstRead = Completer<void>();
      late final _Bridge bridge;
      bridge = _Bridge(
        onRead: (id) async {
          if (bridge.requests[id]!['action'] == 'pause') {
            return {
              'status': 'done',
              'snapshot': {'playing': false},
            };
          }
          if (!firstRead.isCompleted) firstRead.complete();
          return {'status': 'pending'};
        },
      );
      final runner = bridge.runner(timeout: const Duration(milliseconds: 100));
      final first = runner.execute('play', isCurrent: () => true);
      final firstCheck = _expectCommandTimeout(first);
      await firstRead.future;
      final second = runner.execute('pause', isCurrent: () => true);
      expect(await second, {'playing': false});
      await firstCheck;

      final firstId = bridge.requests.entries
          .firstWhere((entry) => entry.value['action'] == 'play')
          .key;
      final secondId = bridge.requests.entries
          .firstWhere((entry) => entry.value['action'] == 'pause')
          .key;
      expect(bridge.idsFor('cancelCommand'), [firstId]);
      expect(bridge.idsFor('forgetCommand'), [secondId, firstId]);
    },
  );
}

Future<void> _expectCommandTimeout(Future<Object> operation) async {
  await expectLater(
    operation.timeout(const Duration(seconds: 1)),
    throwsA(
      isA<TimeoutException>().having(
        (error) => error.message,
        'runner timeout rather than test guard',
        'O navegador não confirmou o comando.',
      ),
    ),
  );
}

class _Bridge {
  _Bridge({required this.onRead, this.onSubmit});

  final Future<Object> Function(String id) onRead;
  final Future<void> Function(String script)? onSubmit;
  final scripts = <String>[];
  final readIds = <String>[];
  final requests = <String, Map<String, dynamic>>{};

  Future<void> submit(String script) async {
    scripts.add(script);
    if (script.contains('.dispatch(')) {
      final request = script.substring(
        script.indexOf(',') + 1,
        script.length - 2,
      );
      requests[_id(script)] = jsonDecode(request) as Map<String, dynamic>;
    }
    if (onSubmit != null) await onSubmit!(script);
  }

  Future<Object> read(String script) {
    final id = _id(script);
    readIds.add(id);
    return onRead(id);
  }

  List<String> idsFor(String action) =>
      scripts.where((script) => script.contains('$action(')).map(_id).toList();

  WebMediaCommandRunner runner({
    Duration timeout = const Duration(seconds: 1),
    Duration pollInterval = const Duration(milliseconds: 1),
  }) => WebMediaCommandRunner(
    submitScript: submit,
    readScript: read,
    timeout: timeout,
    pollInterval: pollInterval,
  );

  static String _id(String script) {
    final match = RegExp(
      r'(?:dispatch|commandResult|cancelCommand|forgetCommand)\(("[^"]+")',
    ).firstMatch(script);
    if (match == null) throw StateError('Unexpected script: $script');
    return jsonDecode(match.group(1)!) as String;
  }
}
