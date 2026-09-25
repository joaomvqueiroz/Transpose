#include "audio_core_c.h"
#ifdef TRANSPOSE_RUBBERBAND_INTERNAL_SPIKE
#include "rubberband_processor.h"
#endif

#include <oboe/Oboe.h>

#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <memory>
#include <mutex>
#include <new>
#include <thread>
#include <utility>
#include <vector>

namespace {
constexpr int32_t kMagic = 0x41434331;
constexpr float kAmplitude = 0.06f;
constexpr float kFrequency = 440.0f;
constexpr float kTwoPi = 6.2831853071795864769f;
constexpr std::streamoff kMaxWavBytes = 64 * 1024 * 1024;

uint16_t read_u16(const uint8_t* bytes) {
  return static_cast<uint16_t>(bytes[0] | (bytes[1] << 8));
}

uint32_t read_u32(const uint8_t* bytes) {
  return static_cast<uint32_t>(bytes[0]) |
         (static_cast<uint32_t>(bytes[1]) << 8) |
         (static_cast<uint32_t>(bytes[2]) << 16) |
         (static_cast<uint32_t>(bytes[3]) << 24);
}

struct WavPcm {
  int32_t sample_rate = 0;
  int32_t channels = 0;
  std::vector<float> samples;
};

struct CallbackMetrics {
  std::atomic<int64_t> calls{0};
  std::atomic<int64_t> max_ns{0};
  std::atomic<int64_t> over_budget{0};

  void reset() {
    calls.store(0, std::memory_order_relaxed);
    max_ns.store(0, std::memory_order_relaxed);
    over_budget.store(0, std::memory_order_relaxed);
  }

