import 'player_presets.dart';
import 'practice_session.dart';

/// A complete, versioned recovery unit. Playback intent is deliberately absent:
/// restoring this value must prepare a paused player, never start playback.
class SessionSnapshot {
  SessionSnapshot({
    required this.media,
    required DateTime savedAt,
    String? sessionId,
    this.screen = 'player',
    this.fullscreen = false,
    this.activePresetId,
    String? practiceSessionId,
    double? practiceCurrent,
    double? practiceTarget,
    this.practice,
  }) : savedAt = savedAt.toUtc(),
       sessionId = sessionId ?? media.id,
       practiceSessionId = practice?.id ?? practiceSessionId,
       practiceCurrent = practice == null
           ? practiceCurrent
           : practice.currentPercent / 100,
       practiceTarget = practice == null
           ? practiceTarget
           : practice.plan.targetPercent / 100;

  static const version = 2;
  static const screens = {'player', 'practice', 'chords', 'stage'};

  final PlayerPreset media;
  final DateTime savedAt;
  final String sessionId, screen;
  final bool fullscreen;
  final String? activePresetId, practiceSessionId;
  final double? practiceCurrent, practiceTarget;
  final PracticeProgress? practice;

  Map<String, Object?> toJson() => {
    'snapshotVersion': version,
    'sessionId': sessionId,
    'media': media.toJson(),
    'savedAt': savedAt.toIso8601String(),
    'screen': screen,
    'fullscreen': fullscreen,
    'activePresetId': activePresetId,
    'practiceSessionId': practiceSessionId,
    'practiceCurrent': practiceCurrent,
    'practiceTarget': practiceTarget,
    'practice': practice?.toJson(),
  };

  /// Malformed supported records return null. A future version is different
  /// from corruption: callers must preserve it and block older-version writes.
  static SessionSnapshot? parse(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final schema = value['snapshotVersion'];
    if (schema is int && schema > version) {
      throw UnsupportedSessionSnapshotVersion(schema);
    }
    if (schema is! int || schema < 1 || schema > version) return null;
    final media = PlayerPreset.parse(value['media']);
    final savedAt = value['savedAt'];
    final id = value['sessionId'];
    final screen = value['screen'];
    if (media == null ||
        id is! String ||
        id.trim().isEmpty ||
        savedAt is! String ||
        screen is! String ||
        !screens.contains(screen) ||
        value['fullscreen'] is! bool) {
      return null;
    }
    // Require an explicit UTC offset; interpreting a persisted local timestamp
    // in another timezone would silently change when the session was saved.
    if (!RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(savedAt)) return null;
    final time = DateTime.tryParse(savedAt);
    if (time == null || time.millisecondsSinceEpoch < 0) return null;
    for (final field in ['activePresetId', 'practiceSessionId']) {
      final id = value[field];
      if (id != null && (id is! String || id.trim().isEmpty)) return null;
    }
    for (final field in ['practiceCurrent', 'practiceTarget']) {
      final speed = value[field];
      if (speed != null &&
          (speed is! num || !speed.isFinite || speed < 0.5 || speed > 1.5)) {
        return null;
      }
    }
    // v1 only had partial display hints; they cannot reconstruct a plan. A bad
    // optional plan must not destroy an otherwise recoverable media session.
    var practice = schema >= 2
        ? PracticeProgress.parse(value['practice'])
        : null;
    final expectedSource = media.youtube
        ? 'youtube:${media.locator}'
        : 'local:${media.locator}';
    if (practice != null &&
        (practice.sourceKey != expectedSource ||
            practice.aMs != media.aMs ||
            practice.bMs != media.bMs)) {
      practice = null;
    }
    return SessionSnapshot(
      media: media,
      savedAt: time,
      sessionId: id,
      screen: screen,
      fullscreen: value['fullscreen'] as bool,
      activePresetId: value['activePresetId'] as String?,
      practiceSessionId: value['practiceSessionId'] as String?,
      practiceCurrent: (value['practiceCurrent'] as num?)?.toDouble(),
      practiceTarget: (value['practiceTarget'] as num?)?.toDouble(),
      practice: practice,
    );
  }
}

class UnsupportedSessionSnapshotVersion implements Exception {
  const UnsupportedSessionSnapshotVersion(this.version);
  final int version;

  @override
  String toString() =>
      'Esta sessão foi guardada por uma versão mais recente do Transpono. '
      'Atualize o app para a recuperar; os dados foram preservados.';
}

class SessionRecoveryResult {
  const SessionRecoveryResult({
    this.snapshot,
    this.fromPrevious = false,
    this.warning,
    this.writeBlocked = false,
  });

  final SessionSnapshot? snapshot;
  final bool fromPrevious, writeBlocked;
  final String? warning;
}

abstract class SessionSnapshotRepository {
  bool get writeBlocked => false;
  Future<SessionRecoveryResult> read();
  Future<void> save(SessionSnapshot snapshot);

  /// Explicit user-requested forgetting, never an automatic error fallback.
  /// An older app must refuse even this operation for a future schema.
  Future<void> clear();
  Future<void> close();
}
