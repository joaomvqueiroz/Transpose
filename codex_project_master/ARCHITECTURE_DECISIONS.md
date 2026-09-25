# ARCHITECTURE DECISIONS

Formato:

```text
ADR-ID
Status: Accepted | Proposed | Open | Superseded
Decision
Why
Consequences
```

## ADR-001 — Local-first

Status: Accepted

Decision:
Pitch, speed, loops, presets, setlists, progresso e gravações devem funcionar localmente sempre que possível.

Why:
Latência, privacidade, disponibilidade e experiência offline.

Consequences:
Cloud é complementar, não base do Player.

## ADR-002 — Modular boundaries

Status: Accepted

Decision:
Separar Player Core, Audio Engine, Practice Engine, User Data e Platform Services.

Why:
Testabilidade e evitar acoplamento UI/DSP.

## ADR-003 — Player por state machine

Status: Accepted

Decision:
Usar estados explícitos em vez de múltiplos booleanos independentes.

## ADR-004 — Fullscreen reutiliza mesma sessão

Status: Accepted

Decision:
Fullscreen é outra apresentação da mesma `MediaSession`.

Why:
Evitar áudio duplicado e divergência de posição.

## ADR-005 — No autoplay após recovery

Status: Accepted

Decision:
Process death, crash ou reboot restaura em READY/PAUSED.

Why:
Segurança e previsibilidade.

## ADR-006 — WebView isolada

Status: Accepted

Decision:
WebView não recebe acesso direto a secure storage/DB/APIs privilegiadas.

## ADR-007 — SQLite/local transactional store

Status: Proposed

Decision:
Usar armazenamento local relacional transacional como default.

Why:
Snapshots consistentes, setlists, loops, migrações.

Confirmar conforme stack existente.

## ADR-008 — Audio master clock

Status: Accepted para fontes locais com DSP (restantes fontes dependem de ADR-013)

Decision:
Quando tecnicamente suportado, usar o clock de apresentação de áudio como referência principal e sincronizar vídeo a ele.

Why:
Áudio é crítico para músicos e time-stretch/pitch tornam timers de UI inadequados.

Validar offset e drift nos dispositivos antes de aprovar o gate A/V.

## ADR-009 — Safe Bluetooth disconnect

Status: Proposed

Decision:
Ao perder headset Bluetooth durante playback, pausar em vez de reproduzir automaticamente no speaker.

Why:
Evitar blast inesperado.

Validar com testes de UX/plataforma.

## ADR-010 — Stack mobile

Status: Accepted

Decision:
Usar Flutter para App Shell/UI e módulos de aplicação em Dart, mantendo o
Player Core independente de widgets. O caminho de áudio a validar é Dart FFI →
C ABI → C++ AudioCore, com adapters nativos Android/iOS.

Why:
- o pedido de produto de 2026-09-24 escolhe explicitamente esta stack;
- o repositório auditado não contém implementação legada a preservar;
- Dart puro permite testar o domínio sem acoplar UI, media SDK ou DSP;
- C ABI mantém uma fronteira estável para o núcleo C++ partilhado.

Consequences:
- Flutter/Dart passam a ser a stack da aplicação;
- DSP e media playback continuam decisões separadas (`ADR-011`/`ADR-012`);
- a viabilidade real-time do caminho FFI/C++ continua sujeita ao spike em
  Android e iOS físicos;
- código de domínio não pode importar widgets nem plugins de plataforma.

## ADR-011 — DSP library

Status: Superseded by ADR-014 (registo histórico do spike interno)

Decision:
Adotar **Rubber Band Library** como processador-alvo de pitch e time-stretch
para fontes locais processáveis. Usar `RubberBandStretcher` em modo real-time,
encapsulado exclusivamente atrás de `DspProcessor`. Começar o spike com o
engine R2/Faster; comparar R3/Finer em qualidade, CPU e latência no hardware
alvo antes de selecionar o preset do produto. Nunca chamar setters em
concorrência com `process()`: comandos FFI são entregues ao núcleo e aplicados
no thread de processamento em ponto seguro. Pré-alocar buffers e medir
latência de saída efetiva, não apenas ACK de comando.

