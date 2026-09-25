#ifndef TRANSPOSE_DSP_PROCESSOR_H
#define TRANSPOSE_DSP_PROCESSOR_H

#include <cstddef>

// Internal S-003 boundary. Audio data is planar float PCM; no Dart buffers
// or platform player types enter this interface.
class DspProcessor {
 public:
  virtual ~DspProcessor() = default;
  virtual size_t start_pad() const = 0;
  virtual size_t start_delay() const = 0;
  virtual void process(const float* const* input, size_t frames, bool final) = 0;
  virtual int available() const = 0;
  virtual size_t retrieve(float* const* output, size_t frames) = 0;
};

#endif
