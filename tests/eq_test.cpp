#include "eq.hpp"
#include <iostream>
#include <stdexcept>
#include <random>
using bridge::Equalizer;
constexpr double pi=3.14159265358979323846;
void check(bool value,const char* message) { if(!value) throw std::runtime_error(message); }
double response(int band,float gain,double frequency,double rate) {
 Equalizer eq; eq.gains[band].store(gain); eq.prepare(rate); eq.begin_block();
 double power=0,input=0;
 for(int i=0;i<static_cast<int>(rate);++i) {
  const float sample=static_cast<float>(0.01*std::sin(2*pi*frequency*i/rate));
  const auto out=eq.process(sample,0);
  check(out[1]==0,"Stereo EQ state must not leak between channels");
  if(i>rate/2) { power+=out[0]*out[0]; input+=sample*sample; }
 }
 return 10*std::log10(power/input);
}
int main() {
 try {
  for(double rate:{44100.0,48000.0,96000.0}) {
   Equalizer flat; flat.prepare(rate); flat.begin_block();
   for(int i=0;i<2000;++i) {
    const float l=static_cast<float>(0.3*std::sin(i*0.1)),r=static_cast<float>(0.2*std::cos(i*0.03));
    const auto out=flat.process(l,r);
    check(out[0]==l && out[1]==r,"Flat EQ must be transparent");
   }
   check(std::abs(response(0,6,30,rate)-6)<0.15,"Low shelf must boost low frequencies");
   check(std::abs(response(0,-6,30,rate)+6)<0.15,"Low shelf must cut low frequencies");
   check(std::abs(response(0,6,10000,rate))<0.1,"Low shelf must preserve high frequencies");
   check(std::abs(response(1,6,1000,rate)-6)<0.05,"Mid bell must boost its center frequency");
   check(std::abs(response(1,-6,1000,rate)+6)<0.05,"Mid bell must cut its center frequency");
   check(std::abs(response(2,6,18000,rate)-6)<0.2,"High shelf must boost high frequencies");
   check(std::abs(response(2,-6,18000,rate)+6)<0.2,"High shelf must cut high frequencies");
   check(std::abs(response(2,6,100,rate))<0.1,"High shelf must preserve low frequencies");
  }
  Equalizer eq; eq.prepare(48000); eq.gains[0].store(12); eq.begin_block();
  for(int i=0;i<4800;++i) eq.process(0.02f,0.01f);
  eq.bypassed.store(true);
  for(int i=0;i<1000;++i) eq.process(0.02f,0.01f);
  auto out=eq.process(0.02f,-0.01f);
  check(out[0]==0.02f && out[1]==-0.01f,"Bypass must settle to exact dry signal");
  eq.gains[1].store(-18); eq.begin_block();
  for(int i=0;i<1000;++i) {
   out=eq.process(0.02f,-0.01f);
   check(out[0]==0.02f && out[1]==-0.01f,"Gain edits while bypassed must remain dry");
  }
  eq.reset(); eq.bypassed.store(false); eq.prepare(48000); eq.begin_block();
  out=eq.process(0,0); check(out[0]==0 && out[1]==0,"Reset must clear filter history");
  std::mt19937 random(4);
  for(double rate:{8000.0,22050.0,44100.0,48000.0,96000.0}) {
   eq.prepare(rate);
   for(int block=0;block<1000;++block) {
    for(auto& gain:eq.gains) gain.store((random()%2)?18.0f:-18.0f);
    eq.bypassed.store((random()%4)==0); eq.begin_block();
    for(int i=0;i<64;++i) {
     out=eq.process(static_cast<float>(0.01*std::sin((block*64+i)*0.17)),0);
     check(std::isfinite(out[0]) && std::abs(out[0])<10 && out[1]==0,"Fast parameter edits must remain finite and stereo independent");
    }
   }
  }
  std::cout<<"PASS: EQ response, flat transparency, cut/boost, stereo isolation, bypass, reset and modulation stability\n";
  return 0;
 } catch(const std::exception& error) { std::cerr<<"FAIL: "<<error.what()<<'\n'; return 1; }
}
