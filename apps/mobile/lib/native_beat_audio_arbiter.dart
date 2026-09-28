/// Exclusive ownership of the single Android `transpose/band_audio` channel.
/// The same instance must be passed to every session using native beat audio.
class NativeBeatAudioArbiter {
  NativeBeatAudioArbiter();

  static final instance = NativeBeatAudioArbiter();
  Object? _owner;

  bool tryAcquire(Object owner) {
    if (_owner != null && !identical(_owner, owner)) return false;
    _owner = owner;
    return true;
  }

  bool owns(Object owner) => identical(_owner, owner);

  void release(Object owner) {
    if (identical(_owner, owner)) _owner = null;
  }
}
