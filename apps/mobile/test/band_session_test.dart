import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:transpose_mobile/band_audio.dart';
import 'package:transpose_mobile/band_clock.dart';
import 'package:transpose_mobile/band_session.dart';
import 'package:transpose_mobile/native_beat_audio_arbiter.dart';
import 'package:transpose_mobile/study_tools.dart';

class FakeAudio implements BandAudio {
  int starts = 0, stops = 0, schedules = 0;
  int? start, revision;
  bool active = false;
  @override
  Future<void> prepare(int Function() now) async {
    starts++;
  }

  @override
  Future<void> schedule({
    required int revision,
    required int startUs,
    required int bpm,
    required int beats,
    required int validUntilUs,
    required int correctionUs,
  }) async {
    this.revision = revision;
    start = startUs;
    schedules++;
    active = true;
  }

  @override
  Future<Map<String, dynamic>> status() async => {'locked': true};
  @override
  Future<void> stop() async {
    stops++;
    active = false;
  }
}

class DelayedStopAudio extends FakeAudio {
  final release = Completer<void>();
  @override
  Future<void> stop() async {
    await release.future;
    await super.stop();
  }
}

class DelayedPrepareAudio extends FakeAudio {
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> prepare(int Function() now) async {
    starts++;
    entered.complete();
    await release.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<void> until(bool Function() ready) async {
    for (var i = 0; i < 40 && !ready(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  test(
    'clock rejects bad samples and bounds offset under asymmetric jitter',
    () {
      final clock = BandClock();
      for (var i = 0; i < 12; i++) {
        final t = i * 250000;
        final outbound = i % 3 == 0 ? 14000 : 2000;
        expect(
          clock.add(
            sent: t,
            received: t + outbound + 2100,
            hostReceived: t + outbound + 750000,
            hostSent: t + outbound + 750100,
          ),
          isTrue,
        );
      }
      expect(clock.ready(2800000), isTrue);
      expect(clock.offsetUs, closeTo(750000, clock.uncertaintyUs));
      expect(clock.localTime(1750000), closeTo(1000000, 2000));
      expect(
        clock.add(sent: 10, received: 5, hostReceived: 15, hostSent: 20),
        isFalse,
      );
      expect(clock.ready(8000000), isFalse);
    },
  );
  test(
    'recent samples track drift without retaining an old best packet forever',
    () {
      final clock = BandClock();
      for (var i = 0; i < 150; i++) {
        final t = i * 250000;
        final offset = 750000 + (t * .0001).round();
        clock.add(
          sent: t,
          received: t + 4100,
          hostReceived: t + 2000 + offset,
          hostSent: t + 2100 + offset,
        );
      }
      expect(clock.offsetUs, closeTo(753725, 1100));
    },
  );
  test('asymmetric RTT outlier cannot suspend or refresh a good clock', () {
    final clock = BandClock();
    void add(int sent, int rtt, int offset) {
      final hostTime = sent + offset + rtt ~/ 2;
      expect(
        clock.add(
          sent: sent,
          received: sent + rtt,
          hostReceived: hostTime,
          hostSent: hostTime,
        ),
        isTrue,
      );
    }

    add(0, 9000, 0);
    add(250000, 9300, 0);
    add(500000, 10000, 0);
    add(750000, 11000, 0);
    expect(clock.ready(761000), isTrue);
    add(1000000, 27600, 10000);
    expect(clock.ready(1027600), isTrue);
    expect(clock.uncertaintyUs, lessThanOrEqualTo(20000));

    // Accepted but high-uncertainty packets must not keep old inliers fresh.
    add(4000000, 27600, 10000);
    expect(clock.ready(4027600), isFalse);
  });
  test('clock never becomes ready from only two precise inliers', () {
    final clock = BandClock();
    void add(int sent, int rtt, int offset) {
      final hostTime = sent + offset + rtt ~/ 2;
      expect(
        clock.add(
          sent: sent,
          received: sent + rtt,
          hostReceived: hostTime,
          hostSent: hostTime,
        ),
        isTrue,
      );
    }

    add(0, 8000, 0);
    add(250000, 9000, 0);
    for (var i = 2; i < 8; i++) {
      add(i * 250000, 120000, 50000);
    }
    expect(clock.inlierCount, 2);
    expect(clock.ready(2000000), isFalse);
    add(2000000, 10000, 0);
    expect(clock.ready(2010000), isTrue);
  });
  test('absolute beat grid does not accumulate rounding over an hour', () {
    const plan = BandBeatPlan(
      revision: 1,
      bpm: 137,
      beatsPerBar: 3,
      startUs: 9000000,
      playing: true,
    );
    expect(plan.beatTime(8220), 3609000000);
    final next = plan.nextBar(plan.beatTime(8));
    expect(next, plan.beatTime(9));
    expect(() => BandBeatPlan.fromJson({'bpm': 0}), throwsFormatException);
  });
  test(
    'two actual UDP sessions align, stop, reject bad code and leave safely',
    () async {
      final hostAudio = FakeAudio(), guestAudio = FakeAudio();
      // These fakes represent separate devices, each with its own channel.
      final host = BandSession(
        audio: hostAudio,
        arbiter: NativeBeatAudioArbiter(),
      );
      final guest = BandSession(
        audio: guestAudio,
        arbiter: NativeBeatAudioArbiter(),
      );
      addTearDown(() async {
        await host.leave();
        await guest.leave();
        host.dispose();
        guest.dispose();
      });
      await host.host(address: InternetAddress.loopbackIPv4);
      expect(host.code, isNotNull);
      await guest.join(host.code!);
      await until(() => host.peers == 1 && guest.clock.ready(guest.now()));
      expect(host.peers, 1);
      expect(guest.clock.ready(guest.now()), isTrue);
      host.setTransport(bpm: 137, beats: 3, playing: true);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(guest.plan.bpm, 137);
      expect(guestAudio.active, isTrue);
      expect(
        guestAudio.start! + guest.clock.offsetUs,
        closeTo(hostAudio.start!, 20000),
      );
      host.setTransport(bpm: 137, beats: 3, playing: false);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(guestAudio.active, isFalse);
      host.setTransport(bpm: 100, beats: 4, playing: true);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await host.leave();
      await Future<void>.delayed(const Duration(milliseconds: 3100));
      expect(
        guestAudio.active,
        isFalse,
        reason: 'A lost host must not leave a click running.',
      );
      await guest.join(
        'transpono://8.8.8.8:9/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      );
      expect(guest.connected, isFalse);
      expect(guest.error, isNotNull);
    },
  );
  test('a later connection request cancels an earlier pending host', () async {
    final audio = DelayedStopAudio();
    final session = BandSession(audio: audio);
    final first = session.host(address: InternetAddress.loopbackIPv4);
    final second = session.join('invalid code');
    audio.release.complete();
    await Future.wait([first, second]);
    expect(session.connected, isFalse);
    expect(session.code, isNull);
    expect(session.error, isNotNull);
    await session.leave();
    session.dispose();
  });
  test('pause during audio preparation does not schedule a click', () async {
    final audio = DelayedPrepareAudio();
    final session = BandSession(audio: audio);
    await session.host(address: InternetAddress.loopbackIPv4);
    session.setTransport(bpm: 120, beats: 4, playing: true);
    await audio.entered.future;
    session.setTransport(bpm: 120, beats: 4, playing: false);
    audio.release.complete();
    await until(() => audio.stops >= 1);
    expect(audio.schedules, 0);
    expect(audio.active, isFalse);
    await session.leave();
    session.dispose();
  });
  test('leaving an unowned band session cannot stop another owner', () async {
    final arbiter = NativeBeatAudioArbiter();
    final youtubeOwner = Object();
    expect(arbiter.tryAcquire(youtubeOwner), isTrue);
    final audio = FakeAudio();
    final session = BandSession(audio: audio, arbiter: arbiter);
    await session.leave();
    expect(audio.stops, 0);
    expect(arbiter.owns(youtubeOwner), isTrue);
    session.dispose();
    arbiter.release(youtubeOwner);
  });
  test(
    'band waits for the shared native output and then releases it',
    () async {
      final arbiter = NativeBeatAudioArbiter();
      final youtubeOwner = Object();
      expect(arbiter.tryAcquire(youtubeOwner), isTrue);
      final audio = FakeAudio();
      final session = BandSession(audio: audio, arbiter: arbiter);
      addTearDown(() async {
        await session.leave();
        session.dispose();
      });
      await session.host(address: InternetAddress.loopbackIPv4);
      session.setTransport(bpm: 120, beats: 4, playing: true);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(audio.starts, 0);
      expect(audio.schedules, 0);
      expect(audio.stops, 0);
      expect(arbiter.owns(youtubeOwner), isTrue);

      arbiter.release(youtubeOwner);
      await until(() => audio.schedules > 0);
      expect(audio.active, isTrue);
      await session.leave();
      expect(audio.stops, 1);
      expect(arbiter.tryAcquire(youtubeOwner), isTrue);
      arbiter.release(youtubeOwner);
    },
  );
  test(
    'leave during prepare holds ownership until native stop completes',
    () async {
      final arbiter = NativeBeatAudioArbiter();
      final audio = DelayedPrepareAudio();
      final session = BandSession(audio: audio, arbiter: arbiter);
      await session.host(address: InternetAddress.loopbackIPv4);
      session.setTransport(bpm: 120, beats: 4, playing: true);
      await audio.entered.future;
      final competingOwner = Object();
      expect(arbiter.tryAcquire(competingOwner), isFalse);
      final leaving = session.leave();
      expect(arbiter.tryAcquire(competingOwner), isFalse);
      audio.release.complete();
      await leaving;
      expect(audio.schedules, 0);
      expect(audio.stops, 1);
      expect(arbiter.tryAcquire(competingOwner), isTrue);
      arbiter.release(competingOwner);
      session.dispose();
    },
  );
  test('concurrent leave calls share one native stop', () async {
    final arbiter = NativeBeatAudioArbiter();
    final audio = DelayedStopAudio();
    final session = BandSession(audio: audio, arbiter: arbiter);
    await session.host(address: InternetAddress.loopbackIPv4);
    session.setTransport(bpm: 120, beats: 4, playing: true);
    await until(() => audio.schedules > 0);
    final competingOwner = Object();
    final first = session.leave();
    final second = session.leave();
    expect(arbiter.tryAcquire(competingOwner), isFalse);
    audio.release.complete();
    await Future.wait([first, second]);
    expect(audio.stops, 1);
    expect(arbiter.tryAcquire(competingOwner), isTrue);
    arbiter.release(competingOwner);
    session.dispose();
  });
  testWidgets('embedded metronome keeps owner session until app pauses', (
    tester,
  ) async {
    final session = BandSession(audio: FakeAudio());
    await session.host(address: InternetAddress.loopbackIPv4);
    expect(session.connected, isTrue);
    session.setTransport(bpm: 137, beats: 3, playing: false);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: embeddedStudyTool('metronome', bandSession: session),
        ),
      ),
    );
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('video'))),
    );
    expect(session.connected, isTrue);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: embeddedStudyTool('metronome', bandSession: session),
        ),
      ),
    );
    expect(find.text('137 BPM'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(session.connected, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    session.dispose();
  });
}
