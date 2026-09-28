import 'package:flutter_test/flutter_test.dart';
import 'package:transpose_mobile/rhythm_map.dart';
import 'package:transpose_mobile/youtube_beat_scheduler.dart';
import 'package:transpose_mobile/youtube_browser.dart';

class FakeBeatOutput implements YouTubeBeatOutput {
  final plans = <YouTubeBeatSchedule>[];
  int stops = 0;
  bool active = false;
  @override
  Future<void> schedule(YouTubeBeatSchedule plan) async {
    plans.add(plan);
    active = true;
  }

  @override
  Future<void> stop() async {
    stops++;
    active = false;
  }
}

const videoId = 'abcdefghijk';
const rhythm = RhythmMap(12, [
  RhythmSection(
    start: 0,
    end: 4.5,
    firstBeat: 0.5,
    bpm: 120,
    beatsPerBar: 3,
    confidence: 0.9,
  ),
  RhythmSection(
    start: 6,
    end: 11.5,
    firstBeat: 6,
    bpm: 90,
    beatsPerBar: 4,
    confidence: 0.85,
  ),
]);

YouTubeTimelineSample sample({
  required int revision,
  required int epoch,
  required int atUs,
  required double positionMs,
  double speed = 1,
  double uncertaintyMs = 2,
  String id = videoId,
}) => YouTubeTimelineSample(
  videoId: id,
  revision: revision,
  epoch: epoch,
  positionMs: positionMs,
  speed: speed,
  browserTimeMs: atUs / 1000,
  hostMidpointUs: atUs,
  uncertaintyMs: uncertaintyMs,
);

YouTubeMediaState media({
  bool playing = true,
  bool ready = true,
  bool ad = false,
  double speed = 1,
  String id = videoId,
}) => YouTubeMediaState(
  videoId: id,
  hasVideo: true,
  playing: playing,
  playbackReady: ready,
  isAd: ad,
  speed: speed,
);

