import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_core/player_core.dart';
import 'package:transpose_mobile/main_player_controller.dart';
import 'package:transpose_mobile/media/local_player_controller.dart';
import 'package:transpose_mobile/player_presets.dart';
import 'package:transpose_mobile/youtube_browser.dart';

import 'fake_youtube_session.dart';

const _id = 'abcdefghijk';
const _otherId = 'ZYXwvutsrqp';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final online in [false, true]) {
    test(
      '${online ? 'YouTube' : 'local'} recovery retains the position inside an active loop',
      () async {
        final local = _RestorableLocal();
        final youtube = _YouTube(<String>[])..state = _video();
        final player = MainPlayerController(
          local: local,
          youtubeFactory: () => youtube,
        );
        await player.restore(
          _preset(youtube: online, loop: true, positionMs: 15000),
        );
        expect(player.lastRestoreSucceeded, isTrue);
        if (online) {
          expect(youtube.commands.last, ('seekTo', 15));
          expect(youtube.commands.where((c) => c.$1 == 'toggleLoop'), isEmpty);
        } else {
          expect(local.position, const Duration(seconds: 15));
          expect(local.loopEnabled, isTrue);
          expect(local.markerA, const Duration(seconds: 10));
          expect(local.markerB, const Duration(seconds: 20));
        }
        expect(player.playing, isFalse);
        player.dispose();
      },
    );

    test(
      '${online ? 'YouTube' : 'local'} recovery clamps out-of-loop position to A',
      () async {
        final local = _RestorableLocal();
        final youtube = _YouTube(<String>[])..state = _video();
        final player = MainPlayerController(
          local: local,
          youtubeFactory: () => youtube,
        );
        await player.restore(
          _preset(youtube: online, loop: true, positionMs: 20000),
        );
        expect(player.lastRestoreSucceeded, isTrue);
        if (online) {
          expect(youtube.commands.last, ('seekTo', 10));
        } else {
          expect(local.position, const Duration(seconds: 10));
          expect(local.loopEnabled, isTrue);
        }
        player.dispose();
      },
    );

    test(
      '${online ? 'YouTube' : 'local'} recovery preserves a lone valid A without enabling a loop',
      () async {
        final local = _RestorableLocal();
        final youtube = _YouTube(<String>[])..state = _video();
        final player = MainPlayerController(
          local: local,
          youtubeFactory: () => youtube,
        );
        await player.restore(_preset(youtube: online, bMs: null));
        expect(player.lastRestoreSucceeded, isTrue);
        if (online) {
          expect(youtube.commands, contains(('markA', null)));
          expect(
            youtube.commands.where(
              (c) => c.$1 == 'markB' || c.$1 == 'toggleLoop',
            ),
            isEmpty,
          );
          expect(youtube.commands.last, ('seekTo', 23));
        } else {
          expect(local.markerA, const Duration(seconds: 10));
          expect(local.markerB, isNull);
          expect(local.position, const Duration(seconds: 23));
          expect(local.loopEnabled, isFalse);
        }
        player.dispose();
      },
    );
  }

  test(
    'restored YouTube rejects a delayed page autoplay until explicit Play',
    () async {
      final youtube = _YouTube(<String>[])..state = _video();
      final player = MainPlayerController(
        local: _Local(<String>[]),
        youtubeFactory: () => youtube,
      );
      await player.restore(_preset());
      youtube.commands.clear();
      youtube.state = _video(playing: true);
      youtube.notifyListeners();
      await Future<void>.delayed(Duration.zero);
      expect(youtube.commands, [('pause', null)]);
      expect(player.playing, isFalse);
      await player.playPause();
      expect(youtube.commands.last, ('play', null));
      player.dispose();
    },
  );

  test(
    'native YouTube Play after a real video touch releases restore guard',
    () async {
      final youtube = _YouTube(<String>[])..state = _video();
      final player = MainPlayerController(
        local: _Local(<String>[]),
        youtubeFactory: () => youtube,
      );
      await player.restore(_preset());
      youtube.commands.clear();
      player.noteNativeVideoTouch();
      youtube.state = _video(playing: true);
      youtube.notifyListeners();
      await Future<void>.delayed(Duration.zero);
      expect(youtube.commands, isEmpty);
      expect(player.playing, isTrue);
      player.dispose();
    },
  );

  for (final initiallyPlaying in [false, true]) {
    test(
      'YouTube transport preserves intent across page state changes ($initiallyPlaying)',
      () async {
        final youtube = _YouTube(<String>[])
          ..state = _video(playing: initiallyPlaying);
        final player = MainPlayerController(
          local: _Local(<String>[]),
          youtubeFactory: () => youtube,
        );
        await player.openYouTube();
        youtube.commands.clear();
        final command = player.playPause();
        youtube.state = _video(playing: !initiallyPlaying);
        await command;
        expect(youtube.commands, [(initiallyPlaying ? 'pause' : 'play', null)]);
        player.dispose();
      },
    );
  }

  test('YouTube Pause bypasses an outstanding pitch acknowledgement', () async {
    final youtube = _YouTube(<String>[])..state = _video(playing: true);
    final player = MainPlayerController(
      local: _Local(<String>[]),
      youtubeFactory: () => youtube,
    );
    await player.openYouTube();
    youtube.pitchGate = Completer<void>();
    final adjusting = player.changePitch(1);
    await Future<void>.delayed(Duration.zero);
    expect(player.busy, isTrue);
    await player.playPause().timeout(const Duration(seconds: 1));
    expect(player.playing, isFalse);
    expect(youtube.commands.last, ('pause', null));
    expect(player.busy, isTrue);
    youtube.pitchGate!.complete();
    await adjusting;
    expect(player.playing, isFalse);
    player.dispose();
  });

  test('YouTube creation waits for local output release', () async {
    final events = <String>[];
    final local = _Local(events)..releaseGate = Completer<void>();
    final youtube = _YouTube(events);
    var factories = 0;
    final player = MainPlayerController(
      local: local,
      youtubeFactory: () {
        factories++;
        return youtube;
      },
    );
    final opening = player.openYouTube();
    await Future<void>.delayed(Duration.zero);
    expect(player.busy, isTrue);
    expect(factories, 0);
    local.releaseGate!.complete();
    await opening;
    expect(events, <String>['local.close', 'youtube.start']);
    expect(player.isYouTube, isTrue);
    expect(factories, 1);
    await player.openYouTube();
    expect(factories, 1);
    player.dispose();
  });

  test(
    'failed local release never creates an overlapping YouTube player',
    () async {
      final local = _Local(<String>[])..releaseFails = true;
      var factories = 0;
      final player = MainPlayerController(
        local: local,
        youtubeFactory: () {
          factories++;
          return _YouTube(<String>[]);
        },
      );
      await player.search('music');
      expect(factories, 0);
      expect(local.hasResource, isTrue);
      expect(player.isYouTube, isFalse);
      expect(player.message, isNotNull);
      player.dispose();
    },
  );

  test(
    'processing reports browser acknowledgement and rejects ad controls',
    () async {
      final youtube = _YouTube(<String>[])..state = _video();
      final player = MainPlayerController(
        local: _Local(<String>[]),
        youtubeFactory: () => youtube,
      );
      await player.openYouTube();
      await player.changePitch(4);
      expect(youtube.commands.last, ('pitch', 4));
      expect(player.pitch, 0);
      youtube.state = _video(pitch: 4);
      youtube.notifyListeners();
      expect(player.pitch, 4);
      youtube.state = _video(ad: true);
      youtube.commands.clear();
      await player.changePitch(3);
      await player.changeSpeed(.75);
      await player.markA();
      await player.seek(const Duration(seconds: 10));
      expect(youtube.commands, isEmpty);
      expect(player.canPitch, isFalse);
      expect(player.canSpeed, isFalse);
      expect(player.canLoop, isFalse);
      expect(player.canSeek, isFalse);
      expect(player.snapshot('ad'), isNull);
      player.dispose();
    },
  );

  test('YouTube accepts 0.25x to 2x and rejects values outside', () async {
    final youtube = _YouTube(<String>[])..state = _video();
    final player = MainPlayerController(
      local: _Local(<String>[]),
      youtubeFactory: () => youtube,
    );
    await player.openYouTube();
    await player.changeSpeed(.25);
    expect(youtube.commands.last, ('speed', .25));
    await player.changeSpeed(2);
    expect(youtube.commands.last, ('speed', 2));
    final count = youtube.commands.length;
    await player.changeSpeed(.2);
    await player.changeSpeed(2.1);
    expect(youtube.commands, hasLength(count));
    player.dispose();
  });

  test(
    'loading local sample pauses the browser before changing the source',
    () async {
      final events = <String>[];
      final youtube = _YouTube(events)..state = _video(playing: true);
      final local = _Local(events);
      final player = MainPlayerController(
        local: local,
        youtubeFactory: () => youtube,
      );
      await player.openYouTube();
      events.clear();
      await player.loadSample();
      expect(events, <String>['youtube.pause', 'local.sample']);
      expect(player.isYouTube, isFalse);
      expect(player.loaded, isTrue);
      expect(youtube.media.playing, isFalse);
      player.dispose();
    },
  );

  test('new YouTube request wins over pending rhythm preview', () async {
    final events = <String>[];
    final youtube = _YouTube(events)..state = _video();
    final local = _Local(events)..previewGate = Completer<void>();
    final player = MainPlayerController(
      local: local,
      youtubeFactory: () => youtube,
    );
    await player.openYouTube();
    final preview = player.loadApprovedRhythmPreview(Uint8List.fromList([1]));
    await local.previewEntered.future;
    final search = player.search('new video');
    local.previewGate!.complete();
    await Future.wait([preview, search]);
    expect(player.isYouTube, isTrue);
    expect(local.previewCommits, 0);
    expect(events, isNot(contains('local.play')));
    player.dispose();
  });

  test('latest rhythm preview wins and only it starts playback', () async {
    final events = <String>[];
    final local = _Local(events)..previewGate = Completer<void>();
    final player = MainPlayerController(local: local);
    final first = player.loadApprovedRhythmPreview(Uint8List.fromList([1]));
    await local.previewEntered.future;
    final second = player.loadApprovedRhythmPreview(Uint8List.fromList([2]));
    local.previewGate!.complete();
    await Future.wait([first, second]);
    expect(local.previewCommits, 1);
    expect(events.where((e) => e == 'local.play').length, 1);
    player.dispose();
  });

  test(
    'rhythm stop leaves normal YouTube playing and pauses only preview',
    () async {
      final events = <String>[];
      final youtube = _YouTube(events)..state = _video(playing: true);
      final local = _Local(events);
      final player = MainPlayerController(
        local: local,
        youtubeFactory: () => youtube,
      );
      await player.openYouTube();
      events.clear();
      await player.stopRhythmPreview();
      expect(events, isEmpty);
      expect(player.isYouTube, isTrue);

      await player.loadApprovedRhythmPreview(Uint8List.fromList([1]));
      expect(player.isRhythmPreview, isTrue);
      expect(player.snapshot('temporary'), isNull);
      events.clear();
      await player.stopRhythmPreview();
      expect(events, contains('local.pause'));
      expect(events, isNot(contains('youtube.pause')));
      player.dispose();
    },
  );

  test(
    'pending browser pitch can be cancelled without claiming it applied',
    () async {
      final youtube = _YouTube(<String>[])
        ..state = const YouTubeMediaState(
          videoId: _id,
          title: 'Paused song',
          hasVideo: true,
          duration: 120,
          pitchStatus: 'loading',
        );
      final player = MainPlayerController(
        local: _Local(<String>[]),
        youtubeFactory: () => youtube,
      );
      await player.openYouTube();
      expect(player.pitchPending, isTrue);
      expect(player.pitch, 0);
      await player.changePitch(3);
      expect(youtube.commands, isEmpty);
      await player.changePitch(0);
      expect(youtube.commands.single, ('pitch', 0));
      player.dispose();
    },
  );

  test(
    'failed local preset restore exposes failure and sends no processing',
    () async {
      final events = <String>[];
      final local = _Local(events)..loadFails = true;
      final youtube = _YouTube(events)..state = _video();
      final player = MainPlayerController(
        local: local,
        youtubeFactory: () => youtube,
      );
      await player.openYouTube();
      events.clear();
      await player.restore(_preset(youtube: false));
      expect(player.loaded, isFalse);
      expect(player.message, 'Ficheiro indisponível');
      expect(events, <String>['local.pause', 'youtube.pause', 'local.load']);
      player.dispose();
    },
  );

  test(
    'YouTube preset restores markers and position without starting playback',
    () async {
      final youtube = _YouTube(<String>[])..state = _video(playing: true);
      final player = MainPlayerController(
        local: _Local(<String>[]),
        youtubeFactory: () => youtube,
      );
      await player.openYouTube();
      await player.restore(_preset());
      expect(youtube.commands, <(String, num?)>[
        ('pause', null),
        ('pause', null),
        ('clearLoop', null),
        ('speed', .75),
        ('pitch', 2),
        ('seekTo', 10),
        ('markA', null),
        ('seekTo', 20),
        ('markB', null),
        ('toggleLoop', null),
        ('seekTo', 23),
      ]);
      expect(youtube.media.playing, isFalse);
      player.dispose();
    },
  );

  testWidgets('restoring current video waits for its ad before processing', (
    tester,
  ) async {
    final youtube = _YouTube(<String>[])
      ..state = _video(ad: true, playing: true);
    final player = MainPlayerController(
      local: _Local(<String>[]),
      youtubeFactory: () => youtube,
    );
    await player.openYouTube();
    final restoring = player.restore(_preset());
    await tester.pump();
    final commandsDuringAd = List<(String, num?)>.of(youtube.commands);
    youtube.state = _video();
    youtube.notifyListeners();
    await tester.pump(const Duration(milliseconds: 300));
    await restoring;
    player.dispose();
    expect(
      commandsDuringAd.every((command) => command.$1 == 'pause'),
      isTrue,
      reason:
          'Pitch, speed, seek and loop must wait until the advertisement ends.',
    );
  });

  testWidgets('lifecycle pause interrupts an ongoing preset readiness wait', (
    tester,
  ) async {
    final youtube = _YouTube(<String>[])..state = _video();
    youtube.openState = _video(id: _otherId, ad: true, playing: true);
    final player = MainPlayerController(
      local: _Local(<String>[]),
      youtubeFactory: () => youtube,
    );
    await player.openYouTube();
    final restoring = player.restore(_preset(id: _otherId));
    await tester.pump();
    youtube.commands.clear();
    final pausing = player.pause();
    await tester.pump(const Duration(milliseconds: 1));
    final commandsWhileWaiting = List<(String, num?)>.of(youtube.commands);
    final pausedWhileWaiting = !youtube.media.playing;
    youtube.state = _video(id: _otherId);
    youtube.notifyListeners();
    await tester.pump(const Duration(milliseconds: 300));
    await restoring;
    await pausing;
    player.dispose();
    expect(commandsWhileWaiting, contains(('pause', null)));
    expect(pausedWhileWaiting, isTrue);
  });

  test('absolute main seek is clamped before dispatching to YouTube', () async {
    final youtube = _YouTube(<String>[])..state = _video();
    final player = MainPlayerController(
      local: _Local(<String>[]),
      youtubeFactory: () => youtube,
    );
    await player.openYouTube();
    await player.seek(const Duration(seconds: 999));
    expect(youtube.commands.last, ('seekTo', 100));
    await player.seek(const Duration(seconds: -5));
    expect(youtube.commands.last, ('seekTo', 0));
    player.dispose();
  });

  test(
    'restore notifies the online surface before waiting for the saved video',
    () async {
      final youtube = _YouTube(<String>[]);
      final player = MainPlayerController(
        local: _Local(<String>[]),
        youtubeFactory: () => youtube,
      );
      var onlineNotified = false;
      player.addListener(() {
        if (player.isYouTube) onlineNotified = true;
      });
      youtube.onOpen = () => expect(onlineNotified, isTrue);
      await player.restore(_preset());
      expect(player.lastRestoreSucceeded, isTrue);
      expect(player.sourceKey, 'youtube:$_id');
      expect(
        youtube.commands.where(
          (c) => ['playPause', 'play', 'unmute'].contains(c.$1),
        ),
        isEmpty,
      );
      player.dispose();
    },
  );
}

