# Arquitetura atual

Data da auditoria: 2026-09-24

As secções 1–12 registam a auditoria inicial histórica. A implementação posterior
e o estado atual estão nas secções 13–19; o projeto já possui app executável.

## 1. Resumo executivo

O repositório ainda não contém uma aplicação mobile executável. O estado inicial
auditado é um conjunto de documentação de produto/engenharia e seis protótipos
visuais independentes em HTML, CSS utilitário e JavaScript. Não existe código
Dart/Flutter, player de media, motor de áudio, persistência, integração nativa,
testes automatizados ou CI.

Por isso, os protótipos são referência visual e comportamental, não uma base de
runtime que possa ser refatorada incrementalmente. A primeira implementação
reutilizável deve nascer em módulos novos, preservando as fronteiras aceites em
`ADR-002` e sem incorporar os booleanos de demonstração dos HTML.

Baseline Git no início da auditoria:

- branch `main` sem commits;
- `origin` sem branches publicadas;
- 57 ficheiros, todos não rastreados;
- nenhum histórico disponível para distinguir código legado de experiências.

## 2. Inventário do repositório

### 2.1 Documentação de produto e engenharia

`codex_project_master/` contém a fonte de verdade do produto, ADRs, specs,
roadmap, backlog, contratos de comportamento, matriz QA e plano do spike. São
documentos; não existe implementação associada.

O `MANIFEST.json` não lista `SPIKE_FLUTTER_CPP_RUBBERBAND.md`, embora outros
documentos e o pedido atual o tratem como obrigatório. Alguns prompts também
referem `docs/SPIKE_FLUTTER_CPP_RUBBERBAND.md`, mas o ficheiro está atualmente
em `codex_project_master/`.

### 2.2 Protótipos visuais

| Área | Entrypoint isolado | Estado atual |
|---|---|---|
| Player principal | `PlayerPrincipal/stitch_virtuoso_practice_studio/code.html` | layout e microinterações locais |
| Fullscreen | `PlayerFullscreen/stitch_virtuoso_practice_studio/code.html` | overlay, auto-hide e lock simulados |
| Prática | `PaineldePratica/stitch_virtuoso_practice_studio/code.html` | contador/velocidade simulados |
| Acordes | `AcordeSincronizado/stitch_virtuoso_practice_studio/code.html` | disclosures estáticos |
| Palco | `ModoPalco/stitch_virtuoso_practice_studio/code.html` | play, pitch e lock simulados |
| Sidebar | `SidebarMenuLateral/stitch_virtuoso_practice_studio/code.html` | abertura/fecho simulado |

Não há `index`, router ou shell comum. Links de navegação usam `href="#"`.
Cada pasta também contém PNGs, uma cópia `.txt` do protótipo e um `DESIGN.md`.
Os seis `DESIGN.md` são idênticos, e os pares `.txt`/`code.html` representam a
mesma tela com pequenas diferenças de normalização, criando fontes duplicadas.

### 2.3 Linguagens e formatos encontrados

- Markdown e CSV para especificação/QA;
- HTML, CSS/Tailwind e JavaScript vanilla nos protótipos;
- PNGs de referência visual;
- JSON apenas para o manifesto documental.

Não foram encontrados Dart, Flutter, Kotlin, Java de aplicação, Swift,
Objective-C/Objective-C++, C/C++, Gradle de projeto, CMake ou CocoaPods.

## 3. Arquitetura de runtime existente

Não existe runtime de produto. A arquitetura executável atual limita-se a:

```text
Browser
  -> HTML standalone
  -> Tailwind carregado por CDN
  -> JavaScript inline de demonstração
  -> mutação local do DOM
```

Os seis scripts inline passam parsing sintático, e os IDs DOM referidos existem,
mas isso prova apenas as microinterações do protótipo. Nenhum HTML contém
`<audio>`, `<video>`, Web Audio, decoder, timeline ou saída de áudio.

### 3.1 Estado

O estado é local e descartável. Exemplos encontrados:

- `PlayerPrincipal`: `isPlaying` e valores de pitch/speed locais;
- `PlayerFullscreen`: outro `isPlaying`, timer de overlay e lock locais;
- `PaineldePratica`: `isPaused` e velocidade local;
- `ModoPalco`: `isPlaying`, `isLocked` e offset local.

