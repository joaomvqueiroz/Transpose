enum PracticeStatus {
  notStarted,
  preparing,
  running,
  paused,
  completed,
  aborted,
}

class PracticePlan {
  const PracticePlan({
    this.startPercent = 60,
    this.targetPercent = 100,
    this.incrementPercent = 5,
    this.repetitionsPerStep = 3,
  });
  final int startPercent, targetPercent, incrementPercent, repetitionsPerStep;
  bool get valid =>
      startPercent >= 50 &&
      targetPercent <= 150 &&
      targetPercent >= startPercent &&
      incrementPercent >= 1 &&
      incrementPercent <= 20 &&
      repetitionsPerStep >= 1 &&
      repetitionsPerStep <= 20;
  int get steps =>
      ((targetPercent - startPercent) / incrementPercent).ceil() + 1;
  Map<String, Object> toJson() => {
    'start': startPercent,
    'target': targetPercent,
    'increment': incrementPercent,
    'repetitions': repetitionsPerStep,
  };
  static PracticePlan? parse(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    if ([
      'start',
      'target',
      'increment',
      'repetitions',
    ].any((key) => raw[key] is! int)) {
      return null;
    }
    final value = PracticePlan(
      startPercent: raw['start'] as int,
      targetPercent: raw['target'] as int,
      incrementPercent: raw['increment'] as int,
      repetitionsPerStep: raw['repetitions'] as int,
    );
    return value.valid ? value : null;
  }
}

/// Recovery data for one plan, independent from native counter epochs.
/// Active/preparing work is always serialized as paused, never autoplay intent.
class PracticeProgress {
  const PracticeProgress({
    required this.id,
    required this.sourceKey,
    required this.aMs,
    required this.bMs,
    required this.plan,
    required this.currentPercent,
    required this.stepRepetitions,
    required this.totalRepetitions,
    required this.status,
  });
  final String id, sourceKey;
  final int aMs, bMs, currentPercent, stepRepetitions, totalRepetitions;
  final PracticePlan plan;
  final PracticeStatus status;
  Map<String, Object> toJson() => {
    'version': 1,
    'id': id,
    'sourceKey': sourceKey,
    'aMs': aMs,
    'bMs': bMs,
    'plan': plan.toJson(),
    'current': currentPercent,
    'stepRepetitions': stepRepetitions,
    'totalRepetitions': totalRepetitions,
    'status': status == PracticeStatus.completed
        ? 'completed'
        : status == PracticeStatus.aborted
        ? 'aborted'
        : 'paused',
  };
  static PracticeProgress? parse(Object? raw) {
    if (raw is! Map<String, dynamic> || raw['version'] != 1) return null;
    final plan = PracticePlan.parse(raw['plan']);
    if (plan == null ||
        ['id', 'sourceKey'].any(
          (key) => raw[key] is! String || (raw[key] as String).trim().isEmpty,
        ) ||
        [
          'aMs',
          'bMs',
          'current',
          'stepRepetitions',
          'totalRepetitions',
        ].any((key) => raw[key] is! int)) {
      return null;
    }
    final a = raw['aMs'] as int,
        b = raw['bMs'] as int,
        current = raw['current'] as int,
        repeats = raw['stepRepetitions'] as int,
        total = raw['totalRepetitions'] as int;
    if (a < 0 ||
        b - a < 250 ||
        current < plan.startPercent ||
        current > plan.targetPercent ||
        (current != plan.targetPercent &&
            (current - plan.startPercent) % plan.incrementPercent != 0) ||
        repeats < 0 ||
        repeats > plan.repetitionsPerStep ||
        total < repeats ||
        total > 1000000000 ||
        !['paused', 'completed', 'aborted'].contains(raw['status'])) {
      return null;
    }
    if (raw['status'] == 'completed' &&
        (current != plan.targetPercent || repeats != plan.repetitionsPerStep)) {
      return null;
    }
    return PracticeProgress(
      id: raw['id'] as String,
      sourceKey: raw['sourceKey'] as String,
      aMs: a,
      bMs: b,
      plan: plan,
      currentPercent: current,
      stepRepetitions: repeats,
      totalRepetitions: total,
      status: PracticeStatus.values.byName(raw['status'] as String),
    );
  }
}
