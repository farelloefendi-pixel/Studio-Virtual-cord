#include <essentia/algorithmfactory.h>
#include <essentia/essentiamath.h>

#include <cmath>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <memory>
#include <string>
#include <vector>

namespace {
constexpr int kSampleRate = 44100;
constexpr double kMinTempo = 45.0;
constexpr double kMaxTempo = 220.0;

bool readFloatPcm(const std::string& path, std::vector<essentia::Real>& audio,
                  std::string& error) {
  std::ifstream input(path, std::ios::binary | std::ios::ate);
  if (!input) {
    error = "cannot_open_input";
    return false;
  }

  const std::streamsize bytes = input.tellg();
  if (bytes <= 0 || bytes % static_cast<std::streamsize>(sizeof(float)) != 0) {
    error = "invalid_pcm_size";
    return false;
  }
  input.seekg(0, std::ios::beg);

  const std::size_t count = static_cast<std::size_t>(bytes / sizeof(float));
  std::vector<float> raw(count);
  if (!input.read(reinterpret_cast<char*>(raw.data()), bytes)) {
    error = "cannot_read_input";
    return false;
  }

  audio.reserve(count);
  for (float sample : raw) {
    if (!std::isfinite(sample)) {
      error = "non_finite_sample";
      return false;
    }
    audio.push_back(static_cast<essentia::Real>(sample));
  }
  if (audio.size() < static_cast<std::size_t>(kSampleRate * 8)) {
    error = "audio_too_short";
    return false;
  }
  return true;
}

void printError(const std::string& code) {
  std::cout << "{\"ok\":false,\"error\":\"" << code << "\"}\n";
}
}  // namespace

int main(int argc, char** argv) {
  if (argc != 2) {
    printError("usage: essentia_tempo <mono_float32le_44100_pcm>");
    return 2;
  }

  std::vector<essentia::Real> audio;
  std::string error;
  if (!readFloatPcm(argv[1], audio, error)) {
    printError(error);
    return 3;
  }

  try {
    essentia::init();
    auto& factory = essentia::standard::AlgorithmFactory::instance();
    std::unique_ptr<essentia::standard::Algorithm> rhythm(
        factory.create("RhythmExtractor2013", "method", std::string("multifeature"),
                       "minTempo", static_cast<int>(kMinTempo),
                       "maxTempo", static_cast<int>(kMaxTempo)));

    essentia::Real bpm = 0.0f;
    essentia::Real confidence = 0.0f;
    std::vector<essentia::Real> ticks;
    std::vector<essentia::Real> estimates;
    std::vector<essentia::Real> intervals;

    rhythm->input("signal").set(audio);
    rhythm->output("bpm").set(bpm);
    rhythm->output("ticks").set(ticks);
    rhythm->output("confidence").set(confidence);
    rhythm->output("estimates").set(estimates);
    rhythm->output("bpmIntervals").set(intervals);
    rhythm->compute();

    if (!std::isfinite(bpm) || bpm < kMinTempo || bpm > kMaxTempo) {
      rhythm.reset();
      essentia::shutdown();
      printError("tempo_out_of_range");
      return 4;
    }

    std::cout << std::fixed << std::setprecision(4);
    std::cout << "{\"ok\":true,\"engine\":\"Essentia\",\"algorithm\":\"RhythmExtractor2013\","
              << "\"method\":\"multifeature\",\"sample_rate\":" << kSampleRate
              << ",\"bpm\":" << bpm << ",\"confidence\":" << confidence
              << ",\"duration_seconds\":"
              << static_cast<double>(audio.size()) / kSampleRate << ",\"ticks\":[";
    for (std::size_t i = 0; i < ticks.size(); ++i) {
      if (i) std::cout << ',';
      std::cout << ticks[i];
    }
    std::cout << "],\"estimates\":[";
    for (std::size_t i = 0; i < estimates.size(); ++i) {
      if (i) std::cout << ',';
      std::cout << estimates[i];
    }
    std::cout << "],\"beat_intervals\":[";
    for (std::size_t i = 0; i < intervals.size(); ++i) {
      if (i) std::cout << ',';
      std::cout << intervals[i];
    }
    std::cout << "]}\n";

    rhythm.reset();
    essentia::shutdown();
    return 0;
  } catch (const std::exception&) {
    essentia::shutdown();
    printError("essentia_analysis_failed");
    return 5;
  }
}