  void observe(std::chrono::steady_clock::time_point start,
               int32_t frames,
               int32_t sample_rate) {
    const auto elapsed = std::chrono::duration_cast<std::chrono::nanoseconds>(
                             std::chrono::steady_clock::now() - start)
                             .count();
    calls.fetch_add(1, std::memory_order_relaxed);
    int64_t previous = max_ns.load(std::memory_order_relaxed);
    while (elapsed > previous &&
           !max_ns.compare_exchange_weak(previous, elapsed,
                                         std::memory_order_relaxed)) {
    }
    const int64_t budget_ns =
        1000000000LL * static_cast<int64_t>(frames) / sample_rate;
    if (elapsed > budget_ns) {
      over_budget.fetch_add(1, std::memory_order_relaxed);
    }
  }
};

bool load_wav_pcm16(const char* path, WavPcm* wav) {
  if (path == nullptr || path[0] == '\0') return false;
  std::ifstream file(path, std::ios::binary | std::ios::ate);
  if (!file) return false;
  const std::streamoff length = file.tellg();
  if (length < 44 || length > kMaxWavBytes) return false;
  std::vector<uint8_t> bytes(static_cast<size_t>(length));
  file.seekg(0);
  if (!file.read(reinterpret_cast<char*>(bytes.data()), length)) return false;
  if (std::memcmp(bytes.data(), "RIFF", 4) != 0 ||
      std::memcmp(bytes.data() + 8, "WAVE", 4) != 0) {
    return false;
  }
  const size_t riff_end = static_cast<size_t>(read_u32(bytes.data() + 4)) + 8;
  if (riff_end > bytes.size() || riff_end < 44) return false;

  const uint8_t* format = nullptr;
  const uint8_t* audio = nullptr;
  uint32_t audio_bytes = 0;
  for (size_t offset = 12; offset + 8 <= riff_end;) {
    const uint8_t* chunk = bytes.data() + offset;
    const uint32_t chunk_bytes = read_u32(chunk + 4);
    offset += 8;
    if (chunk_bytes > riff_end - offset) return false;
    if (std::memcmp(chunk, "fmt ", 4) == 0 && chunk_bytes >= 16) {
      format = bytes.data() + offset;
    } else if (std::memcmp(chunk, "data", 4) == 0 && audio == nullptr) {
      audio = bytes.data() + offset;
      audio_bytes = chunk_bytes;
    }
    offset += chunk_bytes;
    if (chunk_bytes & 1U) ++offset;
    if (offset > riff_end) return false;
  }
  if (format == nullptr || audio == nullptr) return false;
  const int32_t channels = read_u16(format + 2);
  const int32_t sample_rate = static_cast<int32_t>(read_u32(format + 4));
  const int32_t block_align = read_u16(format + 12);
  if (read_u16(format) != 1 || channels < 1 || channels > 2 ||
      sample_rate < 8000 || sample_rate > 192000 ||
      block_align != channels * 2 || read_u16(format + 14) != 16 ||
      audio_bytes == 0 || audio_bytes % block_align != 0) {
    return false;
  }

  wav->sample_rate = sample_rate;
  wav->channels = channels;
  wav->samples.resize(audio_bytes / 2);
  for (size_t index = 0; index < wav->samples.size(); ++index) {
    int32_t value = read_u16(audio + index * 2);
    if (value >= 32768) value -= 65536;
    wav->samples[index] = static_cast<float>(value) / 32768.0f;
  }
  return true;
}

#ifdef TRANSPOSE_RUBBERBAND_INTERNAL_SPIKE
void write_u16(uint8_t* target, uint16_t value) {
  target[0] = static_cast<uint8_t>(value);
  target[1] = static_cast<uint8_t>(value >> 8);
}

void write_u32(uint8_t* target, uint32_t value) {
  for (int shift = 0; shift < 32; shift += 8) {
    target[shift / 8] = static_cast<uint8_t>(value >> shift);
  }
}

bool save_wav_pcm16(const char* path, const WavPcm& wav) {
  if (wav.samples.empty() || wav.samples.size() > 32 * 1024 * 1024 ||
      wav.channels < 1 || wav.channels > 2 ||
      wav.samples.size() % wav.channels != 0) {
    return false;
  }
  const uint32_t data_bytes = static_cast<uint32_t>(wav.samples.size() * 2);
  std::array<uint8_t, 44> header{};
  std::memcpy(header.data(), "RIFF", 4);
  write_u32(header.data() + 4, data_bytes + 36);
  std::memcpy(header.data() + 8, "WAVEfmt ", 8);
  write_u32(header.data() + 16, 16);
  write_u16(header.data() + 20, 1);
  write_u16(header.data() + 22, static_cast<uint16_t>(wav.channels));
  write_u32(header.data() + 24, static_cast<uint32_t>(wav.sample_rate));
  write_u32(header.data() + 28,
            static_cast<uint32_t>(wav.sample_rate * wav.channels * 2));
  write_u16(header.data() + 32, static_cast<uint16_t>(wav.channels * 2));
  write_u16(header.data() + 34, 16);
  std::memcpy(header.data() + 36, "data", 4);
  write_u32(header.data() + 40, data_bytes);

  std::ofstream file(path, std::ios::binary | std::ios::trunc);
  if (!file.write(reinterpret_cast<const char*>(header.data()), header.size())) {
    return false;
  }
  std::array<uint8_t, 8192> chunk{};
  size_t offset = 0;
  while (offset < wav.samples.size()) {
    const size_t count = std::min(chunk.size() / 2, wav.samples.size() - offset);
    for (size_t index = 0; index < count; ++index) {
      const float bounded = std::clamp(wav.samples[offset + index], -1.0f,
                                       32767.0f / 32768.0f);
      const int32_t pcm = static_cast<int32_t>(std::lrint(bounded * 32768.0f));
      write_u16(chunk.data() + index * 2, static_cast<uint16_t>(pcm));
    }
    if (!file.write(reinterpret_cast<const char*>(chunk.data()), count * 2)) {
      return false;
    }
    offset += count;
  }
  return static_cast<bool>(file.flush());
}

int32_t render_wav_dsp(const char* input_path, const char* output_path,
                       double semitones, double speed, int32_t finer) {
  if (input_path == nullptr || output_path == nullptr ||
      input_path[0] == '\0' || output_path[0] == '\0' ||
      std::strcmp(input_path, output_path) == 0 || !std::isfinite(semitones) ||
      !std::isfinite(speed) || semitones < -12.0 || semitones > 12.0 ||
      speed < 0.5 || speed > 2.0 || (finer != 0 && finer != 1)) {
    return -1;
  }
  WavPcm input;
  if (!load_wav_pcm16(input_path, &input)) return -2;
  std::unique_ptr<DspProcessor> processor =
      std::make_unique<RubberBandProcessor>(input.sample_rate, input.channels,
                                            semitones, speed, finer != 0);
  WavPcm output;
  output.sample_rate = input.sample_rate;
  output.channels = input.channels;
  constexpr size_t kBlock = 512;
  std::array<float, kBlock> input_left{};
  std::array<float, kBlock> input_right{};
  std::array<float, kBlock> output_left{};
  std::array<float, kBlock> output_right{};
  const float* input_planes[2] = {input_left.data(), input_right.data()};
  float* output_planes[2] = {output_left.data(), output_right.data()};
  size_t trim = processor->start_delay();

  const auto pump = [&](size_t frames, bool final) -> bool {
    processor->process(input_planes, frames, final);
    for (int available = processor->available(); available > 0;
         available = processor->available()) {
      const size_t count = std::min(static_cast<size_t>(available), kBlock);
      const size_t retrieved = processor->retrieve(output_planes, count);
      if (retrieved == 0) break;
      for (size_t frame = 0; frame < retrieved; ++frame) {
        if (trim > 0) {
          --trim;
          continue;
        }
        if (output.samples.size() + input.channels > 32 * 1024 * 1024) {
          return false;
        }
        output.samples.push_back(output_left[frame]);
        if (input.channels == 2) output.samples.push_back(output_right[frame]);
      }
    }
    return true;
  };

  size_t pad = processor->start_pad();
  while (pad > 0) {
    const size_t count = std::min(pad, kBlock);
    if (!pump(count, false)) return -3;
    pad -= count;
  }
  const size_t total_frames = input.samples.size() / input.channels;
  for (size_t cursor = 0; cursor < total_frames;) {
    const size_t count = std::min(kBlock, total_frames - cursor);
    for (size_t frame = 0; frame < count; ++frame) {
      input_left[frame] = input.samples[(cursor + frame) * input.channels];
      if (input.channels == 2) {
        input_right[frame] = input.samples[(cursor + frame) * input.channels + 1];
      }
    }
    cursor += count;
    if (!pump(count, cursor == total_frames)) return -3;
  }
  if (output.samples.empty() || !save_wav_pcm16(output_path, output)) return -4;
  return 0;
}
#endif

class ToneCallback final : public oboe::AudioStreamDataCallback {
 public:
  explicit ToneCallback(CallbackMetrics* metrics) : metrics_(metrics) {
    for (int32_t index = 0; index <= kTableSize; ++index) {
      table_[index] = std::sin(kTwoPi * static_cast<float>(index) /
                               static_cast<float>(kTableSize));
    }
  }

