import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/widgets.dart';

import 'band_audio.dart';
import 'band_clock.dart';
import 'native_beat_audio_arbiter.dart';

class BandSession extends ChangeNotifier with WidgetsBindingObserver {
  BandSession({
    BandAudio? audio,
    NativeBeatAudioArbiter? arbiter,
    int Function()? now,
    this.onDiagnostic,
  }) : audio = audio ?? NativeBandAudio(),
       arbiter = arbiter ?? NativeBeatAudioArbiter.instance {
    final watch = Stopwatch()..start();
    this.now = now ?? (() => watch.elapsedMicroseconds);
    WidgetsBinding.instance.addObserver(this);
  }
  final BandAudio audio;
  final NativeBeatAudioArbiter arbiter;
  final void Function(Map<String, Object?> event)? onDiagnostic;
  late final int Function() now;
  final clock = BandClock();
  RawDatagramSocket? _socket;
  Timer? _timer;
  InternetAddress? _hostAddress;
  int _hostPort = 0;
  String _token = '';
  final _peers = <String, ({InternetAddress address, int port, int seen})>{};
  final _pings = <int, int>{};
  int _sequence = 0, _lastSequence = -1, _lastState = -1, _nonce = 0;
  int _generation = 0, _activeRevision = -1, _effectiveStart = 0;
  bool _disposed = false, _ticking = false, _prepared = false;
  bool _ownsAudio = false;
  Completer<void>? _tickDone;
  Future<void>? _audioStopTask;
  bool? _lastHealthy;
  int _acceptedPongs = 0, _rejectedPongs = 0;
  bool isHost = false;
  bool get connected => _socket != null;
  int get peers => _peers.length;
  String? code, error;
  String connectionStatus = 'Desligado';
  int correctionMs = 0;
  Map<String, dynamic> audioStatus = {};
  BandBeatPlan plan = const BandBeatPlan(
    revision: 0,
    bpm: 100,
    beatsPerBar: 4,
    startUs: 0,
    playing: false,
  );

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _trace(String event, [Map<String, Object?> details = const {}]) {
    onDiagnostic?.call({'event': event, 'atUs': now(), ...details});
  }

  Map<String, Object?> get diagnosticStatus {
    final time = now();
    final lastClock = clock.lastSampleAt;
    final lastAccepted = clock.lastAcceptedAt;
    return {
      'stateAgeMs': _lastState < 0 ? null : (time - _lastState) / 1000,
      'clockAgeMs': lastClock == null ? null : (time - lastClock) / 1000,
      'acceptedClockAgeMs': lastAccepted == null
          ? null
          : (time - lastAccepted) / 1000,
      'inlierCount': clock.inlierCount,
      'uncertaintyUs': clock.uncertaintyUs.isFinite
          ? clock.uncertaintyUs.round()
          : null,
      'bestRttUs': clock.bestRttUs,
      'recentRttsUs': clock.recentRttsUs,
      'acceptedPongs': _acceptedPongs,
      'rejectedPongs': _rejectedPongs,
    };
  }

  static bool localAddress(InternetAddress address) {
    final b = address.rawAddress;
    return address.type == InternetAddressType.IPv4 &&
        (b[0] == 10 ||
            b[0] == 127 ||
            (b[0] == 192 && b[1] == 168) ||
            (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
            (b[0] == 169 && b[1] == 254));
  }

  Future<void> host({InternetAddress? address}) async {
    final generation = _generation + 1;
    await leave();
    if (_disposed || generation != _generation) return;
    try {
      if (address == null) {
        final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4,
        );
        address = interfaces
            .expand((i) => i.addresses)
            .where((a) => localAddress(a) && !a.isLoopback)
            .firstOrNull;
      }
      if (address == null || !localAddress(address)) {
        throw const SocketException('Ligue o telemóvel à rede Wi-Fi da banda.');
      }
      final socket = await RawDatagramSocket.bind(address, 0);
      if (_disposed || generation != _generation) {
        socket.close();
        return;
      }
      final random = Random.secure();
      _token = List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      isHost = true;
      code = 'transpono://${address.address}:${socket.port}/$_token';
      _attach(socket);
    } on Object catch (e) {
      if (generation == _generation) _fail(e);
    }
  }

