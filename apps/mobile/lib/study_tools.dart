import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'microphone_tuner.dart';

/// Opens the study tool attached to the current player's pitch.
Future<void> showStudyTool(
  BuildContext context, {
  required String tool,
  required double pitch,
}) async {
  final (String, Widget) content = switch (tool) {
    'metronome' => ('Metrônomo', const _MetronomeTool()),
    'tuner' => ('Afinador', const _InstrumentTunerTool()),
    'chords' => ('Acordes', _ChordTool(pitch: pitch.round())),
    _ => throw ArgumentError.value(tool, 'tool'),
  };
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (BuildContext sheetContext) => Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.viewInsetsOf(sheetContext).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    content.$1,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Fechar ferramenta',
                  onPressed: () => Navigator.pop(sheetContext),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            content.$2,
          ],
        ),
      ),
    ),
  );
}

/// Reuses the same working tool inside the player's horizontally browsable tabs.
Widget embeddedStudyTool(String tool) => switch (tool) {
  'metronome' => const _MetronomeTool(),
  'tuner' => const _InstrumentTunerTool(),
  _ => throw ArgumentError.value(tool, 'tool'),
};

/// PCM16 mono WAV. Beat positions use absolute sample indices, so rounding
/// does not accumulate between beats. The loop repeats a complete eight-bar
/// phrase; playback timing belongs to the audio player, not a Dart timer.
Uint8List buildMetronomeWav({
  required int bpm,
  required int beatsPerBar,
  int bars = 8,
  int sampleRate = 44100,
}) {
  if (bpm < 40 || bpm > 240) throw RangeError.range(bpm, 40, 240, 'bpm');
  if (beatsPerBar < 1 || beatsPerBar > 12) {
    throw RangeError.range(beatsPerBar, 1, 12, 'beatsPerBar');
  }
  if (bars < 1 || bars > 16) throw RangeError.range(bars, 1, 16, 'bars');
  _validateSampleRate(sampleRate);
  final double interval = sampleRate * 60 / bpm;
  final int beats = beatsPerBar * bars;
  final int frames = (interval * beats).round();
  final ByteData wav = _wavHeader(frames, sampleRate);
  final int clickFrames = (sampleRate * .025).round();
  for (int beat = 0; beat < beats; beat++) {
    final int onset = (beat * interval).round();
    final bool accent = beat % beatsPerBar == 0;
    final double frequency = accent ? 1800 : 1100;
    for (int i = 0; i < clickFrames && onset + i < frames; i++) {
      final double phase = i / (clickFrames - 1);
      final double envelope = math.sin(math.pi * phase) * math.exp(-5 * phase);
      final double sample = math.sin(2 * math.pi * frequency * i / sampleRate);
      wav.setInt16(
        44 + (onset + i) * 2,
        (sample * envelope * (accent ? .8 : .6) * 32767).round(),
        Endian.little,
      );
    }
  }
  return wav.buffer.asUint8List();
}

/// A repeatable reference note with gentle fade-in/out, not microphone input.
Uint8List buildReferenceToneWav({
  required double frequency,
  int sampleRate = 44100,
}) {
  if (!frequency.isFinite || frequency < 40 || frequency > 2000) {
    throw RangeError.range(frequency, 40, 2000, 'frequency');
  }
  _validateSampleRate(sampleRate);
  final int frames = sampleRate * 2;
  final int fade = (sampleRate * .025).round();
  final ByteData wav = _wavHeader(frames, sampleRate);
  for (int i = 0; i < frames; i++) {
    final double phase = 2 * math.pi * frequency * i / sampleRate;
    final double edge = math.min(i, frames - 1 - i) / fade;
    final double envelope = edge < 1 ? .5 - .5 * math.cos(math.pi * edge) : 1;
    final double sample = .30 * math.sin(phase) + .06 * math.sin(phase * 2);
    wav.setInt16(
      44 + i * 2,
      (sample * envelope * 32767).round(),
      Endian.little,
    );
  }
  return wav.buffer.asUint8List();
}

