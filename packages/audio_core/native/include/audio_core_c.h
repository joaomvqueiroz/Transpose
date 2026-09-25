#ifndef AUDIO_CORE_C_H
#define AUDIO_CORE_C_H

#include <stdint.h>

#if defined(_WIN32)
#define AC_EXPORT __declspec(dllexport)
#else
#define AC_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef void* ACHandle;

// S-001 diagnostics and isolated S-002 Android tone/WAV output.
AC_EXPORT int32_t ac_abi_version(void);
AC_EXPORT ACHandle ac_create(void);
AC_EXPORT int32_t ac_ping(ACHandle handle, int32_t value);
// Test-only: request 2..4 bursts before opening a stream; default is 2.
AC_EXPORT int32_t ac_set_buffer_bursts(ACHandle handle, int32_t bursts);
// Returns 0 on success; a negative value means unavailable or failed.
AC_EXPORT int32_t ac_start_tone(ACHandle handle);
// Preloads a RIFF PCM16 mono/stereo WAV (up to 64 MiB) outside the callback.
// Returns -2 for missing/unsupported WAV; no Dart audio buffers enter C++.
AC_EXPORT int32_t ac_start_wav(ACHandle handle, const char* path);
// Closes the current diagnostic output, whether tone or WAV.
AC_EXPORT int32_t ac_stop_tone(ACHandle handle);
// Actual source frames emitted (not silent tail); -1 before WAV is loaded.
AC_EXPORT int64_t ac_wav_frames(ACHandle handle);
// 1 when the WAV source reached its end, 0 otherwise, -1 for invalid handle.
AC_EXPORT int32_t ac_wav_finished(ACHandle handle);
// Diagnostic callback work only: excludes scheduling wait and DAC latency.
AC_EXPORT int64_t ac_callback_calls(ACHandle handle);
AC_EXPORT int64_t ac_callback_max_us(ACHandle handle);
AC_EXPORT int64_t ac_callback_over_budget(ACHandle handle);
// Internal S-003 only. Unavailable (-5) in every normal/default build.
AC_EXPORT int32_t ac_dsp_available(void);
// Render a local WAV with independent pitch (semitones) and speed (factor).
// This synchronous test render is not the live real-time output path.
AC_EXPORT int32_t ac_render_wav_dsp(const char* input_path,
                                    const char* output_path,
                                    double semitones,
                                    double speed,
                                    int32_t finer);
// Internal S-003: DSP worker streams into a bounded PCM queue for Oboe.
// All return -5 in default builds without the opt-in DSP dependency.
AC_EXPORT int32_t ac_start_live_dsp(ACHandle handle, const char* path,
                                    double semitones, double speed,
                                    int32_t finer);
AC_EXPORT int64_t ac_live_frames(ACHandle handle);
AC_EXPORT int32_t ac_live_finished(ACHandle handle);
AC_EXPORT int64_t ac_live_queue_underruns(ACHandle handle);
AC_EXPORT int64_t ac_tone_frames(ACHandle handle);
AC_EXPORT int32_t ac_tone_sample_rate(ACHandle handle);
AC_EXPORT int32_t ac_tone_burst_frames(ACHandle handle);
AC_EXPORT int32_t ac_tone_buffer_frames(ACHandle handle);
// Returns -1 when the output API cannot report underruns.
AC_EXPORT int32_t ac_tone_xruns(ACHandle handle);
AC_EXPORT void ac_destroy(ACHandle handle);

#ifdef __cplusplus
}
#endif

#endif
