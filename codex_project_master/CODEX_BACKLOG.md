# CODEX BACKLOG

Formato:
- ID
- objetivo
- dependências
- critérios
- testes associados

## EPIC 0 — Foundation

### CORE-001 — Mapear arquitetura atual

Dependências: nenhuma.

Tarefa:
- inspecionar projeto;
- listar stack;
- dependências;
- pontos de entrada;
- player atual;
- storage atual;
- riscos.

Aceitação:
- nenhum código funcional alterado;
- relatório `CURRENT_ARCHITECTURE.md`.

### CORE-002 — Criar módulos/layers

Depende: CORE-001.

Aceitação:
- boundaries conforme TECHNICAL_SPEC;
- build continua verde;
- nenhuma feature quebrada.

### CORE-003 — Logging sanitizado

Aceitação:
- logger único;
- níveis;
- redaction de token;
- release sem logs sensíveis.

### CORE-004 — Feature flags

Aceitação:
- flags tipadas;
- defaults;
- sem uso como segurança de entitlement.

## EPIC 1 — Player Core

### PLAYER-001 — Implementar PlayerState

Depende: CORE-002.

Aceitação:
- estados do STATE_MACHINES;
- transições testadas;
- nenhuma combinação impossível.

Tests:
- AUD-001/002/004.

### PLAYER-002 — MediaSource abstraction

Aceitação:
- LocalFileSource funcional;
- capabilities tipadas.

### PLAYER-003 — Load/unload

Aceitação:
- recursos libertados;
- novo load não duplica sessão.

Tests:
- AUD-008: recuperação após falha de carregamento (caminho de estado em unit test; decoder real pendente);
- AUD-004: ausência de recurso duplicado em loads concorrentes (integração de áudio pendente).

### PLAYER-004 — Play/Pause

Metas:
- P95 < 100 ms.

Tests:
- AUD-001: fronteira de confirmação Play coberta por unit test; latência acústica e P50/P95/P99 pendentes de backend/dispositivo;
- AUD-002: fronteira de confirmação Pause coberta por unit test; silêncio real e P95/P99 pendentes de backend/dispositivo;
- AUD-004: 20 sequências de 30 alternâncias em fake serializado; ausência de áudio duplicado em dispositivo pendente.

Integração piloto (2026-09-24): `apps/mobile` liga Player Core ao plugin
`video_player` com ficheiros locais e amostra WAV. O ACK do plugin é de comando,
não do primeiro buffer audível; nenhuma meta P95 é considerada aprovada por
esta integração. O backend `video_player` permanece piloto; a arquitetura
local-alvo escolhida posteriormente em ADR-012 ainda não foi integrada.

### PLAYER-005 — Seek

Tests:
- AUD-003: validação de faixa, serialização e posição reportada em unit tests;
  seek no Android com WAV local confirmado na UI; erro de posição acústico e
  P95 até áudio pronto ainda pendentes de instrumentação;
- AV-005: vídeo com A/V sync ainda pendente de ativo de teste e medição física.

### PLAYER-006 — End of media

Tests:
- AUD-007: 100 fins de faixa em fake sem reinício espontâneo, duplicação ou
  recurso residual; no Samsung, WAV local de 12 s chegou a ENDED com posição
  reportada 00:12/00:12 e Recomeçar exigiu toque. As 100 repetições físicas e
  a medição independente da posição final (±100 ms) ainda estão pendentes.

### PLAYER-007 — Fullscreen same-session

Aceitação:
- mesma session id: teste de widget confirma a mesma instância da sessão,
  `sessionId` e fonte, sem novo load;
- zero áudio duplicado: um único controlador de media é reutilizado e o vídeo
  embutido é retirado da árvore enquanto a rota fullscreen está aberta;
  medição acústica independente ainda pendente;
