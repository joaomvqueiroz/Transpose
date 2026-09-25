#ifndef TRANSPOSE_RUBBERBAND_PROCESSOR_H
#define TRANSPOSE_RUBBERBAND_PROCESSOR_H

#include "dsp_processor.h"

#include <rubberband/RubberBandStretcher.h>

class RubberBandProcessor final : public DspProcessor {
 public:
  RubberBandProcessor(size_t sample_rate, size_t channels, double semitones,
                      double speed, bool finer);

  size_t start_pad() const override;
  size_t start_delay() const override;
  void process(const float* const* input, size_t frames, bool final) override;
  int available() const override;
  size_t retrieve(float* const* output, size_t frames) override;

 private:
  RubberBand::RubberBandStretcher stretcher_;
};

#endif
