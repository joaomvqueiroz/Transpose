# PROJECT MEMORY — App Musical

> Fonte de verdade operacional do produto. Ler antes de alterações relevantes.

## Ajuste posterior — fixação opcional e player sem faixa duplicada

O utilizador pediu botão no próprio vídeo para fixar/soltar durante a rolagem.
Solto é o estado inicial; fixar não recria a WebView. No player principal foram
retirados título, indicação «YouTube · Navegador integrado» e seek de baixo do
vídeo; seek e ecrã cheio aparecem ao tocar no box, durante dois segundos.
Quando existe sessão YouTube pendente, mostrar só «Restaurar vídeo» sem o texto
«Última sessão» nem X. Seguir adenda A1–A4 no roadmap; os demais modos de Cifra,
regras de importação e a separação Transpono Dev/original permanecem válidos.

## Correção prioritária de UX — 2026-09-25

O pedido atual substitui a primeira revisão de cifra permanente/vídeo fixo.
Seguir `docs/PLAYER_CIFRA_SEQUENTIAL_PLAN.md` e S0–S5 no ROADMAP, sequencialmente.
Só cabeçalho fixo: YouTube rola no player principal. Cifra começa desligada;
cards de Tom/Velocidade/A–B inline. Quando ligada, cifra substitui cards e os
ajustes ficam num overlay dentro do box do vídeo, com fecho explícito. Transporte
Play/Pausa/+/-10 s auto-hide de 2 s permanece separado dos ajustes.

Botão Cifra abre navegador para escolher/importar página de cifras, com preview,
origem e confirmação; priorizar acesso gratuito sem cadastro. Pesquisa/páginas
são superfícies não confiáveis: HTTPS/allowlist, sem API privada, scraping em
lote ou bypass de login/paywall/challenge. Termos dos fornecedores não equivalem
a licença de distribuição; revisão/autorizações comerciais continuam abertas.

Texto original e calibração por música ficam locais. Acompanhar áudio usa pitch
confirmado (incluindo botões +/- da cifra); desligado transpõe só acordes.
Trocar fonte invalida importação pendente. Sem detecção automática de tom/letra.
Atualizações neste PC usam SOMENTE `com.example.transpose_mobile.dev`; preservar
o app original e sua chave/dados. Evidências finais pertencem ao gate S5, não
inferir release-ready a partir de testes de widget.

## Visão

Aplicativo mobile premium para músicos praticarem e executarem músicas.

Não é apenas um player e não deve virar uma DAW completa.

Princípio central:

> **Simples por fora. Poderoso por dentro.**

O utilizador deve conseguir:

- tocar uma música;
- mudar o tom em semitons;
- alterar velocidade sem alterar o tom;
- criar loop A-B;
- praticar um trecho progressivamente;
- acompanhar acordes;
- guardar presets e loops;
- organizar setlists;
- gravar a própria execução;
- usar metrónomo/afinador;
- entrar em Modo Palco;
- recuperar a sessão depois de interrupções.

## Utilizador principal

Músicos iniciantes e avançados: guitarristas, baixistas, pianistas, bateristas, cantores, professores, músicos de igreja/banda e estudantes.

Não pressupor conhecimento de engenharia de áudio.

## Navegação principal

Bottom navigation:

- Player
- Prática
- Acordes
- Palco

Sidebar:

- Agora a tocar
- Biblioteca
- Setlists
- Loops
- Predefinições
- Gravações
- Ferramentas
- Progresso
- Configurações

Header:

- `☰`
- nome da tela
- `⋯`

## Linguagem

Preferir:

- Tom
- Velocidade
- Loop
- Acordes
- Metrónomo
- Afinador
- Gravações
- Predefinições

Evitar no fluxo comum:

- DSP
- engine
- sample rate
- headroom
- buffer
- latency
- clock

Informação técnica pertence a áreas avançadas/QA.

## Visual

- dark mode;
- fundo azul-preto profundo;
- cyan para ação/estado ativo;
- branco principal;
- cinza secundário;
- pouco brilho;
- cards discretos;
- Inter como tipografia principal;
- JetBrains Mono apenas para dados técnicos/números quando necessário;
- animações curtas e profissionais;
- sem efeitos contínuos sem função.

