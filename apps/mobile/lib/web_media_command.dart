import 'dart:async';
import 'dart:convert';

/// Waits for the page's asynchronous command, not just JavaScript submission.
/// The current-document guard prevents an old page acknowledging a new source.
class WebMediaCommandRunner {
  WebMediaCommandRunner({
    required this.submitScript,
    required this.readScript,
    this.pollInterval = const Duration(milliseconds: 50),
    this.timeout = const Duration(seconds: 18),
  });

  final Future<void> Function(String) submitScript;
  final Future<Object> Function(String) readScript;
  final Duration pollInterval, timeout;
  final String _session = DateTime.now().microsecondsSinceEpoch.toString();
  int _sequence = 0;

  Future<Map<String, dynamic>> execute(
    String action, {
    num? value,
    required bool Function() isCurrent,
  }) async {
    final id = '$_session-${++_sequence}';
    final encodedId = jsonEncode(id);
    final request = jsonEncode(<String, Object>{
      'action': action,
      'value': ?value,
    });
    if (!isCurrent()) throw const WebMediaCommandCancelled();
    final watch = Stopwatch()..start();
    bool settled = false;
    try {
      await _withinDeadline(
        () => submitScript(
          'window.TransponoMedia.dispatch($encodedId,$request);',
        ),
        watch,
      );
      while (watch.elapsed < timeout) {
        if (!isCurrent()) throw const WebMediaCommandCancelled();
        final raw = await _withinDeadline(
          () => readScript(
            'JSON.stringify(window.TransponoMedia?.commandResult($encodedId) ?? null)',
          ),
          watch,
        );
        if (!isCurrent()) throw const WebMediaCommandCancelled();
        dynamic decoded = raw;
        try {
          for (int i = 0; decoded is String && i < 2; i++) {
            decoded = jsonDecode(decoded);
          }
        } on FormatException {
          throw const WebMediaCommandException();
        }
        if (decoded is! Map<String, dynamic>) {
          throw const WebMediaCommandException();
        }
        final status = decoded['status'];
        final state = decoded['snapshot'];
        if (status == 'done' && state is Map<String, dynamic>) {
          settled = true;
          return state;
        }
        if (status == 'error') {
          settled = true;
          throw WebMediaCommandException(
            snapshot: state is Map<String, dynamic> ? state : null,
          );
        }
        if (status != 'pending') throw const WebMediaCommandException();
        await _withinDeadline(() => Future<void>.delayed(pollInterval), watch);
      }
      throw TimeoutException('O navegador não confirmou o comando.', timeout);
    } finally {
      // Cleanup is scoped to this request/document and cannot erase newer work.
      await _cleanup(encodedId, cancel: !settled, isCurrent: isCurrent);
    }
  }

  Future<T> _withinDeadline<T>(
    Future<T> Function() operation,
    Stopwatch watch,
  ) {
    final remaining = timeout - watch.elapsed;
    if (remaining <= Duration.zero) {
      throw TimeoutException('O navegador não confirmou o comando.', timeout);
    }
    return operation().timeout(
      remaining,
      onTimeout: () => throw TimeoutException(
        'O navegador não confirmou o comando.',
        timeout,
      ),
    );
  }

  Future<void> _cleanup(
    String encodedId, {
    required bool cancel,
    required bool Function() isCurrent,
  }) async {
    final watch = Stopwatch()..start();
    const budget = Duration(milliseconds: 250);
    final actions = <String>[if (cancel) 'cancelCommand', 'forgetCommand'];
    for (final action in actions) {
      final remaining = budget - watch.elapsed;
      if (!isCurrent() || remaining <= Duration.zero) return;
      try {
        await submitScript('window.TransponoMedia?.$action($encodedId);')
            .timeout(remaining);
      } on Object {
        // Cleanup cannot mask the result or wait forever on a destroyed page.
      }
    }
  }
}

class WebMediaCommandException implements Exception {
  const WebMediaCommandException({this.snapshot});
  final Map<String, dynamic>? snapshot;
  @override
  String toString() => 'O navegador não conseguiu confirmar este ajuste.';
}

class WebMediaCommandCancelled implements Exception {
  const WebMediaCommandCancelled();
  @override
  String toString() => 'A fonte mudou antes de concluir o ajuste.';
}