  Future<void> join(String invitation) async {
    final generation = _generation + 1;
    await leave();
    if (_disposed || generation != _generation) return;
    try {
      final uri = Uri.parse(invitation.trim());
      final address = InternetAddress.tryParse(uri.host);
      if (uri.scheme != 'transpono' ||
          address == null ||
          !localAddress(address) ||
          !uri.hasPort ||
          uri.port < 1 ||
          uri.port > 65535 ||
          uri.pathSegments.length != 1 ||
          !RegExp(r'^[a-f0-9]{32}$').hasMatch(uri.pathSegments.single)) {
        throw const FormatException(
          'Cole o código completo da sessão da banda.',
        );
      }
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      if (_disposed || generation != _generation) {
        socket.close();
        return;
      }
      _hostAddress = address;
      _hostPort = uri.port;
      _token = uri.pathSegments.single;
      isHost = false;
      _attach(socket);
    } on Object catch (e) {
      if (generation == _generation) _fail(e);
    }
  }

  void _attach(RawDatagramSocket socket) {
    _socket = socket;
    error = null;
    connectionStatus = isHost
        ? 'Anfitrião · à espera da banda'
        : 'A ligar à banda…';
    socket.listen(
      (event) {
        if (event != RawSocketEvent.read || socket != _socket) return;
        Datagram? packet;
        while ((packet = socket.receive()) != null) {
          _receive(packet!);
        }
      },
      onError: (Object e) {
        if (socket != _socket || _disposed) return;
        _fail(e);
        unawaited(leave());
      },
    );
    _timer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => unawaited(_tick()),
    );
    unawaited(_tick());
    _notify();
  }

  void _send(Map<String, Object> message, InternetAddress address, int port) {
    try {
      _socket?.send(
        utf8.encode(jsonEncode({'v': 1, 'token': _token, ...message})),
        address,
        port,
      );
    } on SocketException catch (e) {
      _fail(e);
    }
  }

  void _receive(Datagram packet) {
    if (packet.data.length > 2048 || !localAddress(packet.address)) return;
    try {
      final m = jsonDecode(utf8.decode(packet.data));
      if (m is! Map<String, dynamic> || m['v'] != 1 || m['token'] != _token) {
        return;
      }
      final received = now();
      if (isHost) {
        if (m['type'] != 'ping' || m['id'] is! int) return;
        final key = '${packet.address.address}:${packet.port}';
        if (!_peers.containsKey(key) && _peers.length >= 16) return;
        _peers[key] = (
          address: packet.address,
          port: packet.port,
          seen: received,
        );
        _send(
          {
            'type': 'pong',
            'id': m['id'] as int,
            'received': received,
            'sent': now(),
          },
          packet.address,
          packet.port,
        );
        _sendState(packet.address, packet.port);
      } else {
        if (packet.address.address != _hostAddress?.address ||
            packet.port != _hostPort) {
          return;
        }
        if (m['type'] == 'pong' &&
            m['id'] is int &&
            m['received'] is int &&
            m['sent'] is int) {
          final sent = _pings.remove(m['id']);
          if (sent != null) {
            final accepted = clock.add(
              sent: sent,
              received: received,
              hostReceived: m['received'] as int,
              hostSent: m['sent'] as int,
            );
            if (accepted) {
              _acceptedPongs++;
            } else {
              _rejectedPongs++;
            }
          }
        } else if (m['type'] == 'state' &&
            m['seq'] is int &&
            (m['seq'] as int) > _lastSequence &&
            m['plan'] is Map<String, dynamic>) {
          final next = BandBeatPlan.fromJson(m['plan'] as Map<String, dynamic>);
          if (next.revision < plan.revision) return;
          _lastSequence = m['seq'] as int;
          _lastState = received;
          plan = next;
        }
      }
    } on Object {
      // Ignore malformed or incompatible datagrams without changing playback.
    }
  }

  void _sendState(InternetAddress address, int port) => _send(
    {'type': 'state', 'seq': ++_sequence, 'plan': plan.toJson()},
    address,
    port,
  );

  void setTransport({
    required int bpm,
    required int beats,
    required bool playing,
  }) {
    if (!connected || !isHost) return;
    if (bpm < 40 || bpm > 240 || beats < 1 || beats > 12) return;
    plan = BandBeatPlan(
      revision: plan.revision + 1,
      bpm: bpm,
      beatsPerBar: beats,
      startUs: now() + 2500000,
      playing: playing,
    );
    for (final peer in _peers.values) {
      _sendState(peer.address, peer.port);
    }
    unawaited(_tick());
    _notify();
  }

  Future<void> _tick() async {
    if (_ticking || !connected || _disposed) return;
    _ticking = true;
    final tickDone = Completer<void>();
    _tickDone = tickDone;
    final generation = _generation;
    try {
      final time = now();
      _peers.removeWhere((_, p) => time - p.seen > 4000000);
      _pings.removeWhere((_, sent) => time - sent > 3000000);
      if (isHost) {
        for (final p in _peers.values) {
          _sendState(p.address, p.port);
        }
      } else {
        _pings[++_nonce] = time;
        _send({'type': 'ping', 'id': _nonce}, _hostAddress!, _hostPort);
      }
      final healthy =
          isHost ||
          (_lastState >= 0 && time - _lastState < 2500000 && clock.ready(time));
      if (_lastHealthy != healthy) {
        _trace('health', {
          'healthy': healthy,
          'playing': plan.playing,
          'connected': connected,
          ...diagnosticStatus,
        });
        _lastHealthy = healthy;
      }
      connectionStatus = isHost
          ? 'Anfitrião · $peers ligado(s)'
          : healthy
          ? 'Relógio alinhado · ±${(clock.uncertaintyUs / 1000).toStringAsFixed(1)} ms'
          : 'A sincronizar · som suspenso';
      if (!healthy || !plan.playing) {
        if (_ownsAudio) {
          _trace('audioStop', {
            'reason': !plan.playing ? 'transportPaused' : 'unhealthy',
            ...diagnosticStatus,
          });
          await _stopOwnedAudio();
        }
        _activeRevision = -1;
      } else {
        if (!_ownsAudio) {
          if (!arbiter.tryAcquire(this)) {
            connectionStatus = 'Saída nativa ocupada';
            _notify();
            return;
          }
          _ownsAudio = true;
        }
        if (!_prepared) {
          _trace('audioPrepare', diagnosticStatus);
          await audio.prepare(now);
          if (generation != _generation || _disposed) {
            await _stopOwnedAudio();
            return;
          }
          _prepared = true;
        }
        if (!connected || !plan.playing) {
          _trace('audioStop', {
            'reason': !connected
                ? 'disconnectedDuringPrepare'
                : 'pausedDuringPrepare',
          });
          await _stopOwnedAudio();
          return;
        }
        if (_activeRevision != plan.revision) {
          final hostNow = isHost ? now() : now() + clock.offsetUs.round();
          _effectiveStart = plan.startUs >= hostNow + 700000
              ? plan.startUs
              : plan.nextBar(hostNow + 700000);
          _activeRevision = plan.revision;
        }
        await audio.schedule(
          revision: plan.revision,
          startUs: isHost ? _effectiveStart : clock.localTime(_effectiveStart),
          bpm: plan.bpm,
          beats: plan.beatsPerBar,
          validUntilUs: now() + 1250000,
          correctionUs: correctionMs * 1000,
        );
        if (generation != _generation || !connected || !plan.playing) {
          _trace('audioStop', {'reason': 'changedDuringSchedule'});
          await _stopOwnedAudio();
          return;
        }
        audioStatus = await audio.status();
        if (audioStatus['error'] != null) {
          throw StateError('${audioStatus['error']}');
        }
      }
      _notify();
    } on Object catch (e) {
      if (generation == _generation) {
        _fail(e);
        unawaited(leave(reason: 'tickError'));
      }
    } finally {
      _ticking = false;
      if (identical(_tickDone, tickDone)) _tickDone = null;
      tickDone.complete();
    }
  }

  Future<void> _stopOwnedAudio() {
    final inProgress = _audioStopTask;
    if (inProgress != null) return inProgress;
    if (!_ownsAudio) return Future<void>.value();
    // Keep the lease until the native stop completes. A failed stop leaves
    // ownership locked rather than allowing another session to overlap it.
    final task = () async {
      await audio.stop();
      _prepared = false;
      _ownsAudio = false;
      arbiter.release(this);
    }();
    _audioStopTask = task;
    return task.whenComplete(() {
      if (identical(_audioStopTask, task)) _audioStopTask = null;
    });
  }

  void _fail(Object e) {
    error = e is FormatException
        ? e.message
        : 'Não foi possível manter a sessão: $e';
    _notify();
  }

  Future<void> leave({String reason = 'explicit'}) async {
    _trace('leave', {'reason': reason, 'prepared': _prepared});
    ++_generation;
    _timer?.cancel();
    _timer = null;
    _socket?.close();
    _socket = null;
    _peers.clear();
    _pings.clear();
    clock.clear();
    _lastSequence = -1;
    _lastState = -1;
    _activeRevision = -1;
    _lastHealthy = null;
    code = null;
    isHost = false;
    audioStatus = {};
    plan = const BandBeatPlan(
      revision: 0,
      bpm: 100,
      beatsPerBar: 4,
      startUs: 0,
      playing: false,
    );
    connectionStatus = 'Desligado';
    await _tickDone?.future;
    await _stopOwnedAudio();
    _notify();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _trace('lifecycle', {'state': state.name});
    if (state != AppLifecycleState.resumed) {
      unawaited(leave(reason: 'lifecycle:${state.name}'));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(leave(reason: 'dispose'));
    super.dispose();
  }
}
