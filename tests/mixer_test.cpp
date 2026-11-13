#include "mixer.hpp"
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>
using bridge::Mixer;
static void check(bool condition, const char* message) { if (!condition) throw std::runtime_error(message); }
static void near(double actual, double expected, double tolerance, const char* message) { check(std::abs(actual-expected)<tolerance,message); }
struct Output {
 std::vector<float> l, r;
 explicit Output(int n):l(n),r(n) {}
 void render(Mixer& mixer) { float* buffers[]={l.data(),r.data()}; mixer.render(buffers,2,static_cast<int>(l.size())); }
};
static void constant(Mixer& m,int track,float value,double seconds=1,double rate=48000) {
 auto& clip=m.tracks[track].clip;
 clip.channels=1; clip.rate=rate; clip.samples[0].assign(static_cast<size_t>(seconds*rate),value);
}
static std::unique_ptr<Mixer> session() { auto m=std::make_unique<Mixer>(); m->master.store(1); return m; }
int main() {
 try {
  auto m=session();
  constant(*m,0,0.2f); constant(*m,1,0.3f);
  m->prepare(48000); m->playing.store(true);
  Output block(2048); block.render(*m);
  near(block.l[1500],0.5,1e-5,"Two tracks must sum on shared clock");
  near(block.r[1500],0.5,1e-5,"Mono must feed both channels");
  near(m->position.load(),2048.0/48000,1e-10,"Clock must advance once per mixed frame");
  m->tracks[1].mute.store(true); block.render(*m);
  near(block.l.back(),0.2,1e-5,"Mute must remove only one track");
  m->tracks[1].mute.store(false); m->tracks[1].solo.store(true); block.render(*m);
  near(block.l.back(),0.3,1e-5,"Solo must exclude non-solo tracks");
  m->tracks[1].pan.store(1); block.render(*m);
  near(block.l.back(),0,1e-5,"Hard right pan must silence left");
  near(block.r.back(),0.3,1e-5,"Hard right pan must retain right");
  m->tracks[1].volume.store(0.5f); block.render(*m);
  near(block.r.back(),0.15,1e-5,"Per-track gain must apply");
  check(m->tracks[1].right.load() >= 0.15f && m->tracks[1].right.load() <= 0.3f,"Meter must include gain transition");
  block.render(*m);
  near(m->tracks[1].right.load(),0.15,1e-5,"Track meter must settle to post-fader peak");
  m->playing.store(false); block.render(*m);
  const double paused=m->position.load(); block.render(*m);
  near(m->position.load(),paused,1e-12,"Paused clock must stay fixed after fade");
  near(block.r.back(),0,1e-12,"Paused output must be silent");
  m->seek(0.5); block.render(*m);
  near(m->position.load(),0.5,1e-12,"Paused seek must land exactly");
  m->playing.store(true); block.render(*m);
  m->seek(0.1); block.render(*m);
  check(m->position.load()>0.1 && m->position.load()<0.15,"Playing seek must fade then continue at target");
  for(size_t i=1;i<block.r.size();++i) check(std::abs(block.r[i]-block.r[i-1])<0.01,"Transport transition must be smoothed");
  m->stop(); block.render(*m);
  near(m->position.load(),0,1e-12,"Stop must rewind after fading");
  m->seek(100); block.render(*m); near(m->position.load(),1,1e-12,"Seek must clamp to session duration");
  m->seek(0); m->playing.store(true); block.render(*m);
  check(m->playing.load() && m->position.load()<0.1,"Play from EOF must restart");

  m=session(); constant(*m,0,0.2f,0.1); constant(*m,1,0.3f,0.1);
  m->tracks[1].offset=0.2; m->prepare(48000); m->playing.store(true);
  Output timeline(16000); timeline.render(*m);
  near(timeline.l[2400],0.2,1e-5,"First clip must start at zero");
  near(timeline.l[7200],0,1e-12,"Gap between clips must be silent");
  near(timeline.l[12000],0.3,1e-5,"Second clip must honor offset");
  near(m->duration(),0.3,1e-12,"Session length must include last clip offset");
  check(!m->playing.load(),"Transport must stop at last clip end");

  m=session(); constant(*m,0,0,0.2,44100);
  auto& clip=m->tracks[0].clip;
  for(size_t i=0;i<clip.samples[0].size();++i) clip.samples[0][i]=static_cast<float>(0.25*std::sin(2*bridge::pi*440*i/44100));
  m->prepare(48000); m->playing.store(true);
  Output resampled(6000); resampled.render(*m);
  for(int i=1000;i<5000;++i) near(resampled.l[i],0.25*std::sin(2*bridge::pi*440*i/48000),0.002,"Resampling must preserve pitch and timing");

  m=session(); constant(*m,0,0,0.3,48000);
  for(size_t i=0;i<m->tracks[0].clip.samples[0].size();++i) m->tracks[0].clip.samples[0][i]=static_cast<float>(0.25*std::sin(2*bridge::pi*20000*i/48000));
  m->prepare(22050); m->playing.store(true);
  Output downsampled(5000); downsampled.render(*m);
  double power=0; for(int i=1000;i<4000;++i) power+=downsampled.l[i]*downsampled.l[i];
  check(std::sqrt(power/3000)<0.02,"Downsampling must suppress content above output Nyquist");

  m=session(); constant(*m,0,0.2f);
  m->tracks[0].clip.channels=2;
  m->tracks[0].clip.samples[1].assign(48000,0.4f);
  m->prepare(48000); m->playing.store(true); block.render(*m);
  near(block.l.back(),0.2,1e-5,"Stereo left channel must be preserved");
  near(block.r.back(),0.4,1e-5,"Stereo right channel must be preserved");
  m->tracks[0].pan.store(-1); block.render(*m);
  near(block.l.back(),0.2,1e-5,"Stereo balance must retain left channel");
  near(block.r.back(),0,1e-5,"Stereo balance must attenuate opposite channel");

  m=session(); constant(*m,0,0.1f); constant(*m,1,0.3f);
  m->tracks[0].eq.gains[0].store(6);
  m->prepare(48000); m->playing.store(true); block.render(*m);
  near(block.l.back(),0.3+0.1*std::pow(10.0,6.0/20),0.002,"EQ must process its own track before summing");
  near(m->tracks[1].left.load(),0.3,1e-5,"Other track meter must remain unaffected by EQ");
  m->tracks[0].eq.bypassed.store(true); block.render(*m);
  near(block.l.back(),0.4,1e-5,"Track EQ bypass must return unprocessed mix");

  m=session(); constant(*m,0,1); constant(*m,1,1); m->prepare(48000); m->playing.store(true); block.render(*m);
  near(block.l.back(),1,1e-12,"Summed output must be safety-clamped");
  check(m->left.load()>1.9,"Master meter must expose overload before clamp");
  std::cout << "PASS: shared clock, summing, offsets, mute/solo, pan, meters, transport fades, EOF, resampling and output ceiling\n";
  return 0;
 } catch(const std::exception& error) { std::cerr << "FAIL: " << error.what() << '\n'; return 1; }
}
