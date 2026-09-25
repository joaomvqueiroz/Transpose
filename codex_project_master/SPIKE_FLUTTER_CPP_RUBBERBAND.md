# EXECUTABLE SPIKE PLAN — Flutter → C++ → Rubber Band → Áudio

**Atualização da decisão (2026-09-24):** ADR-011 escolheu Rubber Band como
alvo técnico após pesquisa e relatos de developers; ADR-012 escolheu saída
nativa única para fontes locais processáveis. Isto não aprova o spike, não
autoriza compra de licença e não permite distribuir build proprietária com
Rubber Band antes de licença comercial válida. Avaliação interna prossegue.

**Objetivo:** provar, em hardware real Android e iOS, que a arquitetura `Flutter UI → Dart FFI → C ABI → C++ AudioCore → Rubber Band → saída nativa` consegue cumprir as metas de latência, estabilidade e independência entre pitch/velocidade antes de integrar o motor ao player completo de vídeo.

**Tipo de trabalho:** spike de engenharia / go-no-go.  
**Escopo deliberadamente limitado:** áudio local + DSP + controlo Flutter + métricas.  
**Fora do spike:** YouTube, cloud, acordes, gravação, Media3/AVFoundation de vídeo, sincronização A/V completa, setlists, autenticação.

---

## 1. Perguntas que o spike precisa responder

No fim do spike devemos conseguir responder objetivamente:

1. Flutter consegue controlar o motor C++ via FFI sem estar no caminho real-time?
2. Rubber Band consegue executar pitch e time-stretch em tempo real no hardware-alvo?
3. Conseguimos trocar `pitch` e `speed` sem clicks/pops e sem reconstruir o motor?
4. O callback de áudio cumpre o deadline sem underruns?
5. Android e iOS conseguem usar o mesmo núcleo C++ com backends de saída diferentes?
6. O controlo de pitch/speed cumpre P95/P99 definidos?
7. O motor fica estável durante 60 minutos?
8. O loop de teste mantém erro/drift dentro das metas?
9. O consumo de CPU/memória é suficientemente baixo para justificar continuar com esta arquitetura?
10. Existe algum blocker de build, licença, ABI, lifecycle ou áudio de plataforma que obrigue a mudar a decisão arquitetural?

---

# 2. Arquitetura do spike

```text
┌────────────────────────────────────┐
│              FLUTTER               │
│                                    │
│ Play / Pause                       │
│ Pitch -12…+12                      │
│ Speed 0.50…1.50                    │
│ Loop A/B                           │
│ Metrics panel                      │
└─────────────────┬──────────────────┘
                  │ Dart FFI
                  │ comandos de controlo
                  ▼
┌────────────────────────────────────┐
│            C ABI BRIDGE            │
│                                    │
│ ac_create                          │
│ ac_load_test_file                  │
│ ac_play / ac_pause                 │
│ ac_set_pitch                       │
│ ac_set_speed                       │
│ ac_set_loop                        │
│ ac_get_metrics                     │
│ ac_destroy                         │
└─────────────────┬──────────────────┘
                  ▼
┌────────────────────────────────────┐
│          C++ AUDIO CORE            │
│                                    │
│ AudioEngine                        │
│ CommandState / atomics             │
│ Ring buffers                       │
│ Media timeline                     │
│ Loop controller                    │
│ Metrics collector                  │
│ RubberBandProcessor                │
└──────────┬─────────────────────────┘
           │
           ├──────── Android ────────► Oboe / AAudio output
           │
           └──────── iOS ────────────► AudioUnit RemoteIO + AVAudioSession
```

### Regra estrutural

Flutter **não** processa buffers de áudio.

Dart pode:

- enviar comandos;
- ler snapshots de métricas;
- renderizar UI.

Dart não pode:

- receber um callback por buffer;
- executar DSP;
- fazer polling em frequência de áudio;
- bloquear a audio thread.

---

# 3. Estrutura de pastas

Recomendação: criar o motor como package/plugin independente, para poder ser usado no app final.

