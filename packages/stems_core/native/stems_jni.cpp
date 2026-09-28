#include <jni.h>
#include <atomic>
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>
#ifdef __ANDROID__
#include <dlfcn.h>
#include <malloc.h>
#endif
#ifdef TRANSPONO_DEMUCS
#include "model.hpp"
#endif

static std::atomic<bool> cancelled{false};
static std::atomic<int> progress{0};
static uint16_t u16(const unsigned char* p) { return p[0] | (p[1] << 8); }
static uint32_t u32(const unsigned char* p) { return p[0] | (p[1] << 8) | (p[2] << 16) | (uint32_t(p[3]) << 24); }
static void put(std::ofstream& out, uint32_t value, int count) {
  for(int i=0;i<count;++i) { out.put(char(value & 255)); value >>= 8; }
}
static void header(std::ofstream& out, int frames) {
  out.write("RIFF",4); put(out,36+frames*4,4); out.write("WAVEfmt ",8);
  put(out,16,4); put(out,1,2); put(out,2,2); put(out,44100,4);
  put(out,176400,4); put(out,4,2); put(out,16,2); out.write("data",4); put(out,frames*4,4);
}
static std::string text(JNIEnv* env, jstring value) {
  const char* raw=env->GetStringUTFChars(value,nullptr);
  std::string result(raw); env->ReleaseStringUTFChars(value,raw); return result;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_example_transpose_1mobile_StemEngine_available(JNIEnv*, jobject) {
#ifdef TRANSPONO_DEMUCS
  return true;
#else
  return false;
#endif
}
extern "C" JNIEXPORT void JNICALL
Java_com_example_transpose_1mobile_StemEngine_cancelNative(JNIEnv*, jobject) { cancelled=true; }
extern "C" JNIEXPORT jint JNICALL
Java_com_example_transpose_1mobile_StemEngine_progressNative(JNIEnv*, jobject) { return progress.load(); }
extern "C" JNIEXPORT void JNICALL
Java_com_example_transpose_1mobile_StemEngine_resetNative(JNIEnv*, jobject) { cancelled=false; progress=0; }
extern "C" JNIEXPORT jint JNICALL
Java_com_example_transpose_1mobile_StemEngine_purgeNative(JNIEnv*, jobject, jint sdkInt) {
#ifdef __ANDROID__
  // mallopt appeared after our minSdk (24), so resolve it only on devices
  // with a supported purge option. The allocator may still decline it.
  if (sdkInt < 28) return 0;
  using Mallopt = int (*)(int, int);
  auto* malloptFunction = reinterpret_cast<Mallopt>(dlsym(RTLD_DEFAULT, "mallopt"));
  if (!malloptFunction) return 0;
  return malloptFunction(sdkInt >= 34 ? M_PURGE_ALL : M_PURGE, 0);
#else
  (void)sdkInt;
  return 0;
#endif
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_example_transpose_1mobile_StemEngine_separateNative(JNIEnv* env,jobject,
    jstring modelPath,jstring inputPath,jstring outputPath) {
  try {
#ifndef TRANSPONO_DEMUCS
    throw std::runtime_error("Separação não disponível nesta arquitetura.");
#else
    const auto source=text(env,inputPath), folder=text(env,outputPath), modelFile=text(env,modelPath);
    std::ifstream input(source,std::ios::binary);
    input.seekg(0,std::ios::end); const auto fileSize=input.tellg(); input.seekg(0);
    if(fileSize<44 || fileSize>64*1024*1024) throw std::runtime_error("WAV inválido ou maior que 64 MB.");
    unsigned char bytes[16]{}; input.read(reinterpret_cast<char*>(bytes),12);
    if(std::string(reinterpret_cast<char*>(bytes),4)!="RIFF" || std::string(reinterpret_cast<char*>(bytes+8),4)!="WAVE")
      throw std::runtime_error("Escolha WAV PCM 16 bits a 44,1 kHz.");
    int channels=0; uint32_t audioBytes=0; std::streamoff dataOffset=0;
    while(input && input.tellg()+std::streamoff(8)<=fileSize) {
      input.read(reinterpret_cast<char*>(bytes),8);
      const std::string tag(reinterpret_cast<char*>(bytes),4); const auto size=u32(bytes+4);
      const auto begin=input.tellg();
      if(begin+std::streamoff(size)>fileSize) throw std::runtime_error("WAV incompleto.");
      if(tag=="fmt " && size>=16) {
        input.read(reinterpret_cast<char*>(bytes),16); channels=u16(bytes+2);
        if(u16(bytes)!=1 || u32(bytes+4)!=44100 || u16(bytes+14)!=16 ||
            channels<1 || channels>2 || u16(bytes+12)!=channels*2)
          throw std::runtime_error("Use WAV PCM 16 bits, 44,1 kHz, mono ou estéreo.");
      } else if(tag=="data") { audioBytes=size; dataOffset=begin; }
      input.seekg(begin+std::streamoff(size+(size&1)));
    }
    if(channels==0 || audioBytes==0 || audioBytes%(channels*2)!=0) throw std::runtime_error("WAV sem amostras válidas.");
    const int total=audioBytes/(channels*2);
    if(total<44100 || total>44100*600) throw std::runtime_error("A duração deve ser de 1 segundo a 10 minutos.");
    if(cancelled) throw std::runtime_error("Cancelado.");
    std::unique_ptr<demucscpp::demucs_model> model;
    const char* names[]={"drums","bass","other","vocals","guitar","piano"};
    std::ofstream outputs[6];
    for(int s=0;s<6;++s) {
      outputs[s].open(folder+"/"+names[s]+".wav",std::ios::binary);
      if(!outputs[s]) throw std::runtime_error("Sem espaço para guardar os instrumentos.");
      header(outputs[s],total);
    }
    constexpr int chunk=44100*12, overlap=33075, step=chunk-overlap;
    std::vector<float> tail(6*2*overlap,0);
    for(int start=0;start<total;start+=step) {
      if(cancelled) throw std::runtime_error("Cancelado.");
      const int size=std::min(chunk,total-start);
      const bool last=start+size==total;
      std::vector<unsigned char> pcm(size*channels*2);
      input.clear(); input.seekg(dataOffset+std::streamoff(start)*channels*2);
      input.read(reinterpret_cast<char*>(pcm.data()),pcm.size());
      if(!input) throw std::runtime_error("Não foi possível ler a gravação.");
      Eigen::MatrixXf audio(2,size);
      double monoSum=0, monoSq=0;
      for(int i=0;i<size;++i) {
        for(int c=0;c<2;++c) audio(c,i)=int16_t(u16(pcm.data()+(i*channels+std::min(c,channels-1))*2))/32768.0f;
        const double v=(audio(0,i)+audio(1,i))*.5; monoSum+=v; monoSq+=v*v;
      }
      Eigen::Tensor3dXf stems(6,2,size);
      // Upstream normalizes by mono standard deviation. Silence or perfectly
      // anti-phase audio would divide by zero; keep the latter in 'other'.
      if(monoSq/size-std::pow(monoSum/size,2)<1e-12) {
        stems.setZero();
        for(int c=0;c<2;++c) for(int i=0;i<size;++i) stems(2,c,i)=audio(c,i);
      } else {
        if (!model) {
          model=std::make_unique<demucscpp::demucs_model>();
          if(!demucscpp::load_demucs_model(modelFile,model.get()) || model->is_4sources)
            throw std::runtime_error("Modelo de seis instrumentos inválido.");
        }
        stems=demucscpp::demucs_inference(*model,audio,[&](float p,const std::string&) {
          if(cancelled) throw std::runtime_error("Cancelado.");
          progress=std::clamp(int((start+size*double(p))*100.0/total),0,99);
        });
      }
      const int writeCount=last?size:step;
      for(int s=0;s<6;++s) {
        for(int i=0;i<writeCount;++i) for(int c=0;c<2;++c) {
          float value=stems(s,c,i);
          if(start>0 && i<overlap) {
            const float weight=float(i)/overlap;
            value=tail[(s*2+c)*overlap+i]*(1-weight)+value*weight;
          }
          if(!std::isfinite(value)) throw std::runtime_error("O modelo gerou áudio inválido.");
          put(outputs[s],uint16_t(int16_t(std::lround(std::clamp(value,-1.0f,1.0f)*32767))),2);
        }
        if(!outputs[s]) throw std::runtime_error("Falha ao guardar os instrumentos.");
        if(!last) for(int c=0;c<2;++c) for(int i=0;i<overlap;++i)
          tail[(s*2+c)*overlap+i]=stems(s,c,step+i);
      }
      if(last) break;
    }
    for(auto& out:outputs) { out.flush(); if(!out) throw std::runtime_error("Falha ao concluir os ficheiros."); }
    progress=100;
    return nullptr;
#endif
  } catch(const std::exception& e) { return env->NewStringUTF(e.what()); }
}