Isto contradiz `ADR-003`: os protótipos usam booleanos independentes e não uma
state machine única. Também não existe uma `MediaSession`, portanto o
invariante de `ADR-004` não pode ser satisfeito nem medido.

### 3.2 Player e media

- não existe player real;
- os frames de vídeo são imagens de fundo remotas;
- posição, duração, loop, pitch e speed são texto/estado visual;
- não existe load, unload, seek, fim de media ou buffering real;
- não existe clock de media nem sincronização A/V.

### 3.3 Persistência

Não existe base de dados, filesystem adapter, secure storage, autosave,
snapshot ou recovery. O repositório não fornece evidência para aceitar ou
rejeitar `ADR-007`.

### 3.4 Integração externa e WebView

Os protótipos carregam Tailwind por CDN, Google Fonts/Material Symbols e imagens
em `googleusercontent.com`. Não há package manager, lockfile, SRI ou execução
offline garantida. Não existe WebView dentro de uma app, bridge nativa, API,
autenticação, token ou cloud.

Os HTML não devem ser empacotados como WebView de produção: são referências de
design dependentes de rede, não uma fronteira segura de produto.

### 3.5 Android, iOS e C/C++

Não existem pastas Android/iOS, C ABI, AudioCore, `DspProcessor`, Rubber Band,
Oboe/AAudio, AVAudioSession ou RemoteIO. Todos aparecem apenas como arquitetura
proposta no documento do spike.

## 4. Testes, QA e entrega

Existe uma matriz manual bem estruturada com 66 casos:

```text
AUD 8   PITCH 7   SPEED 7   LOOP 10
AV 7    BT 7      INT 6     BG 5     STATE 9
```

Não existem:

- testes unitários ou de integração;
- runner/harness;
- mocks/fakes;
- ativos WAV determinísticos;
- instrumentação de latência/underrun;
- resultados do spike;
- workflow de CI;
- configuração de análise estática.

`AUD-001`, `AUD-002` e `AUD-004`, citados por `PLAYER-001`, medem integração
com áudio real. Não conseguem provar isoladamente a state machine e só podem
ser executados de forma honesta quando `PLAYER-004` e o backend existirem.
`PLAYER-001` precisa adicionalmente de testes unitários derivados da tabela de
`STATE_MACHINES.md`.

## 5. O que já funciona

- documentação extensa e coerente sobre produto, módulos, estados e QA;
- identidade visual reproduzida nos seis protótipos;
- microinterações de demonstração: disclosures, drawers, lock visual,
  auto-hide e alterações de texto/ícone;
- touch targets de aproximadamente 44/48 px em vários controlos;
- matriz QA sem IDs duplicados nem campos obrigatórios vazios.

## 6. O que é apenas mock

- reprodução, pausa e posição;
- pitch, speed e loop;
- vídeo e fullscreen de media;
- prática progressiva;
- acordes sincronizados;
- modo palco e setlist;
- estado de DSP/rota/sample rate;
- biblioteca, gravações, presets e progresso;
- navegação entre telas e persistência.

Em particular, a sidebar mostra “Motor DSP Ativo” e “44.1 kHz · 32 bit” sem
qualquer motor existente. Esses valores não podem ser tratados como telemetria.

## 7. Elementos reutilizáveis

- `PROJECT_MEMORY.md` e ADRs aceites como contrato de produto;
- tabela de transições de `STATE_MACHINES.md`;
- matriz QA como catálogo de gates;
- paleta azul-preto/cyan e tokens de tipografia/spacing dos `DESIGN.md`;
- hierarquia das telas e conteúdo em português;
- PNGs e HTML como referência visual durante a implementação Flutter.

Os HTML não devem ser convertidos mecanicamente em widgets. A lógica inline é
descartável; os tokens e a hierarquia visual são o material reutilizável.

## 8. O que precisa ser criado ou refatorado

1. Criar boundaries reais (`App Shell`, `Player Core`, `Audio Engine`,
   `Platform Services`, `User Data`) conforme `ADR-002`.
2. Implementar `Player Core` em Dart puro, sem dependência de widgets, media SDK
   ou DSP concreto.
3. Substituir todos os estados de demonstração por uma única state machine
   observável por sessão.
4. Definir `MediaSource` e capabilities antes de escolher adapters de media.
5. Criar app Flutter e adapters somente depois de existir toolchain validada.
6. Manter fullscreen como apresentação da mesma sessão, nunca como segundo
   player.
