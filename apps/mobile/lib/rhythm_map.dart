import 'dart:math' as math;
import 'dart:typed_data';

/// Bounded rhythm estimation. Deliberately returns an editable estimate, not a
/// claim that amplitude accents uniquely determine musical metre.
class RhythmSection {
  const RhythmSection({
    required this.start,
    required this.end,
    required this.firstBeat,
    required this.bpm,
    required this.beatsPerBar,
    required this.confidence,
  });
  final double start, end, firstBeat, bpm, confidence;
  final int? beatsPerBar;
  RhythmSection corrected({double? bpm, int? beats, double? firstBeat}) =>
      RhythmSection(
        start: start,
        end: end,
        firstBeat: firstBeat ?? this.firstBeat,
        bpm: bpm ?? this.bpm,
        beatsPerBar: beats ?? beatsPerBar,
        confidence: confidence,
      );
}

class RhythmMap {
  const RhythmMap(this.duration, this.sections);
  final double duration;
  final List<RhythmSection> sections;
}

class PcmWave {
  PcmWave(this.bytes) {
    if (bytes.length < 44 || bytes.length > 64 * 1024 * 1024) {
      throw const FormatException('Escolha um WAV com até 64 MB.');
    }
    data = ByteData.sublistView(bytes);
    String tag(int offset) =>
        String.fromCharCodes(bytes.sublist(offset, offset + 4));
    if (tag(0) != 'RIFF' || tag(8) != 'WAVE') {
      throw const FormatException(
        'É necessário um ficheiro WAV PCM de 16 bits.',
      );
    }
    var formatSeen = false;
    for (var offset = 12; offset + 8 <= bytes.length;) {
      final size = data.getUint32(offset + 4, Endian.little);
      final begin = offset + 8, end = begin + size;
      if (end > bytes.length) throw const FormatException('WAV incompleto.');
      if (tag(offset) == 'fmt ' && size >= 16) {
        channels = data.getUint16(begin + 2, Endian.little);
        sampleRate = data.getUint32(begin + 4, Endian.little);
        if (data.getUint16(begin, Endian.little) != 1 ||
            data.getUint16(begin + 14, Endian.little) != 16 ||
            channels < 1 ||
            channels > 2 ||
            sampleRate < 8000 ||
            sampleRate > 96000 ||
            data.getUint16(begin + 12, Endian.little) != channels * 2) {
          throw const FormatException(
            'Use WAV PCM 16 bits, mono ou estéreo (8–96 kHz).',
          );
        }
        formatSeen = true;
      } else if (tag(offset) == 'data') {
        dataOffset = begin;
        dataSize = size;
      }
      offset = end + (size & 1);
    }
    if (!formatSeen || dataSize == 0 || dataSize % (channels * 2) != 0) {
      throw const FormatException('WAV sem áudio PCM válido.');
    }
    frames = dataSize ~/ (channels * 2);
    if (duration < 8 || duration > 600) {
      throw const FormatException(
        'Use uma gravação de 8 segundos a 10 minutos.',
      );
    }
  }
  final Uint8List bytes;
  late final ByteData data;
  int channels = 0, sampleRate = 0, dataOffset = 0, dataSize = 0, frames = 0;
  double get duration => frames / sampleRate;
}

RhythmMap analyzeRhythm(Uint8List bytes) {
  final wav = PcmWave(bytes);
  const hz = 100;
  final energy = List<double>.filled((wav.duration * hz).ceil(), 0);
  final counts = List<int>.filled(energy.length, 0);
  for (var frame = 0; frame < wav.frames; frame++) {
    final bin = frame * hz ~/ wav.sampleRate;
    for (var channel = 0; channel < wav.channels; channel++) {
      final value =
          wav.data.getInt16(
            wav.dataOffset + (frame * wav.channels + channel) * 2,
            Endian.little,
          ) /
          32768;
      energy[bin] += value * value;
    }
    counts[bin] += wav.channels;
  }
  final novelty = List<double>.filled(energy.length, 0);
  var previous = 0.0;
  for (var i = 0; i < energy.length; i++) {
    final value = math.sqrt(energy[i] / math.max(1, counts[i]));
    novelty[i] = math.max(0, value - previous);
    previous = value;
  }
  return analyzeRhythmNovelty(novelty, duration: wav.duration);
}

