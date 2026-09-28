#include "model.hpp"
#include <chrono>
#include <cmath>
#include <fstream>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <sys/resource.h>

int main(int argc, char** argv) {
  if (argc < 2 || argc > 3) {
    std::cerr << "Usage: transpono_stems_probe <verified-6s-model> [seconds: 1-12]\n";
    return 2;
  }
  try {
    const auto start = std::chrono::steady_clock::now();
    auto model = std::make_unique<demucscpp::demucs_model>();
    if (!demucscpp::load_demucs_model(argv[1], model.get()) || model->is_4sources)
      throw std::runtime_error("Six-source model unavailable");
    // Self-generated signal only: bass + harmonic pluck + transient noise.
    constexpr int rate = 44100;
    const int seconds = argc == 3 ? std::stoi(argv[2]) : 2;
    if (seconds < 1 || seconds > 12) throw std::runtime_error("Probe duration must be 1-12 seconds");
    const int frames = rate * seconds;
    Eigen::MatrixXf audio(2, frames);
    for (int i = 0; i < frames; ++i) {
      double t = i / double(rate), pulse = std::fmod(t, .5);
      double value = .12 * std::sin(2 * M_PI * 110 * t) +
          .12 * std::exp(-5 * pulse) * (std::sin(2 * M_PI * 330 * t) +
          .5 * std::sin(2 * M_PI * 660 * t)) +
          .04 * std::exp(-100 * pulse) * std::sin(2 * M_PI * 3301 * t);
      audio(0, i) = float(value); audio(1, i) = float(value * .9);
    }
    auto output = demucscpp::demucs_inference(*model, audio,
      [](float progress, const std::string& stage) {
        rusage usage{}; getrusage(RUSAGE_SELF, &usage);
        std::cerr << "TRANSPONO_STEMS_PROGRESS " << progress << " " << stage
                  << " peakRssKb=" << usage.ru_maxrss << std::endl;
      });
    if (output.dimension(0) != 6 || output.dimension(1) != 2 || output.dimension(2) != frames)
      throw std::runtime_error("Unexpected output shape");
    double energy[6] = {};
    for (int s = 0; s < 6; ++s) for (int c = 0; c < 2; ++c) for (int i = 0; i < frames; ++i) {
      const float value = output(s, c, i);
      if (!std::isfinite(value)) throw std::runtime_error("Non-finite stem output");
      energy[s] += value * value;
    }
    rusage usage{}; getrusage(RUSAGE_SELF, &usage);
    const double elapsed = std::chrono::duration<double>(std::chrono::steady_clock::now() - start).count();
    std::cerr << "TRANSPONO_STEMS_RESULT {\"passed\":true,\"inputSeconds\":" << seconds
              << ",\"seconds\":" << elapsed
              << ",\"peakRssKb\":" << usage.ru_maxrss << ",\"rms\":[";
    for (int s = 0; s < 6; ++s) { if(s) std::cerr << ','; std::cerr << std::sqrt(energy[s]/(frames*2)); }
    std::cerr << "]}" << std::endl;
    return 0;
  } catch (const std::exception& e) { std::cerr << "STEMS_ERROR " << e.what() << std::endl; return 1; }
}
