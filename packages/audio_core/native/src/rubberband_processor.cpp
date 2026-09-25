#include "rubberband_processor.h"

#include <cmath>

namespace {
RubberBand::RubberBandStretcher::Options options(bool finer) {
  return RubberBand::RubberBandStretcher::OptionProcessRealTime |
         RubberBand::RubberBandStretcher::OptionThreadingNever |
         (finer ? RubberBand::RubberBandStretcher::OptionEngineFiner
                : RubberBand::RubberBandStretcher::OptionEngineFaster);
}
}  // namespace

RubberBandProcessor::RubberBandProcessor(size_t sample_rate, size_t channels,
                                         double semitones, double speed,
                                         bool finer)
    : stretcher_(sample_rate, channels, options(finer), 1.0 / speed,
                 std::pow(2.0, semitones / 12.0)) {
  stretcher_.setMaxProcessSize(512);
}

size_t RubberBandProcessor::start_pad() const {
  return stretcher_.getPreferredStartPad();
}

size_t RubberBandProcessor::start_delay() const {
  return stretcher_.getStartDelay();
}

void RubberBandProcessor::process(const float* const* input, size_t frames,
                                  bool final) {
  stretcher_.process(input, frames, final);
}

int RubberBandProcessor::available() const { return stretcher_.available(); }

size_t RubberBandProcessor::retrieve(float* const* output, size_t frames) {
  return stretcher_.retrieve(output, frames);
}