  oboe::DataCallbackResult onAudioReady(oboe::AudioStream* stream,
                                        void* audio_data,
                                        int32_t num_frames) override {
    const auto started = std::chrono::steady_clock::now();
    // Real-time path: no allocation, lock, I/O, logging or Dart callback.
    auto* output = static_cast<float*>(audio_data);
    const int32_t channels = stream->getChannelCount();
    const float step = static_cast<float>(kTableSize) * kFrequency /
                       static_cast<float>(stream->getSampleRate());
    float phase = phase_;
    for (int32_t frame = 0; frame < num_frames; ++frame) {
      const int32_t index = static_cast<int32_t>(phase);
      const float fraction = phase - static_cast<float>(index);
      const float sample = kAmplitude *
                           (table_[index] +
                            (table_[index + 1] - table_[index]) * fraction);
      for (int32_t channel = 0; channel < channels; ++channel) {
        output[frame * channels + channel] = sample;
      }
      phase += step;
      if (phase >= static_cast<float>(kTableSize)) {
        phase -= static_cast<float>(kTableSize);
      }
    }
    phase_ = phase;
    frames_.fetch_add(num_frames, std::memory_order_relaxed);
    metrics_->observe(started, num_frames, stream->getSampleRate());
    return oboe::DataCallbackResult::Continue;
  }

  int64_t frames() const { return frames_.load(std::memory_order_relaxed); }