YouTubeMediaState _video({
  String id = _id,
  bool ad = false,
  bool playing = false,
  double pitch = 0,
}) => YouTubeMediaState(
  videoId: id,
  title: 'Song',
  hasVideo: true,
  duration: 100,
  isAd: ad,
  playing: playing,
  pitch: pitch,
  pitchStatus: pitch == 0 ? 'idle' : 'active',
);

PlayerPreset _preset({
  bool youtube = true,
  String id = _id,
  bool loop = false,
  int positionMs = 23000,
  int? aMs = 10000,
  int? bMs = 20000,
}) => PlayerPreset(
  id: 'saved',
  name: 'Study',
  title: 'Song',
  sourceId: id,
  locator: youtube ? id : 'file:///C:/missing.wav',
  youtube: youtube,
  pitch: 2,
  speed: .75,
  positionMs: positionMs,
  aMs: aMs,
  bMs: bMs,
  loop: loop,
);

class _RestorableLocal extends _Local {
  _RestorableLocal() : super(<String>[]);
  @override
  bool get canLoop => loaded;
  @override
  bool get canSpeed => loaded;
  @override
  bool get canPitch => loaded;
  @override
  Duration get duration => const Duration(seconds: 100);
  @override
  Duration position = Duration.zero;
  @override
  Duration? markerA;
  @override
  Duration? markerB;
  @override
  bool loopEnabled = false;