Why:
- [documentação do autor](https://www.breakfastquay.com/rubberband/code-doc/)
  confirma pitch e tempo independentes, modo real-time e as restrições de
  thread safety/alocação;
- relatos de utilizadores/developers de [Mixxx](https://www.reddit.com/r/DJs/comments/dv1d2b/),
  [Ardour](https://discourse.ardour.org/t/time-stretching-of-bad-quality/86904)
  e de uma [ferramenta de prática musical](https://www.reddit.com/r/DSP/comments/1uy2g9x/rubband_tensorfriendly_bindings_to_the_c_rubber/)
  favorecem Rubber Band para qualidade musical; são experiências, não
  benchmarks do nosso app;
- SoundTouch fica como alternativa de menor custo CPU, não como default de
  qualidade; Signalsmith Stretch (MIT) permanece fallback de licenciamento,
  ainda sem validação mobile/latência equivalente.

Consequences and gates:
- A [licença do autor](https://breakfastquay.com/rubberband/license.html) é
  GPL para a distribuição open-source ou comercial para app proprietária.
  **Não publicar nem entregar APK/IPA proprietária contendo Rubber Band sem
  licença comercial válida em nome do publicador.** Nenhuma licença foi
  comprada nesta decisão. O autor distingue licença de distribuição da
  avaliação/desenvolvimento; o spike deve permanecer interno até resolução.
- A escolha não aprova P95, clicks, CPU, A/V sync ou iOS: executar S-003 e os
  gates do spike em Android e iPhone físicos antes de declarar GO.
- Se custo/licença ou métricas tornarem esta opção inviável, reabrir ADR-011 e
  comparar Signalsmith; não trocar biblioteca silenciosamente.
- Sequência de execução em 2026-09-24: avançar S-003 **internamente** para
  reduzir o risco técnico DSP enquanto a medição acústica e os XRuns de S-002
  permanecem abertos. Isto não promove S-002 a PASS nem autoriza distribuir
  Rubber Band em APK/IPA proprietária; ver `docs/AUDIO_SPIKE_PROGRESS.md`.

## ADR-012 — Media playback stack

Status: Superseded by ADR-014 for the product path (spikes S-002/S-003 retained)

Decision:
Para ficheiros **locais processáveis**, uma só `PlayerSession` coordena uma
única saída de áudio nativa: PCM descodificado → `DspProcessor` → Oboe no
Android e RemoteIO/AVAudioSession no iOS. Android usa APIs nativas de
extração/descodificação (MediaExtractor/MediaCodec); iOS usa AVAssetReader
para PCM. Vídeo é apresentado por componentes nativos Media3/AVFoundation
**sem segunda saída de áudio**, sincronizado à posição de apresentação de
áudio do núcleo. Flutter permanece apenas UI/controlo. `video_player` é
piloto substituível e não será ligado em paralelo à saída DSP.

Why:
- Oboe é [recomendado pelo Android](https://developer.android.com/ndk/guides/audio)
  para áudio de alto desempenho e já abriu output no Samsung do spike;
- Media3 permite processamento PCM, mas [relatos de desenvolvedores](https://github.com/google/ExoPlayer/issues/8722)
  mostram lag de controlo na ordem de centenas de ms em cadeias de áudio; isso
  põe em risco o objetivo P95 < 150 ms de Tom/Velocidade. Tirar PCM de um
  player e tocar externamente também tem [risco observado de sync em
  seek/loop](https://github.com/google/ExoPlayer/issues/10929);
- AVAssetReader pode fornecer [PCM descodificado](https://developer.apple.com/documentation/AVFoundation/AVAssetReaderTrackOutput),
  e AVFoundation expõe [frames de vídeo](https://developer.apple.com/documentation/avfoundation/avplayeritemvideooutput);
  a combinação concreta e o scheduler ainda precisam de prova em iPhone.

Consequences and gates:
- O áudio é o clock master para o modo DSP local; UI nunca soma timers para
  inventar posição. Isto fixa a direção de ADR-008 apenas neste modo.
- S-002/S-003 provam output/DSP; depois medir A/V offset/drift, seek, loop,
  background, interrupções e troca de rota. Não declarar release nem métricas
  aprovadas antes desses testes em Android e iOS.
- Fontes remotas/protegidas continuam sob ADR-013: usar as capabilities
  efetivas do adapter; não prometer pitch/loop onde não há PCM autorizado.

## ADR-013 — Online source strategy

Status: Open

Decision pendente:
Quais fontes externas serão oficialmente suportadas e quais capabilities existem por fonte.

Não acoplar o produto a uma única integração antes desta decisão.

## ADR-014 — Tom e Velocidade sem Rubber Band

Status: Accepted as the next implementation path; acoustic release gate open

Decision:
Tom e Velocidade independentes continuam funcionalidades centrais. Por escolha
do utilizador, a implementação de produto deve avançar **sem Rubber Band** e
sem uma segunda saída de áudio paralela. Testar primeiro processamento no
próprio player nativo: Media3 `PlaybackParameters(speed, pitch)` em Android e
`AVAudioUnitTimePitch` no iPhone. Manter `AudioProcessingPort` e o estado de
aplicação confirmada independentes do backend. Os spikes Rubber Band/Oboe
continuam apenas como evidência técnica, fora da build normal; não publicar
APK/IPA com Rubber Band sem licença válida.

Why:
- [Media3](https://developer.android.com/reference/androidx/media3/common/PlaybackParameters)
  e [AVAudioUnitTimePitch](https://developer.apple.com/documentation/avfaudio/avaudiounittimepitch)
  expõem Tom e Velocidade independentes sem esta licença de terceiros;
- no Samsung SM-A165F, um probe isolado Media3 1.9.2 preparou WAV local,
  aceitou −2 semitons/0,75× e alteração ao vivo para +3/1,25×, com avanço de
  posição coerente; isto **não** mede saída acústica, latência de aplicação
  nem qualidade musical;
- a escolha reduz dependência de licenciamento, mas exige adapters Android/iOS
  separados e prova de equivalência funcional.

Consequences and gates:
- Integrar os controlos no **mesmo player que possui a saída**; nunca iniciar
  simultaneamente o probe ou o antigo núcleo Oboe para a mesma faixa.
- Medir em hardware a latência comando→som (P50/P95/P99), artefactos, loops,
  seek, sincronização A/V, interrupções e diferenças entre Android/iPhone.
- Se a qualidade ou latência do backend nativo falhar, comparar alternativas
  de licença permissiva antes de reconsiderar uma biblioteca comercial.
- S-005 integrou Media3 no áudio local Android com uma única saída para
  Play/Pausa/Seek e Tom/Velocidade; o probe S-004 continua isolado. Isto ainda
  não satisfaz os gates acústicos nem implementa a via iPhone/vídeo.

## ADR-015 — Painéis funcionais sobre uma sessão, recursos avançados por etapas

Status: Accepted — 2026-09-25; gates de release continuam abertos.

Decision: completar fullscreen e converter Prática/Palco/Acordes em projeções
do mesmo player. Presets e setlist têm CRUD local; cifras/tempos/notas são
introduzidos manualmente e persistidos por fonte. Remover dados fictícios da
interface funcional, preservando os arquivos de referência. Não implementar
progresso automático por estimativas de timers nem alegar detecção musical.

Why: relatos de criadores/músicos favorecem controles de tempo acessíveis e
loops úteis; documentação oficial sustenta a integração nativa e obriga atenção
ao foco/lifecycle. Pesquisa, alternativas, links e limites em
`docs/FULLSCREEN_AND_STUDY_DELIVERY.md`.

Consequences: Media3 continua sendo o caminho Android de áudio local. YouTube
WebView/pitch continua experimental. Estado do motor confirmado é a fonte para
todos os painéis; fullscreen e troca de painel não criam outra saída. IA/stems,
detecção automática e gravação aguardam recuperação e segurança do núcleo.

## ADR-016 — Recuperação transacional e fontes locais duráveis

Status: Accepted — 2026-09-25; gates estatísticos e de plataforma abertos.

Decision: usar SQLite somente para o snapshot versionado atual e a cópia
anterior válida, gravados na mesma transação. `SessionRecoveryController`
persiste confirmações do player e checkpoints de posição a cada 5 s durante
reprodução, também ao pausar/background. Não depender de callback de saída.
Não migrar as coleções existentes nesta entrega nem introduzir cloud/contas.

Why: [shared_preferences](https://pub.dev/packages/shared_preferences) não se
propõe a persistência crítica; [SQLite](https://www.sqlite.org/atomiccommit.html)
oferece transações com rollback. Os [relatos de manutenção Flutter](https://www.reddit.com/r/FlutterDev/comments/tzqwpg/)
informam os riscos de manutenção, mas não são uma prova de superioridade universal.
Pesquisa e alternativas: `docs/RECOVERY_RESEARCH_AND_QA.md`.

Consequences:
- Áudio/vídeo local é preparado pausado; fullscreen não reabre sozinho.
- YouTube mostra somente metadata até toque explícito; sem criar WebView no
  relaunch por causa da sessão guardada. Não acrescentar extração/download.
- Importações novas usam cópia privada persistente, concluída antes de trocar
  a fonte; originais permanecem intactos. Caminhos de cache antigos não são
  migrados automaticamente. Gestão de espaço da biblioteca fica pendente.
- Falha de recuperação mantém os ajustes e exige tentativa/seleção explícita
  ou adoção do estado atual; não sobrescrever uma sessão boa com estado parcial.
- Formatos futuros e banco ilegível suspendem escrita preservando os dados.
  Falha transitória ao abrir requer reinício; falha de save permite nova tentativa.
- Fallback e rollback são testáveis; um teste físico não prova P95, 99,9%,
  reboot, falha de alimentação nem precisão relativa ao instante exato do kill.
  Os últimos segundos depois do checkpoint podem não sobreviver ao processo.

## ADR-017 — Prática progressiva por voltas confirmadas

Status: Accepted — 2026-09-25; suíte automatizada e percurso físico Android
aprovados nos limites descritos em `docs/PRACTICE_PROGRESSION_QA.md`. Build
release instalada por atualização e painel conferido. iPhone, YouTube real e
gates acústicos/estatísticos ainda não aprovados por isto.

Decision: acrescentar `PracticeController` sobre o mesmo `MainPlayerController`,
com plano configurável de velocidade inicial/alvo, incremento em pontos
percentuais e voltas por etapa. O padrão é 60→100%, +5 pontos, três voltas em
cada etapa, incluindo a final. Manter treino manual onde a fonte não oferece
contagem confiável. O motor de prática não produz áudio e não usa timers para
inventar repetições.

Why: os relatos do [criador de Practice Hero](https://www.reddit.com/r/Guitar/comments/1ugeobv/i_built_a_tool_to_help_practice_with_youtube/)
e o [pedido concreto de progressão automática](https://www.reddit.com/r/Guitar/comments/1n2b3po/free_tool_for_slowing_down_music_to_help_with/)
mostram utilidade em reduzir ajustes manuais; o [guia oficial Anytune](https://anytune.zendesk.com/hc/en-us/articles/360025666651-Step-It-Up-Loop-Trainer)
documenta início/alvo/repetições e ação final. São sinais e precedentes, não
consenso nem prova de ganho musical. A recomendação, alternativas e gates estão
em `docs/PRACTICE_PROGRESSION_RESEARCH.md`.

Consequences:
- Contagem Media3 usa fronteiras nativas de repetição; WebView usa voltas A/B
  confirmadas pelo seu adaptador, com identidade/revisão da fonte. Seek, evento
  antigo, anúncio e troca de mídia não são voltas de treino.
- Na mudança de etapa, pausar brevemente, aplicar/confirmar taxa, voltar a A e
  retomar. A UI informa a pausa; esta progressão **não é gapless**. Não prometer
  precisão acústica a partir de callbacks lógicos.
- Pausar/encerrar invalidam operações pendentes. Ajuste manual suspende a
  automação; voltar à aba não cria outra sessão. “Próxima etapa” é uma ação
  explícita que não conta voltas que não foram reproduzidas.
- Mudança de fonte/A-B invalida também o plano já pausado. Voltar depois à
  mesma faixa não restaura silenciosamente a possibilidade de retomar o plano
  anterior; é preciso iniciar/recomeçar explicitamente.
- No alvo, completar as voltas e pausar. “Plano concluído” não significa
  “música dominada” nem uma avaliação do instrumento do utilizador.
- Vídeo local sem observação confiável permanece no treino manual. No YouTube,
  B igual ao fim da mídia desativa conservadoramente a capability automática:
  tratar a fronteira final como repetição exigirá prova específica do adaptador.
- Snapshot v2 acrescenta plano/progresso junto do player e continua a ler v1.
  Restauro de treino ativo torna-se pausado; YouTube continua metadata-only até
  ação explícita. Esquemas futuros/ilegíveis mantêm a proteção não destrutiva.
- Não acrescentar cloud, captura do instrumento, avaliação por IA, stems ou
  novos players. Testes de longo prazo, interrupções, recuperação com treino,
  acústica, acessibilidade e iPhone continuam gates separados.

## ADR-018 — Comandos WebView confirmados e intenção de reprodução cancelável

Status: Accepted — 2026-09-25; arquitetura aceita, 363 testes automatizados
aprovados (260 mobile + 56 Player Core + 47 JavaScript/WASM) e Flutter analyze
limpo, repetido após a última alteração do probe. A sétima passagem física aprovou no
Samsung SM-A165F o vídeo YouTube real testado: pitch +1, A20/B22, plano
60→65→70% com seis voltas, pausa/retoma, fullscreen preservando sessão,
conclusão pausada e ajuste manual a 75% suspendendo automação. Nenhum anúncio
foi registrado nos snapshots/eventos; anúncio real não está aprovado.
Build release instalada por `adb install -r`, preservando a sessão anterior,
com smoke visual de recuperação. O percurso YouTube completo passou em profile
QA, não foi repetido em release. iPhone e gates acústicos/estatísticos continuam
abertos; instalação não equivale à aprovação integral de distribuição/release.
Seis tentativas anteriores não aprovadas incluem fragilidades do próprio probe,
não constituem uma estatística de falhas universais do app. Evidências e limites em
`docs/YOUTUBE_PRACTICE_QA.md`.

Decision: manter uma única sessão/WebView e substituir conclusão presumida de
JavaScript por confirmação assíncrona por ID. `WebMediaCommandRunner` envia
`dispatch`, consulta `commandResult` e só devolve resultado tipado quando a
operação termina com snapshot. Publicação de estado usa revisão monotónica
por documento; respostas antigas não revertem confirmações mais recentes.

Why: a preparação do treino depende da ordem real Pausa → taxa → seek → Play.
Enviar um comando não prova sua aplicação; o próprio contrato oficial do
[YouTube](https://developers.google.com/youtube/iframe_api_reference) distingue
taxa solicitada e taxa confirmada. A implementação usa a página principal,
não IFrame API: esse contrato fundamenta a distinção, não garante suporte ao
DOM atual. Eventos de [mídia HTML](https://html.spec.whatwg.org/multipage/media.html)
separam seek, prontidão e reprodução. Relatos e alternativas estão em
`docs/YOUTUBE_PRACTICE_RESEARCH.md`; não representam consenso de developers.

Consequences:
- Prazo compartilhado de 18 s para envio, consultas e polling de 50 ms; cleanup
  limitado a 250 ms no total. Prazo evita espera indefinida, não satisfaz P95
  nem garante execução de cancelamento numa ponte que deixou de responder.
- IDs são idempotentes enquanto retidos na tabela limitada de 64 entradas.
  Cancelar/esquecer um ID não remove outra operação nem permite que callbacks
  antigos recriem o resultado descartado. Documento novo não recebe cleanup
  destinado ao anterior.
- `snapshotRevision` ordena observações dentro do documento, sem substituir
  `loopEpoch` ou revisões de intenção. Navegação descarta respostas antigas;
  JSON/status/snapshot inválidos falham explicitamente.
- Play e pitch pendentes pertencem ao ID/revisão/fonte que os iniciou. Pausa
  invalida Play pendente, sem desfazer um ajuste de tom válido. Descarte,
  cancelamento do pedido e mudanças incompatíveis invalidam o trabalho respectivo; uma conclusão antiga
  não pode iniciar áudio abandonado nem parar um Play novo válido. Cancelar
  pitch pendente vigente conserva áudio original, sem cancelar ajuste novo.
- Play explícito é idempotente e preserva mute. `MainPlayerController` captura
  a intenção antes da fila e envia Play/Pausa/Ativar som explícito, em vez de
  inverter transporte com base num snapshot que pode ter mudado durante await.
- **Pausa é prioritária:** o controller a executa sem esperar a fila. Player
  principal, fullscreen, Prática e Palco permitem Pausa durante `busy` quando a
  fonte já reproduz sem mute; Play novo e Ativar som continuam bloqueados.
  Locks explícitos de fullscreen/Palco são respeitados. Não tornar todos os
  controles ativos por causa dessa exceção de segurança.
- ACK de preparação de pitch não é confirmação de sinal processado;
  `playing` transitório antes de readiness não prova avanço da timeline.
  Probes devem exigir prontidão e avanço efetivo antes de aprovar playback,
  mantendo medição acústica como gate separado.
- Não alterar recuperação sem autoplay, política de anúncio, extração,
  download, CORS/CSP/DRM ou arquitetura DSP. ADR-013 e revisão de distribuição
  continuam abertos, assim como iPhone, chamadas/BT, acústica e uso prolongado.
