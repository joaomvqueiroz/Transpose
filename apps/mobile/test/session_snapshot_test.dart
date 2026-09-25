import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:transpose_mobile/player_presets.dart';
import 'package:transpose_mobile/practice_session.dart';
import 'package:transpose_mobile/session_snapshot.dart';

void main() {
  final media = PlayerPreset(
    id: 'snapshot-1',
    name: 'Sessão',
    title: 'My song',
    sourceId: 'file-1',
    locator: Uri.file('/music/song.mp3').toString(),
    youtube: false,
    pitch: -2,
    speed: 0.8,
    positionMs: 12345,
    aMs: 10000,
    bMs: 20000,
    loop: true,
  );
  late SessionSnapshot snapshot;
  setUp(() {
    snapshot = SessionSnapshot(
      media: media,
      savedAt: DateTime.utc(2026, 9, 25, 10, 20, 30),
      screen: 'practice',
      fullscreen: true,
      activePresetId: 'preset-1',
      practiceSessionId: 'practice-1',
      practiceCurrent: 0.8,
      practiceTarget: 1,
    );
  });

  test('snapshot round trip preserves the complete atomic recovery unit', () {
    final restored = SessionSnapshot.parse(
      jsonDecode(jsonEncode(snapshot.toJson())),
    )!;
    expect(restored.toJson(), snapshot.toJson());
    expect(restored.savedAt.isUtc, isTrue);
    expect(restored.sessionId, media.id);
    expect(restored.toJson().keys, isNot(contains('playing')));
    expect(restored.toJson().keys, isNot(contains('wasPlaying')));
  });

  test('timestamp with explicit offset is normalized to UTC', () {
    final value = snapshot.toJson()..['savedAt'] = '2026-09-25T11:20:30+01:00';
    expect(SessionSnapshot.parse(value)!.savedAt, snapshot.savedAt);
  });

  PracticeProgress progress({
    String? sourceKey,
    int aMs = 10000,
    int bMs = 20000,
  }) => PracticeProgress(
    id: 'practice-v2',
    sourceKey: sourceKey ?? 'local:${media.locator}',
    aMs: aMs,
    bMs: bMs,
    plan: const PracticePlan(
      startPercent: 60,
      targetPercent: 85,
      incrementPercent: 5,
      repetitionsPerStep: 3,
    ),
    currentPercent: 80,
    stepRepetitions: 2,
    totalRepetitions: 14,
    status: PracticeStatus.running,
  );

  test('v2 round trip stores the whole plan and removes autoplay intent', () {
    final value = SessionSnapshot(
      media: media,
      savedAt: snapshot.savedAt,
      practice: progress(),
    );
    final restored = SessionSnapshot.parse(
      jsonDecode(jsonEncode(value.toJson())),
    )!;
    expect(restored.toJson()['snapshotVersion'], 2);
    expect(restored.practice!.toJson(), progress().toJson());
    expect(restored.practice!.status, PracticeStatus.paused);
    expect(restored.practiceSessionId, 'practice-v2');
    expect(restored.practiceCurrent, .8);
    expect(restored.practiceTarget, .85);
    expect(restored.media.toJson(), media.toJson());
  });

  test(
    'v1 migrates media and display hints without inventing a practice plan',
    () {
      final v1 = snapshot.toJson()
        ..['snapshotVersion'] = 1
        ..['practice'] = progress().toJson();
      final restored = SessionSnapshot.parse(v1)!;
      expect(restored.practice, isNull);
      expect(restored.practiceSessionId, 'practice-1');
      expect(restored.practiceCurrent, .8);
      expect(restored.practiceTarget, 1);
      expect(restored.media.toJson(), media.toJson());
      expect(restored.toJson()['snapshotVersion'], 2);
    },
  );

  test('malformed or future optional practice preserves the media session', () {
    for (final value in <Object?>[
      'bad',
      [],
      {'version': 999},
      progress().toJson()..['current'] = '80',
      progress().toJson()..['stepRepetitions'] = -1,
      progress().toJson()..['status'] = 'playing',
    ]) {
      final restored = SessionSnapshot.parse(
        snapshot.toJson()..['practice'] = value,
      )!;
      expect(restored.practice, isNull);
      expect(restored.media.toJson(), media.toJson());
      expect(restored.screen, snapshot.screen);
    }
  });

  test('practice from another source or A/B range is ignored', () {
    for (final invalid in [
      progress(sourceKey: 'local:file:///different.mp3'),
      progress(sourceKey: 'youtube:${media.locator}'),
      progress(aMs: 11000),
      progress(bMs: 21000),
    ]) {
      final restored = SessionSnapshot.parse(
        snapshot.toJson()..['practice'] = invalid.toJson(),
      )!;
      expect(restored.practice, isNull);
      expect(restored.media.toJson(), media.toJson());
    }
  });

  test('YouTube practice identity uses the video locator, not a preset id', () {
    final onlineMedia = media.toJson()
      ..['youtube'] = true
      ..['locator'] = 'abcdefghijk'
      ..['sourceId'] = 'unrelated-metadata-id';
    final restored = SessionSnapshot.parse(
      snapshot.toJson()
        ..['media'] = onlineMedia
        ..['practice'] = progress(sourceKey: 'youtube:abcdefghijk').toJson(),
    )!;
    expect(restored.practice, isNotNull);
    expect(restored.practice!.sourceKey, 'youtube:abcdefghijk');
  });

  test(
    'unsupported future schema is not treated as corrupt or older schema',
    () {
      final value = snapshot.toJson()
        ..['snapshotVersion'] = SessionSnapshot.version + 1;
      expect(
        () => SessionSnapshot.parse(value),
        throwsA(isA<UnsupportedSessionSnapshotVersion>()),
      );
      value['snapshotVersion'] = 0;
      expect(SessionSnapshot.parse(value), isNull);
      value['snapshotVersion'] = 1.0;
      expect(SessionSnapshot.parse(value), isNull);
    },
  );

  test('malformed roots required fields and local timestamps are rejected', () {
    for (final value in [null, 0, [], 'snapshot']) {
      expect(SessionSnapshot.parse(value), isNull);
    }
    final invalid = <String, Object?>{
      'sessionId': '',
      'screen': 'unexpected-screen',
      'fullscreen': 'yes',
      'savedAt': '2026-09-25T10:20:30',
      'activePresetId': ' ',
      'practiceSessionId': 1,
      'practiceCurrent': double.nan,
      'practiceTarget': 2,
    };
    for (final entry in invalid.entries) {
      expect(
        SessionSnapshot.parse(snapshot.toJson()..[entry.key] = entry.value),
        isNull,
        reason: entry.key,
      );
    }
  });

  test(
    'all supported screens accepted and optional references may be null',
    () {
      for (final screen in SessionSnapshot.screens) {
        final value = SessionSnapshot(
          media: media,
          savedAt: snapshot.savedAt,
          screen: screen,
        );
        expect(SessionSnapshot.parse(value.toJson())!.screen, screen);
      }
    },
  );

  test('position pitch speed and loop invariants checked before recovery', () {
    for (final change in <String, Object?>{
      'positionMs': -1,
      'pitch': double.infinity,
      'speed': 0.49,
      'bMs': 10000,
      'aMs': null,
      'locator': '',
    }.entries) {
      final invalidMedia = media.toJson()..[change.key] = change.value;
      expect(
        SessionSnapshot.parse(snapshot.toJson()..['media'] = invalidMedia),
        isNull,
        reason: change.key,
      );
    }
  });
}