/// Estimates an editable map from a 100 Hz non-negative onset-novelty envelope.
/// A microphone producer can discard each PCM block after extracting features;
/// this function receives no audio and stores no PCM or video content.
RhythmMap analyzeRhythmNovelty(
  List<double> novelty, {
  required double duration,
}) {
  if (!duration.isFinite ||
      duration < 8 ||
      duration > 600 ||
      novelty.length != (duration * 100).ceil() ||
      novelty.any((value) => !value.isFinite || value < 0)) {
    throw const FormatException(
      'Use características rítmicas válidas a 100 Hz (8 segundos a 10 minutos).',
    );
  }
  final sections = <RhythmSection>[];
  // Every sample is scanned. Short windows allow tempo/metre changes; their
  // boundaries are estimates that must be reviewed, especially for rubato.
  for (var start = 0; start < novelty.length; start += 1600) {
    final end = math.min(start + 1600, novelty.length);
    if (end - start < 400 && sections.isNotEmpty) {
      // Too short to infer a new metre: do not extend clicks into this tail.
      break;
    }
    final section = _estimate(novelty, start, end);
    if (section == null) {
      continue; // Silence/ambiguity never produces fake beats.
    }
    if (sections.isNotEmpty) {
      final last = sections.last;
      if ((last.end - section.start).abs() < .02 &&
          (last.bpm - section.bpm).abs() < 2 &&
          last.beatsPerBar == section.beatsPerBar &&
          ((section.firstBeat - last.firstBeat) * last.bpm / 60 -
                      ((section.firstBeat - last.firstBeat) * last.bpm / 60)
                          .round())
                  .abs() <
              .12) {
        sections[sections.length - 1] = RhythmSection(
          start: last.start,
          end: section.end,
          firstBeat: last.firstBeat,
          bpm: (last.bpm + section.bpm) / 2,
          beatsPerBar: last.beatsPerBar,
          confidence: math.min(last.confidence, section.confidence),
        );
        continue;
      }
    }
    sections.add(section);
  }
  return RhythmMap(duration, sections);
}