- estado preservado: teste de widget confirma PLAYING -> PAUSED no fullscreen
  e retorno sem release. No Samsung SM-A165F, vídeo MP4 local preencheu a tela,
  comandos apareceram ao toque e desapareceram após o timeout; retorno
  preservou PAUSED em 00:01 e reprodução posterior terminou em ENDED em 00:07.
  O clipe temporário de QA não foi incluído na aplicação.

## EPIC 2 — Audio Engine

### AUDIO-001 — Definir audio processing interface

Aceitação:
- UI não importa DSP concreto: `packages/audio_engine` é Dart puro e o app
  continua sem dependência/import de biblioteca DSP;
- contrato separa ACK de comando da aplicação efetiva por sequência e estado
  confirmado, com capacidades independentes de pitch e time-stretch;
- 3 testes de contrato passam. Há um render DSP nativo isolado no spike S-003,
  mas ainda não há processamento ao vivo, medição de latência ou ligação ao
  player Flutter. ADR-011 e ADR-012
  foram escolhidos tecnicamente depois; implementação e gates seguem abertos.

### AUDIO-002 — Pitch

Metas:
- P95 < 150 ms;
- sem clicks.

Tests:
- fase de aplicação concluída: `PitchController` valida -12…+12 semitons,
  distingue pendente/confirmado, preserva speed e reverte intenção após falha;
  6 testes automatizados cobrem estas regras, comandos rápidos e reset;
- PITCH-001..007 acústicos/integração ainda pendentes: S-005 ligou os
  parâmetros Media3 ao **mesmo player de áudio local Android** usado pela UI;
  não há medições de saída acústica, latência/clicks/persistência nem iPhone;
- opções comparadas em `docs/AUDIO_002_DSP_OPTIONS.md`; ADR-014 substitui
  ADR-011 para implementar sem Rubber Band. S-003 confirmou digitalmente -2
  semitons em WAV local; S-004 confirmou parâmetros Media3 e mudança durante
  reprodução no Samsung, **sem medição acústica**. AUDIO-002 permanece parcial,
  não aprovado nas metas físicas.

### AUDIO-003 — Speed/time stretch

Metas:
- P95 < 150 ms;
- pitch preservado.

Tests:
- SPEED-001..007.
- S-003 interno mediu WAV 0,75x próximo de 16 s (entrada de 12 s), mantendo
  frequência próxima de 440 Hz; ainda não é speed ao vivo nem gate físico.
- S-004 Media3 aceitou 0,75x e depois 1,25x durante playback no Samsung; falta
  medir saída real, qualidade e latência. S-005 integrou os controlos no
  player de áudio local Android, com teste UI de reprodução e pausa.

### AUDIO-004 — Pitch + speed combinado

Tests:
- DSP stress;
- AV-004.

### AUDIO-005 — Underrun instrumentation

Aceitação:
- contador;
- timestamp;
- debug overlay.

## EPIC 3 — Loop

### LOOPDEV-001 — Loop domain model

Aceitação:
- invariant A < B.

Estado: `LoopRange` implementado e testado com posições de mídia; sem
persistência ou edição ao vivo.

### LOOPDEV-002 — A/B execution

Tests:
- LOOP-001;
- LOOP-002.

Estado: Media3 Android recorta/repite no mesmo player, sem timer UI; ensaio
Samsung com A=2 s/B=4 s contou duas voltas. Botões A/B e Seek fora testados.
Metas LOOP-001/002 (1000 voltas, erro/drift acústicos) **não aprovadas**.

### LOOPDEV-003 — Loop curto/longo

Tests:
- LOOP-003/004/005.

Estado: ensaio Android de 500 ms/100 transições com alterações dinâmicas de
Tom/Velocidade passou; parâmetros Media3 persistiram após desligar o loop.
Ainda faltam meta completa, loop longo, captura acústica de clicks/precisão e
dispositivos adicionais. LOOP-003/004/005 **não aprovados**.

### LOOPDEV-004 — Edit A/B live