7. Traduzir os tokens visuais para tema Flutter e corrigir acessibilidade,
   idioma e semântica dinâmica ao implementar a UI.

## 9. Contradições e lacunas

- `PLAYER-001` depende de `CORE-002` no backlog, mas o pedido atual manda
  avançar diretamente após `CORE-001`. Como não há projeto, a fundação mínima
  de módulos precisa ser criada junto ao primeiro ticket; não é possível
  “encapsular” código inexistente.
- O protótipo principal altera pitch em ±1 semitom; o Modo Palco altera ±2 por
  toque, embora o texto visual diga ±1 Tom. A unidade oficial deve permanecer
  semitom até decisão explícita de UX.
- O protótipo de acordes exibe simultaneamente referências de transposição que
  não são internamente consistentes (`B♭ (-2 st)` e detalhes `+2 semitons`).
- Quatro protótipos declaram `lang="en"` apesar do conteúdo em português.
- Todos desativam zoom no viewport, em tensão com os requisitos de text scaling
  e acessibilidade.
- O design system descreve uma workstation densa, enquanto `PROJECT_MEMORY`
  exige “Simples por fora”. A paleta é reutilizável; a densidade técnica não é.
- Não está definido o comportamento de `PAUSE` durante `BUFFERING`; a state
  machine inicial deve rejeitar a transição em vez de inventar uma regra.
- “qualquer carregado + SEEK” é ambíguo para `ENDED`; a transição explícita
  `ENDED + SEEK_VALID -> PAUSED` deve prevalecer até clarificação.

## 10. Riscos técnicos

| Risco | Impacto | Tratamento imediato |
|---|---|---|
| Ausência de baseline Git | difícil rever/regredir | criar alterações pequenas e verificáveis; não assumir histórico |
| Flutter/Dart ausentes no host | sem build mobile imediato | usar SDK Dart portátil para o domínio e registar o bloqueio Flutter |
| NDK/CMake/Rubber Band ausentes | spike Android bloqueado | concluir S-000 antes do spike |
| Host Windows sem Xcode/iPhone | spike iOS não validável | executar a parte iOS em host macOS com devices físicos |
| Só existe Android fraco disponível | gate GO incompleto | obter também Android médio (6–8 GB) |
| ADRs de DSP/media abertas | risco de acoplamento prematuro | depender apenas de ports/interfaces |
| Assets remotos sem proveniência de licença | risco de distribuição | tratar imagens apenas como referência até validar direitos |
| Prototipagem duplicada | divergência visual/funcional | eleger Flutter como implementação; preservar mocks como referência |

## 11. ADRs

Nenhum ADR aberto pode ser fechado apenas pela implementação atual, porque ela
não existe.

O pedido mais recente escolhe explicitamente Flutter para UI/application e
Dart FFI -> C ABI -> C++ para o caminho a validar. Isso permite atualizar
`ADR-010` para aceite quanto à stack de aplicação. Não fecha:

- `ADR-011` (biblioteca DSP): Rubber Band continua sujeita ao spike/licença;
- `ADR-012` (media playback): Media3/AVFoundation continuam por validar;
- `ADR-013` (fontes online): capabilities continuam por definir por integração;
- `ADR-007`/`008`/`009`: continuam propostas até implementação e teste.

## 12. Fundação alvo imediata

```text
Flutter UI (futura app shell)
  -> Application/controller (futuro)
  -> packages/player_core (Dart puro)
       -> PlayerStateMachine
       -> MediaSource + capabilities
       -> ports futuros para engine/media
  -> adapters Flutter/native (futuros)
```

Esta direção permite testar `PLAYER-001` e `PLAYER-002` sem escolher
silenciosamente a biblioteca de playback ou de DSP e sem depender de hardware.

## 13. Evolução da implementação em 2026-09-24

As secções 1–12 acima preservam a auditoria do repositório **antes** da
implementação. O estado executável agora é:

```text
apps/mobile (Flutter, Android/iOS)
  -> PlayerScreen (estado observado de PlayerSession)
  -> VideoPlayerMediaLoader (piloto substituível)
  -> packages/player_core (Dart puro)
       -> PlayerSession / PlayerStateMachine / MediaSource
  -> video_player (Media3/ExoPlayer Android; AVPlayer iOS)

packages/audio_engine (Dart puro, contrato ainda sem adapter de produção)
  -> AudioProcessingPort / AudioProcessingAppliedState
```