void _validateSampleRate(int sampleRate) {
  if (sampleRate < 8000 || sampleRate > 96000) {
    throw RangeError.range(sampleRate, 8000, 96000, 'sampleRate');
  }
}

ByteData _wavHeader(int frames, int sampleRate) {
  final ByteData wav = ByteData(44 + frames * 2);
  void label(int offset, String value) {
    for (int i = 0; i < value.length; i++) {
      wav.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  label(0, 'RIFF');
  wav.setUint32(4, 36 + frames * 2, Endian.little);
  label(8, 'WAVE');
  label(12, 'fmt ');
  wav.setUint32(16, 16, Endian.little);
  wav.setUint16(20, 1, Endian.little);
  wav.setUint16(22, 1, Endian.little);
  wav.setUint32(24, sampleRate, Endian.little);
  wav.setUint32(28, sampleRate * 2, Endian.little);
  wav.setUint16(32, 2, Endian.little);
  wav.setUint16(34, 16, Endian.little);
  label(36, 'data');
  wav.setUint32(40, frames * 2, Endian.little);
  return wav;
}

/// Transposes chord symbols while retaining whitespace, qualities and slash
/// basses. Unrecognized tokens stay intact, allowing section names and notes.
String transposeChordProgression(String progression, int semitones) {
  if (semitones % 12 == 0) return progression;
  final RegExp chord = RegExp(
    r'^([A-G])([#b♯♭]?)((?:(?:maj|min|dim|aug|sus|add|m|M|Δ|ø|°|\+|-)\d*|\d+|[#b♯♭]\d+|\([^\s()]*\))*)(?:/([A-G])([#b♯♭]?))?$',
  );
  return progression.replaceAllMapped(RegExp(r'[^\s|,;]+'), (Match token) {
    final String original = token.group(0)!;
    final RegExpMatch? match = chord.firstMatch(original);
    if (match == null) return original;
    final bool flats = original.contains('b') || original.contains('♭');
    final String root = _transposeNote(match[1]!, match[2]!, semitones, flats);
    final String bass = match[4] == null
        ? ''
        : '/${_transposeNote(match[4]!, match[5]!, semitones, flats)}';
    return '$root${match[3]}$bass';
  });
}

String _transposeNote(String note, String accidental, int shift, bool flats) {
  const Map<String, int> notes = <String, int>{
    'C': 0,
    'D': 2,
    'E': 4,
    'F': 5,
    'G': 7,
    'A': 9,
    'B': 11,
  };
  const List<String> sharpNames = <String>[
    'C',
    'C#',
    'D',
    'D#',
    'E',
    'F',
    'F#',
    'G',
    'G#',
    'A',
    'A#',
    'B',
  ];
  const List<String> flatNames = <String>[
    'C',
    'Db',
    'D',
    'Eb',
    'E',
    'F',
    'Gb',
    'G',
    'Ab',
    'A',
    'Bb',
    'B',
  ];
  final int adjustment = switch (accidental) {
    '#' || '♯' => 1,
    'b' || '♭' => -1,
    _ => 0,
  };
  final int index = (notes[note]! + adjustment + shift) % 12;
  return (flats ? flatNames : sharpNames)[index];
}

/// Serializes replacement/disposal so changing notes cannot create two sounds.
class _StudySound extends ChangeNotifier with WidgetsBindingObserver {
  _StudySound() {
    WidgetsBinding.instance.addObserver(this);
  }

  VideoPlayerController? _player;
  Directory? _directory;
  Future<void> _pending = Future<void>.value();
  bool _disposed = false;
  bool playing = false;
  bool busy = false;
  String? error;
  int _generation = 0;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> play(Uint8List bytes) {
    final int generation = ++_generation;
    busy = true;
    error = null;
    _notify();
    _pending = _pending.then((_) async {
      await _release();
      if (_disposed || generation != _generation) return;
      try {
        _directory = await Directory.systemTemp.createTemp('transpono-study-');
        final File file = File('${_directory!.path}/sound.wav');
        await file.writeAsBytes(bytes, flush: true);
        final VideoPlayerController player = VideoPlayerController.file(
          file,
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
        );
        _player = player;
        await player.initialize();
        if (_disposed || generation != _generation) {
          await _release();
          return;
        }
        await player.setLooping(true);
        if (_disposed || generation != _generation) {
          await _release();
          return;
        }
        await player.play();
        if (_disposed || generation != _generation) {
          await _release();
          return;
        }
        playing = player.value.isPlaying;
        if (!playing || player.value.hasError) {
          throw StateError('Reference playback did not start.');
        }
      } on Object {
        await _release();
        error = 'Não foi possível tocar. Tente novamente.';
      } finally {
        if (generation == _generation) busy = false;
        _notify();
      }
    });
    return _pending;
  }

  Future<void> stop() {
    ++_generation;
    playing = false;
    busy = false;
    _notify();
    _pending = _pending.then((_) async {
      await _release();
      _notify();
    });
    return _pending;
  }

  Future<void> _release() async {
    final VideoPlayerController? player = _player;
    final Directory? directory = _directory;
    _player = null;
    _directory = null;
    playing = false;
    if (player != null) {
      try {
        await player.dispose();
      } on Object {
        // Still clean up the app-owned temporary WAV after a platform failure.
      }
    }
    if (directory != null) {
      try {
        final File file = File('${directory.path}/sound.wav');
        if (await file.exists()) await file.delete();
        if (await directory.exists()) await directory.delete();
      } on FileSystemException {
        // Cache files are disposable and do not prevent subsequent playback.
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(stop());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposed = true;
    unawaited(stop());
    super.dispose();
  }
}

class _MetronomeTool extends StatefulWidget {
  const _MetronomeTool();
  @override
  State<_MetronomeTool> createState() => _MetronomeToolState();
}

class _MetronomeToolState extends State<_MetronomeTool> {
  final _StudySound _sound = _StudySound();
  int _bpm = 100;
  int _beats = 4;

  Future<void> _start() =>
      _sound.play(buildMetronomeWav(bpm: _bpm, beatsPerBar: _beats));

  void _setTempo(int value) {
    setState(() => _bpm = value.clamp(40, 240));
    if (_sound.playing) unawaited(_start());
  }

  @override
  void dispose() {
    _sound.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _sound,
    builder: (BuildContext context, _) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Text('A primeira batida de cada compasso é acentuada.'),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            IconButton(
              tooltip: 'Diminuir BPM',
              onPressed: !_sound.busy && _bpm > 40
                  ? () => _setTempo(_bpm - 1)
                  : null,
              icon: const Icon(Icons.remove),
            ),
            Text(
              '$_bpm BPM',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            IconButton(
              tooltip: 'Aumentar BPM',
              onPressed: !_sound.busy && _bpm < 240
                  ? () => _setTempo(_bpm + 1)
                  : null,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        Slider(
          min: 40,
          max: 240,
          divisions: 200,
          value: _bpm.toDouble(),
          label: '$_bpm BPM',
          semanticFormatterCallback: (double value) => '${value.round()} BPM',
          onChanged: _sound.busy
              ? null
              : (double v) => setState(() => _bpm = v.round()),
          onChangeEnd: (_) {
            if (_sound.playing) unawaited(_start());
          },
        ),
        DropdownButtonFormField<int>(
          initialValue: _beats,
          decoration: const InputDecoration(labelText: 'Batidas por compasso'),
          items: <DropdownMenuItem<int>>[
            for (int value = 1; value <= 12; value++)
              DropdownMenuItem(value: value, child: Text('$value')),
          ],
          onChanged: _sound.busy
              ? null
              : (int? value) {
                  if (value == null) return;
                  setState(() => _beats = value);
                  if (_sound.playing) unawaited(_start());
                },
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const Key('metronomePlayback'),
          onPressed: _sound.busy
              ? null
              : () => _sound.playing ? _sound.stop() : _start(),
          icon: Icon(_sound.playing ? Icons.stop : Icons.play_arrow),
          label: Text(
            _sound.busy
                ? 'A preparar…'
                : _sound.playing
                ? 'Parar metrônomo'
                : 'Iniciar metrônomo',
          ),
        ),
        if (_sound.error != null) Text(_sound.error!),
      ],
    ),
  );
}

class _InstrumentTunerTool extends StatelessWidget {
  const _InstrumentTunerTool();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: const [
      MicrophoneTunerTool(),
      ExpansionTile(
        title: Text('Notas de referência'),
        children: [_ReferenceTunerTool()],
      ),
    ],
  );
}

class _ReferenceTunerTool extends StatefulWidget {
  const _ReferenceTunerTool();
  @override
  State<_ReferenceTunerTool> createState() => _ReferenceTunerToolState();
}

class _ReferenceTunerToolState extends State<_ReferenceTunerTool> {
  final _StudySound _sound = _StudySound();
  String? _selected;
  static const List<(String, String, double)> _notes =
      <(String, String, double)>[
        ('E2', '6ª · Mi', 82.406889),
        ('A2', '5ª · Lá', 110),
        ('D3', '4ª · Ré', 146.832384),
        ('G3', '3ª · Sol', 195.997718),
        ('B3', '2ª · Si', 246.941651),
        ('E4', '1ª · Mi', 329.627557),
        ('A4', 'Lá 440', 440),
      ];

  @override
  void dispose() {
    _sound.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _sound,
    builder: (BuildContext context, _) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Text(
          'Afinação de ouvido · afinação padrão da guitarra. Escolha uma nota e compare com a sua corda.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final (String, String, double) note in _notes)
              ChoiceChip(
                label: Text('${note.$1} · ${note.$2}'),
                selected: _sound.playing && _selected == note.$1,
                onSelected: _sound.busy
                    ? null
                    : (_) {
                        if (_sound.playing && _selected == note.$1) {
                          unawaited(_sound.stop());
                        } else {
                          setState(() => _selected = note.$1);
                          unawaited(
                            _sound.play(
                              buildReferenceToneWav(frequency: note.$3),
                            ),
                          );
                        }
                      },
              ),
          ],
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _sound.playing || _sound.busy ? _sound.stop : null,
          icon: const Icon(Icons.stop),
          label: const Text('Parar nota'),
        ),
        const Text(
          'Este modo toca notas de referência; não mede o som do microfone.',
        ),
        if (_sound.error != null) Text(_sound.error!),
      ],
    ),
  );
}

