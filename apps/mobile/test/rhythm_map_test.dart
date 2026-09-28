import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:transpose_mobile/rhythm_map.dart';
import 'package:transpose_mobile/study_tools.dart';

void main() {
  test('100 Hz novelty shares the estimator across a full changing song', () {
    final novelty = List<double>.filled(60000, 0);
    void beats(double start, double end, double bpm, int metre) {
      for (var beat = 0; ; beat++) {
        final time = start + beat * 60 / bpm;
        if (time >= end) break;
        novelty[(time * 100).round()] = beat % metre == 0 ? 1 : .25;
      }
    }

    beats(0, 304, 120, 4);
    beats(304, 600, 90, 3);
    final map = analyzeRhythmNovelty(novelty, duration: 600);
    expect(map.duration, 600);
    expect(map.sections.first.bpm, closeTo(120, 1));
    expect(map.sections.first.beatsPerBar, 4);
    expect(map.sections.first.confidence, greaterThan(.85));
    expect(map.sections.last.bpm, closeTo(90, 1));
    expect(map.sections.last.beatsPerBar, 3);
    expect(map.sections.last.confidence, greaterThan(.8));
    expect(map.sections.any((section) => section.start >= 304), isTrue);
  });

  test('100 Hz novelty leaves silence and ambiguous metre unclaimed', () {
    expect(
      analyzeRhythmNovelty(List<double>.filled(800, 0), duration: 8).sections,
      isEmpty,
    );
    final equalAccents = List<double>.filled(1600, 0);
    for (var beat = 0; beat < 32; beat++) {
      equalAccents[beat * 50] = .5;
    }
    final estimate = analyzeRhythmNovelty(equalAccents, duration: 16);
    expect(estimate.sections.single.bpm, closeTo(120, 1));
    expect(estimate.sections.single.beatsPerBar, isNull);
    expect(
      () => analyzeRhythmNovelty([double.nan], duration: 8),
      throwsFormatException,
    );
  });

  test('full synthetic ternary/quaternary tracks yield tempo and accents', () {
    for (final beats in [3, 4]) {
      final bytes = buildMetronomeWav(
        bpm: 120,
        beatsPerBar: beats,
        bars: 16,
        sampleRate: 16000,
      );
      final map = analyzeRhythm(bytes);
      expect(map.sections, isNotEmpty);
      expect(map.sections.first.bpm, closeTo(120, 1));
      expect(map.sections.first.beatsPerBar, beats);
      expect(map.sections.first.confidence, greaterThan(.85));
    }
  });
  test('silence has no invented tempo or metre', () {
    final bytes = buildMetronomeWav(bpm: 120, beatsPerBar: 4, sampleRate: 8000);
    bytes.fillRange(44, bytes.length, 0);
    expect(analyzeRhythm(bytes).sections, isEmpty);
  });
  test('tempo changes across the complete recording are retained', () {
    final first = buildMetronomeWav(
      bpm: 120,
      beatsPerBar: 4,
      bars: 8,
      sampleRate: 8000,
    );
    final second = buildMetronomeWav(
      bpm: 90,
      beatsPerBar: 3,
      bars: 8,
      sampleRate: 8000,
    );
    final joined = Uint8List(first.length + second.length - 44);
    joined.setAll(0, first);
    joined.setAll(first.length, second.sublist(44));
    final header = ByteData.sublistView(joined);
    header.setUint32(4, joined.length - 8, Endian.little);
    header.setUint32(40, joined.length - 44, Endian.little);
    final map = analyzeRhythm(joined);
    expect(map.sections.first.bpm, closeTo(120, 1));
    expect(map.sections.last.bpm, closeTo(90, 1));
    expect(map.sections.last.beatsPerBar, 3);
  });
  test('preview is sample aligned and leaves original bytes untouched', () {
    final bytes = buildMetronomeWav(bpm: 120, beatsPerBar: 4, sampleRate: 8000);
    final original = Uint8List.fromList(bytes);
    final map = analyzeRhythm(bytes);
    final mixed = mixRhythmPreview((bytes, map.sections));
    expect(bytes, original);
    expect(mixed.length, bytes.length);
    expect(mixed, isNot(bytes));
    final unknown = map.sections.first.corrected(firstBeat: -1);
    expect(() => mixRhythmPreview((bytes, [unknown])), throwsFormatException);
  });
  test('truncated and unsupported WAVs fail before processing', () {
    expect(() => analyzeRhythm(Uint8List(44)), throwsFormatException);
    final bytes = buildMetronomeWav(bpm: 120, beatsPerBar: 4, sampleRate: 8000);
    ByteData.sublistView(bytes).setUint16(34, 24, Endian.little);
    expect(() => analyzeRhythm(bytes), throwsFormatException);
  });
}
