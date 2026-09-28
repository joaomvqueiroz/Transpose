import 'dart:async';
import 'dart:math' as math;

import 'rhythm_map.dart';
import 'youtube_browser.dart';

/// A short-lived beat grid, not an acoustic synchronization measurement.
/// [gridStartUs] is the predicted first beat in the same Stopwatch epoch as
/// [YouTubeTimelineSample.hostMidpointUs]. The output must treat renewals with
/// the same revision/grid as idempotent, and enforce [validUntilUs].
class YouTubeBeatSchedule {
  const YouTubeBeatSchedule({
    required this.revision,
    required this.epoch,
    required this.sectionIndex,
    required this.gridStartUs,
    required this.nextBeatUs,
    required this.nextBeatIndex,
    required this.bpm,
    required this.beatsPerBar,
    required this.validUntilUs,
  });

  final int revision, epoch, sectionIndex, gridStartUs;
  final int nextBeatUs, nextBeatIndex, beatsPerBar, validUntilUs;
  final double bpm;
}

abstract class YouTubeBeatOutput {
  Future<void> schedule(YouTubeBeatSchedule plan);
  Future<void> stop();
}

/// Pure coordinator. It owns no AudioTrack or WebView and has no UI binding.
/// [nowUs] MUST use the very same Stopwatch instance/epoch that bracketed the
/// timeline sample; Android System.nanoTime is a different epoch.
class YouTubeBeatScheduler {
  YouTubeBeatScheduler({
    required this.map,
    required this.videoId,
    required this.output,
    required this.nowUs,
    this.minimumConfidence = 0.55,
    this.maximumUncertaintyMs = 20,
  }) {
    if (videoId.isEmpty ||
        !map.duration.isFinite ||
        map.duration <= 0 ||
        !minimumConfidence.isFinite ||
        minimumConfidence < 0 ||
        minimumConfidence > 1 ||
        !maximumUncertaintyMs.isFinite ||
        maximumUncertaintyMs <= 0) {
      throw ArgumentError('Invalid YouTube beat scheduler configuration.');
    }
  }

  final RhythmMap map;
  final String videoId;
  final YouTubeBeatOutput output;
  final int Function() nowUs;
  final double minimumConfidence, maximumUncertaintyMs;

  Future<void> _tail = Future<void>.value();
  YouTubeTimelineSample? _sample;
  YouTubeMediaState? _media;
  bool _seeking = false, _closed = false;
  int? _epoch, _sectionIndex, _gridStartUs;
  int _revision = 0, _lastSampleRevision = -1, _validUntilUs = 0;
  YouTubeBeatSchedule? _active;
  YouTubeBeatSchedule? get activeSchedule => _active;
  String? lastStopReason;

  static const maximumSampleAgeUs = 1000000;
  // The initial lead must fit inside the one-second timeline freshness lease.
  // A native output may reject this if it cannot prepare within 200 ms.
  static const minimumLeadUs = 200000;
  static const leaseUs = 1250000;
  static const clickTailUs = 25000;
  static const renewWithinUs = 250000;

  Future<void> update({
    required YouTubeTimelineSample? sample,
    required YouTubeMediaState media,
    bool seeking = false,
  }) => _enqueue(() async {
    if (_closed) return;
    _sample = sample;
    _media = media;
    _seeking = seeking;
    await _reconcile();
  });

  /// Called by an owner timer to expire sound even when WebView polling stops.
  Future<void> tick() => _enqueue(() async {
    if (!_closed) await _reconcile();
  });

  Future<void> stop() => _enqueue(() async {
    _sample = null;
    _media = null;
    await _stop('explicit');
  });

  Future<void> close() => _enqueue(() async {
    if (_closed) return;
    _closed = true;
    _sample = null;
    _media = null;
    await _stop('closed');
  });

  Future<void> _enqueue(Future<void> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.onError((Object _, StackTrace _) {});
    return result;
  }