O Android debug foi compilado e instalado num Samsung SM-A165F; a amostra WAV
local carregou e as transições Play/Pause foram observadas na UI sem crash.
O seletor de ficheiros do Android abriu; posteriormente, a importação e
reprodução de um MP4 local foram validadas no Samsung SM-A165F. iOS foi gerado,
mas não compilado neste host Windows.

Os 52 testes de `player_core` e os 2 testes Flutter passam;
ambos os módulos analisam sem erros. A confirmação do plugin representa ACK do
comando, não o primeiro buffer audível nem silêncio acústico. Assim,
`AUD-001/002/004` e a meta P95 permanecem abertos. À data desta implementação,
`ADR-012` permanecia Open; este adapter não fornece o pipeline PCM/DSP exigido
para pitch/speed. A decisão posterior está registada abaixo.

`PLAYER-005` acrescentou Seek serializado ao port e à sessão. No Android,
o WAV de 12 segundos foi reposicionado de 00:00 para 00:09 em READY e de volta
para cerca de 00:02 durante reprodução, preservando PLAYING; a UI mostrou
00:03 após a pausa. Isto comprova o fluxo de comando/posição reportada, não
o erro acústico, tempo de áudio pronto ou sincronização A/V exigidos por
`AUD-003`/`AV-005`.

`PLAYER-006` acrescentou um canal de fim natural no port. A sessão só aceita
esse evento da fonte atual enquanto PLAYING, evita duplicações e expõe ENDED.
No Samsung, a amostra não-looping de 12 s terminou em 00:12/00:12 sem reiniciar;
o botão Recomeçar iniciou nova reprodução apenas após toque. Houve 100 ciclos
unitários, mas apenas uma execução física; `AUD-007` ainda não está fechado.

`PLAYER-007` acrescentou uma rota Flutter de ecrã inteiro que recebe a mesma
`PlayerSession` e o mesmo `VideoPlayerController`; não cria, recarrega ou liberta
media. O vídeo embutido é retirado da árvore durante a rota para evitar dois
renderizadores. No fullscreen, o vídeo usa `BoxFit.cover`, a UI do sistema fica
imersiva e os controles surgem por toque, ocultando-se após 2,5 s. O teste de
widget confirma a identidade da sessão, load único e estado preservado ao
voltar. No Samsung SM-A165F, um MP4 temporário de QA confirmou vídeo a ocupar
a tela, overlay por toque e retorno em PAUSED em 00:01; após reprodução,
chegou a ENDED em 00:07. Isto não é medição acústica de áudio duplicado nem
validação iOS.

`AUDIO-001` acrescentou `packages/audio_engine`, separado do transporte de
`player_core`. O port aceita comandos absolutos de pitch em semitons e speed
como fator, mas distingue a sequência de comando aceite do estado efetivamente
aplicado. O estado inicial é 0 semitons/1,0×, com latências desconhecidas
(`null`), não falsamente zero. Capacidades de processamento são do pipeline
preparado; a UI só poderá ativar controles quando a fonte e o adapter os
suportarem. Não há ainda adapter DSP nem ligação ao player Flutter, pelo que
nenhuma alteração sonora ou meta P95 foi validada. À data desta implementação,
`ADR-011` e `ADR-012` continuavam Open; as decisões posteriores estão abaixo.

`AUDIO-002` iniciou a camada de aplicação para Tom com `PitchController` no
pacote `audio_engine`. O valor confirmado só muda após evento do adapter;
intenção pendente e falha não fingem alteração sonora. São aceites valores
finitos de -12 a +12 semitons, sem alterar speed. O controller não faz DSP,
não está ligado à UI e não substitui o spike nativo. As opções de biblioteca e
os gates estão em `docs/AUDIO_002_DSP_OPTIONS.md`. PITCH-001..007 físicos e
P95 < 150 ms continuam pendentes.

O spike de áudio passou o gate inicial S-001 apenas no Android: a APK compila
`libaudio_core.so` com NDK/CMake, e um teste físico no Samsung confirmou a
chamada Flutter → Dart FFI → C ABI → C++ e a libertação do handle. S-002 abriu
saída nativa Oboe com tom 440 Hz isolado do player. Em 30 s foram reportados
48 kHz, 1.441.024 frames e 1 XRun; após pedir buffer de dois bursts, outra
execução de 30 s reportou 48 kHz, 1.440.768 frames e 0 XRuns. Uma terceira
execução confirmou burst de 256 frames, buffer de 512 frames e 0 XRuns. O gate de
10 minutos continua aberto. Não há DSP, build iOS, medição acústica ou P95. S-000 continua parcial
porque não há iPhone/macOS; ver `docs/AUDIO_SPIKE_PROGRESS.md`.

