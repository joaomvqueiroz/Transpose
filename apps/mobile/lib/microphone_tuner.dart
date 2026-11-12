import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:record/record.dart';

import 'piano_reference_player.dart';
import 'pitch_detector.dart';
import 'studio_native_pages.dart';
import 'studio_appearance.dart';

/// Feedback follows the measured distance from the selected string, not a
/// repeating decorative animation.
Color tunerFeedbackColor(double? cents, {required bool inTune}) {
  if (cents == null) return const Color(0xFF77777D);
  if (inTune) return const Color(0xFF4ADE80);
  if (cents.abs() <= 30) return const Color(0xFFFB923C);
  return const Color(0xFFF87171);
}

class MicrophoneTunerTool extends StatefulWidget {
  const MicrophoneTunerTool({
    super.key,
    this.referencePlayer,
    this.appearance = const StudioAppearance(),
  });

  /// Optional injection for tests; production uses bundled piano recordings.
  final PianoReferencePlayer? referencePlayer;
  final StudioAppearance appearance;

  @override
  State<MicrophoneTunerTool> createState() => _MicrophoneTunerToolState();
}

class _MicrophoneTunerToolState extends State<MicrophoneTunerTool>
    with WidgetsBindingObserver {
  static const _sampleRate = 16000;
  static const _windowSize = 4096;
  final AudioRecorder _recorder = AudioRecorder();
  PianoReferencePlayer? _referencePlayer;
  final List<double> _samples = List.filled(_windowSize, 0);
  StreamSubscription<Uint8List>? _subscription;
  PitchReading? _reading;
  Timer? _silenceTimer;
  final List<double> _recentCents = [];
  double _needleCents = 0;
  bool _inTune = false;
  String? _error;
  bool _active = false;
  bool _starting = false;
  int _cursor = 0;
  int _seen = 0;
  int _sinceEstimate = 0;
  int? _trackedMidi;
  int? _candidateMidi;
  int _candidateCount = 0;
  String? _previewNote;
  Timer? _previewTimer;
  int _previewRequest = 0;
  int _captureRequest = 0;

  static const _strings = <(String, double)>[
    ('E2', 82.41),
    ('A2', 110.00),
    ('D3', 146.83),
    ('G3', 196.00),
    ('B3', 246.94),
    ('E4', 329.63),
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
    if (state != AppLifecycleState.resumed) {
      unawaited(_referencePlayer?.stop());
      _finishPreview();
      if (_active || _starting) unawaited(_stop());
    }
  }

  void _finishPreview() {
    ++_previewRequest;
    _previewTimer?.cancel();
    _previewTimer = null;
    if (mounted) setState(() => _previewNote = null);
    _cursor = _seen = _sinceEstimate = 0;
  }

  Future<void> _playReference(String note) async {
    final request = ++_previewRequest;
    _previewTimer?.cancel();
    setState(() {
      _previewNote = note;
      _reading = null;
      _needleCents = 0;
      _inTune = false;
      _trackedMidi = null;
      _recentCents.clear();
      _error = null;
    });
    _silenceTimer?.cancel();
    _silenceTimer = null;
    _cursor = _seen = _sinceEstimate = 0;
    try {
      final player = _referencePlayer ??=
          widget.referencePlayer ?? SampledPianoReferencePlayer();
      await player.play(note);
      if (!mounted || request != _previewRequest) return;
      _previewTimer = Timer(const Duration(milliseconds: 2800), _finishPreview);
    } on Object {
      if (!mounted || request != _previewRequest) return;
      _finishPreview();
      setState(() => _error = 'Não foi possível tocar a nota de piano.');
    }
  }

  Future<void> _start() async {
    if (_active || _starting) return;
    final request = ++_captureRequest;
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      if (!await _recorder.hasPermission()) {
        throw StateError('Autorize o microfone nas definições do dispositivo.');
      }
      if (!mounted || request != _captureRequest) return;
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
      if (!mounted || request != _captureRequest) {
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
    if (!_active || _previewNote != null || bytes.length < 2) return;
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
    if (next == null) {
      // A single weak frame must not snap the needle back to the centre.
      _silenceTimer ??= Timer(const Duration(milliseconds: 450), () {
        _silenceTimer = null;
        if (!mounted || !_active) return;
        setState(() {
          _reading = null;
          _needleCents = 0;
          _inTune = false;
          _recentCents.clear();
          _trackedMidi = _candidateMidi = null;
          _candidateCount = 0;
        });
      });
      return;
    }
    _silenceTimer?.cancel();
    _silenceTimer = null;
    if (_trackedMidi != null && next.midiNote != _trackedMidi) {
      if (_candidateMidi == next.midiNote) {
        _candidateCount++;
      } else {
        _candidateMidi = next.midiNote;
        _candidateCount = 1;
      }
      if (_candidateCount < 2) return;
      _recentCents.clear();
      _inTune = false;
    }
    _trackedMidi = next.midiNote;
    _candidateMidi = null;
    _candidateCount = 0;
    final cents = next.cents;
    _recentCents.add(cents.clamp(-50.0, 50.0));
    if (_recentCents.length > 3) _recentCents.removeAt(0);
    final ordered = [..._recentCents]..sort();
    final stableCents = ordered[ordered.length ~/ 2];
    if (mounted) {
      setState(() {
        _reading = next;
        _needleCents = stableCents;
        // Hysteresis prevents the green state flickering at the boundary.
        _inTune = _inTune ? stableCents.abs() < 14 : stableCents.abs() <= 10;
      });
    }
  }

  Future<void> _stop() async {
    ++_captureRequest;
    _silenceTimer?.cancel();
    _silenceTimer = null;
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
        _needleCents = 0;
        _inTune = false;
        _recentCents.clear();
        _trackedMidi = _candidateMidi = null;
        _candidateCount = 0;
        _cursor = _seen = _sinceEstimate = 0;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ++_captureRequest;
    ++_previewRequest;
    _silenceTimer?.cancel();
    _previewTimer?.cancel();
    unawaited(_referencePlayer?.dispose());
    unawaited(_subscription?.cancel());
    unawaited(_recorder.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final light = widget.appearance.mode == StudioAppearanceMode.light;
    const lightInk = Color(0xFF193244);
    const lightMuted = Color(0xFF526577);
    final reading = _reading;
    final targetCents = reading?.cents;
    final accurate = reading != null && _inTune;
    final feedbackColor = reading == null
        ? (light ? lightInk : Colors.white)
        : light
        ? accurate
              ? const Color(0xFF16743A)
              : _needleCents.abs() <= 30
              ? const Color(0xFF9B4E00)
              : const Color(0xFFB42332)
        : tunerFeedbackColor(_needleCents, inTune: accurate);
    final skin = studioSpotifySkin;
    final status = _previewNote != null
        ? 'Nota de referência · piano'
        : !_active
        ? skin
              ? 'Ative o microfone · toque numa corda para ouvir a nota'
              : 'Ative o microfone · botões tocam piano'
        : reading == null
        ? 'Toque uma corda de cada vez'
        : accurate
        ? 'Nota afinada'
        : targetCents! < 0
        ? 'Baixa · aperte a corda'
        : 'Alta · afrouxe a corda';
    return Container(
      key: const Key('chromaticTunerCard'),
      padding: EdgeInsets.all(skin ? 0 : 12),
      decoration: skin
          ? null
          : studioPanelDecoration(mode: widget.appearance.mode),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (skin)
            Row(
              children: [
                Expanded(child: skinLabel('Afinador cromático')),
                Text(
                  'Auto · 440 Hz',
                  style: TextStyle(fontSize: 13, color: skinSubdued),
                ),
              ],
            )
          else
            Row(
              children: [
                Icon(
                  Icons.tune,
                  size: 16,
                  color: light ? lightInk : Colors.white,
                ),
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
                Text(
                  'AUTO · 440 Hz',
                  style: TextStyle(
                    fontSize: 10,
                    color: light ? lightMuted : const Color(0xFFBEBEC4),
                  ),
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
                  child: TunerGauge(
                    cents: reading == null ? null : _needleCents,
                    inTune: accurate,
                  ),
                ),
                if (!skin)
                  Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 220),
                        style: TextStyle(
                          fontSize: 31,
                          fontWeight: FontWeight.w900,
                          color: feedbackColor,
                          height: 1,
                        ),
                        child: Text(
                          _previewNote ??
                              (reading == null
                                  ? '—'
                                  : _westernNote(reading.midiNote)),
                          key: const Key('tunerDetectedNote'),
                        ),
                      ),
                      Text(
                        _previewNote != null
                            ? 'PIANO'
                            : reading == null
                            ? 'ESCUTA AUTOMÁTICA'
                            : 'NOTA DETETADA',
                        style: TextStyle(
                          fontSize: 9,
                          letterSpacing: 1,
                          color: light ? lightMuted : const Color(0xFFA1A1AA),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          // The note under the dial, as on the source's own pages.
          if (skin)
            Text(
              _previewNote ??
                  (reading == null ? '—' : _westernNote(reading.midiNote)),
              key: const Key('tunerDetectedNote'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w700,
                color: reading == null ? Colors.white : feedbackColor,
              ),
            ),
          SizedBox(height: skin ? 2 : 8),
          if (skin)
            Text(
              status,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: reading == null ? skinSubdued : feedbackColor,
              ),
            )
          else
            Text(
              status,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: reading == null
                    ? (light ? lightMuted : const Color(0xFFBABAC0))
                    : feedbackColor,
              ),
            ),
          if (reading != null)
            Text(
              '${targetCents! >= 0 ? '+' : ''}${targetCents.round()} cents · ${reading.frequency.toStringAsFixed(1)} Hz',
              key: const Key('tunerCents'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: feedbackColor),
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
                      onPressed: () => _playReference(string.$1),
                      style: skin
                          ? OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              minimumSize: Size.zero,
                              foregroundColor:
                                  _previewNote == string.$1 && studioYouTubeSkin
                                  ? skinChipOnInk
                                  : Colors.white,
                              backgroundColor: _previewNote == string.$1
                                  ? studioYouTubeSkin
                                        ? skinChipOn
                                        : const Color(0x33FFFFFF)
                                  : skinChip,
                              side: BorderSide.none,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            )
                          : OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              minimumSize: Size.zero,
                              foregroundColor: light ? lightInk : Colors.white,
                              backgroundColor: light
                                  ? _previewNote == string.$1
                                        ? const Color(0xFFDCEBF3)
                                        : const Color(0xFFE8EEF4)
                                  : _previewNote == string.$1
                                  ? const Color(0xFF38383E)
                                  : const Color(0xFF232326),
                              side: BorderSide(
                                color: light
                                    ? _previewNote == string.$1
                                          ? lightInk
                                          : const Color(0xFFB7C4D2)
                                    : _previewNote == string.$1
                                    ? const Color(0xFFBEBEC4)
                                    : const Color(0xFF35353A),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(13),
                              ),
                            ),
                      child: Column(
                        children: [
                          Text(
                            string.$1,
                            style: TextStyle(
                              fontSize: skin ? 15 : 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            '${string.$2.toStringAsFixed(0)} Hz',
                            style: TextStyle(
                              fontSize: skin ? 11 : 7,
                              color: light
                                  ? lightMuted
                                  : const Color(0xFFA1A1AA),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: skin ? 14 : 8),
          if (skin)
            FilledButton.icon(
              key: const Key('tunerMicrophoneToggle'),
              onPressed: _starting
                  ? null
                  : _active
                  ? _stop
                  : _start,
              icon: Icon(
                _active ? Icons.mic_off_outlined : Icons.mic_none,
                size: 20,
              ),
              label: Text(
                _starting
                    ? 'A iniciar…'
                    : _active
                    ? 'Parar microfone'
                    : 'Ativar microfone',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: skinChipOn,
                foregroundColor: skinChipOnInk,
                minimumSize: Size.fromHeight(studioYouTubeSkin ? 44 : 48),
                shape: const StadiumBorder(),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else
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
                style: TextStyle(color: light ? Colors.black : null),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: light ? lightInk : Colors.white,
                backgroundColor: light ? const Color(0xFFE8EEF4) : null,
                side: BorderSide(
                  color: light
                      ? const Color(0xFFB7C4D2)
                      : const Color(0xFF66666D),
                ),
              ),
            ),
          if (_error != null)
            Text(_error!, key: const Key('tunerMicrophoneError')),
        ],
      ),
    );
  }
}

/// Animates measured cents; no demo loop is played without microphone input.
class TunerGauge extends StatelessWidget {
  const TunerGauge({super.key, required this.cents, required this.inTune});

  final double? cents;
  final bool inTune;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    key: const Key('tunerNeedleAnimation'),
    tween: Tween<double>(begin: cents ?? 0, end: cents ?? 0),
    duration: const Duration(milliseconds: 240),
    curve: Curves.easeOutCubic,
    builder: (context, animatedCents, _) => TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: inTune ? 1 : 0, end: inTune ? 1 : 0),
      duration: const Duration(milliseconds: 260),
      builder: (context, green, _) => CustomPaint(
        key: const Key('tunerGaugePaint'),
        painter: _TunerGaugePainter(
          cents: cents == null ? null : animatedCents,
          green: green,
        ),
      ),
    ),
  );
}