  @override
  Future<void> resetProcessing() async {
    markerA = markerB = null;
    loopEnabled = false;
  }

  @override
  Future<void> setLoopMarkers(Duration a, Duration b) async {
    markerA = a;
    markerB = b;
  }

  @override
  Future<void> markA() async => markerA = position;
  @override
  Future<void> toggleLoop() async => loopEnabled = !loopEnabled;
  @override
  Future<void> seek(Duration target) async {
    if (loopEnabled && (target < markerA! || target >= markerB!)) {
      loopEnabled = false;
    }
    position = target;
  }
}

class _YouTube extends FakeYouTubeSession {
  _YouTube(this.events);
  final List<String> events;
  YouTubeMediaState? openState;
  Completer<void>? pitchGate;
  void Function()? onOpen;

  @override
  Future<void> start(Uri uri) async {
    events.add('youtube.start');
    await super.start(uri);
  }

  @override
  Future<void> openVideo(String videoId) async {
    onOpen?.call();
    events.add('youtube.open');
    state = openState ?? _video(id: videoId);
    notifyListeners();
  }

  @override
  Future<void> command(String action, [num? value]) async {
    events.add('youtube.$action');
    await super.command(action, value);
    if (action == 'pitch') await pitchGate?.future;
    if (action == 'pause') {
      state = YouTubeMediaState(
        videoId: state.videoId,
        title: state.title,
        hasVideo: state.hasVideo,
        duration: state.duration,
        position: state.position,
        isAd: state.isAd,
        muted: state.muted,
        pitch: state.pitch,
        pitchStatus: state.pitchStatus,
        speed: state.speed,
        loopA: state.loopA,
        loopB: state.loopB,
        loopEnabled: state.loopEnabled,
      );
      notifyListeners();
    }
  }
}