Após pesquisa técnica e relatos de developers em 2026-09-24, a escolha de
arquitetura foi registada nos ADRs: Rubber Band real-time como alvo DSP
(`ADR-011`), e uma única saída nativa de áudio para fontes locais processáveis
(`ADR-012`): Oboe no Android, RemoteIO/AVAudioSession no iOS, com vídeo nativo
sem áudio duplicado e clock de apresentação de áudio como master (`ADR-008`).
O piloto `video_player` continua executável, mas não é o pipeline DSP final.
Esta decisão **não** significa que Rubber Band esteja integrado, que a sua
licença comercial tenha sido adquirida, ou que A/V sync, latência, loop e iOS
tenham passado nos gates. Fontes online/protegidas permanecem sob ADR-013.

Em 2026-09-24, S-002 avançou após os testes de 30 s acima: o tom Oboe foi
executado no Samsung SM-A165F por 600 segundos numa APK profile, com 48 kHz,
burst de 256 frames, buffer de 512 frames, 28.803.328 frames gerados e 0
XRuns nas 20 amostras. Isto valida continuidade observável do callback neste
aparelho, não saída acústica sem clicks, latência, reprodução de WAV, release
ou DSP. Ver `docs/AUDIO_SPIKE_PROGRESS.md`.
Uma execução separada de 600 segundos em release no mesmo aparelho também
reportou 48 kHz, buffer de 512 frames, 28.800.512 frames e 0 XRuns. Ambos os
resultados são apenas do tom de diagnóstico e não fecham o gate acústico S-002.
O caminho nativo S-002 também reproduz o WAV local de QA (RIFF PCM16, 12 s)
até ao fim: 576.000 frames no Samsung. Houve 0 XRuns em debug e, em cinco
passagens profile, 1, 0, 0, 0 e 0 XRuns. O tom também teve XRuns em execuções
profile curtas, mesmo após passar a gerar as amostras a partir de tabela de
seno pré-calculada. A variabilidade mantém o gate aberto; o
pipeline de produto e Rubber Band ainda não usam este decoder limitado.
Instrumentação posterior na ABI 5 mediu trabalho máximo do callback abaixo de
0,5 ms, sem callbacks acima do orçamento de ~5,3 ms nas passagens observadas.
Os XRuns apareceram cedo; mudar de 2 para 3 bursts não os eliminou em duas
execuções comparativas. Dois bursts permanecem o padrão, e o motivo dos XRuns
e a qualidade acústica ainda não foram comprovados.
S-003 iniciou uma integração **opcional e interna** da Rubber Band v4.0.0:
`DspProcessor`/`RubberBandProcessor` processam WAV local com R2/R3, com Tom e
Velocidade independentes no fixture QA. A ABI 6 também usa um worker nativo e
uma fila SPSC de PCM pré-alocada para alimentar o callback Oboe sem executar
DSP nele. R2 e R3 tocaram no Samsung sem falhas de fila ou XRuns nas passagens
medidas. A build normal não inclui Rubber Band. Latência ponta a ponta,
métricas P95, qualidade acústica, alterações em tempo real, iOS e licença de
distribuição permanecem abertos; ver `docs/AUDIO_SPIKE_PROGRESS.md`.

