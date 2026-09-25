# TECHNICAL SPEC

## 1. Objetivo

Definir arquitetura, contratos e requisitos não funcionais para que o Codex implemente o app sem acoplamento entre UI, reprodução, DSP, persistência e serviços de plataforma.

Este documento é intencionalmente independente de Flutter/React Native/native enquanto a stack final não estiver formalmente decidida.

## 2. Regra de dependências

Direção permitida:

```text
UI
↓
Application / Use Cases
↓
Domain
↓
Ports / Interfaces
↓
Infrastructure / Platform Adapters
```

O domínio não importa widgets, SDK de analytics, WebView, armazenamento concreto ou APIs de plataforma.

## 3. Módulos

### 3.1 App Shell

Responsabilidades:

- bootstrap;
- DI;
- navegação;
- tema;
- feature flags;
- sessão global;
- tratamento de deep links;
- composição dos módulos.

Não deve conter lógica DSP.

### 3.2 Player Core

Responsabilidades:

- lifecycle de `MediaSession`;
- load/unload;
- play/pause;
- seek;
- posição;
- duração;
- buffering;
- fim de faixa;
- fullscreen state;
- ligação ao Audio Engine;
- ligação ao renderer de vídeo;
- state machine do player.

Interface conceitual:

```text
PlayerController
  load(MediaSource)
  play()
  pause()
  seek(position)
  setPitch(semitones)
  setSpeed(rate)
  setLoop(loop?)
  unload()

  state: Stream<PlayerState>
  position: Stream<Duration>
```

### 3.3 Audio Engine

Responsabilidades:

- PCM pipeline;
- time stretch;
- pitch shift;
- volume;
- EQ;
- metering;
- compensação de latência;
- eventos de underrun;
- timing de loop;
- adaptação à rota de áudio.

Nunca deve depender da UI.

### 3.4 Video Renderer

Responsabilidades:

- apresentar frames;
- sincronizar com master clock;
- não controlar diretamente o áudio;
- reportar dropped frames;
- reagir a seek e rate.

### 3.5 Practice Engine

Responsabilidades:

- A/B;
- repetições;
- treino incremental;
- markers;
- partes;
- loops salvos;
- progresso.

Não deve implementar playback; deve comandar o Player Core.

### 3.6 Music Intelligence

Responsabilidades futuras:

- BPM;
- key;
- acordes;
- estrutura;
- análise offline/remota.

Resultado sempre versionado, por exemplo:

```text
analysis_version
algorithm_version
confidence
generated_at
```

### 3.7 User Data

Responsabilidades:

- biblioteca;
- presets;
- setlists;
- loops;
- practice history;
- recordings metadata;
- session snapshot;
- settings.

### 3.8 Platform Services

Adapters para:

- audio focus;
- interruptions;
- Bluetooth/audio routes;
- background;
- lifecycle;
- secure storage;
- file picker;
- microphone;
- haptics;
- brightness/volume gestures.

### 3.9 Optional Cloud

Não obrigatório para o núcleo.

Pode oferecer:

- conta;
- backup;
- sync;
- subscription/entitlement;
- processamento remoto.

O app deve degradar graciosamente sem cloud.

## 4. MediaSource

Abstração:

```text
MediaSource
- id
- type
- displayName
- durationHint?
- capabilities
```

Tipos:

```text
LocalFileSource
AuthorizedRemoteSource
EmbeddedVideoSource
```

Capabilities possíveis:

```text
canSeek
canBackgroundPlay
canProcessAudio
canCache
canExport
canLoopPrecisely
```

A UI deve adaptar ações às capabilities.

Nunca assumir que todas as fontes permitem o mesmo processamento.

## 5. Session Coordinator

Objeto de aplicação que coordena:

- Player;
- Practice;
- Recording;
- autosave;
- interruptions;
- route changes.

Regra: ele orquestra; não processa áudio.

## 6. Clock e timeline

Conceito:

```text
media position
≠ wall clock
≠ UI animation clock
```

Quando possível:

- audio presentation clock é master;
- vídeo segue o audio clock;
- UI apenas observa;
- loop usa posições da timeline de mídia;
- pitch não altera timeline;
- speed altera relação tempo real ↔ media position.

Não calcular posição da música somando timers de UI.

## 7. Threading

### Real-time audio thread

Proibido:

- disk I/O;
- network;
- locks longos;
- JSON;
- DB;
- logs síncronos pesados;
- alocação excessiva;
- chamadas UI.

Permitido:

- processamento PCM previsível;
- estruturas pré-alocadas;
- troca de parâmetros lock-free/segura.

### Worker threads

Usar para:

- decode/preparation;
- análise;
- persistência;
- waveform;
- import;
- export.

### Main/UI

Somente apresentação e eventos de interação.

## 8. Fullscreen

Fullscreen não cria outro player.

É uma representação diferente da mesma `MediaSession`.

Invariante:

```text
normal screen session_id == fullscreen session_id
```

Assim evita:

- áudio duplicado;
- posição diferente;
- loop diferente;
- dois decoders.

## 9. Background

Política deve depender de capability/configuração.

Ao entrar background:

- persistir snapshot;
- manter ou pausar áudio conforme suporte;
- parar renderização de UI desnecessária;
- não continuar animações;
- manter apenas serviços necessários.

## 10. Interruptions

Eventos normalizados:

```text
InterruptionBegan(reason)
InterruptionEnded(shouldResumeHint)
AudioFocusLost(kind)
AudioFocusGained
RouteChanged(old,new,reason)
```

Platform adapter traduz Android/iOS para eventos internos.

Player Core recebe eventos normalizados.

## 11. Persistência

Default recomendado: base local transacional, como SQLite, salvo se a stack atual já tiver decisão equivalente.

Separar:

- entidades duráveis;
- snapshot efémero recuperável;
- ficheiros grandes (áudio/gravações);
- secure storage.

Não guardar blobs grandes de gravação dentro da DB.

## 12. Segurança

Boundary:

```text
External Content
    ↓
Web/Media Adapter
    ↓
sanitized domain models
```

WebView não acessa diretamente:

- auth tokens;
- DB;
- gravações;
- file system arbitrário;
- APIs privilegiadas.

## 13. Observabilidade

Debug builds devem medir:

- player state transitions;
- A/V offset;
- underruns;
- buffer health;
- seek latency;
- pitch/speed apply latency;
- loop error;
- audio route;
- restore duration;
- dropped frames.

Produção deve coletar apenas telemetria necessária e sanitizada.

## 14. Feature flags

Usar para funções arriscadas/futuras:

```text
new_audio_engine
chord_detection
cloud_sync
new_fullscreen_gestures
recording_studio
```

Flag não substitui autorização premium.

## 15. APIs internas

Eventos devem preferir objetos tipados.

Exemplo:

```text
SetPitchRequested(-2)
PitchApplying(-2)
PitchApplied(-2, latencyMs)
```

Evitar stringly typed events.

## 16. Testabilidade

Cada módulo deve ter ports mockáveis:

- clock;
- persistence;
- audio route;
- interruption;
- file source;
- entitlement.

State machines devem ser testáveis sem dispositivo físico.

## 17. Critérios não funcionais

- zero autoplay inesperado após recovery;
- zero áudio duplicado;
- zero corrupção de take em interrupção;
- P95 de ações dentro das metas;
- sem regressões silenciosas em background/BT;
- suporte a low-memory/process death;
- acessibilidade mínima desde o início.

## 18. Decisões ainda abertas

Não decidir silenciosamente:

- Flutter vs React Native vs native;
- biblioteca DSP;
- biblioteca de media playback;
- estratégia exata de integração com fontes online;
- versões mínimas Android/iOS;
- cloud provider;
- auth provider;
- formato final de sync.

Registrar no ADR antes de fechar.
