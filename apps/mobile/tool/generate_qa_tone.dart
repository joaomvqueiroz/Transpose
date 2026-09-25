import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Deterministic, quiet fixture for checking the real output path on a phone.
void main() {
  const int sampleRate = 48000;
  const int seconds = 12;
  const int sampleCount = sampleRate * seconds;
  const int dataBytes = sampleCount * 2;
  final ByteData wav = ByteData(44 + dataBytes);

  void ascii(int offset, String value) {
    for (int i = 0; i < value.length; i++) {
      wav.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  wav.setUint32(4, 36 + dataBytes, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  wav.setUint32(16, 16, Endian.little);
  wav.setUint16(20, 1, Endian.little);
  wav.setUint16(22, 1, Endian.little);
  wav.setUint32(24, sampleRate, Endian.little);
  wav.setUint32(28, sampleRate * 2, Endian.little);
  wav.setUint16(32, 2, Endian.little);
  wav.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  wav.setUint32(40, dataBytes, Endian.little);

  for (int i = 0; i < sampleCount; i++) {
    final double fadeIn = math.min(1, i / 2400);
    final double fadeOut = math.min(1, (sampleCount - i) / 2400);
    final double envelope = math.min(fadeIn, fadeOut);
    final double tone = math.sin(2 * math.pi * 440 * i / sampleRate);
    wav.setInt16(44 + 2 * i, (tone * envelope * 3800).round(), Endian.little);
  }

  final File output = File('assets/qa_tone.wav');
  output.parent.createSync(recursive: true);
  output.writeAsBytesSync(wav.buffer.asUint8List(), flush: true);
  stdout.writeln('Generated ${output.path} (${output.lengthSync()} bytes)');
}
