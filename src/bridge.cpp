#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <juce_audio_devices/juce_audio_devices.h>
#include <juce_audio_formats/juce_audio_formats.h>
#include <atomic>
#include <cmath>
#include <memory>
#include <algorithm>

static_assert(std::atomic<float>::is_always_lock_free, "Audio atomics must be lock free");
static_assert(std::atomic<double>::is_always_lock_free, "Audio atomics must be lock free");
static_assert(std::atomic<bool>::is_always_lock_free, "Audio atomics must be lock free");

#include "mixer.hpp"

// All API methods run on Godot's main thread. Structural edits detach the callback.
class JuceEngine : public godot::RefCounted, private juce::AudioIODeviceCallback {
 GDCLASS(JuceEngine, godot::RefCounted)
 juce::AudioDeviceManager devices;
 bridge::Mixer mixer;
 bool attached = false;
 bool valid(int track) const { return track >= 0 && track < mixer.count; }
 void detach() { if (attached) { devices.removeAudioCallback(this); attached = false; } }
 void attach() { if (!attached && devices.getCurrentAudioDevice()) { devices.addAudioCallback(this); attached = true; } }
 void audioDeviceAboutToStart(juce::AudioIODevice* d) override { mixer.prepare(d->getCurrentSampleRate()); }
 void audioDeviceStopped() override { mixer.left.store(0); mixer.right.store(0); }
 void audioDeviceIOCallbackWithContext(const float* const*, int, float* const* out, int channels, int frames, const juce::AudioIODeviceCallbackContext&) override {
  mixer.render(out, channels, frames);
 }
protected:
 static void _bind_methods() {
  using namespace godot;
  ClassDB::bind_method(D_METHOD("initialize"), &JuceEngine::initialize);
  ClassDB::bind_method(D_METHOD("shutdown"), &JuceEngine::shutdown);
  ClassDB::bind_method(D_METHOD("get_output_devices"), &JuceEngine::get_output_devices);
  ClassDB::bind_method(D_METHOD("select_output_device", "name"), &JuceEngine::select_output_device);
  ClassDB::bind_method(D_METHOD("load_wav", "absolute_path"), &JuceEngine::load_wav);
  ClassDB::bind_method(D_METHOD("load_track_wav", "track", "absolute_path"), &JuceEngine::load_track_wav);
  ClassDB::bind_method(D_METHOD("add_track"), &JuceEngine::add_track);
  ClassDB::bind_method(D_METHOD("clear_track", "track"), &JuceEngine::clear_track);
  ClassDB::bind_method(D_METHOD("get_track_count"), &JuceEngine::get_track_count);
  ClassDB::bind_method(D_METHOD("get_track_duration", "track"), &JuceEngine::get_track_duration);
  ClassDB::bind_method(D_METHOD("get_track_offset", "track"), &JuceEngine::get_track_offset);
  ClassDB::bind_method(D_METHOD("set_track_offset", "track", "seconds"), &JuceEngine::set_track_offset);
  ClassDB::bind_method(D_METHOD("set_track_volume", "track", "linear_gain"), &JuceEngine::set_track_volume);
  ClassDB::bind_method(D_METHOD("set_track_pan", "track", "pan"), &JuceEngine::set_track_pan);
  ClassDB::bind_method(D_METHOD("set_track_mute", "track", "muted"), &JuceEngine::set_track_mute);
  ClassDB::bind_method(D_METHOD("set_track_solo", "track", "solo"), &JuceEngine::set_track_solo);
  ClassDB::bind_method(D_METHOD("set_track_eq_gain", "track", "band", "gain_db"), &JuceEngine::set_track_eq_gain);
  ClassDB::bind_method(D_METHOD("set_track_eq_bypassed", "track", "bypassed"), &JuceEngine::set_track_eq_bypassed);
  ClassDB::bind_method(D_METHOD("get_track_levels", "track"), &JuceEngine::get_track_levels);
  ClassDB::bind_method(D_METHOD("play"), &JuceEngine::play);
  ClassDB::bind_method(D_METHOD("pause"), &JuceEngine::pause);
  ClassDB::bind_method(D_METHOD("stop"), &JuceEngine::stop);
  ClassDB::bind_method(D_METHOD("seek", "seconds"), &JuceEngine::seek);
  ClassDB::bind_method(D_METHOD("set_volume", "linear_gain"), &JuceEngine::set_volume);
  ClassDB::bind_method(D_METHOD("get_position"), &JuceEngine::get_position);
  ClassDB::bind_method(D_METHOD("get_duration"), &JuceEngine::get_duration);
  ClassDB::bind_method(D_METHOD("is_playing"), &JuceEngine::is_playing);
  ClassDB::bind_method(D_METHOD("get_levels"), &JuceEngine::get_levels);
 }
public:
 ~JuceEngine() override { shutdown(); }
 godot::String initialize() {
  if(devices.getCurrentAudioDevice()) return {};
  auto error=devices.initialiseWithDefaultDevices(0,2);
  if(error.isEmpty()) attach();
  return godot::String(error.toRawUTF8());
 }
 void shutdown() { mixer.playing.store(false); detach(); devices.closeAudioDevice(); mixer.reset(); }
 godot::PackedStringArray get_output_devices() {
  godot::PackedStringArray result;
  if(auto* type=devices.getCurrentDeviceTypeObject()) {
   type->scanForDevices();
   for(auto& name:type->getDeviceNames(false)) result.append(godot::String(name.toRawUTF8()));
  }
  return result;
 }
 godot::String select_output_device(godot::String name) {
  if(!devices.getCurrentAudioDevice()) return "Initialize audio first.";
  juce::AudioDeviceManager::AudioDeviceSetup setup;
  devices.getAudioDeviceSetup(setup);
  setup.outputDeviceName=juce::String::fromUTF8(name.utf8().get_data());
  detach();
  auto error=devices.setAudioDeviceSetup(setup,true);
  attach();
  return godot::String(error.toRawUTF8());
 }
 int get_track_count() const { return mixer.count; }
 int add_track() {
  if(mixer.count >= bridge::max_tracks) return -1;
  detach();
  const int index=mixer.count++;
  attach();
  return index;
 }
 godot::String load_wav(godot::String path) { return load_track_wav(0,path); }
 godot::String load_track_wav(int track, godot::String path) {
  if(!valid(track)) return "Invalid track index.";
  juce::WavAudioFormat format;
  auto stream=juce::File(juce::String::fromUTF8(path.utf8().get_data())).createInputStream();
  if(!stream) return "Cannot open file. Pass an absolute filesystem path.";
  std::unique_ptr<juce::AudioFormatReader> reader(format.createReaderFor(stream.release(),true));
  if(!reader) return "Not a supported WAV file.";
  if(reader->numChannels<1 || reader->numChannels>2 || reader->lengthInSamples<=0 || reader->lengthInSamples>33554432 || !std::isfinite(reader->sampleRate) || reader->sampleRate<=0)
   return "WAV must be mono/stereo and at most 33,554,432 frames.";
  size_t bytes=static_cast<size_t>(reader->lengthInSamples)*reader->numChannels*sizeof(float);
  for(int t=0;t<mixer.count;++t) if(t!=track)
   for(const auto& channel:mixer.tracks[t].clip.samples) bytes+=channel.size()*sizeof(float);
  if(bytes>256u*1024u*1024u) return "Total decoded audio limit is 256 MiB. Clear a track first.";
  juce::AudioBuffer<float> decoded(static_cast<int>(reader->numChannels),static_cast<int>(reader->lengthInSamples));
  if(!reader->read(&decoded,0,decoded.getNumSamples(),0,true,true)) return "WAV decoding failed.";
  bridge::Clip next;
  next.rate=reader->sampleRate; next.channels=static_cast<int>(reader->numChannels);
  for(int c=0;c<next.channels;++c) next.samples[c].assign(decoded.getReadPointer(c),decoded.getReadPointer(c)+decoded.getNumSamples());
  detach();
  mixer.playing.store(false);
  mixer.tracks[track].clip=std::move(next);
  mixer.tracks[track].prepare(mixer.rate);
  mixer.reset();
  attach();
  return {};
 }
 godot::String clear_track(int track) {
  if(!valid(track)) return "Invalid track index.";
  detach(); mixer.playing.store(false);
  mixer.tracks[track].clip=bridge::Clip{};
  mixer.reset(); attach(); return {};
 }
 double get_track_duration(int track) const { return valid(track)?mixer.tracks[track].clip.duration():0; }
 double get_track_offset(int track) const { return valid(track)?mixer.tracks[track].offset:0; }
 godot::String set_track_offset(int track, double seconds) {
  if(!valid(track) || !std::isfinite(seconds) || seconds<0 || seconds>86400) return "Offset must be finite, between 0 and 86400 seconds, on a valid track.";
  detach(); mixer.playing.store(false); mixer.tracks[track].offset=seconds;
  mixer.reset(); attach(); return {};
 }
 void set_track_eq_gain(int track, int band, double db) {
  if(valid(track) && band>=0 && band<3 && std::isfinite(db))
   mixer.tracks[track].eq.gains[band].store(static_cast<float>(std::clamp(db,-18.0,18.0)));
 }
 void set_track_eq_bypassed(int track, bool value) { if(valid(track)) mixer.tracks[track].eq.bypassed.store(value); }
 void set_track_volume(int track, double value) { if(valid(track)&&std::isfinite(value)) mixer.tracks[track].volume.store(static_cast<float>(std::clamp(value,0.0,1.0))); }
 void set_track_pan(int track, double value) { if(valid(track)&&std::isfinite(value)) mixer.tracks[track].pan.store(static_cast<float>(std::clamp(value,-1.0,1.0))); }
 void set_track_mute(int track, bool value) { if(valid(track)) mixer.tracks[track].mute.store(value); }
 void set_track_solo(int track, bool value) { if(valid(track)) mixer.tracks[track].solo.store(value); }
 godot::Vector2 get_track_levels(int track) const { return valid(track)?godot::Vector2(mixer.tracks[track].left.load(),mixer.tracks[track].right.load()):godot::Vector2(); }
 void play() {
  if(!attached || mixer.duration()<=0) return;
  if(mixer.position.load()>=mixer.duration()) mixer.seek(0);
  mixer.playing.store(true);
 }
 void pause() { mixer.playing.store(false); }
 void stop() { mixer.stop(); }
 void seek(double seconds) { mixer.seek(seconds); }
 void set_volume(double value) { if(std::isfinite(value)) mixer.master.store(static_cast<float>(std::clamp(value,0.0,1.0))); }
 double get_position() const { return mixer.position.load(); }
 double get_duration() const { return mixer.duration(); }
 bool is_playing() const { return mixer.playing.load(); }
 godot::Vector2 get_levels() const { return {mixer.left.load(),mixer.right.load()}; }
};

static std::unique_ptr<juce::ScopedJuceInitialiser_GUI> juce_runtime;
static void initialize_bridge(godot::ModuleInitializationLevel level) {
 if(level==godot::MODULE_INITIALIZATION_LEVEL_SCENE) {
  juce_runtime=std::make_unique<juce::ScopedJuceInitialiser_GUI>();
  godot::ClassDB::register_class<JuceEngine>();
 }
}
static void uninitialize_bridge(godot::ModuleInitializationLevel level) {
 if(level==godot::MODULE_INITIALIZATION_LEVEL_SCENE) juce_runtime.reset();
}
extern "C" GDExtensionBool GDE_EXPORT juce_bridge_init(GDExtensionInterfaceGetProcAddress address, GDExtensionClassLibraryPtr library, GDExtensionInitialization* initialization) {
 godot::GDExtensionBinding::InitObject init(address,library,initialization);
 init.register_initializer(initialize_bridge);
 init.register_terminator(uninitialize_bridge);
 init.set_minimum_library_initialization_level(godot::MODULE_INITIALIZATION_LEVEL_SCENE);
 return init.init();
}