Tests:
- LOOP-006/007.

Estado: UI Android permite editar A/B com loop ativo, rejeita intervalo
inferior a 1 ms e só confirma marcador após reconfiguração. Teste de UI e
200 edições de cada ponto em profile no Samsung passaram para estado/comandos.
Ainda faltam latência e continuidade/clicks medidos na saída; LOOP-006/007
**não aprovados**.

### LOOPDEV-005 — Seek interaction

Comportamento:
- seek fora desativa loop, preserva A/B.

Tests:
- LOOP-008.

Estado: teste profile no Samsung com 100 ciclos de Seek dentro e fora de A/B
passou para estado, preservação de marcadores e Tom/Velocidade. A posição final
foi reportada fora do intervalo. LOOP-008 continua sem prova da saída física.

### LOOPDEV-006 — Save loops

Aceitação:
- persistência;
- rename/delete;
- Undo ou confirmação.

### LOOPDEV-007 — Alternar loop durante playback

Teste de 100 ciclos ON/OFF no Samsung passou para comandos, estado e retenção
de marcadores/Tom/Velocidade. LOOP-009 continua parcial: duplicação de saída,
lacunas e clicks exigem medição acústica.

## EPIC 4 — Persistence/Recovery

### STATEDEV-001 — Session snapshot schema

Estado 2026-09-25: implementado schema v1 e validação de fonte/intervalos/campos
finitos. Sem intenção PLAYING. Testes de round-trip e formato futuro; treino
automático ainda não existe e os seus campos permanecem nulos.

Aceitação:
- versionado;
- validação.

### STATEDEV-002 — Autosave service

Estado 2026-09-25: implementado na UI de produção, confirmação de parâmetros,
posição por throttle 5 s, pausa/background e escrita transacional. Testes de
concorrência, erro/retry e confirmação versus intenção pendente passaram.

Aceitação:
- eventos imediatos;
- posição debounced;
- transacional.

### STATEDEV-003 — Restore service

Estado 2026-09-25: local pausado e YouTube metadata-only até toque explícito,
erro sem sobrescrever snapshot bom e adoção explícita do estado atual. Gates
físicos/estatísticos têm o estado e evidências em `docs/RECOVERY_RESEARCH_AND_QA.md`;
não declarar STATE-001/002 completos por um só ensaio.

Aceitação:
- process death sem autoplay.

Tests:
- STATE-001/002.

### STATEDEV-004 — Last Known Good

Estado 2026-09-25: duas gerações SQLite, fallback de payload e rollback testados
com SQLite real via FFI. Banco ilegível preservado. Kill físico durante escrita
e hot-journal excepcional ainda exigem QA.

Tests:
- STATE-007/008.

### STATEDEV-005 — Schema migration

Estado 2026-09-25: versão inicial v1 e bloqueio de versão futura implementados;
nenhuma migração v1→v2 é alegada. Gate de atualização permanece aberto.

Tests:
- STATE-006.

### STATEDEV-006 — Recovery timing instrumentation

Estado 2026-09-25: duração de restauração instrumentada no coordenador e probe.
Não equivale aos marcos completos cold-launch/first-frame/audio-ready nem a P95.

Tests:
- STATE-009.

## EPIC 5 — Platform lifecycle

### PLATFORM-001 — Audio focus adapter

Tests:
- INT-001..006.

### PLATFORM-002 — Bluetooth route adapter

Tests:
- BT-001..007.

### PLATFORM-003 — Background lifecycle

Tests:
- BG-001/002/005.

Estado: política provisória Android pausa ao sair de foreground e não retoma
automaticamente; teste profile com evento `paused` simulado por 10 s no
Samsung preservou controles e A/B. Faltam Home/bloqueio reais, 500 ciclos,
process death e serviço de mídia para playback contínuo. **Não aprovado**.

### PLATFORM-004 — Lock/unlock

Tests:
- BG-003/004.