Regra: se tudo é cyan, nada é destaque.

## Player

Hierarquia:

1. vídeo;
2. Tom;
3. Velocidade;
4. Loop A-B;
5. transporte;
6. ferramentas adicionais recolhidas.

Tom atual deve ser visualmente dominante.

Play/Pause deve ser a principal ação de reprodução.

## Fullscreen

Controls hidden = 100% vídeo.

Não mostrar persistentemente:

- header;
- bottom nav;
- cards;
- pitch;
- speed;
- texto técnico.

Tap simples mostra overlay.

Auto-hide aproximado: 2–3 s sem interação.

Gestos:

- duplo toque esquerda → -10 s;
- duplo toque direita → +10 s;
- duplo toque centro → Play/Pause;
- horizontal → seek;
- vertical direita → volume;
- vertical esquerda → brilho;
- lock → bloquear gestos/toques acidentais.

## Prática

Tela principal deve focar em "Dominar Trecho":

```text
Solo Principal
02:13 — 02:37

70%
Repetição 2/3
Próximo: 75%

[PAUSAR TREINO]
```

Configuração avançada recolhida.

Progressão típica configurável:

```text
60% ×3
65% ×3
70% ×3
75% ×3
80% ×3
90% ×2
100% ×2
```

## Acordes

Tela deve comunicar:

```text
AGORA
B♭

A SEGUIR
Gm
```

Acorde atual dominante.

Diagrama, progressão completa e detalhes ficam recolhidos.

Gravador é uma tela separada.

## Modo Palco

Tela mais simples.

Mostrar principalmente:

- música;
- posição na setlist;
- tom;
- offset de pitch;
- -1/+1;
- Play/Pause;
- anterior/próxima;
- lock.

Botões grandes.

## Segurança

- nenhum secret privado no cliente;
- tokens sensíveis em Keychain/Keystore;
- HTTPS;
- autorização importante no servidor;
- compras/entitlements validados no servidor quando aplicável;
- WebView tratada como superfície não confiável;
- allowlist de domínios;
- sem tokens em URL;
- não expor funções nativas sensíveis a páginas arbitrárias;
- gravações privadas por padrão;
- permissões just-in-time;
- logs sanitizados;
- ficheiros importados tratados como entrada não confiável.

## Arquitetura

Módulos:

```text
App Shell
Player Core
Audio Engine
Practice Engine
Music Intelligence
User Data
Platform Services
Optional Cloud
```

Player/Audio/Data não devem depender diretamente de widgets/telas.

Stack de aplicação aceite em 2026-09-24:

```text
Flutter UI / App Shell
  ↓
Dart application + domain packages
  ↓
Dart FFI
  ↓
C ABI
  ↓
C++ AudioCore + adapters nativos
```

A stack Flutter/FFI é distinta das escolhas de DSP e reprodução. Em 2026-09-24,
após pesquisa técnica e relatos de developers, ADR-011 escolheu Rubber Band
como alvo DSP e ADR-012 escolheu saída nativa única para media local
processável; a validação de desempenho e licenciamento ainda são gates.
Após comparação física de 2 e 3 bursts no Samsung, ambos mostraram XRuns
intermitentes no início sem callback acima do orçamento. Mantemos 2 como
padrão e avançamos S-003 apenas como spike interno; S-002 acústico, iOS e
licenciamento de publicação continuam abertos.

A conversa de conceção partilhada pelo utilizador em 2026-09-24 reforça o
princípio de interface simples, ferramentas avançadas recolhidas e fullscreen
de vídeo sem controlos permanentes. Nela foram propostas Media3/AVFoundation
para reprodução e Rubber Band para DSP; eram propostas nessa conversa. A
escolha técnica posterior está documentada em `ARCHITECTURE_DECISIONS.md`,
sem fingir que a implementação ou os testes de Android/iOS estão concluídos.

## Local-first

Sempre que possível:

- pitch local;
- speed local;
- loops locais;
- presets locais;
- setlists locais;
- progresso local;
- gravações locais.

Cloud apenas para funções que realmente precisem dela.

## Estados principais

Player:

```text
IDLE
LOADING
READY
PLAYING
PAUSED
BUFFERING
INTERRUPTED
ERROR
ENDED
```