 private:
  static constexpr int32_t kTableSize = 2048;
  CallbackMetrics* const metrics_;
  std::array<float, kTableSize + 1> table_{};
  std::atomic<int64_t> frames_{0};
  float phase_ = 0.0f;
};

class WavCallback final : public oboe::AudioStreamDataCallback {
 public:
  WavCallback(WavPcm wav, CallbackMetrics* metrics)
      : wav_(std::move(wav)), metrics_(metrics) {}

  oboe::DataCallbackResult onAudioReady(oboe::AudioStream* stream,
                                        void* audio_data,
                                        int32_t num_frames) override {
    const auto started = std::chrono::steady_clock::now();
    // PCM is decoded before opening the stream; this path performs no I/O,
    // allocation, locking, logging or calls into Dart.
    auto* output = static_cast<float*>(audio_data);
    const int32_t output_channels = stream->getChannelCount();
    const size_t total_frames = wav_.samples.size() / wav_.channels;
    const size_t remaining = total_frames - cursor_;
    const size_t copy_frames =
        remaining < static_cast<size_t>(num_frames) ? remaining : num_frames;
    for (size_t frame = 0; frame < copy_frames; ++frame) {
      for (int32_t channel = 0; channel < output_channels; ++channel) {
        const int32_t source_channel =
            channel < wav_.channels ? channel : wav_.channels - 1;
        output[frame * output_channels + channel] =
            wav_.samples[(cursor_ + frame) * wav_.channels + source_channel];
      }
    }
    for (size_t frame = copy_frames; frame < static_cast<size_t>(num_frames);
         ++frame) {
      for (int32_t channel = 0; channel < output_channels; ++channel) {
        output[frame * output_channels + channel] = 0.0f;
      }
    }
    cursor_ += copy_frames;
    rendered_.store(static_cast<int64_t>(cursor_), std::memory_order_relaxed);
    metrics_->observe(started, num_frames, stream->getSampleRate());
    if (cursor_ == total_frames) {
      finished_.store(true, std::memory_order_release);
      return oboe::DataCallbackResult::Stop;
    }
    return oboe::DataCallbackResult::Continue;
  }

  int64_t rendered() const {
    return rendered_.load(std::memory_order_relaxed);
  }
  bool finished() const { return finished_.load(std::memory_order_acquire); }
  int32_t sample_rate() const { return wav_.sample_rate; }

 private:
  const WavPcm wav_;
  CallbackMetrics* const metrics_;
  size_t cursor_ = 0;
  std::atomic<int64_t> rendered_{0};
  std::atomic<bool> finished_{false};
};

#ifdef TRANSPOSE_RUBBERBAND_INTERNAL_SPIKE
// Single producer (DSP worker), single consumer (Oboe callback). The ring and
// source PCM are allocated before the audio stream is opened.
class LiveDspCallback final : public oboe::AudioStreamDataCallback {
 public:
  LiveDspCallback(WavPcm wav, CallbackMetrics* metrics, double semitones,
                  double speed, bool finer)
      : wav_(std::move(wav)), metrics_(metrics), semitones_(semitones),
        speed_(speed), finer_(finer), ring_(kCapacity * 2) {}

  ~LiveDspCallback() override { stop_worker(); }

  int32_t sample_rate() const { return wav_.sample_rate; }
  int64_t frames() const { return frames_.load(std::memory_order_relaxed); }
  bool finished() const { return finished_.load(std::memory_order_acquire); }
  int64_t underruns() const {
    return underruns_.load(std::memory_order_relaxed);
  }

  void start_worker() { worker_ = std::thread([this] { produce(); }); }