Atualização ADR-014: por decisão do utilizador, o produto deve implementar
Tom e Velocidade sem Rubber Band. ADR-011/012 ficam como histórico dos spikes;
o alvo atual é aplicar parâmetros no **mesmo player nativo** que possui a
saída (Media3 Android, AVAudioUnitTimePitch iOS), preservando o port Dart e
sem duplicar áudio. Um probe Media3 isolado já aceitou parâmetros independentes
e alterações durante playback no Samsung, mas não está integrado no player da
UI e não satisfaz o gate acústico/latência/loop/iPhone. Ver ADR-014 e S-004.
S-005 passou a encaminhar áudio local Android para um único player Media3 que
recebe Play/Pausa/Seek e Tom/Velocidade no mesmo recurso; vídeo permanece no
plugin anterior. A UI mostra os controlos só para o áudio Android suportado.
Isto ainda não valida o som efetivo, nem cobre iPhone ou vídeo; ver S-005.
S-006 acrescenta `LoopRange` e repetição nativa de clip A/B no mesmo Media3
Android. A UI não executa seek periódico; um seek fora desliga o loop e mantém
os marcadores. Ainda não há prova de precisão/drift/clicks em 1000 voltas;
um teste de 500 ms/100 transições com alteração dinâmica de tom/velocidade
passou no Samsung, mas não substitui medição acústica;
ver `docs/AUDIO_SPIKE_PROGRESS.md`.
Marcadores A/B agora podem ser editados com o loop ativo: a UI valida o novo
intervalo e espera o Media3 confirmar antes de mostrar a mudança. O motor
recria o clip para cada edição; teste de 200 A + 200 B passou para estado,
mas desempenho e continuidade acústica permanecem abertos.
A política provisória de background é pausar no ciclo de vida
`inactive`/`paused`/`detached` e nunca fazer autoplay no regresso. O player
continua na atividade, sem `MediaSessionService`; audio focus, chamadas,
persistência de sessão e playback contínuo em segundo plano não estão
implementados. Ver S-007.

## 14. YouTube dentro do Transpono — 2026-09-25

O botão de pesquisa abre `YouTubeBrowserScreen` com WebView Android/WKWebView,
incluindo resultados, miniaturas e seleção na própria página. A navegação não
invoca `url_launcher`. `WebViewYouTubeSession` controla a WebView e observa o
elemento de media por uma ponte JavaScript restrita à origem YouTube.

O áudio do navegador não passa pelo Media3 nem pelo `PlayerSession` de ficheiros.
Usa uma só cadeia Web Audio sobre o elemento existente, com Signalsmith Stretch
Web 1.3.2 (MIT) para pitch. O adapter prefere AudioWorklet e usa o mesmo WASM por
ScriptProcessor quando a política da página impede carregar o módulo Blob.
Velocidade e A/B usam a timeline HTML; esse loop por polling não possui a
precisão nativa/gapless do caminho de ficheiros. Nenhum stream é extraído.

Apenas o sinal digital confirmado atualiza o valor aplicado de tom. Conteúdo
incompatível, mudo ou falhas têm mensagens explícitas; CSP/DRM não são alterados.
O lifecycle pausa o navegador; o retorno não inicia automaticamente playback.
As fontes locais mantêm os adapters existentes, separados desta experiência.

O percurso real de pesquisa/reprodução/pitch/velocidade passou no Samsung
SM-A165F, além de medição de frequências em fixture sintético no aparelho.
Os detalhes, limites de qualidade/latência e o gate iPhone estão em
`docs/YOUTUBE_INTEGRATION_DECISION.md`. ADR-013 permanece aberto para suporte
oficial de distribuição, compatibilidade e política de fontes online.

## 15. Painel principal ligado à sessão — 2026-09-25

`StudioVisualHome` usa agora `MainPlayerController` + `MainPlayerPanel` em vez
dos hotspots da referência estática. O contrato `PlayerPanelModel` permite
usar os mesmos botões para a fonte local e o YouTube. `LocalPlayerController`
é o proprietário reutilizável da sessão local. A pesquisa do shell já não
cria/descarta uma rota `YouTubeBrowserScreen`: conserva a mesma WebView ao
usar o vídeo no painel e ao entrar/sair de fullscreen.

Os valores fictícios de música/tom/tempo do painel foram substituídos por
estado confirmado e um estado vazio. Presets/setlist locais, ferramentas
sonoras de estudo e cifras manuais estão ligados ao menu. Stems continuam
indisponíveis. Escopo, limites e testes: `docs/MAIN_PLAYER_FUNCTIONALITY.md`.

## 16. Fullscreen, estudo e segurança local — 2026-09-25

`MainPlayerFullscreen` mantém a superfície em área completa, com overlay,
auto-hide, A/B, tom/velocidade, lock e callbacks de ferramentas. Não cria sessão.
`StudioVisualHome` agora monta painéis funcionais (`PracticePanel`, `StagePanel`,
`ChordsPanel`) em lugar dos hotspots com conteúdo fictício. YouTube e vídeo
continuam visíveis durante a navegação e usam a mesma `GlobalKey`.