```text
repo/
├── apps/
│   └── audio_spike/
│       ├── lib/
│       │   ├── main.dart
│       │   ├── spike_page.dart
│       │   └── widgets/
│       │       └── metrics_panel.dart
│       ├── assets/
│       │   └── qa/
│       │       ├── sine_440hz.wav
│       │       ├── click_120bpm.wav
│       │       ├── loop_2s.wav
│       │       └── music_test.wav
│       └── integration_test/
│           └── audio_spike_test.dart
│
├── packages/
│   └── audio_core/
│       ├── lib/
│       │   ├── audio_core.dart
│       │   └── src/
│       │       ├── audio_core_ffi.dart
│       │       ├── audio_core_bindings.dart
│       │       ├── audio_metrics.dart
│       │       └── audio_engine_api.dart
│       │
│       ├── native/
│       │   ├── include/
│       │   │   ├── audio_core_c.h
│       │   │   ├── audio_engine.h
│       │   │   ├── audio_backend.h
│       │   │   ├── dsp_processor.h
│       │   │   ├── loop_controller.h
│       │   │   └── metrics.h
│       │   │
│       │   ├── src/
│       │   │   ├── audio_core_c.cpp
│       │   │   ├── audio_engine.cpp
│       │   │   ├── rubber_band_processor.cpp
│       │   │   ├── loop_controller.cpp
│       │   │   ├── wav_reader.cpp
│       │   │   └── metrics.cpp
│       │   │
│       │   ├── platform/
│       │   │   ├── android/
│       │   │   │   ├── oboe_audio_backend.cpp
│       │   │   │   └── oboe_audio_backend.h
│       │   │   └── ios/
│       │   │       ├── ios_audio_backend.mm
│       │   │       └── ios_audio_backend.h
│       │   │
│       │   ├── third_party/
│       │   │   └── rubberband/
│       │   │       └── README_LICENSE.md
│       │   │
│       │   ├── tests/
│       │   │   ├── dsp_accuracy_test.cpp
│       │   │   ├── loop_accuracy_test.cpp
│       │   │   └── command_state_test.cpp
│       │   │
│       │   └── CMakeLists.txt
│       │
│       ├── android/
│       │   ├── build.gradle
│       │   └── CMakeLists.txt
│       │
│       ├── ios/
│       │   ├── audio_core.podspec
│       │   └── Classes/
│       │       └── AudioCorePlugin.mm
│       │
│       └── test/
│           └── audio_core_ffi_test.dart
│
├── docs/
│   └── SPIKE_FLUTTER_CPP_RUBBERBAND.md
│
└── tools/
    ├── generate_test_audio.py
    ├── analyze_latency.py
    ├── analyze_loop.py
    └── summarize_metrics.py
```

### Regra para o código da Rubber Band

Não espalhar chamadas da biblioteca pelo projeto.

Somente:

```text
rubber_band_processor.cpp
```

conhece diretamente a API da Rubber Band.

O restante do app conhece apenas `DspProcessor`.

---

# 4. Interfaces

## 4.1 Dart

```dart
abstract interface class AudioEngineApi {
  Future<void> initialize();
  Future<void> load(String path);

  void play();
  void pause();

  void setPitchSemitones(double semitones);
  void setSpeed(double speed);

  void setLoop({
    required Duration start,
    required Duration end,
  });

  void disableLoop();

  AudioMetrics readMetrics();

  void dispose();
}
```

### Regra

`setPitchSemitones()` e `setSpeed()` não aguardam processamento DSP na UI.

O comando deve ser rápido e retornar depois de ter sido entregue ao núcleo. A confirmação real aparece em `AudioMetrics.lastPitchAppliedSequence` / eventos de estado.

---

## 4.2 C ABI

Nunca expor classes C++ diretamente para Dart FFI.

