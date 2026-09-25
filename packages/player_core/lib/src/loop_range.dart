/// A valid A/B range on the original media timeline, never a UI timer.
final class LoopRange {
  LoopRange({required this.start, required this.end}) {
    if (start.isNegative || end <= start) {
      throw ArgumentError('Loop requires 0 <= A < B.');
    }
  }

  final Duration start;
  final Duration end;

  Duration get length => end - start;

  bool contains(Duration position) => position >= start && position < end;

  @override
  bool operator ==(Object other) =>
      other is LoopRange && start == other.start && end == other.end;

  @override
  int get hashCode => Object.hash(start, end);
}