  bool wait_for_prebuffer() const {
    const auto deadline = std::chrono::steady_clock::now() +
                          std::chrono::seconds(3);
    while (std::chrono::steady_clock::now() < deadline) {
      if (write_.load(std::memory_order_acquire) >= 4096) return true;
      if (producer_done_.load(std::memory_order_acquire)) {
        return write_.load(std::memory_order_acquire) > 0 &&
               !failed_.load(std::memory_order_acquire);
      }
      std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
    return false;
  }

  void stop_worker() {
    cancelled_.store(true, std::memory_order_release);
    if (worker_.joinable()) worker_.join();
  }

  oboe::DataCallbackResult onAudioReady(oboe::AudioStream* stream,
                                        void* audio_data,
                                        int32_t num_frames) override {
    const auto started = std::chrono::steady_clock::now();
    auto* output = static_cast<float*>(audio_data);
    const int32_t channels = stream->getChannelCount();
    uint64_t read = read_.load(std::memory_order_relaxed);
    const uint64_t write = write_.load(std::memory_order_acquire);
    bool empty = false;
    for (int32_t frame = 0; frame < num_frames; ++frame) {
      float left = 0.0f;
      float right = 0.0f;
      if (read < write) {
        const size_t slot = static_cast<size_t>(read % kCapacity) * 2;
        left = ring_[slot];
        right = ring_[slot + 1];
        ++read;
      } else {
        empty = true;
      }
      for (int32_t channel = 0; channel < channels; ++channel) {
        output[frame * channels + channel] = channel == 0 ? left : right;
      }
    }
    read_.store(read, std::memory_order_release);
    frames_.store(static_cast<int64_t>(read), std::memory_order_relaxed);
    const bool done = producer_done_.load(std::memory_order_acquire);
    if (empty && !done) underruns_.fetch_add(1, std::memory_order_relaxed);
    metrics_->observe(started, num_frames, stream->getSampleRate());
    if (done && read == write_.load(std::memory_order_acquire)) {
      finished_.store(true, std::memory_order_release);
      return oboe::DataCallbackResult::Stop;
    }
    return oboe::DataCallbackResult::Continue;
  }

 private:
  static constexpr size_t kBlock = 512;
  static constexpr uint64_t kCapacity = 48000;

  bool push(float left, float right) {
    uint64_t write = write_.load(std::memory_order_relaxed);
    while (write - read_.load(std::memory_order_acquire) >= kCapacity) {
      if (cancelled_.load(std::memory_order_acquire)) return false;
      std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
    if (cancelled_.load(std::memory_order_acquire)) return false;
    const size_t slot = static_cast<size_t>(write % kCapacity) * 2;
    ring_[slot] = left;
    ring_[slot + 1] = right;
    write_.store(write + 1, std::memory_order_release);
    return true;
  }

  void produce() {
    try {
      RubberBandProcessor processor(wav_.sample_rate, wav_.channels,
                                    semitones_, speed_, finer_);
      std::array<float, kBlock> input_left{};
      std::array<float, kBlock> input_right{};
      std::array<float, kBlock> output_left{};
      std::array<float, kBlock> output_right{};
      const float* input_planes[2] = {input_left.data(), input_right.data()};
      float* output_planes[2] = {output_left.data(), output_right.data()};
      size_t trim = processor.start_delay();
      const auto pump = [&](size_t count, bool final) -> bool {
        processor.process(input_planes, count, final);
        for (int available = processor.available(); available > 0;
             available = processor.available()) {
          const size_t take = std::min(static_cast<size_t>(available), kBlock);
          const size_t got = processor.retrieve(output_planes, take);
          if (got == 0) break;
          for (size_t frame = 0; frame < got; ++frame) {
            if (trim > 0) {
              --trim;
              continue;
            }
            if (!push(output_left[frame], wav_.channels == 2
                                              ? output_right[frame]
                                              : output_left[frame])) return false;
          }
        }
        return true;
      };
      size_t pad = processor.start_pad();
      while (pad > 0 && !cancelled_.load(std::memory_order_acquire)) {
        const size_t count = std::min(pad, kBlock);
        if (!pump(count, false)) break;
        pad -= count;
      }
      const size_t total = wav_.samples.size() / wav_.channels;
      for (size_t cursor = 0;
           cursor < total && !cancelled_.load(std::memory_order_acquire);) {
        const size_t count = std::min(kBlock, total - cursor);
        for (size_t frame = 0; frame < count; ++frame) {
          input_left[frame] = wav_.samples[(cursor + frame) * wav_.channels];
          if (wav_.channels == 2) {
            input_right[frame] =
                wav_.samples[(cursor + frame) * wav_.channels + 1];
          }
        }
        cursor += count;
        if (!pump(count, cursor == total)) break;
      }
    } catch (...) {
      failed_.store(true, std::memory_order_release);
    }
    producer_done_.store(true, std::memory_order_release);
  }

  const WavPcm wav_;
  CallbackMetrics* const metrics_;
  const double semitones_;
  const double speed_;
  const bool finer_;
  std::vector<float> ring_;
  std::thread worker_;
  std::atomic<uint64_t> read_{0};
  std::atomic<uint64_t> write_{0};
  std::atomic<int64_t> frames_{0};
  std::atomic<int64_t> underruns_{0};
  std::atomic<bool> cancelled_{false};
  std::atomic<bool> producer_done_{false};
  std::atomic<bool> failed_{false};
  std::atomic<bool> finished_{false};
};
#endif

struct AudioCoreHandleState {
  int32_t magic = kMagic;
  std::mutex control_mutex;
  CallbackMetrics metrics;
  std::shared_ptr<ToneCallback> callback =
      std::make_shared<ToneCallback>(&metrics);
  std::shared_ptr<WavCallback> wav_callback;
#ifdef TRANSPOSE_RUBBERBAND_INTERNAL_SPIKE
  std::shared_ptr<LiveDspCallback> live_callback;
#endif
  std::shared_ptr<oboe::AudioStream> stream;
  int32_t last_sample_rate = 0;
  int32_t last_burst_frames = 0;
  int32_t last_buffer_frames = 0;
  int32_t last_xruns = -1;
  int32_t buffer_bursts = 2;
};

AudioCoreHandleState* checked(ACHandle handle) {
  auto* state = static_cast<AudioCoreHandleState*>(handle);
  return state != nullptr && state->magic == kMagic ? state : nullptr;
}

int32_t open_output(AudioCoreHandleState* state,
                    oboe::AudioStreamDataCallback* callback,
                    int32_t sample_rate) {
  oboe::AudioStreamBuilder builder;
  builder.setDirection(oboe::Direction::Output)
      ->setPerformanceMode(oboe::PerformanceMode::LowLatency)
      ->setSharingMode(oboe::SharingMode::Shared)
      ->setFormat(oboe::AudioFormat::Float)
      ->setChannelCount(oboe::ChannelCount::Stereo)
      ->setDataCallback(callback);
  if (sample_rate > 0) builder.setSampleRate(sample_rate);
  std::shared_ptr<oboe::AudioStream> stream;
  if (builder.openStream(stream) != oboe::Result::OK || stream == nullptr) {
    return -2;
  }
  if (sample_rate > 0 && stream->getSampleRate() != sample_rate) {
    stream->close();
    return -4;  // No implicit resampling in this diagnostic path.
  }
  const int32_t burst_frames = stream->getFramesPerBurst();
  stream->setBufferSizeInFrames(state->buffer_bursts * burst_frames);
  state->last_sample_rate = stream->getSampleRate();
  state->last_burst_frames = burst_frames;
  state->last_buffer_frames = stream->getBufferSizeInFrames();
  if (stream->requestStart() != oboe::Result::OK) {
    stream->close();
    return -3;
  }
  state->stream = std::move(stream);
  return 0;
}
}  // namespace

extern "C" AC_EXPORT int32_t ac_abi_version(void) { return 6; }

extern "C" AC_EXPORT int32_t ac_dsp_available(void) {
#ifdef TRANSPOSE_RUBBERBAND_INTERNAL_SPIKE
  return 1;
#else
  return 0;
#endif
}

extern "C" AC_EXPORT int32_t ac_render_wav_dsp(const char* input_path,
                                                const char* output_path,
                                                double semitones,
                                                double speed,
                                                int32_t finer) {
#ifdef TRANSPOSE_RUBBERBAND_INTERNAL_SPIKE
  try {
    return render_wav_dsp(input_path, output_path, semitones, speed, finer);
  } catch (...) {
    return -6;
  }
#else
  (void)input_path;
  (void)output_path;
  (void)semitones;
  (void)speed;
  (void)finer;
  return -5;
#endif
}

extern "C" AC_EXPORT ACHandle ac_create(void) {
  return new (std::nothrow) AudioCoreHandleState();
}

extern "C" AC_EXPORT int32_t ac_ping(ACHandle handle, int32_t value) {
  if (checked(handle) == nullptr || value < 0 || value >= INT32_MAX) return -1;
  return value + 1;
}

extern "C" AC_EXPORT int32_t ac_set_buffer_bursts(ACHandle handle,
                                                    int32_t bursts) {
  auto* state = checked(handle);
  if (state == nullptr) return -1;
  if (bursts < 2 || bursts > 4) return -2;
  std::lock_guard<std::mutex> lock(state->control_mutex);
  if (state->stream != nullptr) return -3;
  state->buffer_bursts = bursts;
  return 0;
}

extern "C" AC_EXPORT int32_t ac_start_tone(ACHandle handle) {
  auto* state = checked(handle);
  if (state == nullptr) return -1;
  std::lock_guard<std::mutex> lock(state->control_mutex);
  if (state->stream != nullptr) {
    return state->wav_callback == nullptr
#ifdef TRANSPOSE_RUBBERBAND_INTERNAL_SPIKE
                   && state->live_callback == nullptr
#endif
               ? 0 : -3;
  }
  state->wav_callback.reset();
#ifdef TRANSPOSE_RUBBERBAND_INTERNAL_SPIKE
  state->live_callback.reset();
#endif
  state->metrics.reset();
  return open_output(state, state->callback.get(), 0);
}

extern "C" AC_EXPORT int32_t ac_start_wav(ACHandle handle, const char* path) {
  auto* state = checked(handle);
  if (state == nullptr) return -1;
  std::lock_guard<std::mutex> lock(state->control_mutex);
  if (state->stream != nullptr) return -3;
  state->wav_callback.reset();
#ifdef TRANSPOSE_RUBBERBAND_INTERNAL_SPIKE
  state->live_callback.reset();
#endif
  WavPcm wav;
  if (!load_wav_pcm16(path, &wav)) return -2;
  state->metrics.reset();
  state->wav_callback =
      std::make_shared<WavCallback>(std::move(wav), &state->metrics);
  const int32_t result =
      open_output(state, state->wav_callback.get(), state->wav_callback->sample_rate());
  if (result != 0) state->wav_callback.reset();
  return result;
}

extern "C" AC_EXPORT int32_t ac_start_live_dsp(ACHandle handle,
                                                const char* path,
                                                double semitones,
                                                double speed,
                                                int32_t finer) {
#ifdef TRANSPOSE_RUBBERBAND_INTERNAL_SPIKE
  auto* state = checked(handle);
  if (state == nullptr || !std::isfinite(semitones) || !std::isfinite(speed) ||
      semitones < -12.0 || semitones > 12.0 || speed < 0.5 || speed > 2.0 ||
      (finer != 0 && finer != 1)) return -1;
  std::lock_guard<std::mutex> lock(state->control_mutex);
  if (state->stream != nullptr) return -3;
  try {
    WavPcm wav;
    if (!load_wav_pcm16(path, &wav)) return -2;
    state->wav_callback.reset();
    state->live_callback.reset();
    state->metrics.reset();
    state->live_callback = std::make_shared<LiveDspCallback>(
        std::move(wav), &state->metrics, semitones, speed, finer != 0);
    state->live_callback->start_worker();
    if (!state->live_callback->wait_for_prebuffer()) {
      state->live_callback.reset();
      return -4;
    }
    const int32_t result = open_output(state, state->live_callback.get(),
                                       state->live_callback->sample_rate());
    if (result != 0) state->live_callback.reset();
    return result;
  } catch (...) {
    state->live_callback.reset();
    return -6;
  }
#else
  (void)handle; (void)path; (void)semitones; (void)speed; (void)finer;
  return -5;
#endif
}

extern "C" AC_EXPORT int64_t ac_live_frames(ACHandle handle) {
#ifdef TRANSPOSE_RUBBERBAND_INTERNAL_SPIKE
  auto* state = checked(handle);
  if (state == nullptr) return -1;
  std::lock_guard<std::mutex> lock(state->control_mutex);
  return state->live_callback ? state->live_callback->frames() : -1;
#else
  (void)handle; return -5;
#endif
}

extern "C" AC_EXPORT int32_t ac_live_finished(ACHandle handle) {
#ifdef TRANSPOSE_RUBBERBAND_INTERNAL_SPIKE
  auto* state = checked(handle);
  if (state == nullptr) return -1;
  std::lock_guard<std::mutex> lock(state->control_mutex);
  return state->live_callback && state->live_callback->finished() ? 1 : 0;
#else
  (void)handle; return -5;
#endif
}

extern "C" AC_EXPORT int64_t ac_live_queue_underruns(ACHandle handle) {
#ifdef TRANSPOSE_RUBBERBAND_INTERNAL_SPIKE
  auto* state = checked(handle);
  if (state == nullptr) return -1;
  std::lock_guard<std::mutex> lock(state->control_mutex);
  return state->live_callback ? state->live_callback->underruns() : -1;
#else
  (void)handle; return -5;
#endif
}

extern "C" AC_EXPORT int64_t ac_wav_frames(ACHandle handle) {
  auto* state = checked(handle);
  if (state == nullptr) return -1;
  std::lock_guard<std::mutex> lock(state->control_mutex);
  return state->wav_callback == nullptr ? -1 : state->wav_callback->rendered();
}

extern "C" AC_EXPORT int32_t ac_wav_finished(ACHandle handle) {
  auto* state = checked(handle);
  if (state == nullptr) return -1;
  std::lock_guard<std::mutex> lock(state->control_mutex);
  return state->wav_callback != nullptr && state->wav_callback->finished() ? 1 : 0;
}

extern "C" AC_EXPORT int64_t ac_callback_calls(ACHandle handle) {
  auto* state = checked(handle);
  return state == nullptr ? -1 :
      state->metrics.calls.load(std::memory_order_relaxed);
}

extern "C" AC_EXPORT int64_t ac_callback_max_us(ACHandle handle) {
  auto* state = checked(handle);
  if (state == nullptr) return -1;
  const int64_t nanoseconds =
      state->metrics.max_ns.load(std::memory_order_relaxed);
  return (nanoseconds + 999) / 1000;
}

extern "C" AC_EXPORT int64_t ac_callback_over_budget(ACHandle handle) {
  auto* state = checked(handle);
  return state == nullptr ? -1 :
      state->metrics.over_budget.load(std::memory_order_relaxed);
}

extern "C" AC_EXPORT int32_t ac_stop_tone(ACHandle handle) {
  auto* state = checked(handle);
  if (state == nullptr) return -1;
  std::lock_guard<std::mutex> lock(state->control_mutex);
  if (state->stream == nullptr) {
#ifdef TRANSPOSE_RUBBERBAND_INTERNAL_SPIKE
    if (state->live_callback) state->live_callback->stop_worker();
#endif
    return 0;
  }
  const auto count = state->stream->getXRunCount();
  state->last_xruns = count ? count.value() : -1;
  state->stream->requestStop();
  const oboe::Result result = state->stream->close();
  state->stream.reset();
#ifdef TRANSPOSE_RUBBERBAND_INTERNAL_SPIKE
  if (state->live_callback) state->live_callback->stop_worker();
#endif
  return result == oboe::Result::OK ? 0 : -2;
}

extern "C" AC_EXPORT int64_t ac_tone_frames(ACHandle handle) {
  auto* state = checked(handle);
  return state == nullptr ? -1 : state->callback->frames();
}

extern "C" AC_EXPORT int32_t ac_tone_sample_rate(ACHandle handle) {
  auto* state = checked(handle);
  return state == nullptr ? -1 : state->last_sample_rate;
}

extern "C" AC_EXPORT int32_t ac_tone_burst_frames(ACHandle handle) {
  auto* state = checked(handle);
  return state == nullptr ? -1 : state->last_burst_frames;
}

extern "C" AC_EXPORT int32_t ac_tone_buffer_frames(ACHandle handle) {
  auto* state = checked(handle);
  return state == nullptr ? -1 : state->last_buffer_frames;
}

extern "C" AC_EXPORT int32_t ac_tone_xruns(ACHandle handle) {
  auto* state = checked(handle);
  if (state == nullptr) return -1;
  std::lock_guard<std::mutex> lock(state->control_mutex);
  if (state->stream == nullptr) return state->last_xruns;
  const auto count = state->stream->getXRunCount();
  return count ? count.value() : -1;
}

extern "C" AC_EXPORT void ac_destroy(ACHandle handle) {
  auto* state = checked(handle);
  if (state == nullptr) return;
  ac_stop_tone(handle);
  state->magic = 0;
  delete state;
}
