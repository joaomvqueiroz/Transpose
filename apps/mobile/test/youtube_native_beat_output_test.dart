import 'package:flutter_test/flutter_test.dart';
import 'package:transpose_mobile/band_audio.dart';
import 'package:transpose_mobile/youtube_beat_scheduler.dart';
import 'package:transpose_mobile/youtube_native_beat_output.dart';

class FakeAudio implements FractionalBeatAudio {
  int prepares = 0, stops = 0, schedules = 0;
  double? bpm;
  int? startUs, beats, expiry, revision;
  bool fail = false;

  @override
  Future<void> prepare(int Function() now) async {
    prepares++;
  }

  @override
  Future<void> scheduleFractional({
    required int revision,
    required int startUs,
    required double bpm,
    required int beats,
    required int validUntilUs,
    required int correctionUs,
  }) async {
    schedules++;
    if (fail) throw StateError('decoder');
    this.revision = revision;
    this.startUs = startUs;
    this.bpm = bpm;
    this.beats = beats;
    expiry = validUntilUs;
    expect(correctionUs, 0);
  }

  @override
  Future<void> stop() async {
    stops++;
  }
}

class FakeArbiter implements YouTubeBeatAudioArbiter {
  bool busy = false;
  int releases = 0;
  @override
  bool tryAcquire() {
    if (busy) return false;
    busy = true;
    return true;
  }

  @override
  void release() {
    busy = false;
    releases++;
  }
}

YouTubeBeatSchedule plan({double bpm = 90.5, int expiry = 11000000}) =>
    YouTubeBeatSchedule(
      revision: 2,
      epoch: 1,
      sectionIndex: 0,
      gridStartUs: 9500000,
      nextBeatUs: 10500000,
      nextBeatIndex: 2,
      bpm: bpm,
      beatsPerBar: 3,
      validUntilUs: expiry,
    );

void main() {
  test(
    '90.5 BPM survives bridge without rounding; one prepare per lease',
    () async {
      var now = 10000000;
      final audio = FakeAudio();
      final arbiter = FakeArbiter();
      final output = YouTubeNativeBeatOutput(
        audio: audio,
        nowUs: () => now,
        arbiter: arbiter,
        bandSessionActive: () => false,
      );
      await output.schedule(plan());
      await output.schedule(plan(expiry: 11200000));
      expect(audio.prepares, 1);
      expect(audio.schedules, 2);
      expect(audio.bpm, 90.5);
      expect(audio.startUs, 9500000);
      expect(audio.beats, 3);
      expect(audio.revision, 2);
      expect(audio.expiry, 11200000);
      await output.stop();
      expect(audio.stops, 1);
      expect(arbiter.busy, false);
      now += 100000;
      await output.schedule(plan(expiry: 11500000));
      expect(audio.prepares, 2);
      await output.stop();
    },
  );

  test('pause/seek stop is idempotent and releases ownership', () async {
    final audio = FakeAudio();
    final arbiter = FakeArbiter();
    final output = YouTubeNativeBeatOutput(
      audio: audio,
      nowUs: () => 10000000,
      arbiter: arbiter,
      bandSessionActive: () => false,
    );
    await output.schedule(plan());
    await output.stop();
    await output.stop();
    expect(audio.stops, 1);
    expect(arbiter.releases, 1);
    expect(arbiter.busy, false);
  });

  test('expired lease and BandSession cannot seize shared channel', () async {
    final audio = FakeAudio();
    final arbiter = FakeArbiter();
    var bandActive = true;
    final output = YouTubeNativeBeatOutput(
      audio: audio,
      nowUs: () => 10000000,
      arbiter: arbiter,
      bandSessionActive: () => bandActive,
    );
    await expectLater(output.schedule(plan()), throwsStateError);
    expect(audio.prepares, 0);
    bandActive = false;
    arbiter.busy = true;
    await expectLater(output.schedule(plan()), throwsStateError);
    expect(audio.prepares, 0);
    arbiter.busy = false;
    await expectLater(
      output.schedule(plan(expiry: 10510000)),
      throwsArgumentError,
    );
    expect(audio.prepares, 0);
    expect(audio.stops, 0, reason: 'must not stop BandSession audio');
  });

  test('schedule error stops owned output and releases lease', () async {
    final audio = FakeAudio()..fail = true;
    final arbiter = FakeArbiter();
    final output = YouTubeNativeBeatOutput(
      audio: audio,
      nowUs: () => 10000000,
      arbiter: arbiter,
      bandSessionActive: () => false,
    );
    await expectLater(output.schedule(plan()), throwsStateError);
    expect(audio.stops, 1);
    expect(arbiter.busy, false);
  });
}
