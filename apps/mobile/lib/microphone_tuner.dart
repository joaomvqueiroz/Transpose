import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:record/record.dart';

import 'pitch_detector.dart';

class MicrophoneTunerTool extends StatefulWidget {
  const MicrophoneTunerTool({super.key});

  @override
  State<MicrophoneTunerTool> createState() => _MicrophoneTunerToolState();
}

class _MicrophoneTunerToolState extends State<MicrophoneTunerTool>
    with WidgetsBindingObserver {
  static const _sampleRate = 16000;
  static const _windowSize = 4096;
  final AudioRecorder _recorder = AudioRecorder();
  final List<double> _samples = List.filled(_windowSize, 0);
  StreamSubscription<Uint8List>? _subscription;
  PitchReading? _reading;
  String? _error;
  bool _active = false;
  bool _starting = false;
  int _cursor = 0;
  int _seen = 0;
  int _sinceEstimate = 0;
  int _targetMidi = 40;

  static const _strings = <(String, int, double)>[
    ('E2', 40, 82.41),
    ('A2', 45, 110.00),
    ('D3', 50, 146.83),
    ('G3', 55, 196.00),
    ('B3', 59, 246.94),
    ('E4', 64, 329.63),
  ];

  String _westernNote(int midi) {
    const names = [
      'C',
      'C♯',
      'D',
      'D♯',
      'E',
      'F',
      'F♯',
      'G',
      'G♯',
      'A',
      'A♯',
      'B',
    ];
    return '${names[midi % 12]}${midi ~/ 12 - 1}';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _active) {
      unawaited(_stop());
    }
  }

  Future<void> _start() async {
    if (_active || _starting) return;
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      if (!await _recorder.hasPermission()) {
        throw StateError('Autorize o microfone nas definições do dispositivo.');
      }
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: _sampleRate,
          numChannels: 1,
          autoGain: false,
          echoCancel: false,
          noiseSuppress: false,
        ),
      );
      if (!mounted) {
        await _recorder.stop();
        return;
      }
      _subscription = stream.listen(
        _consume,
        onError: (Object error) {
          if (mounted) {
            setState(() => _error = 'Falha ao ouvir o microfone: $error');
          }
          unawaited(_stop());
        },
      );
      setState(() => _active = true);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = 'Não foi possível iniciar o afinador: $error');
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  void _consume(Uint8List bytes) {
    if (!_active || bytes.length < 2) return;
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      _samples[_cursor] = data.getInt16(i, Endian.little) / 32768;
      _cursor = (_cursor + 1) % _windowSize;
      _seen++;
      _sinceEstimate++;
    }
    if (_seen < _windowSize || _sinceEstimate < 2048) return;
    _sinceEstimate = 0;
    final window = [..._samples.skip(_cursor), ..._samples.take(_cursor)];
    final next = detectInstrumentPitch(window, sampleRate: _sampleRate);
    if (mounted) setState(() => _reading = next);
  }

  Future<void> _stop() async {
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    try {
      await _recorder.stop();
    } on Object {
      // The stream may already have ended after an OS interruption.
    }
    if (mounted) {
      setState(() {
        _active = false;
        _reading = null;
        _cursor = _seen = _sinceEstimate = 0;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_subscription?.cancel());
    unawaited(_recorder.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reading = _reading;
    final target = _strings.firstWhere((string) => string.$2 == _targetMidi);
    final targetCents = reading == null
        ? null
        : 1200 * math.log(reading.frequency / target.$3) / math.ln2;
    final accurate = targetCents != null && targetCents.abs() < 5;
    final status = !_active
        ? 'Ative o microfone e toque uma corda'
        : reading == null
        ? 'Toque uma corda de cada vez'
        : accurate
        ? 'Corda afinada'
        : targetCents!.abs() > 50
        ? 'Nota distante de ${target.$1}'
        : targetCents < 0
        ? 'Baixa · aperte a corda'
        : 'Alta · afrouxe a corda';
    return Container(
      key: const Key('chromaticTunerCard'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF18181B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF35353A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.tune, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'AFINADOR CROMÁTICO',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const Text(
                'A4 · 440 Hz',
                style: TextStyle(fontSize: 10, color: Color(0xFFBEBEC4)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 132,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _TunerGaugePainter(cents: targetCents),
                  ),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      reading == null
                          ? target.$1
                          : _westernNote(reading.midiNote),
                      key: const Key('tunerDetectedNote'),
                      style: const TextStyle(
                        fontSize: 31,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        height: 1,
                      ),
                    ),
                    Text(
                      reading == null ? 'ALVO' : 'NOTA DETETADA',
                      style: const TextStyle(
                        fontSize: 9,
                        letterSpacing: 1,
                        color: Color(0xFFA1A1AA),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            status,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: accurate ? Colors.white : const Color(0xFFBABAC0),
            ),
          ),
          if (reading != null)
            Text(
              '${targetCents! >= 0 ? '+' : ''}${targetCents.round()} cents · ${reading.frequency.toStringAsFixed(1)} Hz',
              key: const Key('tunerCents'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10, color: Color(0xFFA1A1AA)),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final string in _strings)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: OutlinedButton(
                      key: Key('tunerString${string.$1}'),
                      onPressed: () => setState(() => _targetMidi = string.$2),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        minimumSize: Size.zero,
                        foregroundColor: Colors.white,
                        backgroundColor: _targetMidi == string.$2
                            ? const Color(0xFF38383E)
                            : const Color(0xFF232326),
                        side: BorderSide(
                          color: _targetMidi == string.$2
                              ? const Color(0xFFBEBEC4)
                              : const Color(0xFF35353A),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            string.$1,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            '${string.$3.toStringAsFixed(0)} Hz',
                            style: const TextStyle(
                              fontSize: 7,
                              color: Color(0xFFA1A1AA),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('tunerMicrophoneToggle'),
            onPressed: _starting
                ? null
                : _active
                ? _stop
                : _start,
            icon: Icon(
              _active ? Icons.mic_off_outlined : Icons.mic_outlined,
              size: 17,
            ),
            label: Text(
              _starting
                  ? 'A iniciar…'
                  : _active
                  ? 'Parar microfone'
                  : 'Ativar microfone',
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Color(0xFF66666D)),
            ),
          ),
          if (_error != null)
            Text(_error!, key: const Key('tunerMicrophoneError')),
        ],
      ),
    );
  }
}

class _TunerGaugePainter extends CustomPainter {
  const _TunerGaugePainter({required this.cents});
  final double? cents;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * .95);
    final radius = math.min(size.width * .39, size.height * .88);
    final arc = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(
      arc,
      math.pi,
      math.pi,
      false,
      Paint()
        ..color = const Color(0xFF3A3A40)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    for (var tick = 0; tick <= 12; tick++) {
      final angle = math.pi + tick * math.pi / 12;
      final outer = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      final innerRadius = radius - (tick == 6 ? 12 : 7);
      final inner = Offset(
        center.dx + innerRadius * math.cos(angle),
        center.dy + innerRadius * math.sin(angle),
      );
      canvas.drawLine(
        inner,
        outer,
        Paint()
          ..color = tick == 6 ? Colors.white : const Color(0xFF77777D)
          ..strokeWidth = tick == 6 ? 2 : 1,
      );
    }
    final offset = (cents ?? 0).clamp(-50.0, 50.0);
    final angle = math.pi * 1.5 + offset / 50 * math.pi / 2;
    final tip = Offset(
      center.dx + radius * .77 * math.cos(angle),
      center.dy + radius * .77 * math.sin(angle),
    );
    canvas.drawLine(
      center,
      tip,
      Paint()
        ..color = cents == null ? const Color(0xFF77777D) : Colors.white
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(center, 3, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_TunerGaugePainter oldDelegate) =>
      oldDelegate.cents != cents;
}
