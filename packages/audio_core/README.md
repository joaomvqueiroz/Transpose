# Native audio-core spike — S-001/S-003

This package proves Dart FFI → C ABI → C++ on Android. The native library
exports diagnostic handle calls and an isolated 440 Hz tone output through
Oboe. It now also preloads a **local RIFF PCM16 mono/stereo WAV** (up to 64 MiB)
for isolated device testing. The WAV parser and conversion run before the
stream opens; the callback reads immutable float samples and stops at end.
The diagnostic path requires the WAV sample rate to be accepted unchanged by
the output device. It is not a general media decoder or the app's player. The
**default build has no DSP library**. Do not interpret it as validated live
pitch, speed, low-latency, or iOS playback.

The mobile Android build uses the NDK and CMake to compile this shared library.
Run the on-device integration test from `apps/mobile`:

```text
flutter test integration_test/audio_core_ffi_test.dart -d <android-device>
```

For the 10-minute profile stress run on a physical Android device:

```text
flutter drive --profile -d <android-device> --driver=test_driver/audio_core_ffi_test.dart --target=integration_test/audio_core_ffi_test.dart --dart-define=AUDIO_STRESS_SECONDS=600 --timeout=900
```

The test prints frame and XRun counters every 30 seconds and requires zero
reported XRuns in the 10-minute run. This cannot verify audible glitches or
physical output latency; those need external observation/instrumentation.
For a short diagnostic comparison, pass
`--dart-define=AUDIO_BUFFER_BURSTS=3` to request three bursts instead of the
default two. The test logs actual burst and buffer frames, callback count,
maximum callback work time and callbacks whose work exceeded one callback's
frame budget. Callback time excludes waiting to be scheduled and therefore
cannot by itself explain an XRun or measure output latency.

Flutter Driver cannot run in release mode. For a release stress test, build
the separate `lib/audio_stress_main.dart` entry point with
`--dart-define=AUDIO_STRESS_SECONDS=600`, install that APK on a test device,
and read the `S-002 release` lines in Android logcat. It is **not** the product
entry point; rebuild from `lib/main.dart` before installing or distributing
the normal app. Do not distribute the diagnostic APK.

No live audio buffer crosses Dart; the integration test copies its bundled QA
fixture to a temporary local file and passes only that file path to C++.
Handle ownership is explicit and disposal is
idempotent on the Dart side. The callback has no locks, allocation, I/O, or
Dart calls. iOS packaging remains to be implemented on macOS.

## Internal S-003 Rubber Band evaluation

Rubber Band v4.0.0 is an **optional, local-only** source dependency. The
default CMake/Gradle build omits it and `AudioCoreFfi.dspAvailable` is false.
For the internal Android spike, clone the official source at tag `v4.0.0`
(commit `1d95888bec3ae0a17c0c4af791810d5a63f6bc35`) into the ignored
`.third_party/rubberband-v4.0.0` directory. Set the process environment
variable `TRANSPOSE_RUBBERBAND_SOURCE_DIR` to that absolute directory before
running `flutter drive --profile` with
`integration_test/audio_dsp_spike_test.dart` and its matching driver. Unset
the variable before building the normal app. The separate
`audio_core_no_dsp_test.dart` checks that default builds exclude the DSP.

The spike renders a local PCM16 WAV synchronously through the real-time R2 or
R3 API behind `DspProcessor`. It also offers an internal streaming test: a
native worker processes the preloaded WAV into a bounded, preallocated SPSC
PCM queue, which the Oboe callback consumes without running DSP or allocating.
Neither path changes parameters during playback or proves audio quality or
end-to-end latency. The vendor's
[license](https://breakfastquay.com/rubberband/license.html) requires a valid
commercial license before distributing a proprietary APK/IPA containing
Rubber Band. No such license has been purchased; do not distribute spike APKs.
