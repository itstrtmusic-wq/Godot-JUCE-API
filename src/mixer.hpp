#pragma once
#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <vector>
#include "eq.hpp"

namespace bridge {
constexpr int max_tracks = 16;
constexpr double pi = 3.14159265358979323846;
struct Clip {
 std::array<std::vector<float>, 2> samples;
 double rate = 48000;
 int channels = 0;
 double duration() const { return channels ? samples[0].size() / rate : 0; }
};
struct Track {
 Clip clip;
 Equalizer eq;
 double offset = 0; // Only changed with audio callback detached.
 std::atomic<float> volume{1}, pan{0}, left{0}, right{0};
 std::atomic<bool> mute{false}, solo{false};
 float current_left = 0, current_right = 0;
 // Polyphase, 32-tap windowed-sinc lowpass for rate conversion.
 static constexpr int phases = 256, taps = 32;
 std::array<std::array<float, taps>, phases> kernel{};
 void prepare(double output_rate) {
  eq.prepare(output_rate);
  const double cutoff = 0.95 * std::min(1.0, output_rate / clip.rate);
  for (int p = 0; p < phases; ++p) {
   double sum = 0;
   for (int j = 0; j < taps; ++j) {
    const double x = j - (taps / 2 - 1) - static_cast<double>(p) / phases;
    const double sinc = std::abs(x) < 1e-12 ? cutoff : std::sin(pi * cutoff * x) / (pi * x);
    const double window = 0.5 + 0.5 * std::cos(pi * x / (taps / 2));
    kernel[p][j] = static_cast<float>(sinc * window);
    sum += kernel[p][j];
   }
   for (auto& value : kernel[p]) value /= static_cast<float>(sum);
  }
 }
 float sample(int channel, double frame, double output_rate) const {
  const auto& data = clip.samples[std::min(channel, clip.channels - 1)];
  const int base = std::min(static_cast<int>(frame), static_cast<int>(data.size()) - 1);
  const double fraction = frame - base;
  if (clip.rate == output_rate && fraction < 1e-7) return data[base];
  const int phase = std::clamp(static_cast<int>(fraction * phases), 0, phases - 1);
  float result = 0;
  for (int j = 0; j < taps; ++j) {
   const int index = base + j - (taps / 2 - 1);
   if (index >= 0 && index < static_cast<int>(data.size())) result += data[index] * kernel[phase][j];
  }
  return result;
 }
};

// The same renderer is used by the JUCE callback and hardware-independent tests.
// Public controls are main-thread only; render() has one audio-thread owner.
class Mixer {
 double cursor = 0, envelope = 0, pending_seek = -1;
 float current_master = 0.5f;
 static float move(float value, float target, float step) {
  return value + std::clamp(target - value, -step, step);
 }
public:
 std::array<Track, max_tracks> tracks;
 int count = 2;
 double rate = 48000;
 std::atomic<bool> playing{false};
 std::atomic<double> position{0}, seek_request{-1};
 std::atomic<float> master{0.5f}, left{0}, right{0};
 double duration() const {
  double end = 0;
  for (int t = 0; t < count; ++t) if (tracks[t].clip.channels) end = std::max(end, tracks[t].offset + tracks[t].clip.duration());
  return end;
 }
 void prepare(double output_rate) {
  rate = output_rate;
  for (int t = 0; t < count; ++t) tracks[t].prepare(rate);
 }
 void seek(double seconds) {
  if (std::isfinite(seconds)) seek_request.store(std::clamp(seconds, 0.0, duration()));
 }
 void stop() { playing.store(false); seek(0); }
 // Used only with callback detached after structural changes or shutdown.
 void reset(double seconds = 0) {
  cursor = std::clamp(seconds, 0.0, duration()); position.store(cursor);
  seek_request.store(-1); pending_seek = -1; envelope = 0;
  left.store(0); right.store(0);
  for (auto& track : tracks) { track.left.store(0); track.right.store(0); track.eq.reset(); }
 }
 void render(float* const* outputs, int channels, int frames) {
  for (int c = 0; c < channels; ++c) if (outputs[c]) std::fill_n(outputs[c], frames, 0.0f);
  const double request = seek_request.exchange(-1);
  if (request >= 0) pending_seek = request;
  const double end = duration();
  const float step = static_cast<float>(1.0 / (rate * 0.005));
  std::array<float, max_tracks> target_l{}, target_r{}, peak_l{}, peak_r{};
  bool any_solo = false;
  for (int t = 0; t < count; ++t) any_solo |= tracks[t].solo.load();
  for (int t = 0; t < count; ++t) {
   auto& track = tracks[t];
   track.eq.begin_block();
   float volume = track.mute.load() || (any_solo && !track.solo.load()) ? 0 : track.volume.load();
   const float pan = track.pan.load();
   target_l[t] = volume * static_cast<float>(pan > 0 ? std::cos(pan * pi / 2) : 1);
   target_r[t] = volume * static_cast<float>(pan < 0 ? std::cos(pan * pi / 2) : 1);
  }
  const float master_target = master.load();
  float master_l = 0, master_r = 0;
  for (int i = 0; i < frames; ++i) {
   if (pending_seek >= 0 && envelope <= 0) {
    cursor = std::clamp(pending_seek, 0.0, end); pending_seek = -1;
    for(int t=0;t<count;++t) tracks[t].eq.reset();
   }
   if (cursor >= end && pending_seek >= 0) { cursor = std::clamp(pending_seek, 0.0, end); pending_seek = -1; envelope = 0; for(int t=0;t<count;++t) tracks[t].eq.reset(); }
   if (cursor >= end) playing.store(false);
   const bool active = playing.load();
   const float target = active && pending_seek < 0 ? 1.0f : 0.0f;
   envelope = move(static_cast<float>(envelope), target, step);
   current_master = move(current_master, master_target, step);
   float mixed_l = 0, mixed_r = 0;
   for (int t = 0; t < count; ++t) {
    auto& track = tracks[t];
    track.current_left = move(track.current_left, target_l[t], step);
    track.current_right = move(track.current_right, target_r[t], step);
    const double local = cursor - track.offset;
    if (!track.clip.channels || local < 0 || local >= track.clip.duration() || envelope <= 0) { track.eq.reset(); continue; }
    // Short clip-edge fades also soften boundaries when clips start at different offsets.
    const float edge = static_cast<float>(std::clamp(std::min(local, track.clip.duration() - local) / 0.005, 0.0, 1.0));
    const double frame = local * track.clip.rate;
    const auto filtered = track.eq.process(track.sample(0, frame, rate)*edge, track.sample(1, frame, rate)*edge);
    const float l = filtered[0] * track.current_left * static_cast<float>(envelope);
    const float r = filtered[1] * track.current_right * static_cast<float>(envelope);
    mixed_l += l; mixed_r += r;
    peak_l[t] = std::max(peak_l[t], std::abs(l)); peak_r[t] = std::max(peak_r[t], std::abs(r));
   }
   mixed_l *= current_master; mixed_r *= current_master;
   master_l = std::max(master_l, std::abs(mixed_l)); master_r = std::max(master_r, std::abs(mixed_r));
   // Safety ceiling for summed tracks. Meter values above one still expose clipping.
   if (channels > 0 && outputs[0]) outputs[0][i] = std::clamp(mixed_l, -1.0f, 1.0f);
   if (channels > 1 && outputs[1]) outputs[1][i] = std::clamp(mixed_r, -1.0f, 1.0f);
   if (active || envelope > 0) cursor = std::min(end, cursor + 1.0 / rate);
  }
  if (cursor >= end) playing.store(false);
  // A paused seek/stop is completed within this block once its fade has ended.
  if (pending_seek >= 0 && envelope <= 0) { cursor = std::clamp(pending_seek, 0.0, end); pending_seek = -1; for(int t=0;t<count;++t) tracks[t].eq.reset(); }
  position.store(cursor); left.store(master_l); right.store(master_r);
  for (int t = 0; t < count; ++t) { tracks[t].left.store(peak_l[t]); tracks[t].right.store(peak_r[t]); }
 }
};
}