void main() {
  test('120→90 BPM sections preserve metre phase and stop in gap', () async {
    var now = 10000000;
    final output = FakeBeatOutput();
    final scheduler = YouTubeBeatScheduler(
      map: rhythm,
      videoId: videoId,
      output: output,
      nowUs: () => now,
    );
    await scheduler.update(
      sample: sample(revision: 1, epoch: 1, atUs: now, positionMs: 1100),
      media: media(),
    );
    expect(
      output.plans,
      isEmpty,
      reason: 'first epoch observation only disarms',
    );
    await scheduler.update(
      sample: sample(revision: 2, epoch: 1, atUs: now, positionMs: 1100),
      media: media(),
    );
    final first = output.plans.single;
    expect(first.bpm, 120);
    expect(first.beatsPerBar, 3);
    expect(first.gridStartUs, 9400000);
    expect(first.nextBeatIndex, 2);
    expect(first.nextBeatUs, 10400000);
    expect(first.validUntilUs, greaterThan(first.nextBeatUs + 25000));

    now += 4000000;
    await scheduler.update(
      sample: sample(revision: 3, epoch: 1, atUs: now, positionMs: 5000),
      media: media(),
    );
    expect(scheduler.activeSchedule, isNull);
    expect(scheduler.lastStopReason, 'sectionGap');

    now += 1450000;
    await scheduler.update(
      sample: sample(revision: 4, epoch: 1, atUs: now, positionMs: 6450),
      media: media(),
    );
    final second = scheduler.activeSchedule!;
    expect(second.bpm, 90);
    expect(second.beatsPerBar, 4);
    expect(second.sectionIndex, 1);
    expect(second.nextBeatIndex, 1);
    expect(second.validUntilUs, greaterThan(second.nextBeatUs + 25000));
    expect(second.revision, greaterThan(first.revision));
    await scheduler.close();
  });

  test('pause, seek, rate, ad and buffering always disarm', () async {
    var now = 10000000;
    final output = FakeBeatOutput();
    final scheduler = YouTubeBeatScheduler(
      map: rhythm,
      videoId: videoId,
      output: output,
      nowUs: () => now,
    );
    Future<void> observe(
      int rev,
      int epoch,
      YouTubeMediaState state, {
      bool seeking = false,
      double speed = 1,
    }) => scheduler.update(
      sample: sample(
        revision: rev,
        epoch: epoch,
        atUs: now,
        positionMs: 1100,
        speed: speed,
      ),
      media: state,
      seeking: seeking,
    );

    await observe(1, 1, media());
    await observe(2, 1, media());
    expect(output.active, true);
    await observe(3, 1, media(playing: false));
    expect(output.active, false);
    await observe(4, 1, media());
    expect(output.active, true);
    await observe(5, 2, media(), seeking: true);
    expect(output.active, false);
    await observe(6, 2, media());
    expect(output.active, false, reason: 'new epoch needs another observation');
    await observe(7, 2, media());
    expect(output.active, true);
    await observe(8, 2, media(speed: 1.25), speed: 1.25);
    expect(output.active, false);
    await observe(9, 2, media());
    expect(output.active, true);
    await observe(10, 2, media(ad: true));
    expect(output.active, false);
    await observe(11, 2, media());
    expect(output.active, true);
    await observe(12, 2, media(ready: false));
    expect(output.active, false);
    await scheduler.close();
  });

  test(
    'stale, uncertain and low-confidence observations produce no lease',
    () async {
      var now = 10000000;
      final output = FakeBeatOutput();
      final lowMap = RhythmMap(12, [
        const RhythmSection(
          start: 0,
          end: 12,
          firstBeat: 0.5,
          bpm: 120,
          beatsPerBar: 4,
          confidence: 0.2,
        ),
      ]);
      final scheduler = YouTubeBeatScheduler(
        map: lowMap,
        videoId: videoId,
        output: output,
        nowUs: () => now,
      );
      await scheduler.update(
        sample: sample(revision: 1, epoch: 1, atUs: now, positionMs: 1100),
        media: media(),
      );
      await scheduler.update(
        sample: sample(revision: 2, epoch: 1, atUs: now, positionMs: 1100),
        media: media(),
      );
      expect(output.active, false);
      expect(scheduler.lastStopReason, 'untrustedSection');
      await scheduler.close();

      final normal = YouTubeBeatScheduler(
        map: rhythm,
        videoId: videoId,
        output: output,
        nowUs: () => now,
      );
      await normal.update(
        sample: sample(revision: 3, epoch: 2, atUs: now, positionMs: 1100),
        media: media(),
      );
      await normal.update(
        sample: sample(
          revision: 4,
          epoch: 2,
          atUs: now,
          positionMs: 1100,
          uncertaintyMs: 30,
        ),
        media: media(),
      );
      expect(output.active, false);
      expect(normal.lastStopReason, 'unsupportedTimeline');
      await normal.update(
        sample: sample(revision: 5, epoch: 2, atUs: now, positionMs: 1100),
        media: media(),
      );
      expect(output.active, true);
      now += 1100000;
      await normal.tick();
      expect(output.active, false);
      expect(normal.lastStopReason, 'staleTimeline');
      await normal.close();
    },
  );

  test(
    'lease renewal reuses grid/revision instead of a duplicate beat',
    () async {
      var now = 10000000;
      final output = FakeBeatOutput();
      final scheduler = YouTubeBeatScheduler(
        map: rhythm,
        videoId: videoId,
        output: output,
        nowUs: () => now,
      );
      await scheduler.update(
        sample: sample(revision: 1, epoch: 1, atUs: now, positionMs: 1100),
        media: media(),
      );
      await scheduler.update(
        sample: sample(revision: 2, epoch: 1, atUs: now, positionMs: 1100),
        media: media(),
      );
      final first = output.plans.single;
      now += 100000;
      await scheduler.tick();
      expect(output.plans.length, 1);
      now += 160000;
      await scheduler.update(
        sample: sample(revision: 3, epoch: 1, atUs: now, positionMs: 1360),
        media: media(),
      );
      expect(output.plans.length, 2);
      final renewal = output.plans.last;
      expect(renewal.revision, first.revision);
      expect(renewal.gridStartUs, first.gridStartUs);
      expect(renewal.nextBeatIndex, first.nextBeatIndex);
      expect(renewal.nextBeatUs, first.nextBeatUs);
      expect(renewal.validUntilUs, greaterThan(renewal.nextBeatUs + 25000));
      await scheduler.close();
    },
  );

  test('40 BPM eventually arms a feasible beat with 200 ms polling', () async {
    var now = 10000000;
    final output = FakeBeatOutput();
    final scheduler = YouTubeBeatScheduler(
      map: const RhythmMap(8, [
        RhythmSection(
          start: 0,
          end: 8,
          firstBeat: 0,
          bpm: 40,
          beatsPerBar: 4,
          confidence: 0.9,
        ),
      ]),
      videoId: videoId,
      output: output,
      nowUs: () => now,
    );
    for (var step = 0; step <= 25; step++) {
      await scheduler.update(
        sample: sample(
          revision: step + 1,
          epoch: 1,
          atUs: now,
          positionMs: 100 + step * 200,
        ),
        media: media(),
      );
      now += 200000;
    }
    expect(output.plans, isNotEmpty);
    for (final plan in output.plans) {
      expect(plan.validUntilUs, greaterThan(plan.nextBeatUs + 25000));
    }
    await scheduler.close();
  });

  test(
    '120 BPM periodic observations arm successive beats without duplicates',
    () async {
      var now = 10000000;
      final output = FakeBeatOutput();
      final scheduler = YouTubeBeatScheduler(
        map: rhythm,
        videoId: videoId,
        output: output,
        nowUs: () => now,
      );
      for (var step = 0; step <= 15; step++) {
        await scheduler.update(
          sample: sample(
            revision: step + 1,
            epoch: 1,
            atUs: now,
            positionMs: 100 + step * 200,
          ),
          media: media(),
        );
        now += 200000;
      }
      expect(output.plans, isNotEmpty);
      final distinct = output.plans.map((p) => p.nextBeatIndex).toSet();
      expect(distinct, containsAll(<int>[1, 2, 3, 4, 5, 6]));
      for (final plan in output.plans) {
        expect(plan.validUntilUs, greaterThan(plan.nextBeatUs + 25000));
      }
      await scheduler.close();
    },
  );
}
