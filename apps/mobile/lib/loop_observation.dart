/// Adapter-confirmed complete A–B traversals. Never inferred from UI time.
/// Epoch changes invalidate comparisons after a seek/source/loop replacement.
class LoopObservation {
  const LoopObservation({
    required this.epoch,
    required this.count,
    required this.ready,
    required this.playing,
  });
  final int epoch, count;
  final bool ready, playing;
}
