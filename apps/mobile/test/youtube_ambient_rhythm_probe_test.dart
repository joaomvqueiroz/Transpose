import 'package:flutter_test/flutter_test.dart';
import 'package:transpose_mobile/youtube_ambient_rhythm_probe.dart';
import 'package:transpose_mobile/youtube_browser.dart';

const _id = 'abcdefghijk';

YouTubeMediaState _media(
  double position, {
  bool playing = true,
  bool ad = false,
  bool ready = true,
  String videoId = _id,
}) => YouTubeMediaState(
  videoId: videoId,
  hasVideo: true,
  playing: playing,
  isAd: ad,
  playbackReady: ready,
  position: position,
  duration: 64,
);

YouTubeTimelineSample _sample(
  double seconds, {
  int epoch = 1,
  String videoId = _id,
}) => YouTubeTimelineSample(
  videoId: videoId,
  revision: (seconds * 10).round() + 1,
  epoch: epoch,
  positionMs: seconds * 1000,
  speed: 1,
  browserTimeMs: seconds * 1000,
  hostMidpointUs: 1000000 + (seconds * 1000000).round(),
  uncertaintyMs: 1,
);

class _FakeFeatures {
  int host = 0;
  bool failStartOnce = false;
  static const offsetUs = 4000000;
  final rows = <Map<String, Object?>>[];
  String quality = 'availableForReview';

  _FakeFeatures() {
    for (var bin = 0; bin < 6400; bin++) {
      final time = bin / 100;
      var novelty = 0.0;
      if (time < 32) {
        final beat = (time * 2).round();
        if ((time * 2 - beat).abs() < .001) novelty = beat % 4 == 0 ? 1 : .25;
      } else {
        final beat = ((time - 32) * 1.5).round();
        if (((time - 32) * 1.5 - beat).abs() < .008) {
          novelty = beat % 3 == 0 ? 1 : .25;
        }
      }
      rows.add({
        'monotonicUs': 1000000 + bin * 10000 + offsetUs,
        'novelty': novelty,
      });
    }
  }

  int clock() => host += 1000;
  Future<Object?> invoke(String method, Object? arguments) async {
    switch (method) {
      case 'clock':
        return host + 500 + offsetUs;
      case 'start':
        if (failStartOnce) {
          failStartOnce = false;
          throw StateError('Microfone indisponível');
        }
        return null;
      case 'finish':
        return null;
      case 'cancel':
        return null;
      case 'status':
        return {
          'phase': 'done',
          'quality': quality,
          'featureCount': rows.length,
          'routeChanged': false,
          'captureOriginMonotonicUs': 1000000 + offsetUs,
          'captureTimestampCount': 2,
          'captureClockSpreadUs': 100,
          'aecEnabled': false,
          'agcEnabled': false,
          'noiseSuppressorEnabled': false,
        };
      case 'readFeatures':
        final args = arguments as Map;
        final offset = args['offset'] as int;
        final limit = args['limit'] as int;
        return {
          'offset': offset,
          'total': rows.length,
          'windowMs': 10,
          'features': rows.skip(offset).take(limit).toList(),
        };
    }
    throw StateError('Unknown method $method');
  }
}

Future<YouTubeAmbientRhythmProbe> _started(_FakeFeatures fake) async {
  final probe = YouTubeAmbientRhythmProbe(
    hostClockUs: fake.clock,
    isVisible: () => true,
    invoke: fake.invoke,
  );
  await probe.calibrateClock();
  fake.host = 1000000;
  await probe.start(_media(0), _sample(0));
  return probe;
}

