#pragma once
#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>

namespace bridge {
// Fixed-frequency stereo EQ. RBJ audio-EQ cookbook biquads, normalized by a0.
// Parameter publication is lock-free; coefficients and histories are audio-owned.
class Equalizer {
 struct Band {
  std::array<double, 5> c{1,0,0,0,0}, target{1,0,0,0,0}, delta{};
  std::array<double, 2> z1{}, z2{};
  int remaining = 0;
  void configure(std::array<double, 5> value, int ramp) {
   target = value; remaining = ramp;
   for (int i=0;i<5;++i) delta[i]=(target[i]-c[i])/ramp;
  }
  void tick() {
   if(remaining>0) {
    for(int i=0;i<5;++i) c[i]+=delta[i];
    if(--remaining==0) c=target;
   }
  }
  double process(double input, int channel) {
   const double result=c[0]*input+z1[channel];
   z1[channel]=c[1]*input-c[3]*result+z2[channel];
   z2[channel]=c[2]*input-c[4]*result;
   if(std::abs(z1[channel])<1e-24) z1[channel]=0;
   if(std::abs(z2[channel])<1e-24) z2[channel]=0;
   return result;
  }
  void reset() { z1={}; z2={}; }
 };
 std::array<Band, 3> bands;
 std::array<float, 3> applied{0,0,0};
 double rate=48000, wet=1;
 int ramp=480;
 static std::array<double,5> coefficients(int band, double db, double sample_rate) {
  if(db==0) return {1,0,0,0,0};
  constexpr double pi=3.14159265358979323846;
  const double frequency=std::min(band==0?200.0:band==1?1000.0:6000.0,sample_rate*0.4);
  const double a=std::pow(10.0,db/40.0), w=2*pi*frequency/sample_rate;
  const double c=std::cos(w), s=std::sin(w);
  double b0,b1,b2,a0,a1,a2;
  if(band==1) {
   const double alpha=s/(2*0.7071067811865476);
   b0=1+alpha*a; b1=-2*c; b2=1-alpha*a;
   a0=1+alpha/a; a1=-2*c; a2=1-alpha/a;
  } else {
   const double alpha=s/std::sqrt(2.0), k=2*std::sqrt(a)*alpha;
   if(band==0) {
    b0=a*((a+1)-(a-1)*c+k); b1=2*a*((a-1)-(a+1)*c); b2=a*((a+1)-(a-1)*c-k);
    a0=(a+1)+(a-1)*c+k; a1=-2*((a-1)+(a+1)*c); a2=(a+1)+(a-1)*c-k;
   } else {
    b0=a*((a+1)+(a-1)*c+k); b1=-2*a*((a-1)+(a+1)*c); b2=a*((a+1)+(a-1)*c-k);
    a0=(a+1)-(a-1)*c+k; a1=2*((a-1)-(a+1)*c); a2=(a+1)-(a-1)*c-k;
   }
  }
  return {b0/a0,b1/a0,b2/a0,a1/a0,a2/a0};
 }
public:
 std::array<std::atomic<float>,3> gains{};
 std::atomic<bool> bypassed{false};
 Equalizer() { for(auto& gain:gains) gain.store(0); }
 void prepare(double output_rate) {
  rate=output_rate; ramp=std::max(1,static_cast<int>(rate*0.01));
  for(int i=0;i<3;++i) {
   applied[i]=gains[i].load();
   bands[i].c=coefficients(i,applied[i],rate); bands[i].target=bands[i].c;
   bands[i].remaining=0;
  }
  wet=bypassed.load()?0:1;
  reset();
 }
 void reset() { for(auto& band:bands) band.reset(); }
 // Called once per device block; no allocation, mutex or Godot calls.
 void begin_block() {
  for(int i=0;i<3;++i) {
   const float value=gains[i].load();
   if(value!=applied[i]) {
    applied[i]=value;
    bands[i].configure(coefficients(i,value,rate),ramp);
   }
  }
 }
 std::array<float,2> process(float left,float right) {
  const double target=bypassed.load()?0:1;
  wet+=std::clamp(target-wet,-1.0/ramp,1.0/ramp);
  double l=left,r=right;
  for(auto& band:bands) { band.tick(); l=band.process(l,0); r=band.process(r,1); }
  return {static_cast<float>(left+wet*(l-left)),static_cast<float>(right+wet*(r-right))};
 }
};
}