### PLATFORM-005 — Safe route-loss policy

Aceitação:
- BT disconnect não dispara speaker inesperadamente.

## EPIC 6 — Player UX

### UX-001 — Player layout final

Aceitação:
- hierarquia definida na memória;
- sem informação técnica.

### UX-002 — Fullscreen overlay

Aceitação:
- controls overlay;
- auto-hide;
- vídeo não encolhe.

### UX-003 — Gestures

Aceitação:
- alternativas por botões;
- lock;
- acessibilidade.

### UX-004 — Collapsible study tools

## EPIC 7 — Practice

Atualização do percurso YouTube — 2026-09-25: ADR-018 confirma comandos WebView,
ordena snapshots e invalida Play pendente; Pausa prioritária permanece acessível
durante ajustes. Prova física de 43 s no Samsung passou com busca real,
pitch +1, A/B 20–22 s, 60→65→70%/duas voltas por etapa, pausa/retoma, fullscreen
sem recarga e ajuste manual suspendendo automação. Isso complementa a prova
Media3/offline descrita abaixo, sem aprovar anúncios reais, iPhone, acústica,
longa duração ou recuperação com treino. Evidência: `docs/YOUTUBE_PRACTICE_QA.md`.
Suíte atual: 260 mobile + 56 Core + 47 JS/WASM = 363; análise Flutter limpa.

### PRACTICE-001 — Practice state machine

Estado 2026-09-25: implementado; testes direcionados e um percurso físico
Media3/fixture WebView offline passaram. Limites em `docs/PRACTICE_PROGRESSION_QA.md`.
`PracticeController` coordena a sessão única do player em
notStarted/preparing/running/paused/completed/aborted. Pausar/encerrar invalidam
operações pendentes; mudança de fonte/trecho invalida a sessão incompatível.
Navegar entre painéis não é criar outro motor. ADR-017.
Fonte/A-B diferente invalida também plano pausado; voltar à mesma faixa não
ressuscita a sessão anterior e exige iniciar/recomeçar.

Gates: PRACTICE-QA-004/005/006/007/009 no documento de pesquisa. Chamadas/BT,
background, callbacks atrasados e fontes remotas exigem provas próprias.

### PRACTICE-002 — Progressive speed plan

Estado 2026-09-25: implementado; plano 60→65→70%, duas voltas por etapa,
pausa/retoma e término pausado passaram em Media3 no Samsung SM-A165F.
Início/alvo 50–150%, incremento 1–20 pontos percentuais, 1–20 voltas por etapa.
Default 60→100%, +5, três voltas por etapa. Nova etapa faz pausa breve,
confirma velocidade, volta a A e reproduz; não se alega progressão gapless.
Editar exige encerrar o plano; avançar manualmente não simula voltas concluídas.
Completar a etapa-alvo pausa, sem atribuir nota musical ao utilizador.

Gates: PRACTICE-QA-001/003/004/010/011/012. Testes direcionados e percurso curto
não aprovam gates prolongados, acústicos ou de todas as plataformas.

### PRACTICE-003 — Repetition counter

Estado 2026-09-25: contagem real Media3/WebView implementada; seis voltas nativas
e duas voltas WebView offline passaram em hardware, incluindo exclusão de
retorno parcial. Isso não comprova YouTube real nem anúncios reais.
Não usa duração × velocidade ou timer para inferir repetições.
Adaptadores distinguem revisões/epochs e fronteiras próprias de seek, anúncio e
troca de mídia. Voltas agrupadas na mesma taxa não inventam etapas noutras taxas.
Fonte sem observação confiável permanece em manual; no YouTube, B no fim da
mídia fica conservadoramente sem capability automática.

Gates: PRACTICE-QA-002/006/009/011/012. Evento lógico não comprova precisão
acústica, clicks, drift ou execução musical. LOOP/PITCH/SPEED permanecem separados.

### PRACTICE-004 — Song sections