class _Local extends LocalPlayerController {
  _Local(this.events);
  final List<String> events;
  Completer<void>? releaseGate;
  Completer<void>? previewGate;
  final previewEntered = Completer<void>();
  int previewCommits = 0;
  String? previewSourceId;
  bool releaseFails = false, loadFails = false;
  bool _loaded = true, _owned = true;
  String? failure;
  @override
  bool get loaded => _loaded;
  @override
  String get sourceId => previewSourceId ?? super.sourceId;
  @override
  bool get hasResource => _owned;
  @override
  String? get message => failure;
  @override
  String? get locator => _loaded ? 'file:///C:/current.wav' : null;
  @override
  Future<void> close() async {
    events.add('local.close');
    await releaseGate?.future;
    if (releaseFails) return;
    _loaded = _owned = false;
    previewSourceId = null;
  }

  @override
  Future<void> pause() async => events.add('local.pause');
  @override
  Future<void> playPause() async => events.add('local.play');
  @override
  Future<bool> loadGeneratedPreview(
    Uint8List bytes, {
    bool Function()? canCommit,
  }) async {
    if (!previewEntered.isCompleted) previewEntered.complete();
    await previewGate?.future;
    if (canCommit?.call() == false) return false;
    previewCommits++;
    _loaded = _owned = true;
    previewSourceId = 'rhythm-preview-fake';
    return true;
  }

  @override
  Future<void> loadSample() async {
    events.add('local.sample');
    _loaded = _owned = true;
  }

  @override
  Future<void> load(LocalFileSource source) async {
    events.add('local.load');
    _loaded = _owned = !loadFails;
    if (loadFails) failure = 'Ficheiro indisponível';
  }

  @override
  Future<void> resetProcessing() async => events.add('local.reset');
  @override
  Future<void> changePitch(double value) async => events.add('local.pitch');
  @override
  Future<void> changeSpeed(double value) async => events.add('local.speed');
}
