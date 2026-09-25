import 'package:player_core/player_core.dart';
import 'package:test/test.dart';

void main() {
  test('A/B range uses original media positions and enforces A < B', () {
    final LoopRange range = LoopRange(
      start: const Duration(seconds: 2),
      end: const Duration(seconds: 4),
    );
    expect(range.length, const Duration(seconds: 2));
    expect(range.contains(const Duration(seconds: 2)), isTrue);
    expect(range.contains(const Duration(seconds: 4)), isFalse);
    expect(
      () => LoopRange(
          start: const Duration(seconds: 2), end: const Duration(seconds: 2)),
      throwsArgumentError,
    );
    expect(
      () => LoopRange(
          start: const Duration(seconds: -1), end: const Duration(seconds: 2)),
      throwsArgumentError,
    );
  });
}