  Future<void> _reconcile() async {
    final sample = _sample;
    final media = _media;
    final now = nowUs();
    if (sample == null || media == null) return _stop('noTimeline');
    if (!media.hasVideo ||
        !media.playing ||
        !media.playbackReady ||
        media.isAd ||
        _seeking) {
      return _stop('playerUnavailable');
    }
    if (sample.videoId != videoId || media.videoId != videoId) {
      return _stop('sourceChanged');
    }
    if (!sample.positionMs.isFinite ||
        !sample.uncertaintyMs.isFinite ||
        sample.uncertaintyMs < 0 ||
        !sample.speed.isFinite ||
        !media.speed.isFinite ||
        sample.positionMs < 0 ||
        sample.uncertaintyMs > maximumUncertaintyMs ||
        (sample.speed - 1).abs() > 0.000001 ||
        (media.speed - 1).abs() > 0.000001) {
      return _stop('unsupportedTimeline');
    }
    final age = now - sample.hostMidpointUs;
    if (age < 0 || age > maximumSampleAgeUs) return _stop('staleTimeline');
    if (sample.epoch != _epoch) {
      await _stop('epochChanged');
      _epoch = sample.epoch;
      _lastSampleRevision = sample.revision;
      // Never arm immediately from the first observation after seek/source/rate.
      return;
    }
    if (sample.revision < _lastSampleRevision) return _stop('oldRevision');
    _lastSampleRevision = sample.revision;
    if (_active != null && now >= _validUntilUs) {
      await _stop('leaseExpired');
    }

    final positionMs = sample.positionMs + age / 1000;
    final index = map.sections.indexWhere(
      (section) =>
          positionMs >= section.start * 1000 && positionMs < section.end * 1000,
    );
    if (index < 0) return _stop('sectionGap');
    final section = map.sections[index];
    if (!section.start.isFinite ||
        !section.end.isFinite ||
        !section.firstBeat.isFinite ||
        !section.bpm.isFinite ||
        !section.confidence.isFinite ||
        section.start < 0 ||
        section.end > map.duration + 0.001 ||
        section.end <= section.start ||
        section.bpm < 40 ||
        section.bpm > 240 ||
        section.confidence < minimumConfidence ||
        section.beatsPerBar == null ||
        section.beatsPerBar! < 1 ||
        section.beatsPerBar! > 12) {
      return _stop('untrustedSection');
    }

    final predictedStartUs =
        sample.hostMidpointUs +
        ((section.firstBeat * 1000 - sample.positionMs) * 1000).round();
    if (_sectionIndex != index || _gridStartUs == null) {
      await _stop('sectionChanged');
      _sectionIndex = index;
      _gridStartUs = predictedStartUs;
      _revision++;
    } else if ((predictedStartUs - _gridStartUs!).abs() > 40000) {
      // A timestamp jump within one epoch needs a fresh anchor, not a click.
      await _stop('timelineJump');
      return;
    }

    final intervalUs = 60000000 / section.bpm;
    // A new grid needs preparation lead. A live grid is already primed; its
    // next beat must not be skipped merely because it is now <lead away.
    final leadUs = _active == null ? minimumLeadUs : 0;
    final nextIndex = math.max(
      0,
      ((now + leadUs - _gridStartUs!) / intervalUs).ceil(),
    );
    final nextVideoMs =
        section.firstBeat * 1000 + nextIndex * 60000 / section.bpm;
    if (nextVideoMs >= section.end * 1000 ||
        nextVideoMs >= map.duration * 1000) {
      return _stop('sectionEnd');
    }
    final expiry = math.min(
      now + leaseUs,
      sample.hostMidpointUs + maximumSampleAgeUs,
    );
    if (expiry - now < 100000) return _stop('shortLease');
    final nextBeatUs = _gridStartUs! + (nextIndex * intervalUs).round();
    if (nextBeatUs + clickTailUs >= expiry) {
      // At a slow tempo no click may fit a short lease yet. A future fresh
      // timeline sample can arm the same beat when it comes into range.
      return _stop('beatOutsideLease');
    }
    if (_active != null && expiry - _validUntilUs < renewWithinUs) return;
    final schedule = YouTubeBeatSchedule(
      revision: _revision,
      epoch: sample.epoch,
      sectionIndex: index,
      gridStartUs: _gridStartUs!,
      nextBeatUs: nextBeatUs,
      nextBeatIndex: nextIndex,
      bpm: section.bpm,
      beatsPerBar: section.beatsPerBar!,
      validUntilUs: expiry,
    );
    try {
      await output.schedule(schedule);
    } on Object {
      // A partially applied output plan must not survive a failed renewal.
      await output.stop();
      _active = null;
      _sectionIndex = null;
      _gridStartUs = null;
      _validUntilUs = 0;
      rethrow;
    }
    _validUntilUs = expiry;
    _active = schedule;
    lastStopReason = null;
  }

  Future<void> _stop(String reason) async {
    lastStopReason = reason;
    if (_active != null) await output.stop();
    _active = null;
    _sectionIndex = null;
    _gridStartUs = null;
    _validUntilUs = 0;
  }
}