`PlayerCollectionsPage` opera CRUD/reordenação de `PlayerPresetStore`; leituras
e escritas de coleções são serializadas entre instâncias no mesmo isolate.
`ChordSheetStore` guarda conteúdo manual versionado por fonte; cifras exibidas
são derivadas do original e do pitch confirmado, não rescritas ao transpor.

`InterruptedLoadedMedia` acrescenta eventos opcionais ao contrato do Player
Core. O adapter Media3 local Android observa revisões de interrupção nativas;
o core confirma INTERRUPTED/PAUSED e invalida Play pendente. O listener nativo
cancela intenção ao perder foco/rota, sem retomar automaticamente. Este caminho
não é suporte de interrupções para WebView/iOS; requer QA físico de chamadas/BT.

Ver `FULLSCREEN_AND_STUDY_DELIVERY.md` e ADR-015 para decisões e limites.

## 17. Recuperação e importação durável — 2026-09-25

`main.dart` injeta `SessionSnapshotStore` na UI de produção; testes e probes
podem omitir a recuperação ou injetar banco isolado. O store SQLite guarda
`current`/`previous` em transação, valida o schema JSON e bloqueia escritas de
formatos futuros. Antes de abrir um banco existente para escrita, verifica-o
em read-only; preserva uma cópia excepcional se um hot journal exigir reparação
escrita. Esse caminho excepcional ainda exige ensaios físicos específicos.

`SessionRecoveryController` observa apenas snapshots confirmados do player.
Tom/velocidade/A-B/fonte/painel e pausa são salvos prontamente; posição durante
playback usa throttle de 5 s, não debounce que adia indefinidamente a escrita.
Ao entrar em operação pendente, conserva a última confirmação, não o alvo de
seek. Navegação e source replacement fazem flush; background tenta flush/pausa,
sem assumir que o sistema espera ou entrega o callback.

Local recupera fonte/ajustes/posição/painel em pausa, sem fullscreen automático.
YouTube não abre a página no startup: mostra ação explícita de recuperar vídeo.
Falha mantém snapshot e aviso; adoção do estado atual é explícita. Não há
intenção `PLAYING` serializada. Restauro A/B conserva posição interna válida,
voltando a A somente se a posição estiver fora de um loop ativo.

`LocalMediaImporter` copia novas seleções para Application Support por streaming,
flush e rename antes de publicar o locator. A amostra também fica fora do cache.
Não toca nos originais; limpeza de dados/desinstalação remove a cópia privada.
Limites, pesquisa e evidências: `RECOVERY_RESEARCH_AND_QA.md`, ADR-016.

## 18. Prática progressiva sobre a sessão única — 2026-09-25

Estado desta revisão: implementação com suíte automatizada e percurso físico
Media3/fixture WebView offline aprovados no Samsung SM-A165F. Build release
instalada por atualização e painel conferido. Isso não aprova iPhone, YouTube real nem
gates de release completos. Decisão e critérios: ADR-017,
`PRACTICE_PROGRESSION_RESEARCH.md`; evidências: `PRACTICE_PROGRESSION_QA.md`.

`PracticePlan`/`PracticeProgress` em `practice_session.dart` modelam plano,
voltas completas e estado recuperável. `PracticeController` observa o mesmo
`MainPlayerController`; não cria player, DSP ou relógio musical paralelo.
`PracticeProgressionCard` apresenta configuração recolhida, resumo, contadores
confirmados e start/pause/resume/next/stop. O painel manual continua disponível.

`LoopObservation` transporta epoch, contagem e estado de reprodução. O caminho
de áudio local Android usa repetições Media3; o caminho web usa retornos A/B
confirmados pelo adaptador. Revisão/identidade protege contra seek, callbacks
antigos e mudança de fonte. Vídeo local não oferece contagem automática enquanto
não tiver um sinal equivalente; no YouTube, B no fim da duração desativa a
capability do treino automático conservadoramente. Isso não remove o player
ou o treino manual já existente.

No limite de etapa, o coordenador pausa, aplica/aguarda velocidade confirmada,
volta a A e inicia a etapa seguinte. Uma breve pausa faz parte do contrato;
não é transição gapless. Deltas de várias voltas recebidas juntas representam
reprodução na taxa anterior, não etapas já tocadas em taxas novas. Pausa,
encerramento e alterações incompatíveis invalidam operações pendentes.
Ajustar manualmente a velocidade suspende automação; completar o alvo pausa.
A fonte/A-B diferente invalida também um plano pausado; regressar posteriormente
à mesma faixa não reativa essa sessão. O utilizador inicia/recomeça outro plano.