```c
#pragma once

#ifdef __cplusplus
extern "C" {
#endif

typedef void* ACHandle;

typedef struct {
    int sample_rate;
    int channels;
    int frames_per_buffer;
} ACConfig;

typedef struct {
    double media_position_ms;

    double pitch_semitones;
    double speed;

    double last_play_apply_ms;
    double last_pause_apply_ms;
    double last_pitch_apply_ms;
    double last_speed_apply_ms;

    double dsp_process_p50_ms;
    double dsp_process_p95_ms;
    double dsp_process_p99_ms;

    double callback_budget_ms;
    double callback_max_ms;

    long long callback_count;
    long long deadline_miss_count;
    long long underrun_count;

    double loop_last_error_ms;
    double loop_max_error_ms;
    double loop_drift_ms;

    int is_playing;
    int route_type;
} ACMetrics;

ACHandle ac_create(const ACConfig* config);
int ac_load_wav(ACHandle handle, const char* path);

void ac_play(ACHandle handle);
void ac_pause(ACHandle handle);

void ac_set_pitch(ACHandle handle, double semitones);
void ac_set_speed(ACHandle handle, double speed);

int ac_set_loop(
    ACHandle handle,
    double start_ms,
    double end_ms
);

void ac_disable_loop(ACHandle handle);

int ac_get_metrics(
    ACHandle handle,
    ACMetrics* out_metrics
);

void ac_destroy(ACHandle handle);

#ifdef __cplusplus
}
#endif
```

### Por que C ABI?

- ABI estável para FFI;
- não expõe STL;
- reduz incompatibilidades de compiler/runtime;
- permite trocar implementação interna sem alterar Dart.

---

## 4.3 DSP

```cpp
class DspProcessor {
public:
    virtual ~DspProcessor() = default;

    virtual bool prepare(
        int sampleRate,
        int channels,
        int maxFrames
    ) = 0;

    virtual void setPitchSemitones(float value) noexcept = 0;
    virtual void setSpeed(float value) noexcept = 0;

    virtual int process(
        const float* const* input,
        int inputFrames,
        float* const* output,
        int outputCapacity
    ) noexcept = 0;

    virtual void reset() noexcept = 0;
};
```

Implementação do spike:

```text
RubberBandProcessor : DspProcessor
```

---

## 4.4 Backend nativo

```cpp
class AudioBackend {
public:
    virtual ~AudioBackend() = default;

    virtual bool open(
        int preferredSampleRate,
        int preferredFramesPerBuffer
    ) = 0;

    virtual bool start() = 0;
    virtual void stop() = 0;
    virtual void close() = 0;

    virtual int sampleRate() const = 0;
    virtual int framesPerBuffer() const = 0;
};
```

Implementações:

```text
AndroidOboeBackend
IOSRemoteIOBackend
```

---

# 5. Thread model

```text
Flutter UI Thread
    │
    │ FFI commands
    ▼
Atomic Command State
    │
    ▼
Audio Callback Thread
    │
    ├── read already prepared command state
    ├── get PCM from ring buffer
    ├── Rubber Band process
    ├── loop/timeline update
    ├── write output
    └── record counters only

Worker Thread
    │
    ├── file I/O
    ├── WAV reading
    ├── refill input ring buffer
    └── expensive diagnostics aggregation
```

## Proibido no callback real-time

- Flutter callbacks;
- Dart calls;
- filesystem;
- DB;
- network;
- JSON;
- mutex que possa bloquear;
- logging síncrono;
- alocação repetitiva;
- criação/destruição de Rubber Band;
- análise estatística pesada.

Usar:

- buffers pré-alocados;
- atomics;
- SPSC ring buffer quando necessário;
- contadores baratos;
- snapshots de métricas fora da callback.

---

# 6. Test assets

Gerar ativos determinísticos.

## `sine_440hz.wav`

- 48 kHz;
- stereo;
- 440 Hz;
- 60 s.

Usos:
- precisão de pitch;
- comprovar que speed não altera pitch.

## `click_120bpm.wav`

- 48 kHz;
- click exato a cada 500 ms;
- 10 min.

Usos:
- timing;
- loop;
- detecção de drift.

## `loop_2s.wav`

Marcadores conhecidos:

```text
A = 10.000 s
B = 12.000 s
```

## `music_test.wav`

Trecho musical autorizado/local.

Usos:
- avaliação auditiva;
- clicks;
- warble;
- artifacts.

---

# 7. Configuração base do spike

Primeiro cenário:

```text
Sample rate:       48 kHz
Channels:          2
Format:            float32 interno
Pitch:             0
Speed:             1.00x
Loop:              OFF
Source:            local WAV
Quality:           modo real-time do DSP
```

Testar buffers:

```text
128
256
512 frames
```

Não congelar o buffer final antes de medir hardware real.

Exemplo de orçamento:

```text
48 kHz / 256 frames
callback period ≈ 5.33 ms
```

Meta interna:

```text
DSP callback P95 < 50% do orçamento
DSP callback P99 < 75% do orçamento
deadline misses = 0 no cenário de aprovação
```

---

# 8. Instrumentação obrigatória

Usar monotonic clock em Dart e C++.

Nunca usar relógio civil para latência.

## Timestamps

Por comando:

```text
T0  Flutter action/request
T1  C ABI receives command
T2  audio thread observes new command sequence
T3  first output buffer containing new state
```

Métricas:

```text
ffi_dispatch_ms = T1 - T0
engine_apply_ms = T3 - T1
user_command_to_processed_audio_ms = T3 - T0
```

T3 ainda é uma métrica interna de pipeline; não representa necessariamente o momento acústico no altifalante.

Por isso o spike deve ter também uma pequena validação física externa para Play/Pause/latência de saída.

---

# 9. Métricas a recolher

Cada sessão precisa guardar CSV/JSON.

```text
platform
device
os_version
build
sample_rate
frames_per_buffer
route
pitch
speed
quality_mode

ffi_dispatch_ms
play_apply_ms
pause_apply_ms
pitch_apply_ms
speed_apply_ms

dsp_process_ms
callback_duration_ms
callback_budget_ms
deadline_miss_count
underrun_count

loop_error_ms
loop_drift_ms

cpu_process
rss_memory_mb
thermal_state

crash_count
audio_duplicate_count
click_pop_count
```

Relatórios:

```text
count
MIN
P50
P95
P99
MAX
```

Não misturar Android e iOS no mesmo percentil principal.

Não misturar 128/256/512 frames.

---

# 10. Critérios do spike

## 10.1 FFI

**Spike-specific**, porque a matriz geral mede ação→áudio e não o overhead isolado.

```text
ffi_dispatch_ms
P50 < 1 ms
P95 < 2 ms
P99 < 5 ms
```

Se o FFI exceder isso de forma persistente, investigar implementação antes de culpar o DSP.

---

## 10.2 Play/Pause

Critério do projeto:

```text
Play:
P50 < 60 ms
P95 < 100 ms
P99 < 150 ms

Pause:
P95 < 100 ms
P99 < 150 ms
```

Adicional:

```text
áudio duplicado = 0
click/pop = 0
```

---

## 10.3 Pitch

```text
P95 apply < 150 ms
P99 apply < 200 ms
clicks/pops = 0
```

Teste:

```text
0 → -1 → -2 → -3 → 0 → +3 → 0
```

---

## 10.4 Speed

```text
P95 apply < 150 ms
pitch drift musical = 0 semitons
underruns audíveis = 0
```

Testar:

```text
0.50x
0.75x
0.85x
1.00x
1.25x
1.50x
```

---

## 10.5 Precisão adicional de DSP

Critério específico do spike para validar implementação, não uma meta já existente no produto.

### Pitch

Com sine 440 Hz:

```text
pitch 0:
≈ 440 Hz

+12:
≈ 880 Hz

-12:
≈ 220 Hz
```

Após remover a zona transitória:

```text
erro de frequência <= 5 cents
```

### Speed

Com clicks conhecidos:

```text
erro de razão de tempo <= 0.1%
```

em janela de 60 s.

Esses números servem para detectar integração errada/configuração errada; não substituem teste auditivo de qualidade musical.

---

## 10.6 Loop

Para o spike implementar loop no C++ usando a timeline do motor.

```text
P50 erro < 10 ms
P95 erro < 25 ms
P99 erro < 40 ms
MAX < 60 ms
drift após 1000 loops < 25 ms
```

Teste obrigatório combinado:

```text
Pitch -2
Speed 0.75x
Loop 2 s
1000 repetições
```

Resultado:

```text
P95 erro < 25 ms
drift < 25 ms
underruns audíveis = 0
```

---

## 10.7 Real-time deadline

Para cada buffer:

```text
callback_budget_ms =
frames_per_buffer / sample_rate * 1000
```

Exemplo:

```text
256 / 48000 ≈ 5.33 ms
```

Gate:

```text
callback P95 < 50% do budget
callback P99 < 75% do budget
deadline misses = 0 durante teste de aprovação
```