Recording:

```text
NOT_RECORDING
STARTING
RECORDING
PAUSED
FINALIZING
ERROR
```

A UI deriva do estado real, não de booleanos independentes conflitantes.

## Persistência

Autosave do estado relevante:

```text
track
source
position
pitch
speed
loop A/B
loop enabled
preset
practice progress
screen
updated_at
```

Process death/reboot não devem causar autoplay inesperado.

## Metas atuais

```text
Play/Pause P95       < 100 ms
Pitch P95            < 150 ms
Speed P95            < 150 ms

Loop P50             < 10 ms
Loop P95             < 25 ms
Loop P99             < 40 ms
Loop MAX             < 60 ms
Loop drift           < 25 ms / 1000 repetições

A/V offset           < 80 ms
A/V drift            < 50 ms / 30 min

State restore        >= 99.9%
Process restore P95  < 2 s

Critical crashes     0
Audible underruns    0
Audio duplication    0
```

## Prioridade

P0:

- Player;
- Pitch;
- Speed;
- Loop;
- Fullscreen;
- Save/Restore;
- Audio Focus;
- Bluetooth básico;
- segurança mínima;
- QA crítico.

P1:

- Prática;
- Presets;
- Biblioteca;
- Sidebar;
- Setlists;
- Palco.

P2:

- Gravações;
- BPM;
- key detection;
- acordes;
- estrutura da música;
- progresso.

P3:

- IA;
- stem separation;
- cloud sync;
- colaboração/social.

## Regra de implementação

Atualização de 2026-09-24: o utilizador decidiu avançar com Tom e Velocidade
sem Rubber Band no produto. ADR-014 substitui os alvos ADR-011/012; os spikes
Rubber Band/Oboe são apenas históricos e internos. S-004 provou parâmetros
Media3 independentes no Samsung. S-005 integrou o mesmo player Media3 no áudio
local Android e mostrou sliders de Tom/Velocidade na UI; teste profile no
Samsung passou. Qualidade acústica, latência e iPhone continuam abertos.
S-006 adicionou loop A/B nativo inicial para áudio Android; duas voltas e
controles da UI passaram no Samsung. Precisão acústica, drift longo,
persistência, edição ao vivo e iPhone continuam pendentes.

Antes de implementar uma feature:

1. qual módulo é responsável?
2. qual state machine muda?
3. o que acontece em background?
4. o que acontece numa chamada?
5. o que acontece se a rota de áudio mudar?
6. o que precisa persistir?
7. como será restaurado?
8. qual teste prova que funciona?
9. há dados sensíveis?
10. precisa estar sempre visível?

Se 10 = não, preferir progressive disclosure.

## Entrega do painel principal — 2026-09-25

O pedido mais recente foi tornar funcionais os botões do painel principal.
A UI passou a usar uma sessão partilhada local/YouTube, com controlos reais,
fullscreen sem recarga, A/B, presets/setlist locais e ferramentas de estudo.
Afinador nesta entrega é por referência sonora; acordes são introduzidos
manualmente. Stems, deteção automática, iOS, audio focus/BT e recuperação
completa de sessão continuam gates abertos. Não interpretar esta entrega
como conclusão do roadmap inteiro. Ver `docs/MAIN_PLAYER_FUNCTIONALITY.md`.

## Fullscreen e demais painéis — 2026-09-25

Pedido ampliado: completar fullscreen e avançar as demais funcionalidades,
tomando decisões com documentação e experiências de desenvolvedores. ADR-015
mantém foco em controles reais sobre uma sessão, dados locais e segurança.
Fullscreen ganha A/B completo, reset, velocidade fina, auto-hide e menu de
ferramentas. Prática é manual sobre A/B; Palco usa setlist real; Acordes permite
cifras/tempos/notas manuais por fonte. Coleções têm renomear, remover confirmado
e ordenar. Referências visuais antigas foram preservadas, dados demonstrativos
deixaram de se passar por análise da música. Detalhes e limites estão em
`docs/FULLSCREEN_AND_STUDY_DELIVERY.md`; roadmap completo não está concluído.

## Recuperação de sessão e decisões — 2026-09-25

