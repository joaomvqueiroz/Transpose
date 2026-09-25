# Audio engine contract

Pure Dart boundary for pitch and speed processing. The current Flutter player
does not implement this port and must not expose pitch/speed controls as
functional yet. `AudioProcessingPort` belongs to one prepared media resource;
it does not own playback or create another output.

`setPitchSemitones` and `setSpeedFactor` return a sequence when a command is
accepted. A matching `appliedStates` update is the separate confirmation that
the adapter applied it. A failed command leaves the last confirmed values
unchanged. Latency fields are optional until the native path can measure the
effective output; null must not be reported as 0 ms.

There is deliberately no Rubber Band, FFI, Flutter, Media3, or AVPlayer import
here. ADR-014 supersedes ADR-011/012 for the product: use platform-native
pitch/speed on the player that owns the output, without Rubber Band. The
isolated Android Media3 probe is not yet the final media adapter. It must
validate hardware capabilities, preserve pitch/speed independence, and prove
latency and audio quality on Android and iOS devices.

`PitchController` provides the application-side pitch behavior for AUDIO-002:
range -12…+12 semitones, a pending request distinct from the confirmed value,
rollback to the latest confirmed value on command failure, and an optional
measured apply latency. It does not smooth PCM itself or make pitch audible;
that remains native-adapter work after the DSP spike.
