import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:transpose_mobile/band_audio.dart';
import 'package:transpose_mobile/band_session.dart';

// One QA APK runs on both phones. This separate invitation channel only
// replaces manually copying the normal random session code; the band protocol
// and AudioTrack engine under test are the production implementations.
const _hostIp = '192.168.1.67';
const _guestIp = '192.168.1.68';
const _invitationPort = 39870;
const _acousticEnabled = bool.fromEnvironment('BAND_QA_ACOUSTIC');
const _acousticChannel = MethodChannel('transpose/qa_band_acoustic');
const _bandChannel = MethodChannel('transpose/band_audio');
const _steadySamples = int.fromEnvironment(
  'BAND_QA_STEADY_SAMPLES',
  defaultValue: 30,
);

Future<void> _until(
  bool Function() ready,
  String description, {
  Duration timeout = const Duration(seconds: 35),
}) async {
  final watch = Stopwatch()..start();
  while (!ready() && watch.elapsed < timeout) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  if (!ready()) throw StateError('Timed out waiting for $description');
}

Future<InternetAddress> _localAddress() async {
  final addresses =
      (await NetworkInterface.list(type: InternetAddressType.IPv4))
          .expand((interface) => interface.addresses)
          .where(
            (address) =>
                address.address == _hostIp || address.address == _guestIp,
          )
          .toList();
  if (addresses.length != 1) {
    throw StateError('Expected exactly one QA Wi-Fi address; found $addresses');
  }
  return addresses.single;
}

Map<String, Object?> _sample(
  String phase,
  BandSession session,
  Map<String, dynamic> native,
) => {
  'phase': phase,
  'elapsedUs': session.now(),
  'connected': session.connected,
  'peers': session.peers,
  'revision': session.plan.revision,
  'playing': session.plan.playing,
  'clockReady': session.isHost ? true : session.clock.ready(session.now()),
  'offsetUs': session.isHost ? 0 : session.clock.offsetUs.round(),
  'uncertaintyUs': session.isHost
      ? 0
      : session.clock.uncertaintyUs.isFinite
      ? session.clock.uncertaintyUs.round()
      : null,
  'clockSamples': session.isHost ? 0 : session.clock.sampleCount,
  'locked': native['locked'],
  'nativeRunning': native['running'],
  'clicks': native['clicks'],
  'underruns': native['underruns'],
  'maxGridErrorUs': native['maxGridErrorUs'],
  'timestampAgeMs': native['timestampAgeMs'],
  'route': native['route'],
  'leaseActive': native['leaseActive'],
  'error': native['error'],
  'sessionError': session.error,
  'nativeGeneration': native['generation'],
  'stateAgeMs': session.diagnosticStatus['stateAgeMs'],
  'clockAgeMs': session.diagnosticStatus['clockAgeMs'],
  'acceptedClockAgeMs': session.diagnosticStatus['acceptedClockAgeMs'],
  'inlierCount': session.diagnosticStatus['inlierCount'],
  'bestRttUs': session.diagnosticStatus['bestRttUs'],
  'acceptedPongs': session.diagnosticStatus['acceptedPongs'],
  'rejectedPongs': session.diagnosticStatus['rejectedPongs'],
};