ADR-016 prioriza State antes de IA/gravação/mais ferramentas. SQLite restrito ao
snapshot atual/anterior, sem migrar coleções. Autosave observa estado confirmado,
posição com throttle 5 s e flush na pausa/background. Fonte local reabre pausada;
YouTube só abre mediante toque explícito, preservando ajustes sem rede no startup.
Importações novas e amostra estão em Application Support, não cache. Presets
antigos não são migrados e podem exigir reimportar um ficheiro já removido pelo SO.

Recuperação incompleta não deve esconder a suspensão de autosave: manter ações
de retry/troca de fonte/usar estado atual. Formatos futuros ou banco ilegível
são preservados. Pesquisa, prova física e limites são registados em
`docs/RECOVERY_RESEARCH_AND_QA.md`. Não marcar 99,9%/P95/reboot/iPhone como
aprovados por causa de um percurso físico. Próximo recurso recomendado é a
progressão real de velocidade, após eventos de loop e segurança de interrupções.

Incidente QA nesta entrega: a limpeza padrão de `flutter drive` desinstalou o
pacote de produção e removeu dados privados; a primeira prova de recuperação
foi invalidada. O utilizador foi informado e não há garantia de recuperar dados
anteriores. Integrações Android agora usam pacote separado `.qa`; executar
sempre APK QA pré-compilado/validado com `--keep-app-running`. O wrapper
`apps/mobile/tool/run_recovery_probe.ps1` aplica essas proteções. Nunca voltar
a testar kill com uninstall/pm clear ou limpeza automática do driver.

## Prática progressiva por eventos — 2026-09-25

ADR-017 acrescenta um plano simples sobre o player existente, escolhido com
relatos concretos de criadores/músicos e documentação oficial. Pesquisa e
critérios em `docs/PRACTICE_PROGRESSION_RESEARCH.md`. Suíte automatizada e um
percurso Android no Samsung SM-A165F passaram: Media3 executou 60→65→70%, duas
voltas por etapa, pausa/retoma e término pausado; WebView real validou contagem
em WAV offline com anúncio simulado, não YouTube real. Evidências e limites em
`docs/PRACTICE_PROGRESSION_QA.md`. Build release instalada por atualização;
recuperação pausada da amostra anterior e novo card conferidos no aparelho.

Início/alvo 50–150%, incremento 1–20 pontos, 1–20 voltas por etapa; default
60→100%, +5, três voltas. A configuração fica recolhida; a tela mostra taxa,
etapa, voltas da etapa e total realmente reproduzido. Pausar, retomar, avançar
etapa e encerrar operam o controller. Cada etapa nova pausa brevemente,
confirma taxa e recomeça em A; não é mudança gapless. Ao completar, pausa.

Contagem depende de eventos reais Media3/WebView, nunca timer. Seek, troca de
fonte, anúncios e eventos antigos não podem inflar progresso. Ajuste manual
suspende automação. Fontes sem capability conservam o treino manual; vídeo
local e YouTube com B no fim da mídia não recebem promessa de progressão.
Mudar fonte/A-B invalida inclusive treino pausado; voltar à mesma música não
ressuscita a sessão anterior e exige Recomeçar.

Snapshot v2 inclui o plano/progresso e aceita leitura v1. Recuperar fica pausado
e retomar requer toque, começando a volta pendente em A. YouTube continua sem
WebView no startup por causa de recovery. Não há avaliação do instrumento ou
“domínio” inferido: plano concluído mede reprodução, não qualidade musical.

Não acrescentar cloud, IA, stems ou gravação por arrasto deste recurso.
Biblioteca completa de seções, encadeamento de trechos, metrónomo sincronizado,
count-in e delay entre voltas ficam para contratos e QA próprios. As proteções
do pacote Android `.qa` e preservação dos dados de produção continuam obrigatórias.

A primeira tentativa física encontrou Play antes da readiness após seek;
`NativeAudioLoadedMedia.play()` agora espera confirmação de forma limitada,
respeitando cancelamento/revisão de interrupção. A segunda passagem durou cerca
de 19 s. Não declarar novo process death com treino, iPhone, YouTube real,
TalkBack, qualidade acústica, latência ou métricas estatísticas aprovados.