RhythmSection? _estimate(List<double> envelope, int start, int end) {
  final peak = envelope.sublist(start, end).fold<double>(0, math.max);
  if (peak < .002) return null;
  final events = <({int at, double strength})>[];
  for (var i = start; i < end - 1; i++) {
    if (envelope[i] < peak * .12 ||
        (i > 0 && envelope[i] < envelope[i - 1]) ||
        envelope[i] <= envelope[i + 1]) {
      continue;
    }
    if (events.isNotEmpty && i - events.last.at < 16) {
      if (envelope[i] > events.last.strength) {
        events[events.length - 1] = (at: i, strength: envelope[i]);
      }
    } else {
      events.add((at: i, strength: envelope[i]));
    }
  }
  if (events.length < 5) return null;
  var bestBpm = 0.0, bestScore = 0.0;
  // Weighted onset coincidences plus a direct-interval term avoids preferring
  // half tempo just because every other beat is louder.
  for (var bpm = 40.0; bpm <= 240; bpm += .5) {
    final period = 6000 / bpm;
    var score = 0.0;
    for (var i = 1; i < events.length; i++) {
      final interval = events[i].at - events[i - 1].at;
      final ratio = interval / period;
      final distance = (ratio - ratio.round()).abs();
      if (ratio >= .75 && distance < .10) {
        score += (1 - distance / .10) * (ratio < 1.25 ? 1 : .4);
      }
    }
    score /= events.length - 1;
    if (score > bestScore) {
      bestScore = score;
      bestBpm = bpm;
    }
  }
  if (bestScore < .45) return null;
  final interval = 6000 / bestBpm;
  var anchor = events.first.at;
  var anchorScore = -1.0;
  for (final event in events.take(12)) {
    var score = 0.0;
    for (final other in events) {
      final phase = (other.at - event.at) / interval;
      if ((phase - phase.round()).abs() < .1) score += other.strength;
    }
    if (score > anchorScore) {
      anchorScore = score;
      anchor = event.at;
    }
  }
  final strengths = <double>[];
  for (var beat = anchor.toDouble(); beat < end; beat += interval) {
    var strength = 0.0;
    for (
      var i = math.max(start, beat.round() - 4);
      i <= math.min(end - 1, beat.round() + 4);
      i++
    ) {
      strength = math.max(strength, envelope[i]);
    }
    strengths.add(strength);
  }
  int? metre;
  // Require a repeatable accent at least 15% above the other beats.
  var metreScore = .15, downbeat = 0;
  for (final count in [2, 3, 4]) {
    if (strengths.length < count * 3) continue;
    for (var phase = 0; phase < count; phase++) {
      var strong = 0.0, weak = 0.0, ns = 0, nw = 0;
      for (var i = 0; i < strengths.length; i++) {
        if (i % count == phase) {
          strong += strengths[i];
          ns++;
        } else {
          weak += strengths[i];
          nw++;
        }
      }
      final contrast = (strong / ns - weak / nw) / peak;
      if (contrast > metreScore + .02) {
        metreScore = contrast;
        metre = count;
        downbeat = phase;
      }
    }
  }
  final first = (anchor + downbeat * interval) / 100;
  return RhythmSection(
    start: start / 100,
    end: end / 100,
    firstBeat: first,
    bpm: bestBpm,
    beatsPerBar: metre,
    confidence: bestScore.clamp(0, 1),
  );
}

/// Mix onto the original PCM timeline, so the preview has a single playback
/// clock. The selected recording is never overwritten.
Uint8List mixRhythmPreview((Uint8List, List<RhythmSection>) input) {
  final wav = PcmWave(input.$1);
  final output = Uint8List.fromList(input.$1);
  final data = ByteData.sublistView(output);
  // Reserve headroom even when the original peaks at full scale.
  for (
    var offset = wav.dataOffset;
    offset < wav.dataOffset + wav.dataSize;
    offset += 2
  ) {
    data.setInt16(
      offset,
      (data.getInt16(offset, Endian.little) * .65).round(),
      Endian.little,
    );
  }
  var previousEnd = 0.0;
  for (final section in input.$2) {
    if (!section.bpm.isFinite ||
        section.bpm < 40 ||
        section.bpm > 240 ||
        section.beatsPerBar == null ||
        section.beatsPerBar! < 1 ||
        section.beatsPerBar! > 12 ||
        !section.firstBeat.isFinite ||
        section.firstBeat < section.start ||
        section.firstBeat >= section.end ||
        section.start < previousEnd ||
        section.end > wav.duration + .02) {
      throw const FormatException(
        'Reveja o início, o BPM e o compasso de cada trecho.',
      );
    }
    previousEnd = section.end;
    for (var beat = 0; ; beat++) {
      final time = section.firstBeat + beat * 60 / section.bpm;
      if (time >= section.end) break;
      final onset = (time * wav.sampleRate).round();
      final length = (wav.sampleRate * .025).round();
      final accent = beat % section.beatsPerBar! == 0;
      for (var i = 0; i < length && onset + i < wav.frames; i++) {
        final phase = i / (length - 1);
        final click =
            math.sin(
              2 * math.pi * (accent ? 1800 : 1100) * i / wav.sampleRate,
            ) *
            math.sin(math.pi * phase) *
            math.exp(-5 * phase) *
            .3 *
            32767;
        for (var c = 0; c < wav.channels; c++) {
          final offset = wav.dataOffset + ((onset + i) * wav.channels + c) * 2;
          data.setInt16(
            offset,
            (data.getInt16(offset, Endian.little) + click).round().clamp(
              -32768,
              32767,
            ),
            Endian.little,
          );
        }
      }
    }
  }
  return output;
}