Se 128 frames não passar mas 256 passar, isso não reprova automaticamente a arquitetura; 256 passa a ser candidato ao default do dispositivo/classe.

---

## 10.8 Estabilidade

Sessão:

```text
60 min
Pitch -2
Speed 0.75x
mudanças periódicas de pitch/speed
loops
pause/resume
```

Gate:

```text
crashes = 0
audio duplicate = 0
audible underruns = 0
deadlocks = 0
state inconsistency = 0
```

---

## 10.9 Memória

Depois de warm-up de 5 min:

```text
crescimento contínuo = 0
RSS delta em 55 min <= 15 MB
```

Uma estabilização acima desse número pode ser aceite se houver explicação objetiva de caches fixos; crescimento linear reprova.

---

## 10.10 CPU / DSP budget

Em vez de usar somente “% de CPU”, usar principalmente deadline do callback.

Gate principal:

```text
P95 DSP < 50% callback budget
P99 DSP < 75% callback budget
```

Registrar CPU do processo como dado comparativo.

**Sinal vermelho:**

- thermal throttling;
- callback começa a piorar com o tempo;
- CPU cresce continuamente;
- device fica em estado térmico crítico.

---

# 11. Matriz mínima de hardware

## Android

### A — mínimo/fraco

```text
3–4 GB RAM
Android suportado pelo produto
ARM64
```

### B — médio

```text
6–8 GB RAM
ARM64
```

### C — forte

```text
topo recente
ARM64
```

Gate arquitetural inicial:

- obrigatório passar no Android médio;
- Android fraco pode exigir 256/512 frames ou quality mode mais leve;
- não pode crashar no fraco.

## iOS

### D — antigo suportado

Um iPhone dentro da versão mínima que o produto pretende suportar.

### E — recente

Um iPhone recente.

Gate:

- obrigatório passar nos dois;
- pode usar tamanho de buffer diferente conforme `AVAudioSession`.

---

# 12. Android — implementação

## Backend

```text
Oboe
  ↓
AAudio quando disponível/adequado
  ↓
fallback do backend conforme plataforma
```

Responsabilidades do adapter:

- abrir output;
- escolher baixa latência quando suportada;
- reportar sample rate real;
- reportar frames/burst;
- callback para AudioEngine;
- tratar start/stop;
- não conter lógica Rubber Band.

## Build

No `CMakeLists.txt`:

```text
audio_core
rubberband
oboe
```

Arquitetura principal do spike:

```text
arm64-v8a
```

Pode compilar outras ABIs para desenvolvimento, mas resultados de aprovação precisam indicar ABI.

## Android acceptance

Obrigatório em dispositivo real:

```text
1. build release/profile, não só debug;
2. speaker;
3. 48 kHz quando disponível;
4. pitch;
5. speed;
6. loop;
7. 60 min stress;
8. app background/foreground básico;
```

O spike não precisa ainda resolver todo BT/audio focus do produto, mas deve provar que o backend fecha/reabre sem crash.

---

# 13. iOS — implementação

## Backend

Usar:

```text
AVAudioSession
+
AudioUnit RemoteIO
```

Adapter Objective-C++:

```text
ios_audio_backend.mm
```

Responsabilidades:

- configurar sessão;
- sample rate preferido;
- I/O buffer duration preferida;
- receber valores efetivos;
- abrir RemoteIO;
- chamar AudioEngine;
- fechar corretamente.

Rubber Band e AudioEngine permanecem C++.

## iOS acceptance

Em dispositivo físico:

```text
1. build Release/Profile;
2. speaker;
3. pitch;
4. speed;
5. loop;
6. 60 min stress;
7. lock/background transition básico sem crash;
8. interruption callback pode ser apenas instrumentado nesta fase;
```

Simulator não conta como aprovação de áudio real-time.

---

# 14. UI do spike

Não construir UI final.

Uma tela apenas:

```text
AUDIO SPIKE

File:
music_test.wav

STATE
PLAYING

[ - ]  Pitch: -2  [ + ]

Speed
0.50  0.75  0.85  1.00  1.25

[ Set A ]
[ Set B ]
Loop: ON

[ PLAY / PAUSE ]

-----------------------

METRICS

Route
Sample Rate
Frames/Buffer

FFI P50/P95/P99
Pitch P50/P95/P99
Speed P50/P95/P99

DSP P50/P95/P99
Callback Budget
Deadline Misses
Underruns

Loop Error
Loop Drift

CPU
Memory
```

Esse painel é QA, não design de produto.

---

# 15. Sequência executável

## Dia 0 — preparação

### Tarefa S-000

- confirmar Flutter toolchain;
- confirmar Android NDK/CMake;
- confirmar Xcode/CocoaPods;
- confirmar dispositivo Android físico;
- confirmar iPhone físico;
- disponibilizar Rubber Band conforme licença escolhida;
- gerar ativos QA.

**Gate:** projeto Flutter vazio executa nos dois aparelhos.

---

## Dia 1 — C++ core + Android

### S-001 — package `audio_core`

- criar plugin/package;
- CMake;
- export C ABI;
- `ac_create` / `ac_destroy`;
- teste FFI ping.

**Gate:** Flutter chama C++ e recebe versão/valor.

### S-002 — Android output

- Oboe backend;
- gerar tom/ler WAV sem DSP;
- Play/Pause.

**Gate:** 10 min sem crash/underrun audível.

### S-003 — Rubber Band

- `DspProcessor`;
- `RubberBandProcessor`;
- pitch;
- speed;
- atomics/command sequence.

**Gate:** `-2` e `0.75x` audíveis e independentes.

---

## Dia 2 — iOS + paridade

### S-004 — iOS backend

- AVAudioSession;
- RemoteIO;
- C++ AudioEngine compartilhado.

**Gate:** mesmo `AudioEngine` toca o mesmo ativo QA.

### S-005 — Flutter controls

- Play/Pause;
- Pitch;
- Speed;
- Metrics.

**Gate:** nenhum buffer atravessa Dart.

### S-006 — DSP accuracy

- sine test;
- click test;
- analisar frequência e tempo.

**Gate:** critérios de precisão do spike.

---

## Dia 3 — loop + benchmark + decisão

### S-007 — Loop controller

- A/B;
- 1000 loops;
- drift.

### S-008 — Metrics collector

- monotonic timestamps;
- P50/P95/P99;
- callback budget;
- underruns;
- memory.

### S-009 — stress

Rodar:

```text
Android médio 60 min
iPhone antigo 60 min
iPhone recente ou Android forte 60 min
```

### S-010 — relatório

Gerar:

```text
SPIKE_RESULTS.md
spike_android.csv
spike_ios.csv
```

---

# 16. Test sequence padrão

Cada dispositivo roda exatamente:

## Run 1 — baseline

```text
10 min
Pitch 0
Speed 1.00
Loop OFF
```

## Run 2 — pitch

```text
100 mudanças
0 ↔ -2
```

## Run 3 — speed

```text
100 mudanças
1.00 ↔ 0.75
```

## Run 4 — combinado

```text
20 min
Pitch -2
Speed 0.75
```

## Run 5 — loop

```text
A=10s
B=12s
1000 loops
Pitch -2
Speed 0.75
```

## Run 6 — stress

```text
60 min

a cada 5 min:
pitch muda

a cada 7 min:
speed muda

a cada 10 min:
Pause/Play

loop ON/OFF repetidamente
```

---

# 17. GO / CONDITIONAL GO / NO-GO

## GO

Arquitetura aprovada se:

```text
Android médio: PASS
iPhone antigo suportado: PASS
iPhone recente: PASS

Play P95 < 100 ms
Pitch P95 < 150 ms
Speed P95 < 150 ms

Loop P95 < 25 ms
Loop P99 < 40 ms
Loop drift < 25 ms / 1000

Deadline misses = 0 em cenário aprovado
Audible underruns = 0
Crashes = 0
Audio duplication = 0

Sem crescimento contínuo de memória
Sem thermal throttling destrutivo
```

Além disso:

- Flutter nunca entra no callback real-time;
- C ABI permanece pequeno;
- mesmo C++ core funciona nas duas plataformas;
- Rubber Band fica encapsulado.

---

## CONDITIONAL GO

Aceitar com ação corretiva se:

- 128 frames falha, mas 256 passa confortavelmente;
- hardware fraco precisa de quality mode mais leve;
- P99 tem poucos outliers explicados, mas P95 cumpre e não há glitch audível;
- sample rate efetivo é diferente do preferido, mas pipeline adapta corretamente.

Registrar a condição como ADR/tech debt antes de continuar.

---

## NO-GO

Parar e reavaliar se qualquer um persistir:

- Flutter precisa participar por buffer;
- C++/Rubber Band não cumpre deadline em hardware médio;
- underruns audíveis continuam em 256/512 frames;
- pitch/speed exigem reconstruir engine com glitches;
- memória cresce continuamente;
- diferenças Android/iOS obrigam duplicar o AudioEngine inteiro;
- loop acumula drift estrutural;
- integração/licença da biblioteca não é viável para distribuição;
- não é possível instrumentar de forma confiável a latência.

No NO-GO, não “otimizar indefinidamente” dentro do spike. Produzir relatório e comparar alternativa DSP/backend.

---

# 18. Critérios que este spike NÃO prova

Mesmo com GO, ainda faltará provar:

- Media3 + AudioCore no Android;
- AVFoundation + AudioCore no iOS;
- vídeo;
- A/V sync;
- fontes remotas;
- Bluetooth completo;
- chamadas/audio focus completo;
- background longo;
- gravação;
- YouTube/embedded sources.

Portanto:

```text
SPIKE 1
Flutter → C++ → Rubber Band → Audio
```

deve ser seguido por:

```text
SPIKE 2
Native Media Playback → PCM/DSP → Audio
                  + Video sync
```

antes de considerar a arquitetura de reprodução inteira congelada.

---

# 19. Entregáveis obrigatórios

O Codex só pode marcar o spike como concluído se existirem:

```text
packages/audio_core/
apps/audio_spike/

SPIKE_RESULTS.md
spike_android.csv
spike_ios.csv

screenshots/metrics opcional
```

E `SPIKE_RESULTS.md` deve conter:

```text
Commit:
Flutter:
NDK:
Xcode:
Rubber Band:
Devices:

ANDROID
device
buffer
sample rate
P50/P95/P99
underruns
loop
memory
PASS/FAIL

iOS
device
buffer
sample rate
P50/P95/P99
underruns
loop
memory
PASS/FAIL

GO / CONDITIONAL GO / NO-GO

Blockers:
Next action:
```

---

# 20. Prompt pronto para Codex

```text
Execute o spike definido em docs/SPIKE_FLUTTER_CPP_RUBBERBAND.md.

Antes de alterar código:
1. leia PROJECT_MEMORY.md;
2. leia ARCHITECTURE_DECISIONS.md;
3. leia TECHNICAL_SPEC.md;
4. leia AUDIO_ARCHITECTURE.md;
5. leia a matriz QA.

Escopo:
Flutter UI mínima → Dart FFI → C ABI → C++ AudioCore → Rubber Band → saída nativa.

Android:
Oboe/AAudio backend.

iOS:
AVAudioSession + AudioUnit RemoteIO backend.

Regras:
- nenhum processamento de áudio em Dart;
- nenhum callback por buffer para Flutter;
- Rubber Band apenas atrás de DspProcessor;
- nenhum I/O/DB/network/log síncrono no callback real-time;
- buffers pré-alocados;
- parâmetros via atomics/estrutura non-blocking;
- usar monotonic clocks;
- medir P50/P95/P99/MAX;
- não implementar UI final;
- não implementar YouTube;
- não implementar acordes/cloud/gravação;
- não integrar vídeo neste spike.

Execute por tarefas S-000 a S-010.

Ao final, gere:
- SPIKE_RESULTS.md
- spike_android.csv
- spike_ios.csv

Não declare GO sem resultados de dispositivo físico Android e iOS.

Se o código/artefacto necessário para avaliação interna não estiver disponível,
pare em um blocker explícito; não substitua silenciosamente a biblioteca.
Não distribua APK/IPA proprietária contendo Rubber Band sem licença comercial
válida do publicador; a compra exige autorização separada do utilizador.

Se uma decisão permanente mudar, atualize ARCHITECTURE_DECISIONS.md e PROJECT_MEMORY.md.
```