Verificação final do código nesta revisão: análise Flutter limpa, 215 testes
mobile, 56 Player Core e 35 JavaScript/WASM aprovados (306 automatizados).
Os dois cenários físicos são adicionais; os testes direcionados antigos estão
incluídos nos totais, não somados outra vez. APK release de 63.110.292 bytes,
SHA-256 `77A2014AAC9080DCDA639786670EBC69180122EA6410DB4C1C265F23269A393B`,
instalado com `adb install -r` (`Success`) no pacote normal sem o desinstalar.
First install preservado, atualização 2026-09-25 02:42:28. Somente o pacote
descartável `.qa` foi removido depois das provas. Evidências e capturas no
relatório QA; a atualização v1→v2 observada não é um kill físico com treino.

## YouTube real e confirmação dos controles — 2026-09-25

ADR-018 mantém pesquisa, tom, velocidade e loop como núcleo, com referências
de desenvolvedores e contratos primários em `docs/YOUTUBE_PRACTICE_RESEARCH.md`.
Não acrescentar cloud/IA/stems para compensar falhas do player. Não trocar o
motor nem reintroduzir Rubber Band neste incremento.

`WebMediaCommandRunner` aguarda ACK assíncrono por ID, com prazo total de 18 s
e cleanup de 250 ms. A página mantém até 64 resultados; snapshots têm revisão
monotónica por documento. Poll atrasado não pode reverter um comando. Play e
pitch pendentes pertencem à intenção/fonte/ID; pausa cancela Play pendente, e
troca de fonte ou cancelamento explícito invalida o ajuste incompatível.
Pausar não desfaz um ajuste de tom válido. Main envia Play explícito idempotente, capturando intenção no
toque. Pausa de playback ativo passa fora da fila e fica habilitada durante
busy nos cinco painéis, sem liberar Play novo nem ignorar locks.

QA real isolado revelou pausa após resize: vídeo de 87×49 CSS px em viewport
342×224, mesmo com página visível. Foco pós-frame/topo instantâneo sozinho não
resolveu. Dar 2/3 da largura ao navegador em paisagem resultou em vídeo
212×119 CSS px, reprodução contínua e pitch confirmado naquele aparelho.
O teste também teve de aguardar a animação de configuração antes de tocar Start;
não substituir esse toque por chamada direta nem por retries de Play.

Após seis tentativas malsucedidas documentadas, o percurso final de 43 s
passou em 2026-09-25 02:15:51–02:16:34 UTC no Samsung SM-A165F/API 36/WebView
152.0.7977.64: 18 miniaturas, vídeo `aqz-KE-bpKQ`, pitch +1 ativo, A/B 20–22 s,
duas voltas em cada taxa 60/65/70%, seis voltas totais e pausa final. Pausa/
retoma, fullscreen real, mesma sessão/documento/elemento e ajuste manual 75%
suspendendo automação também passaram. Não houve anúncio registrado nos
snapshots; isso não aprova o cenário de anúncio real nem todos os vídeos.

260 testes mobile + 56 Core + 47 JS/WASM = 363 automatizados passaram;
`flutter analyze` final limpo. Resultados dirigidos são subconjuntos. O cenário
físico é adicional, não tantos testes quanto os passos internos. Evidências,
tentativas anteriores, hash/instalação e limitações: `docs/YOUTUBE_PRACTICE_QA.md`.
Continuam abertos iPhone, acústica/latência, chamadas/BT, playback prolongado,
novo kill com plano e distribuição YouTube (ADR-013). O roadmap não terminou.

Release final deste incremento: APK de 63.177.124 bytes, SHA-256
`8348F483478BB736BA9252ADCA29F7CE828A793C125AF20AD715BB1290D2D1AD`,
metadata `com.example.transpose_mobile`/release, instalado com `adb install -r`
(`Success`). First install 2026-09-25 02:14:50 preservado; last update 03:18:54.
Smoke visual confirmou Prática/amostra 440 Hz anterior com recuperação pausada,
sem substituir a sessão de produção pelo vídeo QA. Captura:
`apps/mobile/build/transpono-release-youtube-ack.png`. O percurso YouTube foi
executado em profile QA, não repetido na release. Somente o pacote descartável
`.qa` foi desinstalado ao terminar; o pacote normal permanece instalado.