class _ChordTool extends StatefulWidget {
  const _ChordTool({required this.pitch});
  final int pitch;
  @override
  State<_ChordTool> createState() => _ChordToolState();
}

class _ChordToolState extends State<_ChordTool> {
  String _input = '';

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      const Text('Cole ou escreva os acordes da música no tom original.'),
      const SizedBox(height: 12),
      TextField(
        key: const Key('chordProgressionInput'),
        minLines: 2,
        maxLines: 5,
        autocorrect: false,
        decoration: const InputDecoration(
          labelText: 'Cifras originais',
          hintText: 'Exemplo: C  Am7  F  G/B',
          border: OutlineInputBorder(),
        ),
        onChanged: (String value) => setState(() => _input = value),
      ),
      const SizedBox(height: 16),
      Text(
        'Tom do player: ${widget.pitch > 0 ? '+' : ''}${widget.pitch} semitons',
      ),
      const SizedBox(height: 8),
      SelectableText(
        _input.trim().isEmpty
            ? 'Os acordes transpostos aparecem aqui.'
            : transposeChordProgression(_input, widget.pitch),
        key: const Key('transposedChords'),
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 12),
      const Text(
        'Use espaços ou barras verticais entre acordes. Textos não reconhecidos são mantidos. Não há detecção automática de acordes neste modo.',
      ),
    ],
  );
}
