import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transpose_mobile/youtube_browser.dart';
import 'package:transpose_mobile/youtube_native_audio_follower.dart';
import 'package:youtube_native_audio/youtube_native_audio.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('transpose/youtube_native_audio');
  late List<MethodCall> calls;
  late Map<String, Object> native;
  late bool failLoad;

  setUp(() {
    calls = [];
    failLoad = false;
    native = {'ready': true, 'playing': false, 'position': 0.0, 'duration': 200.0};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'load':
              if (failLoad) throw PlatformException(code: 'LOAD_FAILED');
              return {'duration': 200.0};
            case 'play':
              native['playing'] = true;
              native['position'] = (call.arguments as Map)['position'] as double;
              return native;
            case 'pause':
              native['playing'] = false;
              return native;
            case 'seek':
              native['position'] = (call.arguments as Map)['position'] as double;
              return native;
            case 'state':
              return native;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  YouTubeMediaState media({
    bool playing = true,
    double position = 10,
    bool muted = false,
    bool isAd = false,
    double speed = 1,
  }) => YouTubeMediaState(
    videoId: 'abcdefghijk',
    hasVideo: true,
    playing: playing,
    position: position,
    muted: muted,
    isAd: isAd,
    speed: speed,
  );

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('loads, mutes the web player and follows its clock', () async {
    final muted = <bool>[];
    final follower = NativeYouTubeAudioFollower(
      setWebMuted: (value) async => muted.add(value),
      onChanged: () {},
      audio: YouTubeNativeAudio(),
    );
    await follower.sync(media());
    await settle();
    expect(follower.status, NativeFollowStatus.ready);

    await follower.sync(media(position: 10));
    expect(muted.last, isTrue);
    expect(calls.where((c) => c.method == 'play').single.arguments, {'position': 10.0});

    // Within tolerance: no seek. Beyond: seek to the web position.
    await follower.sync(media(position: 10.2, muted: true));
    expect(calls.where((c) => c.method == 'seek'), isEmpty);
    await follower.sync(media(position: 42, muted: true));
    expect(calls.where((c) => c.method == 'seek').single.arguments, {'position': 42.0});

    await follower.sync(media(playing: false, position: 42, muted: true));
    expect(calls.last.method, 'pause');
  });

  test('pitch is native once ready and shown in the media state', () async {
    final follower = NativeYouTubeAudioFollower(
      setWebMuted: (_) async {},
      onChanged: () {},
    );
    await follower.sync(media());
    await settle();
    expect(follower.handles('pitch'), isTrue);
    expect(follower.handles('chorus'), isFalse);
    await follower.command('pitch', 3);
    final configure = calls.lastWhere((c) => c.method == 'configure');
    expect((configure.arguments as Map)['pitch'], 3.0);
    final shown = follower.overlay(media(muted: true));
    expect(shown.pitch, 3);
    expect(shown.muted, isFalse);
    expect(shown.pitchStatus, 'active');
  });

  test('speed follows the web player rate', () async {
    final follower = NativeYouTubeAudioFollower(
      setWebMuted: (_) async {},
      onChanged: () {},
    );
    await follower.sync(media());
    await settle();
    await follower.sync(media(speed: 0.75));
    final configure = calls.lastWhere((c) => c.method == 'configure');
    expect((configure.arguments as Map)['rate'], 0.75);
  });

  test('a failed load keeps YouTube audio and leaves commands to the web', () async {
    failLoad = true;
    final muted = <bool>[];
    final follower = NativeYouTubeAudioFollower(
      setWebMuted: (value) async => muted.add(value),
      onChanged: () {},
    );
    await follower.sync(media());
    await settle();
    expect(follower.status, NativeFollowStatus.failed);
    expect(follower.handles('pitch'), isFalse);
    expect(muted, isNot(contains(true)));
    expect(follower.overlay(media()).pitchMessage, contains('indisponível'));
  });

  test('ads pause the native track and restore web audio', () async {
    final muted = <bool>[];
    final follower = NativeYouTubeAudioFollower(
      setWebMuted: (value) async => muted.add(value),
      onChanged: () {},
    );
    await follower.sync(media());
    await settle();
    await follower.sync(media());
    expect(native['playing'], isTrue);
    await follower.sync(media(isAd: true, muted: true));
    expect(native['playing'], isFalse);
    expect(muted.last, isFalse);
  });
}