void main() {
  test(
    'seven-round-trip calibration chooses narrow bounded clock offset',
    () async {
      final fake = _FakeFeatures();
      final probe = YouTubeAmbientRhythmProbe(
        hostClockUs: fake.clock,
        isVisible: () => true,
        invoke: fake.invoke,
      );
      await probe.calibrateClock();
      expect(probe.clockUncertaintyMs, .5);
    },
  );

  test(
    'complete 64 s feature-only video yields 120 to 90 editable draft',
    () async {
      final fake = _FakeFeatures();
      final probe = await _started(fake);
      for (var n = 1; n < 128; n++) {
        final seconds = n / 2;
        probe.observe(_media(seconds), _sample(seconds));
      }
      probe.observe(_media(63.9), _sample(63.9));
      probe.observe(_media(64, playing: false), null);
      final map = await probe.finish(_media(64, playing: false));
      expect(map.sections.first.bpm, closeTo(120, 1));
      expect(map.sections.last.bpm, closeTo(90, 1));
      expect(map.sections.first.beatsPerBar, 4);
      expect(map.sections.last.beatsPerBar, 3);
    },
  );

  test('seek, ad, early pause and a player gap invalidate the pass', () async {
    for (final kind in ['seek', 'ad', 'pause', 'gap']) {
      final fake = _FakeFeatures();
      final probe = await _started(fake);
      if (kind == 'seek') probe.observe(_media(2), _sample(2, epoch: 2));
      if (kind == 'ad') probe.observe(_media(.5, ad: true), null);
      if (kind == 'pause') probe.observe(_media(.5, playing: false), null);
      if (kind == 'gap') probe.observe(_media(2), _sample(2));
      expect(probe.failure, isNotNull, reason: kind);
      await expectLater(
        probe.finish(_media(64, playing: false)),
        throwsFormatException,
      );
    }
  });

  test('failed native start clears local state and permits retry', () async {
    final fake = _FakeFeatures()..failStartOnce = true;
    final probe = YouTubeAmbientRhythmProbe(
      hostClockUs: fake.clock,
      isVisible: () => true,
      invoke: fake.invoke,
    );
    await probe.calibrateClock();
    fake.host = 1000000;
    await expectLater(probe.start(_media(0), _sample(0)), throwsStateError);
    await probe.start(_media(0), _sample(0));
    for (var n = 1; n < 128; n++) {
      final seconds = n / 2;
      probe.observe(_media(seconds), _sample(seconds));
    }
    probe.observe(_media(63.9), _sample(63.9));
    probe.observe(_media(64, playing: false), null);
    final map = await probe.finish(_media(64, playing: false));
    expect(map.sections.last.bpm, closeTo(90, 1));
  });

  test('invalid microphone quality cannot create a rhythm map', () async {
    final fake = _FakeFeatures()..quality = 'audioEffectsActive';
    final probe = await _started(fake);
    for (var n = 1; n < 128; n++) {
      final seconds = n / 2;
      probe.observe(_media(seconds), _sample(seconds));
    }
    probe.observe(_media(63.9), _sample(63.9));
    probe.observe(_media(64, playing: false), null);
    await expectLater(
      probe.finish(_media(64, playing: false)),
      throwsFormatException,
    );
  });

  test(
    'missing microphone windows and loss of visibility fail closed',
    () async {
      final fake = _FakeFeatures();
      fake.rows.removeRange(1000, 1150); // 1.5 s acoustic gap.
      final probe = await _started(fake);
      for (var n = 1; n < 128; n++) {
        final seconds = n / 2;
        probe.observe(_media(seconds), _sample(seconds));
      }
      probe.observe(_media(63.9), _sample(63.9));
      probe.observe(_media(64, playing: false), null);
      await expectLater(
        probe.finish(_media(64, playing: false)),
        throwsFormatException,
      );

      final hidden = _FakeFeatures();
      var visible = true;
      final hiddenProbe = YouTubeAmbientRhythmProbe(
        hostClockUs: hidden.clock,
        isVisible: () => visible,
        invoke: hidden.invoke,
      );
      await hiddenProbe.calibrateClock();
      hidden.host = 1000000;
      await hiddenProbe.start(_media(0), _sample(0));
      visible = false;
      hiddenProbe.observe(_media(.5), _sample(.5));
      expect(hiddenProbe.failure, isNotNull);
    },
  );
}