O snapshot v2 agrega `PracticeProgress` à unidade de recuperação do player e
mantém leitura de snapshots v1. O coordenador de recuperação salva transições
confirmadas do treino e restaura estado ativo como pausado. A retoma do treino
é explícita e começa em A, sem creditar a volta parcial. As políticas de
versionamento futuro, fallback, erro não destrutivo e YouTube metadata-only
do ADR-016 continuam válidas; nenhuma coleção é migrada por este incremento.

Contadores descrevem reprodução lógica. Não representam precisão acústica,
ausência de clicks, qualidade do time-stretch ou avaliação do músico. Planos
concluídos não geram notas, “domínio adquirido” ou estatísticas de acerto.
Validações acústicas, corrida/interrupções, morte de processo com plano, uso
prolongado e acessibilidade física continuam gates independentes.

O primeiro probe físico revelou Play aceite antes de terminar a preparação do
seek. `NativeAudioLoadedMedia.play()` agora aguarda estado de reprodução por
até 40 intervalos de 50 ms enquanto a intenção é válida, sem ultrapassar
cancelamento/release/revisão de interrupção. A segunda passagem no pacote `.qa`
concluiu seis voltas a 60/65/70% e pausou. Contagem web passou em fixture WAV
offline com anúncio simulado; não comprova a página real do YouTube.

No código final desta revisão passaram 215 testes mobile, 56 Player Core e 35
JavaScript/WASM, total de 306 automatizados, com `flutter analyze` limpo.
Dois cenários físicos adicionais não aprovam a matriz completa. Build release
de 63.110.292 bytes instalada com `adb install -r` no pacote normal, preservando
first install/dados existentes. Amostra anterior recuperada pausada na leitura
v1→v2, com card e controles conferidos. Somente o pacote `.qa` foi removido após
as provas. Hash, capturas e limites em `PRACTICE_PROGRESSION_QA.md`.

## 19. Confirmação WebView e transporte seguro — 2026-09-25

ADR-018 acrescenta `WebMediaCommandRunner`: dispatch com ID, consulta de ACK
assíncrono e snapshot final, prazo compartilhado de 18 s e cleanup limitado a
250 ms. O envio JavaScript não é conclusão da Promise. Respostas e cleanup
pertencem à geração do documento; `snapshotRevision` impede que um poll antigo
reverta um comando mais recente. A tabela de ACKs da página limita-se a 64 IDs.

Intenções Play/pitch têm ownership e revisão. Pausa invalida Play pendente;
descarte/troca de fonte e cancelamento do pedido invalidam o trabalho respectivo.
Pausar não desfaz, por si, um ajuste de tom ainda válido. Callbacks antigos não
podem ressuscitar playback nem cancelar uma intenção nova. Play explícito é
idempotente; o controller
captura a intenção do botão antes da fila, sem depender de toggle tardio.
Pausa de mídia em reprodução passa fora da fila de ajustes. Os cinco painéis
mantêm Pausa disponível durante busy, mas não Play/Ativar som; locks continuam
a bloquear toques conforme o contrato. Recovery continua sem autoplay.

A seleção do vídeo monta primeiro o painel final, depois foca o topo da página
sem scroll animado. Em paisagem a superfície fixada recebe 2/3 da largura,
preservando os controles Flutter ao lado. A prova física encontrou vídeo de
87×49 CSS px no viewport antigo; a nova proporção mostrou 212×119 CSS px e
permitiu reprodução contínua, pitch +1 confirmado e A/B 20–22 s naquele vídeo.
Não há alteração do DOM visual do YouTube, ocultação de controles/anúncios ou
retomada forçada para compensar pausas da página.

Nesta revisão passaram 260 testes mobile, 56 Player Core e 47 JavaScript/WASM
(363 automatizados), com análise Flutter limpa. Resultado integral do percurso
YouTube, tentativas físicas, instalação e limites devem ser consultados em
`YOUTUBE_PRACTICE_QA.md`. A pesquisa está em `YOUTUBE_PRACTICE_RESEARCH.md`.
ACK e sinal DSP não comprovam precisão acústica, qualidade, latência ou iPhone.
Distribuição YouTube continua sujeita ao gate ADR-013.
