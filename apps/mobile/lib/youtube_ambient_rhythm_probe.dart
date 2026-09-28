import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';

import 'rhythm_map.dart';
import 'youtube_browser.dart';

/// QA-only feature/clock experiment. It never receives PCM or a media stream.
/// No UI or production workflow calls this class.
class YouTubeAmbientRhythmProbe {
  YouTubeAmbientRhythmProbe({
    required this.hostClockUs,
    required this.isVisible,
    Future<Object?> Function(String, Object?)? invoke,
  }) : _invoke = invoke ?? _channelInvoke;

  static const _channel = MethodChannel('transpose/qa_phone_rhythm_features');
  static Future<Object?> _channelInvoke(String method, Object? arguments) =>
      _channel.invokeMethod<Object?>(method, arguments);

  final int Function() hostClockUs;
  final bool Function() isVisible;
  final Future<Object?> Function(String, Object?) _invoke;
  int? _nativeMinusHostUs;
  double? clockUncertaintyMs;
  String? _videoId;
  int? _timelineEpoch;
  double? _duration;
  final _anchors = <YouTubeTimelineSample>[];
  bool _started = false;
  bool _terminalEof = false;
  String? failure;

  /// Seven same-process round trips; the smallest RTT limits scheduling noise.
  Future<void> calibrateClock() async {
    var bestRtt = 1 << 62;
    int? bestOffset;
    for (var attempt = 0; attempt < 7; attempt++) {
      final before = hostClockUs();
      final result = await _invoke('clock', null);
      final after = hostClockUs();
      final rtt = after - before;
      if (result is! num ||
          !result.isFinite ||
          result != result.truncateToDouble() ||
          rtt < 0) {
        throw const FormatException('Relógio do microfone indisponível.');
      }
      if (rtt < bestRtt) {
        bestRtt = rtt;
        bestOffset = result.toInt() - (before + rtt ~/ 2);
      }
    }
    if (bestOffset == null || bestRtt > 100000) {
      throw const FormatException('Calibração de relógios imprecisa.');
    }
    _nativeMinusHostUs = bestOffset;
    clockUncertaintyMs = bestRtt / 2000;
  }

  Future<void> start(
    YouTubeMediaState media,
    YouTubeTimelineSample sample,
  ) async {
    if (_started ||
        _nativeMinusHostUs == null ||
        !isVisible() ||
        !media.hasVideo ||
        !media.playing ||
        !media.playbackReady ||
        media.isAd ||
        media.videoId != sample.videoId ||
        sample.positionMs > 250 ||
        (sample.speed - 1).abs() > .001 ||
        (media.speed - 1).abs() > .001 ||
        media.duration < 8 ||
        media.duration > 600 ||
        sample.uncertaintyMs > 125 ||
        (hostClockUs() - sample.hostMidpointUs).abs() > 500000) {
      throw const FormatException(
        'Inicie uma reprodução válida desde o início.',
      );
    }
    _videoId = sample.videoId;
    _timelineEpoch = sample.epoch;
    _duration = media.duration;
    _anchors.add(sample);
    try {
      await _invoke('start', {'durationMs': (media.duration * 1000).ceil()});
      _started = true;
    } on Object {
      // A failed native start must not strand an anchor or prevent retry.
      try {
        await _invoke('cancel', null);
      } on Object {
        /* Keep start error. */
      }
      _videoId = null;
      _timelineEpoch = null;
      _duration = null;
      _anchors.clear();
      _terminalEof = false;
      rethrow;
    }
  }

  /// Call after each WebView refresh. One invalid playback transition aborts.
  void observe(YouTubeMediaState media, YouTubeTimelineSample? sample) {
    if (!_started || failure != null) return;
    if (_terminalEof) return;
    // HTMLMediaElement often reports paused/not-ready at natural EOF. The last
    // stable anchor must already cover the final quarter-second; an early
    // pause, seek, ad, or changed video cannot be mistaken for completion.
    if (isVisible() &&
        media.hasVideo &&
        !media.playing &&
        !media.isAd &&
        media.videoId == _videoId &&
        (media.duration - _duration!).abs() <= .05 &&
        media.position >= _duration! - .25 &&
        media.position <= _duration! + .25 &&
        _anchors.last.positionMs >= (_duration! - .25) * 1000 &&
        (sample == null ||
            (sample.videoId == _videoId && sample.epoch == _timelineEpoch))) {
      _terminalEof = true;
      return;
    }
    if (!isVisible() ||
        sample == null ||
        !media.hasVideo ||
        !media.playing ||
        !media.playbackReady ||
        media.isAd ||
        media.videoId != _videoId ||
        sample.videoId != _videoId ||
        sample.epoch != _timelineEpoch ||
        (media.duration - _duration!).abs() > .05 ||
        sample.hostMidpointUs <= _anchors.last.hostMidpointUs ||
        sample.hostMidpointUs - _anchors.last.hostMidpointUs > 1000000 ||
        sample.positionMs + 50 < _anchors.last.positionMs ||
        sample.uncertaintyMs > 125) {
      failure = 'A reprodução mudou ou perdeu continuidade.';
      unawaited(
        _invoke('cancel', null).then<void>((_) {}).catchError((Object _) {}),
      );
      return;
    }
    _anchors.add(sample);
  }

