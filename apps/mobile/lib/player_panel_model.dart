import 'package:flutter/foundation.dart';

import 'loop_observation.dart';

/// Read-only engine acknowledgements plus intents used by the native panel.
abstract class PlayerPanelModel extends ChangeNotifier {
  LoopObservation? get loopObservation => null;
  bool get loaded;
  bool get playing;
  bool get busy;
  bool get canPitch;
  bool get pitchPending => false;
  bool get canSpeed;
  bool get canLoop;
  bool get canSeek => loaded && duration > Duration.zero;
  bool get muted;
  String get title;
  String get sourceLabel;
  String? get message;
  Duration get position;
  Duration get duration;
  double get pitch;
  int? get detectedKeyRoot => null;
  String get detectedKeyMode => '';
  String get keyDetectionStatus => 'waiting';
  double get speed;
  Duration? get markerA;
  Duration? get markerB;
  bool get loopEnabled;
  Future<void> playPause();
  Future<void> seek(Duration position);
  Future<void> changePitch(double value);
  Future<void> changeSpeed(double value);
  Future<void> markA();
  Future<void> markB();
  Future<void> toggleLoop();
  Future<void> clearLoop();
  Future<void> resetProcessing();
}
