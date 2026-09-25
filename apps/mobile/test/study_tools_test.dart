import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transpose_mobile/study_tools.dart';

void main() {
  test('metronome WAV has PCM header and sample-accurate beat positions', () {
    const int bpm = 137;
    const int sampleRate = 44100;
    const int beatCount = 4 * 8;
    final Uint8List bytes = buildMetronomeWav(bpm: bpm, beatsPerBar: 4);
    final ByteData wav = ByteData.sublistView(bytes);
    expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
    expect(wav.getUint16(20, Endian.little), 1);
    expect(wav.getUint16(22, Endian.little), 1);
    expect(wav.getUint32(24, Endian.little), sampleRate);
    expect(wav.getUint32(28, Endian.little), sampleRate * 2);
    expect(wav.getUint16(34, Endian.little), 16);
    final int frames = (sampleRate * 60 * beatCount / bpm).round();
    expect(bytes.length, 44 + 2 * frames);
    expect(wav.getUint32(40, Endian.little), 2 * frames);

    for (int beat = 0; beat < beatCount; beat++) {
      final int onset = (beat * sampleRate * 60 / bpm).round();
      expect(wav.getInt16(44 + onset * 2, Endian.little), 0);
      final int end = onset + (sampleRate * .025).round();
      int energy = 0;
      for (int frame = onset; frame < end; frame++) {
        energy += wav.getInt16(44 + frame * 2, Endian.little).abs();
      }
      expect(energy, greaterThan(100000));
      final int next = beat == beatCount - 1
          ? frames
          : ((beat + 1) * sampleRate * 60 / bpm).round();
      for (int frame = end; frame < next; frame++) {
        expect(wav.getInt16(44 + frame * 2, Endian.little), 0);
      }
    }
  });

  test(
    'reference tone contains requested frequency and smooth silent edges',
    () {
      const int rate = 16000;
      final ByteData wav = ByteData.sublistView(
        buildReferenceToneWav(frequency: 440, sampleRate: rate),
      );
      expect(wav.lengthInBytes, 44 + rate * 2 * 2);
      expect(wav.getInt16(44, Endian.little), 0);
      expect(wav.getInt16(wav.lengthInBytes - 2, Endian.little), 0);
      double correlation(double frequency) {
        double cosine = 0, sine = 0;
        for (int i = rate ~/ 2; i < rate * 3 ~/ 2; i++) {
          final int sample = wav.getInt16(44 + i * 2, Endian.little);
          final double angle = 2 * math.pi * frequency * i / rate;
          cosine += sample * math.cos(angle);
          sine += sample * math.sin(angle);
          expect(sample.abs(), lessThan(16000));
        }
        return math.sqrt(cosine * cosine + sine * sine);
      }

      expect(correlation(440), greaterThan(correlation(430) * 100));
      expect(correlation(440), greaterThan(correlation(880) * 4));
    },
  );

  test('audio generators reject invalid timing and non-finite frequencies', () {
    expect(() => buildMetronomeWav(bpm: 0, beatsPerBar: 4), throwsRangeError);
    expect(() => buildMetronomeWav(bpm: 100, beatsPerBar: 0), throwsRangeError);
    expect(
      () => buildMetronomeWav(bpm: 100, beatsPerBar: 4, bars: 0),
      throwsRangeError,
    );
    expect(
      () => buildReferenceToneWav(frequency: double.nan),
      throwsRangeError,
    );
    expect(
      () => buildReferenceToneWav(frequency: 440, sampleRate: 0),
      throwsRangeError,
    );
  });

  test(
    'chords retain qualities, altered extensions, slash bass and spacing',
    () {
      expect(
        transposeChordProgression('C  Am7 | F  G/B\nDm7 G7 Cmaj7', 2),
        'D  Bm7 | G  A/C#\nEm7 A7 Dmaj7',
      );
      expect(
        transposeChordProgression('Bbmaj7/D Ebm7 Ab7(b9) F#m7b5', -2),
        'Abmaj7/C Dbm7 Gb7(b9) Em7b5',
      );
      expect(
        transposeChordProgression('Bø7 Cdim7 Fsus4 Eaug Dadd9', 1),
        'Cø7 C#dim7 F#sus4 Faug D#add9',
      );
      expect(transposeChordProgression('C♯m/G♯ D♭maj7', -1), 'Cm/G Cmaj7');
      expect(
        transposeChordProgression('Intro: | Bridge Chorus N.C. C', 1),
        'Intro: | Bridge Chorus N.C. C#',
      );
      expect(transposeChordProgression('Bb/D  C#m7', 12), 'Bb/D  C#m7');
    },
  );

  testWidgets('chord tool transposes only user-entered progression', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  showStudyTool(context, tool: 'chords', pitch: -2),
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    expect(find.text('Os acordes transpostos aparecem aqui.'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('chordProgressionInput')),
      'Dm7 G/B',
    );
    await tester.pump();
    expect(find.text('Cm7 F/A'), findsOneWidget);
    await tester.tap(find.byTooltip('Fechar ferramenta'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chordProgressionInput')), findsNothing);
  });
}