  Future<RhythmMap> finish(YouTubeMediaState media) async {
    if (!_started ||
        failure != null ||
        !_terminalEof ||
        !isVisible() ||
        _duration == null ||
        media.playing ||
        media.videoId != _videoId ||
        media.isAd ||
        media.position < _duration! - .25 ||
        _anchors.last.positionMs < (_duration! - .25) * 1000) {
      if (_started) await _invoke('cancel', null);
      throw FormatException(failure ?? 'O vídeo não foi ouvido até ao fim.');
    }
    try {
      return await _finishDraft();
    } finally {
      await _invoke('cancel', null);
    }
  }

  Future<RhythmMap> _finishDraft() async {
    await _invoke('finish', null);
    Map? status;
    for (var attempt = 0; attempt < 40; attempt++) {
      final response = await _invoke('status', null);
      if (response is! Map) throw const FormatException('Estado QA inválido.');
      status = response;
      if (status['phase'] == 'done' ||
          status['phase'] == 'error' ||
          status['phase'] == 'cancelled') {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (status?['phase'] != 'done' ||
        status?['quality'] != 'availableForReview' ||
        status?['routeChanged'] != false ||
        status?['captureOriginMonotonicUs'] is! num ||
        (status?['captureTimestampCount'] as num? ?? 0) < 2 ||
        (status?['captureClockSpreadUs'] as num? ?? double.infinity) > 5000 ||
        status?['aecEnabled'] == true ||
        status?['agcEnabled'] == true ||
        status?['noiseSuppressorEnabled'] == true) {
      throw const FormatException('Qualidade do microfone inconclusiva.');
    }
    final expectedCount = status?['featureCount'];
    if (expectedCount is! int || expectedCount < 0 || expectedCount > 60000) {
      throw const FormatException('Contagem de características inválida.');
    }
    final features = <({int nativeUs, double novelty})>[];
    var offset = 0;
    int? total;
    while (total == null || offset < total) {
      final response = await _invoke('readFeatures', {
        'offset': offset,
        'limit': 500,
      });
      if (response is! Map ||
          response['windowMs'] != 10 ||
          response['offset'] != offset ||
          response['total'] is! int ||
          response['features'] is! List) {
        throw const FormatException('Página de características QA inválida.');
      }
      total ??= response['total'] as int;
      if (total < 0 || total > 60000 || response['total'] != total) {
        throw const FormatException(
          'Comprimento de características QA inválido.',
        );
      }
      final page = response['features'] as List;
      if (page.length > 500 || offset + page.length > total) {
        throw const FormatException(
          'Página de características fora dos limites.',
        );
      }
      if (page.isEmpty && offset < total) {
        throw const FormatException('Página de características em falta.');
      }
      for (final row in page) {
        if (row is! Map ||
            row['monotonicUs'] is! num ||
            (row['monotonicUs'] as num) <= 0 ||
            (row['monotonicUs'] as num) !=
                (row['monotonicUs'] as num).truncateToDouble() ||
            row['novelty'] is! num ||
            !(row['novelty'] as num).isFinite ||
            (row['novelty'] as num) < 0) {
          throw const FormatException('Característica rítmica inválida.');
        }
        final nativeUs = (row['monotonicUs'] as num).toInt();
        if (features.isNotEmpty &&
            (nativeUs <= features.last.nativeUs ||
                nativeUs - features.last.nativeUs > 1000000)) {
          throw const FormatException('Lacuna no microfone.');
        }
        features.add((
          nativeUs: nativeUs,
          novelty: (row['novelty'] as num).toDouble(),
        ));
      }
      offset += page.length;
    }
    if (features.length != expectedCount) {
      throw const FormatException('Características incompletas.');
    }
    if (features.isEmpty) {
      throw const FormatException('Sem características rítmicas.');
    }
    final bins = List<double>.filled((_duration! * 100).ceil(), 0);
    final covered = List<bool>.filled(bins.length, false);
    var anchor = 0;
    for (final feature in features) {
      final hostUs = feature.nativeUs - _nativeMinusHostUs!;
      while (anchor + 1 < _anchors.length &&
          _anchors[anchor + 1].hostMidpointUs < hostUs) {
        anchor++;
      }
      final left = _anchors[anchor];
      final right = _anchors[math.min(anchor + 1, _anchors.length - 1)];
      if (hostUs < left.hostMidpointUs &&
          left.hostMidpointUs - hostUs > 250000) {
        continue;
      }
      double mediaMs;
      if (identical(left, right)) {
        if ((hostUs - left.hostMidpointUs).abs() > 250000) continue;
        mediaMs =
            left.positionMs +
            (hostUs - left.hostMidpointUs) / 1000 * left.speed;
      } else {
        mediaMs =
            left.positionMs +
            (right.positionMs - left.positionMs) *
                (hostUs - left.hostMidpointUs) /
                (right.hostMidpointUs - left.hostMidpointUs);
      }
      final bin = (mediaMs / 10).round();
      if (bin < 0 || bin >= bins.length) continue;
      bins[bin] = math.max(bins[bin], feature.novelty);
      covered[bin] = true;
    }
    final coverage = covered.where((value) => value).length / bins.length;
    if (coverage < .95 ||
        !covered.take(25).any((value) => value) ||
        !covered.skip(math.max(0, bins.length - 25)).any((value) => value)) {
      throw const FormatException('Cobertura acústica incompleta.');
    }
    return analyzeRhythmNovelty(bins, duration: _duration!);
  }

  Future<void> cancel() async {
    failure = 'Operação cancelada.';
    await _invoke('cancel', null);
  }
}
