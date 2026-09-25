import 'package:flutter_test/flutter_test.dart';
import 'package:transpose_mobile/practice_session.dart';

void main() {
  group('PracticePlan', () {
    test('defaults and a final shortened increment are deterministic', () {
      const defaults = PracticePlan();
      expect(defaults.valid, isTrue);
      expect(defaults.startPercent, 60);
      expect(defaults.targetPercent, 100);
      expect(defaults.incrementPercent, 5);
      expect(defaults.repetitionsPerStep, 3);
      expect(defaults.steps, 9);
      expect(const PracticePlan(targetPercent: 67).steps, 3);
      expect(
        const PracticePlan(startPercent: 100, targetPercent: 100).steps,
        1,
      );
      expect(
        PracticePlan.parse(defaults.toJson())?.toJson(),
        defaults.toJson(),
      );
    });

    test('rejects invalid ranges, missing fields and non-integer settings', () {
      final valid = const PracticePlan().toJson();
      for (final invalid in <Object?>[
        null,
        <Object>[],
        <String, Object>{},
        {...valid, 'start': 49},
        {...valid, 'start': 101},
        {...valid, 'target': 151},
        {...valid, 'increment': 0},
        {...valid, 'increment': 21},
        {...valid, 'repetitions': 0},
        {...valid, 'repetitions': 21},
        {...valid, 'start': 60.0},
        {...valid, 'target': '100'},
      ]) {
        expect(PracticePlan.parse(invalid), isNull, reason: '$invalid');
      }
    });
  });

  group('PracticeProgress', () {
    test('serializes active/preparing sessions as paused, never autoplay', () {
      for (final status in <PracticeStatus>[
        PracticeStatus.notStarted,
        PracticeStatus.preparing,
        PracticeStatus.running,
        PracticeStatus.paused,
      ]) {
        final saved = _progress(status: status).toJson();
        expect(saved['status'], 'paused');
        final restored = PracticeProgress.parse(saved)!;
        expect(restored.status, PracticeStatus.paused);
        expect(restored.id, 'practice-fixture');
        expect(restored.sourceKey, 'local:file:///practice.wav');
        expect(restored.currentPercent, 65);
        expect(restored.stepRepetitions, 1);
        expect(restored.totalRepetitions, 4);
      }
    });

    test('keeps valid completed and aborted records distinct', () {
      final done = _progress(
        current: 100,
        step: 3,
        total: 27,
        status: PracticeStatus.completed,
      );
      expect(
        PracticeProgress.parse(done.toJson())?.status,
        PracticeStatus.completed,
      );
      expect(
        PracticeProgress.parse(
          _progress(status: PracticeStatus.aborted).toJson(),
        )?.status,
        PracticeStatus.aborted,
      );
    });

    test('accepts target that is not an exact increment', () {
      final saved = _progress().toJson();
      saved['plan'] = const PracticePlan(targetPercent: 67).toJson();
      saved['current'] = 67;
      expect(PracticeProgress.parse(saved)?.currentPercent, 67);
    });

    test('rejects corrupt, future, impossible and autoplay records', () {
      final valid = _progress().toJson();
      for (final invalid in <Object?>[
        null,
        <String, Object>{},
        {...valid, 'version': 2},
        {...valid, 'id': ''},
        {...valid, 'sourceKey': '  '},
        {...valid, 'aMs': -1},
        {...valid, 'bMs': 2249},
        {...valid, 'aMs': 2000.0},
        {...valid, 'current': 59},
        {...valid, 'current': 101},
        {...valid, 'current': 62},
        {...valid, 'stepRepetitions': -1},
        {...valid, 'stepRepetitions': 4},
        {...valid, 'totalRepetitions': 0},
        {...valid, 'totalRepetitions': 1000000001},
        {...valid, 'status': 'running'},
        {...valid, 'status': 'preparing'},
        {...valid, 'status': 'unknown'},
        {...valid, 'status': 'completed'},
        {...valid, 'status': 'completed', 'current': 100},
        {...valid, 'plan': <String, Object>{}},
      ]) {
        expect(PracticeProgress.parse(invalid), isNull, reason: '$invalid');
      }
    });
  });
}

PracticeProgress _progress({
  int current = 65,
  int step = 1,
  int total = 4,
  PracticeStatus status = PracticeStatus.paused,
}) => PracticeProgress(
  id: 'practice-fixture',
  sourceKey: 'local:file:///practice.wav',
  aMs: 2000,
  bMs: 4000,
  plan: const PracticePlan(),
  currentPercent: current,
  stepRepetitions: step,
  totalRepetitions: total,
  status: status,
);