/// The needle begins on the gauge's horizontal baseline, above the panel edge.
Offset tunerGaugePivot(Size size) => Offset(size.width / 2, size.height * .82);

class _TunerGaugePainter extends CustomPainter {
  const _TunerGaugePainter({required this.cents, required this.green});
  final double? cents;
  final double green;

  @override
  void paint(Canvas canvas, Size size) {
    final center = tunerGaugePivot(size);
    final radius = math.min(size.width * .39, size.height * .75);
    final arc = Rect.fromCircle(center: center, radius: radius);
    final needleColor = cents == null
        ? (studioSpotifySkin
              ? Colors.white
              : tunerFeedbackColor(null, inTune: false))
        : Color.lerp(
            tunerFeedbackColor(cents, inTune: false),
            tunerFeedbackColor(cents, inTune: true),
            green,
          )!;
    if (cents != null) {
      final cloud = Rect.fromCenter(
        center: Offset(center.dx, center.dy - radius * .16),
        width: radius * 1.8,
        height: radius * .88,
      );
      canvas.drawOval(
        cloud,
        Paint()
          ..shader = RadialGradient(
            colors: [
              needleColor.withValues(alpha: .34 + .18 * green),
              needleColor.withValues(alpha: .12 + .08 * green),
              Colors.transparent,
            ],
            stops: const [0, .42, 1],
          ).createShader(cloud),
      );
    }
    if (green > 0) {
      canvas.drawArc(
        arc,
        math.pi,
        math.pi,
        true,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(0, .65),
            radius: .9,
            colors: [
              const Color(0xBB22C55E).withValues(alpha: .50 * green),
              const Color(0x5522C55E).withValues(alpha: .20 * green),
              Colors.transparent,
            ],
          ).createShader(arc),
      );
    }
    canvas.drawArc(
      arc,
      math.pi,
      math.pi,
      false,
      Paint()
        ..color = studioSpotifySkin
            ? const Color(0x33FFFFFF)
            : const Color(0xFF3A3A40)
        ..style = PaintingStyle.stroke
        ..strokeWidth = studioSpotifySkin ? 4 : 1.5,
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
          ..color = tick == 6
              ? studioSpotifySkin
                    ? (studioYouTubeSkin
                          ? const Color(0xFFFF0033)
                          : skinGreen)
                    : Color.lerp(Colors.white, const Color(0xFF4ADE80), green)!
              : studioSpotifySkin
              ? const Color(0x66FFFFFF)
              : const Color(0xFF77777D)
          ..strokeWidth = tick == 6 ? 2 : 1,
      );
    }
    final offset = (cents ?? 0).clamp(-50.0, 50.0);
    final angle = math.pi * 1.5 + offset / 50 * math.pi / 2;
    final tip = Offset(
      center.dx + radius * .77 * math.cos(angle),
      center.dy + radius * .77 * math.sin(angle),
    );
    if (cents != null) {
      canvas.drawCircle(
        tip,
        7,
        Paint()..color = needleColor.withValues(alpha: .22),
      );
    }
    canvas.drawLine(
      center,
      tip,
      Paint()
        ..color = needleColor
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(tip, 3, Paint()..color = needleColor);
    canvas.drawCircle(center, 3, Paint()..color = needleColor);
  }

  @override
  bool shouldRepaint(_TunerGaugePainter oldDelegate) =>
      oldDelegate.cents != cents || oldDelegate.green != green;
}
