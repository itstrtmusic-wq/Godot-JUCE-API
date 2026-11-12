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

// All public methods are called on Godot's main thread. Only the callback owns cursor.
class JuceEngine : public godot::RefCounted, private juce::AudioIODeviceCallback {
 GDCLASS(JuceEngine, godot::RefCounted)
 juce::AudioDeviceManager devices;
 juce::AudioBuffer<float> clip;
 double source_rate = 44100.0, device_rate = 44100.0, cursor = 0.0;
 std::atomic<bool> playing{false};
 std::atomic<float> gain{0.5f}, left{0}, right{0};
 std::atomic<double> position{0};
 std::atomic<bool> rewind_requested{false};
 bool attached = false;
 float previous_gain = 0.5f;
 void detach() { if (attached) { devices.removeAudioCallback(this); attached = false; } }
 void attach() { if (!attached && devices.getCurrentAudioDevice()) { devices.addAudioCallback(this); attached = true; } }
 void audioDeviceAboutToStart(juce::AudioIODevice* d) override { device_rate = d->getCurrentSampleRate(); }
 void audioDeviceStopped() override { left.store(0); right.store(0); }
 void audioDeviceIOCallbackWithContext(const float* const*, int, float* const* out, int channels, int frames, const juce::AudioIODeviceCallbackContext&) override {
  for (int c=0;c<channels;++c) if(out[c]) juce::FloatVectorOperations::clear(out[c], frames);
  if(rewind_requested.exchange(false)) cursor=0;
  float peaks[2]={0,0};
  const float target=gain.load();
  const double step=source_rate/device_rate;
  const int length=clip.getNumSamples();
  if(playing.load() && length>0) {
   for(int i=0;i<frames;++i) {
    if(cursor>=length) { playing.store(false); break; }
    const int a=static_cast<int>(cursor), b=std::min(a+1,length-1);
    const float fraction=static_cast<float>(cursor-a);
    const float volume=previous_gain+(target-previous_gain)*static_cast<float>(i+1)/frames;
    for(int c=0;c<std::min(channels,2);++c) {
     const float* data=clip.getReadPointer(std::min(c,clip.getNumChannels()-1));
     const float value=(data[a]+(data[b]-data[a])*fraction)*volume;
     if(out[c]) out[c][i]=value;
     peaks[c]=std::max(peaks[c],std::abs(value));
    }
    cursor+=step;
   }
  }
  previous_gain=target;
  position.store(std::min(cursor,static_cast<double>(length))/source_rate);
  left.store(peaks[0]); right.store(peaks[1]);
 }
protected:
 static void _bind_methods() {
  using namespace godot;
  ClassDB::bind_method(D_METHOD("initialize"), &JuceEngine::initialize);
  ClassDB::bind_method(D_METHOD("shutdown"), &JuceEngine::shutdown);
  ClassDB::bind_method(D_METHOD("get_output_devices"), &JuceEngine::get_output_devices);
  ClassDB::bind_method(D_METHOD("select_output_device", "name"), &JuceEngine::select_output_device);
  ClassDB::bind_method(D_METHOD("load_wav", "absolute_path"), &JuceEngine::load_wav);
  ClassDB::bind_method(D_METHOD("play"), &JuceEngine::play);
  ClassDB::bind_method(D_METHOD("pause"), &JuceEngine::pause);
  ClassDB::bind_method(D_METHOD("stop"), &JuceEngine::stop);
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
 void shutdown() { playing.store(false); detach(); devices.closeAudioDevice(); }
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
 godot::String load_wav(godot::String path) {
  juce::WavAudioFormat format;
  auto stream=juce::File(juce::String::fromUTF8(path.utf8().get_data())).createInputStream();
  if(!stream) return "Cannot open file. Pass an absolute filesystem path.";
  auto* raw=stream.release();
  std::unique_ptr<juce::AudioFormatReader> reader(format.createReaderFor(raw,true));
  if(!reader) return "Not a supported WAV file.";
  // MVP loads into memory. Bound decoded storage to 256 MiB, mono/stereo only.
  if(reader->numChannels<1 || reader->numChannels>2 || reader->lengthInSamples<=0 || reader->lengthInSamples>33554432 || reader->sampleRate<=0)
   return "WAV must be mono/stereo and at most 33,554,432 frames.";
  juce::AudioBuffer<float> next(static_cast<int>(reader->numChannels),static_cast<int>(reader->lengthInSamples));
  if(!reader->read(&next,0,next.getNumSamples(),0,true,true)) return "WAV decoding failed.";
  playing.store(false);
  detach(); // Wait for any callback before changing storage or callback-owned state.
  clip=std::move(next); source_rate=reader->sampleRate; cursor=0;
  position.store(0); rewind_requested.store(false); left.store(0); right.store(0);
  attach();
  return {};
 }
 void play() {
  if(clip.getNumSamples()==0 || !attached) return;
  if(position.load()>=get_duration()) rewind_requested.store(true);
  playing.store(true);
 }
 void pause() { playing.store(false); }
 void stop() { playing.store(false); rewind_requested.store(true); position.store(0); }
 void set_volume(double value) { if(std::isfinite(value)) gain.store(static_cast<float>(std::clamp(value,0.0,1.0))); }
 double get_position() const { return position.load(); }
 double get_duration() const { return clip.getNumSamples()/source_rate; }
 bool is_playing() const { return playing.load(); }
 godot::Vector2 get_levels() const { return {left.load(),right.load()}; }
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
