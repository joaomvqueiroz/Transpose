import 'package:flutter/material.dart';
import 'package:transpose_mobile/youtube_browser.dart';

class FakeYouTubeSession extends YouTubeBrowserSession {
  Uri? startedUri;
  String? lastQuery;
  final List<(String, num?)> commands = <(String, num?)>[];
  bool disposed = false;
  bool back = false;
  String? failure;
  YouTubeMediaState state = const YouTubeMediaState();

  @override
  YouTubeMediaState get media => state;
  @override
  int get progress => 100;
  @override
  String? get error => failure;
  @override
  bool get canGoBack => back;
  @override
  Future<void> start(Uri uri) async => startedUri = uri;
  @override
  Future<void> search(String query) async => lastQuery = query;
  @override
  Future<void> reload() async {
    failure = null;
    notifyListeners();
  }

  @override
  Future<void> goBack() async {
    back = false;
    notifyListeners();
  }

  @override
  Future<void> command(String action, [num? value]) async {
    commands.add((action, value));
    if (value != null &&
        <String>{
          'bass',
          'mid',
          'treble',
          'gain',
          'chorus',
          'feedback',
          'delay',
          'reverb',
        }.contains(action)) {
      state = YouTubeMediaState(
        videoId: state.videoId,
        title: state.title,
        hasVideo: state.hasVideo,
        playing: state.playing,
        muted: state.muted,
        position: state.position,
        duration: state.duration,
        speed: state.speed,
        pitch: state.pitch,
        pitchStatus: state.pitchStatus,
        pitchMessage: state.pitchMessage,
        loopA: state.loopA,
        loopB: state.loopB,
        loopEnabled: state.loopEnabled,
        isAd: state.isAd,
        loopCount: state.loopCount,
        loopEpoch: state.loopEpoch,
        loopEventsSupported: state.loopEventsSupported,
        playbackReady: state.playbackReady,
        keyRoot: state.keyRoot,
        keyMode: state.keyMode,
        keyStatus: state.keyStatus,
        audioEffects: {...state.audioEffects, action: value.toDouble()},
      );
      notifyListeners();
    }
  }

  @override
  Widget buildView() => const Center(child: Text('Resultados com miniaturas'));
  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}
