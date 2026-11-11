import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';

import 'rhythm_map.dart';
import 'studio_appearance.dart';

/// Personal/development build only. This listens to the room, not to a video
/// stream; a resulting tempo must never be presented as verified YouTube sync.
class AmbientRhythmTrial extends StatefulWidget {
  const AmbientRhythmTrial({
    super.key,
    this.requestPermission,
    this.appearanceMode = StudioAppearanceMode.dark,
  });

  /// Test seam; the personal app uses Android's microphone permission dialog.
  final Future<bool> Function()? requestPermission;
  final StudioAppearanceMode appearanceMode;

  @override
  State<AmbientRhythmTrial> createState() => _AmbientRhythmTrialState();
}

class _AmbientRhythmTrialState extends State<AmbientRhythmTrial>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('transpose/qa_phone_rhythm_features');
  AudioRecorder? _recorder;
  bool _busy = false;
  int _request = 0;
  RhythmMap? _map;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _cancel();
  }

  void _cancel() {
    final request = ++_request;
    unawaited(() async {
      try {
        await _channel.invokeMethod<void>('cancel');
      } on Object {
        // The isolated native channel may already have stopped.
      }
      if (mounted && request == _request) setState(() => _busy = false);
    }());
  }

  Future<void> _measure() async {
    if (_busy) return;
    final request = ++_request;
    setState(() {
      _busy = true;
      _map = null;
      _message = null;
    });
    try {
      final permission =
          widget.requestPermission ??
          () => (_recorder ??= AudioRecorder()).hasPermission();
      if (!await permission()) {
        throw const FormatException('Autoriza o microfone para medir o ritmo.');
      }
      if (!mounted || request != _request) return;
      await _channel.invokeMethod<void>('start', {'durationMs': 12000});
      await Future<void>.delayed(const Duration(seconds: 10));
      if (!mounted || request != _request) return;
      await _channel.invokeMethod<void>('finish');
      Map? status;
      for (var i = 0; i < 40; i++) {
        status = await _channel.invokeMapMethod<Object?, Object?>('status');
        if (status?['busy'] == false) break;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      if (!mounted || request != _request) return;
      if (status?['phase'] != 'done' ||
          status?['quality'] != 'availableForReview' ||
          status?['routeChanged'] != false) {
        throw const FormatException(
          'A captação não teve qualidade suficiente. Tenta num lugar mais silencioso.',
        );
      }
      final count = status?['featureCount'];
      if (count is! int || count < 800 || count > 1200) {
        throw const FormatException('A captação ficou incompleta.');
      }
      final novelty = <double>[];
      for (var offset = 0; offset < count; offset += 500) {
        final page = await _channel.invokeMapMethod<Object?, Object?>(
          'readFeatures',
          {'offset': offset, 'limit': 500},
        );
        if (page?['offset'] != offset ||
            page?['total'] != count ||
            page?['windowMs'] != 10 ||
            page?['features'] is! List) {
          throw const FormatException('Características acústicas incompletas.');
        }
        final rows = page!['features'] as List;
        if (rows.isEmpty || rows.length > 500) {
          throw const FormatException('Página acústica inválida.');
        }
        for (final row in rows) {
          final value = row is Map ? row['novelty'] : null;
          if (value is! num || !value.isFinite || value < 0) {
            throw const FormatException('Característica acústica inválida.');
          }
          novelty.add(value.toDouble());
        }
      }
      if (novelty.length != count || !mounted || request != _request) return;
      final map = analyzeRhythmNovelty(novelty, duration: count / 100);
      setState(() {
        _map = map;
        _message = map.sections.isEmpty
            ? 'Não encontrei um pulso suficientemente estável.'
            : 'Estimativa do som ambiente; ainda não sincronizada com o vídeo.';
      });
    } on Object catch (error) {
      if (mounted && request == _request) {
        setState(() {
          _message = error is FormatException
              ? error.message
              : 'Não foi possível medir o ritmo pelo microfone.';
        });
      }
    } finally {
      if (request == _request) {
        try {
          await _channel.invokeMethod<void>('cancel');
        } on Object {
          // The isolated native channel may already have stopped.
        }
      }
      if (mounted && request == _request) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancel();
    final recorder = _recorder;
    if (recorder != null) unawaited(recorder.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('personalAmbientRhythmTrial'),
    width: double.infinity,
    decoration: BoxDecoration(
      color: switch (widget.appearanceMode) {
        StudioAppearanceMode.light => const Color(0xFFF7F9FC),
        StudioAppearanceMode.glass => studioGlassToolFill(),
        StudioAppearanceMode.dark => const Color(0xFF202023),
      },
      border: Border.all(
        color: switch (widget.appearanceMode) {
          StudioAppearanceMode.light => const Color(0xFFB7C4D2),
          StudioAppearanceMode.glass => studioGlassToolBorder(),
          StudioAppearanceMode.dark => const Color(0xFF4A4A50),
        },
      ),
      borderRadius: BorderRadius.circular(24),
    ),
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Ritmo pelo microfone · experimental'),
        const SizedBox(height: 5),
        Text(
          'Ouve 10 segundos do ambiente. Usa o altifalante; auscultadores e ruído podem impedir a medição. Não guarda áudio.',
          style: TextStyle(
            fontSize: 11,
            color: widget.appearanceMode == StudioAppearanceMode.light
                ? const Color(0xFF526273)
                : const Color(0xFFB6B6BC),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('measureAmbientRhythm'),
          onPressed: _busy ? _cancel : _measure,
          icon: Icon(_busy ? Icons.stop : Icons.mic_outlined, size: 16),
          label: Text(_busy ? 'Parar medição' : 'Medir BPM do ambiente'),
        ),
        if (_message != null) ...[
          const SizedBox(height: 6),
          Text(_message!, style: const TextStyle(fontSize: 11)),
        ],
        if (_map != null)
          for (final section in _map!.sections)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                '${section.bpm.toStringAsFixed(1)} BPM · '
                '${section.beatsPerBar == null ? 'compasso incerto' : '${section.beatsPerBar} tempos'} '
                '· confiança ${(section.confidence * 100).round()}%',
                style: const TextStyle(fontSize: 12),
              ),
            ),
      ],
    ),
  );
}