Estado 2026-09-25: trechos A/B nomeados e guardados continuam disponíveis pelas
coleções existentes. Biblioteca completa de estrutura/partes da música e
encadeamento automático de vários trechos permanecem pendentes. Não converter
esta entrega do treino de um loop em conclusão de todo PRACTICE-004.

### PRACTICE-005 — Resume practice session

Estado 2026-09-25: integração de plano/progresso no snapshot v2, compatível com
leitura v1, com testes de widget/storage aprovados. Prova física específica de
process death/reboot com treino permanece pendente.
Persistir etapa/taxa confirmada, voltas completas, plano e identidade do trecho.
Recuperar ativo como pausado; retoma explícita inicia volta pendente em A.
YouTube não é aberto no startup; falhas seguem a política não destrutiva existente.

Aceitação:
- progress persistido.

Gates: PRACTICE-QA-008 e STATE-001..009 aplicáveis. O probe antigo de recuperação
do player, sem plano de treino, não aprova automaticamente este novo estado.
Pesquisa/contratos: `docs/PRACTICE_PROGRESSION_RESEARCH.md`.
Evidências verificadas: `docs/PRACTICE_PROGRESSION_QA.md`. Build release instalada
por atualização sem desinstalar o pacote normal; amostra anterior recuperada
pausada v1→v2 e card conferido. Isso não é prova de kill físico contendo treino.
Suíte final: 215 testes mobile, 56 Player Core e 35 JavaScript/WASM aprovados
(306 automatizados), com análise Flutter limpa. Grupos direcionados de testes
já fazem parte desse total; os dois cenários físicos QA são adicionais.

## EPIC 8 — Presets/Library/Setlists

### DATA-001 — Presets CRUD

### DATA-002 — Apply preset transaction

### DATA-003 — Library

### DATA-004 — Setlists CRUD

### DATA-005 — Reorder setlist

### DATA-006 — Per-song overrides

## EPIC 9 — Stage

### STAGE-001 — Stage screen

### STAGE-002 — Stage lock

### STAGE-003 — Setlist navigation

### STAGE-004 — Quick tuner/metronome

## EPIC 10 — Recording

### REC-001 — Permission flow

### REC-002 — Recording state machine

### REC-003 — Incremental file writer

### REC-004 — Interruption-safe finalize

Tests:
- INT-003.

### REC-005 — Take library

### REC-006 — Crash recovery

Aceitação:
- no corrupted-valid take.

## EPIC 11 — Music intelligence

Somente após estabilidade do core.

### MUSIC-001 — BPM

### MUSIC-002 — Key detection

### MUSIC-003 — Chord timeline

### MUSIC-004 — Chord transposition

### MUSIC-005 — Structure/sections

## EPIC 12 — Security

### SEC-001 — Secret audit

### SEC-002 — Secure token storage

### SEC-003 — WebView allowlist/bridge audit

### SEC-004 — Import validation

### SEC-005 — Production logging audit

### SEC-006 — Entitlement server validation

## EPIC 13 — QA

### QA-001 — Debug overlay

### QA-002 — Percentile collector

### QA-003 — Loop synthetic tests

### QA-004 — A/V flash-click asset

### QA-005 — Restore stress harness

### QA-006 — Export diagnostics

### QA-007 — Release report generator

## Ordem recomendada

```text
CORE
→ PLAYER
→ AUDIO
→ LOOP
→ STATE
→ PLATFORM
→ PLAYER UX
→ PRACTICE
→ DATA
→ STAGE
→ RECORDING
→ MUSIC INTELLIGENCE
```

Security e QA correm transversalmente.

## Regra para cada tarefa

Antes:
- listar ficheiros a alterar;
- citar docs relevantes;
- declarar riscos;
- declarar testes.

Depois:
- resumo de alterações;
- testes executados;
- métricas;
- dívidas/remanescentes;
- atualizar memória/ADR quando necessário.