Future<void> main() async {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('two real phones keep a band beat, pause, lose host and rejoin', (
    tester,
  ) async {
    final address = await _localAddress();
    final host = address.address == _hostIp;
    await _bandChannel.invokeMethod<void>(
      'setQaAcousticRole',
      host ? 'A' : 'B',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Text(host ? 'Band host QA' : 'Band guest QA')),
      ),
    );
    final audio = NativeBandAudio();
    final session = BandSession(
      audio: audio,
      onDiagnostic: (event) =>
          debugPrint('TRANSPONO_BAND_DIAG ${jsonEncode(event)}'),
    );
    final samples = <Map<String, Object?>>[];
    RawDatagramSocket? invitationSocket;
    StreamSubscription<RawSocketEvent>? invitationEvents;
    Timer? invitationTimer;
    Timer? signalTimer;
    String? latestInvitation;
    String? firstInvitation;
    int? invitationSourcePort;
    bool guestReady = false;
    bool guestDone = false;
    bool startReceived = false;
    Map<String, dynamic>? acousticStatus;
    try {
      if (host) {
        invitationSocket = await RawDatagramSocket.bind(address, 0);
        invitationEvents = invitationSocket.listen((event) {
          if (event != RawSocketEvent.read) return;
          Datagram? datagram;
          while ((datagram = invitationSocket!.receive()) != null) {
            if (datagram!.address.address != _guestIp) continue;
            try {
              final message = jsonDecode(utf8.decode(datagram.data));
              if (message is! Map<String, dynamic> ||
                  message['code'] != session.code) {
                continue;
              }
              if (message['kind'] == 'band-qa-ready') guestReady = true;
              if (message['kind'] == 'band-qa-done') guestDone = true;
            } on FormatException {
              // Ignore unrelated LAN datagrams.
            }
          }
        });
        void sendInvitation() {
          final code = session.code;
          if (code == null) return;
          invitationSocket!.send(
            utf8.encode(jsonEncode({'kind': 'band-qa-invite', 'code': code})),
            InternetAddress(_guestIp),
            _invitationPort,
          );
          if (guestReady) {
            invitationSocket.send(
              utf8.encode(jsonEncode({'kind': 'band-qa-start', 'code': code})),
              InternetAddress(_guestIp),
              _invitationPort,
            );
          }
        }

        await session.host();
        expect(session.code, isNotNull);
        expect(
          Uri.parse(session.code!).host,
          _hostIp,
          reason: 'Default host selection must choose the active band Wi-Fi.',
        );
        invitationTimer = Timer.periodic(
          const Duration(milliseconds: 400),
          (_) => sendInvitation(),
        );
        sendInvitation();
        await _until(
          () => session.peers == 1,
          'first guest join',
          timeout: const Duration(seconds: 75),
        );
        await Future<void>.delayed(const Duration(seconds: 3));
        session.setTransport(bpm: 137, beats: 3, playing: true);
        await _until(
          () =>
              session.audioStatus['locked'] == true &&
              (session.audioStatus['clicks'] as num? ?? 0) >= 2,
          'host native clicks',
        );
        await _until(
          () => guestReady,
          'guest native-ready signal',
          timeout: const Duration(seconds: 45),
        );
        if (_acousticEnabled) {
          await _acousticChannel.invokeMethod<void>('start', {
            'durationMs': 10000,
            'beatIntervalMs': 438,
          });
        }
      } else {
        invitationSocket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          _invitationPort,
        );
        invitationEvents = invitationSocket.listen((event) {
          if (event != RawSocketEvent.read) return;
          Datagram? datagram;
          while ((datagram = invitationSocket!.receive()) != null) {
            if (datagram!.address.address != _hostIp) continue;
            try {
              final message = jsonDecode(utf8.decode(datagram.data));
              if (message is Map<String, dynamic> &&
                  message['kind'] == 'band-qa-invite' &&
                  message['code'] is String) {
                latestInvitation = message['code'] as String;
                invitationSourcePort = datagram.port;
              } else if (message is Map<String, dynamic> &&
                  message['kind'] == 'band-qa-start' &&
                  message['code'] == firstInvitation) {
                startReceived = true;
              }
            } on FormatException {
              // Ignore unrelated LAN datagrams.
            }
          }
        });
        await _until(
          () => latestInvitation != null,
          'first invitation',
          timeout: const Duration(seconds: 75),
        );
        firstInvitation = latestInvitation;
        await session.join(latestInvitation!);
        expect(session.error, isNull);
        await _until(
          () => session.clock.ready(session.now()),
          'three sufficiently precise clock exchanges',
          timeout: const Duration(seconds: 45),
        );
        await _until(
          () =>
              session.plan.playing &&
              session.audioStatus['locked'] == true &&
              (session.audioStatus['clicks'] as num? ?? 0) >= 2,
          'guest scheduled native clicks',
          timeout: const Duration(seconds: 45),
        );
        void sendReady() {
          invitationSocket!.send(
            utf8.encode(
              jsonEncode({'kind': 'band-qa-ready', 'code': firstInvitation}),
            ),
            InternetAddress(_hostIp),
            invitationSourcePort!,
          );
        }

        signalTimer = Timer.periodic(
          const Duration(milliseconds: 400),
          (_) => sendReady(),
        );
        sendReady();
        await _until(
          () => startReceived,
          'host start signal',
          timeout: const Duration(seconds: 45),
        );
        signalTimer.cancel();
        signalTimer = null;
      }

      // Capture drift, clock uncertainty and any audio restarts over five
      // minutes. This measures presentation scheduling, not audible onset.
      for (var i = 0; i <= _steadySamples; i++) {
        final native = await audio.status();
        final point = _sample('steady', session, native);
        samples.add(point);
        if (i % 3 == 0) {
          debugPrint(
            'TRANSPONO_DUAL_${host ? 'HOST' : 'GUEST'} '
            '${jsonEncode(point)}',
          );
        }
        if (i < _steadySamples) {
          await Future<void>.delayed(const Duration(seconds: 10));
        }
      }

      final steadyFailures = <String>[];
      if (_acousticEnabled && host) {
        acousticStatus = Map<String, dynamic>.from(
          await _acousticChannel.invokeMapMethod<String, dynamic>('status') ??
              {},
        );
        debugPrint('TRANSPONO_ACOUSTIC_RESULT ${jsonEncode(acousticStatus)}');
      }
      for (var i = 0; i <= _steadySamples; i++) {
        final point = samples[i];
        if (point['connected'] != true ||
            point['playing'] != true ||
            point['clockReady'] != true ||
            point['locked'] != true ||
            point['nativeRunning'] != true ||
            point['leaseActive'] != true ||
            point['error'] != null ||
            point['sessionError'] != null ||
            (point['underruns'] as num? ?? -1) != 0) {
          steadyFailures.add('sample $i unhealthy: ${jsonEncode(point)}');
        }
        if (i > 0) {
          final delta =
              (point['clicks'] as num? ?? 0) -
              (samples[i - 1]['clicks'] as num? ?? 0);
          if (delta < 15 || delta > 30) {
            steadyFailures.add(
              'sample $i clicks advanced by $delta, expected 15–30',
            );
          }
        }
      }

      if (host) {
        session.setTransport(bpm: 137, beats: 3, playing: false);
        await Future<void>.delayed(const Duration(seconds: 15));
        samples.add(_sample('paused', session, await audio.status()));
        expect(samples.last['leaseActive'], isNot(true));
        session.setTransport(bpm: 137, beats: 3, playing: true);
        await Future<void>.delayed(const Duration(seconds: 12));
        samples.add(_sample('resumed', session, await audio.status()));
        expect(samples.last['leaseActive'], true);
        expect((samples.last['clicks'] as num? ?? 0), greaterThanOrEqualTo(2));
        await session.leave();
        await Future<void>.delayed(const Duration(seconds: 8));
        await session.host();
        expect(Uri.parse(session.code!).host, _hostIp);
        await _until(
          () => session.peers == 1,
          'rejoined guest',
          timeout: const Duration(seconds: 45),
        );
        await Future<void>.delayed(const Duration(seconds: 3));
        session.setTransport(bpm: 120, beats: 4, playing: true);
        await _until(
          () =>
              session.audioStatus['locked'] == true &&
              (session.audioStatus['clicks'] as num? ?? 0) >= 2,
          'host clicks after rejoin',
        );
        samples.add(_sample('rejoined', session, await audio.status()));
        await _until(
          () => guestDone,
          'guest final rejoin acknowledgement',
          timeout: const Duration(seconds: 45),
        );
      } else {
        await _until(
          () => !session.plan.playing,
          'host pause',
          timeout: const Duration(seconds: 30),
        );
        await Future<void>.delayed(const Duration(seconds: 2));
        samples.add(_sample('paused', session, await audio.status()));
        expect(samples.last['leaseActive'], isNot(true));
        await _until(
          () => session.plan.playing,
          'host resume',
          timeout: const Duration(seconds: 20),
        );
        await _until(
          () =>
              session.audioStatus['leaseActive'] == true &&
              (session.audioStatus['clicks'] as num? ?? 0) >= 2,
          'guest native clicks after resume',
          timeout: const Duration(seconds: 20),
        );
        samples.add(_sample('resumed', session, await audio.status()));
        await _until(
          () =>
              !session.clock.ready(session.now()) &&
              session.connectionStatus.contains('som suspenso'),
          'host loss suspends sound',
          timeout: const Duration(seconds: 25),
        );
        final lost = await audio.status();
        samples.add(_sample('hostLost', session, lost));
        expect(lost['leaseActive'], isNot(true));
        await _until(
          () => latestInvitation != null && latestInvitation != firstInvitation,
          'new host invitation',
          timeout: const Duration(seconds: 45),
        );
        await session.join(latestInvitation!);
        await _until(
          () => session.clock.ready(session.now()),
          'clock after rejoin',
          timeout: const Duration(seconds: 45),
        );
        await _until(
          () =>
              session.plan.playing &&
              session.plan.bpm == 120 &&
              session.audioStatus['locked'] == true &&
              (session.audioStatus['clicks'] as num? ?? 0) >= 2,
          'guest clicks after rejoin',
          timeout: const Duration(seconds: 45),
        );
        samples.add(_sample('rejoined', session, await audio.status()));
        for (var i = 0; i < 12; i++) {
          invitationSocket.send(
            utf8.encode(
              jsonEncode({'kind': 'band-qa-done', 'code': latestInvitation}),
            ),
            InternetAddress(_hostIp),
            invitationSourcePort!,
          );
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
      expect(samples.last['error'], isNull);
      binding.reportData = {
        'role': host ? 'host' : 'guest',
        'deviceIp': address.address,
        'steadySampleCount': _steadySamples + 1,
        'samples': samples,
        'steadyFailures': steadyFailures,
        'acoustic': acousticStatus,
        'scope': _acousticEnabled
            ? 'UDP clock, AudioTrack status, and local QA microphone onset metrics'
            : 'UDP clock and AudioTrack presentation status; no acoustic measurement',
      };
      debugPrint('TRANSPONO_DUAL_RESULT ${jsonEncode(binding.reportData)}');
      expect(steadyFailures, isEmpty);
      if (_acousticEnabled && host) {
        expect(acousticStatus?['busy'], false);
        expect(acousticStatus?['phase'], anyOf('done', 'inconclusive'));
      }
    } finally {
      invitationTimer?.cancel();
      signalTimer?.cancel();
      await invitationEvents?.cancel();
      invitationSocket?.close();
      await session.leave();
      session.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 9)));
}
