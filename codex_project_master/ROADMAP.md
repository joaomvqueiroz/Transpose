# ROADMAP

## Revisão final do Player principal — 2026-09-25

### Correção do Play nativo após restaurar vídeo

- [x] O bloqueio contra autoplay já não interpreta o toque real no Play do
  YouTube como reprodução automática: o toque no vídeo libera o bloqueio
  quando a reprodução começa. Sem toque, o restauro continua pausado.
- [x] `flutter analyze --no-pub` limpo, 291 testes Flutter aprovados, build
  Dev instalada no Samsung e reprodução observada durante vários segundos
  após tocar no Play. O pacote original não foi alterado.

### Controles YouTube sem duplicação

- [x] No Player principal e fullscreen do YouTube, os controles nativos do
  YouTube respondem por Play/Pausa e ±10 s; os botões equivalentes do Transpono
  desaparecem. Áudio/ficheiro local conserva o seu transporte.
- [x] As posições das três bolas passam a ser − tom, semitons no centro ciano
  e + tom; a cifra ligada ao áudio acompanha o tom confirmado.
- [x] Análise sem problemas, 290 testes aprovados e captura Dev da nova fila
  circular de tom; app `com.example.transpose_mobile.dev` instalado no Samsung.

### Ajustes seguintes — pesquisa inicial e compactação

- [x] Arranque sem vídeo selecionado abre a pesquisa YouTube com campo focado;
  se houver vídeo pendente, «Restaurar vídeo» permanece acessível no topo.
- [x] Ponto A/B em tamanho normal passam a aproximadamente dois terços da
  largura e altura anteriores; fontes ampliadas mantêm dimensões acessíveis.
- [x] Menos altura entre busca, tom, velocidade e marcadores nos Ajustes do
  Player principal. O fullscreen independente conserva as medidas anteriores.
- [x] Análise sem problemas, 290 testes aprovados após a última alteração,
  instalação Dev e capturas físicas da pesquisa inicial e dos botões A/B a
  44 dp. O pacote original não foi alterado.
- [x] Quando Ajustes está aberto, a faixa escura prolonga-se até ao rodapé
  atrás do botão «Fechar ajustes», sem tapar os controlos; no Player principal
  a faixa é opaca para não deixar texto do YouTube aparecer através dela.
  Fechada, desaparece e o YouTube fica totalmente visível. Teste de regressão
  passou; falta captura Dev desta última correção visual.

- [x] Player principal reutiliza `MainPlayerFullscreen`; sem barra superior
  «Transpono» nem barra inferior de separadores. Sidebar e pin sobre o vídeo.
- [x] «Ajustes» é botão contornado com fundo semitransparente, sem faixa fixa;
  Abrir ficheiro, Cifra e YouTube ficam dentro da rolagem dos ajustes.
- [x] Transporte em fila (−10, Play/Pausa, +10) e tom logo abaixo
  (−, semitons, +), alinhados pelas mesmas colunas.
- [x] Removido o painel legado de mensagem sob o vídeo quando Cifra está
  desligada; em modo Cifra a mensagem não é duplicada.
- [x] Ao rolar a cifra com Ajustes abertos, o overlay de Play/Tom fecha mesmo
  com vídeo fixado; o pin do vídeo e a cifra permanecem.
- [x] Sem Cifra, abrir Ajustes não encurta o YouTube nem deixa faixa vazia; o
  overlay termina acima do botão flutuante, sem cobrir a última linha.
- [x] Altura máxima da faixa de Ajustes no Player principal ampliada em 1/4,
  de 40% para 50% da superfície de vídeo; fullscreen independente preservado.
- [x] Análise sem problemas, 289 testes aprovados, build e instalação Dev no
  Samsung, captura física dos Ajustes abertos e rolados. Pacote original intacto.

## Correção da composição fullscreen no Player — 2026-09-25

- [x] C1: retirar barra de separadores; Player/Prática/Acordes/Palco só na
  sidebar. «Ajustes» ocupa o rodapé.
- [x] C2: botão inferior abre/fecha controlos logo após vídeo ou sobre vídeo
  quando Cifra está ligada; Cifra e pin preservados.
- [ ] C3: testes de navegação, WebView única, análise, build e captura Dev.
  Análise limpa; 287 testes passaram e um teste desatualizado da recuperação
  foi corrigido e passou isoladamente. Build Dev e captura no Samsung concluídos;
  falta repetir a suíte completa e validar a última limpeza visual.

## Nova direção — fullscreen como Player principal (2026-09-25)

Contrato: `docs/PLAYER_CIFRA_SEQUENTIAL_PLAN.md` (B1–B4). O painel principal
adota a aparência/controles compactos do fullscreen, com botão de sidebar no
lugar de voltar; Cifra imediatamente sob vídeo; com Cifra ativa, ajustes no
overlay do vídeo. Preservar pin exclusivo do vídeo e WebView única.

- [ ] B1: navegação/composição visual do Player.
- [ ] B2: controlos compactos estilo fullscreen, inicialmente recolhidos;
  seta grande logo abaixo do vídeo abre/fecha a faixa e destaca o tom.
- [ ] B3: Cifra sob vídeo e engrenagem de ajustes no vídeo.
- [ ] B4: testes, análise, build Dev e conferência física.

## Ajuste pedido depois do primeiro player com cifra — 2026-09-25

Adenda ao contrato: `docs/PLAYER_CIFRA_SEQUENTIAL_PLAN.md`. O vídeo continua
solto por padrão, com botão para fixar/soltar durante a rolagem. O aviso de
recuperação de YouTube mostra só «Restaurar vídeo». O título, origem e posição
duplicados sob o vídeo são removidos; seek/ecrã cheio ficam no vídeo.

- [x] A1: botão opcional de fixação; rolagem e WebView única verificadas.
- [x] A2: aviso compacto de recuperação verificado.
- [x] A3: faixa duplicada removida; controlos no vídeo verificados.
  Gate: 22 testes dirigidos de player, sessão, Prática e recuperação passaram.
- [ ] A4: análise, testes completos e Transpono Dev no telemóvel.
- [ ] A5: corrigir vídeo YouTube reduzido após restauro: foco único no topo
  da página interna quando o vídeo existir; comparar com a segunda captura.
- [ ] A6: só o vídeo permanece fixo; cabeçalho e «Restaurar vídeo» rolam
  normalmente, e o botão desaparece após restauro bem-sucedido.

## Prioridade atual — Player e cifras, sequência corrigida (2026-09-25)

Contrato/prompt: `docs/PLAYER_CIFRA_SEQUENTIAL_PLAN.md`. Executar S1 → S2 → S3 →
S4 → S5, uma alteração e respetivo gate de testes de cada vez, sem implementação
paralela. A primeira revisão visual não correspondia ao pedido e não é a referência.

- [x] S0: prompt e critérios registados.
- [x] S1: vídeo YouTube rola com a página; só cabeçalho fixo; mesma sessão.
  Gate: 5 testes de rolagem/lifetime/foco passaram.
- [x] S2: Cifra inicialmente desligada; cards Tom/Velocidade/Loop restaurados;
  quando ativa, ajustes dentro do box do vídeo e cifra no lugar dos cards.
  Gate: 23 testes de painéis/alternância/cifra passaram; ajustes preservados.
- [x] S3: pesquisa interna Cifra Club/outro site, importar página escolhida,
  preview/confirmação/origem, segurança e persistência por música.
  Gate: 16 testes Flutter + 6 extração DOM sintética. Sites gratuitos identificados;
  navegação/importação reais no telefone ainda pertencem ao gate S5.
- [x] S4: transpor cifra independentemente ou seguindo tom confirmado do player.
  Gate: 26 testes dirigidos passaram, incluindo ACK, calibração, persistência e
  colunas de acordes/baixos sem alterar letra ou texto original.
- [ ] S5: testes completos + análise + APK Dev + validação física documentada.
  Gate parcial: 284/284 testes Flutter finais + 6 casos DOM, analyze limpo.
  APK Dev final instalada e aberta; app original preservado.
  Cifra OFF e abertura real do Cifra Club conferidos no Samsung. Importação de
  página real permanece pendente: seleção automatizada bloqueada pela ferramenta,
  sem tentativa de contorno. Não marcar compatibilidade de importação aprovada.

Nenhuma destas etapas autoriza substituir/desinstalar o app original do telefone.

## Estado funcional atualizado — 2026-09-25

Esta lista distingue implementação de aprovação para release. Os critérios
de cada fase e a Definition of Done abaixo continuam válidos.

- Player principal e fullscreen: controles ligados à mesma sessão; fullscreen
  inclui A/B completo, auto-hide, lock e ferramentas. Gates de playback longo,
  qualidade acústica e acessibilidade em hardware ainda abertos.
- Dados: predefinições e uma setlist local com guardar/abrir/renomear/remover
  confirmado/ordenar. Biblioteca completa e múltiplas setlists ainda pendentes.
- Recuperação: snapshot atual/anterior transacional, autosave confirmado e
  restauro local pausado implementados; YouTube oferecido sem abrir a página
  no startup. Novas importações locais ficam fora do cache. Evidências físicas
  e limites estão em `docs/RECOVERY_RESEARCH_AND_QA.md`; a fase State ainda não
  está aprovada estatisticamente nem em todas as plataformas.
  Um percurso de force-stop físico em app QA isolado passou, recuperando fonte,
  ajustes, loop, posição do checkpoint e Prática sem iniciar reprodução.
- Prática: progressão configurável, contagem por eventos Media3/WebView e
  recuperação do plano implementadas; suíte automatizada e um percurso físico
  Media3/fixture WebView offline passaram no Samsung SM-A165F. Um percurso
  YouTube real também passou: pesquisa, pitch +1, A/B 20–22 s, seis voltas em
  60/65/70%, pausa/retoma, fullscreen e suspensão por ajuste manual. Anúncios
  reais, iPhone, novo kill físico com treino e gates prolongados seguem abertos.
  Cada mudança de etapa pausa brevemente e recomeça em A; não é
  gapless. Treino manual permanece para fontes sem capability, incluindo vídeo
  local e o caso conservador YouTube com B no fim da mídia. Snapshot v2 lê v1 e
  recupera treino pausado. Não marcar PRACTICE-001..005 nem fase Practice como
  aprovados para release sem as evidências específicas.
- Palco: dados reais, seleção anterior/próxima da setlist sem autoplay,
  controles grandes e lock. Wake-lock e validação em apresentações pendentes.
- Acordes: cifras/tempos/notas introduzidos manualmente, sincronização com a
  posição e transposição confirmada; não equivale a reconhecimento automático.
- Plataforma: foco/noisy para áudio local Android com interrupção propagada
  ao estado e invalidação de Play antigo. Chamadas/BT físicos, vídeo e WebView
  ainda exigem validação/cobertura própria. Background permanece pausa segura.
- Em aberto antes da v1: hardening/reboot/migrações da recuperação, qualidade/latência,
  iPhone, gravação segura, inteligência musical, QA longo e publicação.

Decisões e pesquisa: `docs/FULLSCREEN_AND_STUDY_DELIVERY.md`,
`docs/RECOVERY_RESEARCH_AND_QA.md`, `docs/PRACTICE_PROGRESSION_RESEARCH.md`,
ADR-015/016/017/018. Evidências e limites de prática:
`docs/PRACTICE_PROGRESSION_QA.md`, `docs/YOUTUBE_PRACTICE_RESEARCH.md` e
`docs/YOUTUBE_PRACTICE_QA.md`. O último documento registra também o artefato e
o estado da atualização Android desta revisão, sem transferir uma prova QA
profile para uma aprovação automática de release.
Validação desta revisão: `flutter analyze` limpo, 260 testes mobile + 56 Player
Core + 47 JavaScript/WASM = 363 automatizados aprovados. O percurso físico
YouTube é adicional; pesquisa/pitch/loop/plano são etapas desse mesmo cenário.

Hardening deste incremento: comandos WebView esperam ACK assíncrono com prazo,
snapshots antigos não revertem o estado, Play pendente pode ser cancelado e
Pausa não espera a fila de ajustes. Em paisagem o navegador recebe mais espaço
para manter o vídeo visível; nenhuma alteração de controles/anúncios da página.
Manter tom/velocidade/A-B/pesquisa como prioridade; adiar cloud, IA e stems até
os gates do núcleo. A revisão de distribuição YouTube do ADR-013 segue aberta.

## Fase 0 — Fundação
CORE-001..004

Saída:
- arquitetura mapeada;
- boundaries;
- logging;
- feature flags;
- CI.

## Fase 1 — Player
PLAYER-001..007

Saída:
- load/play/pause/seek/fullscreen;
- state machine;
- 60 min playback.

## Fase 2 — Audio Engine
AUDIO-001..005

Saída:
- pitch;
- speed;
- instrumentação;
- sem clicks/duplicação.

## Fase 3 — Loop
LOOPDEV-001..006

Saída:
- A/B preciso;
- edição;
- loops salvos.

## Fase 4 — State
STATEDEV-001..006

Saída:
- autosave;
- process death;
- recovery;
- migrations.

## Fase 5 — Platform
PLATFORM-001..005

Saída:
- chamadas;
- audio focus;
- Bluetooth;
- background;
- lock.

## Fase 6 — Player UX
UX-001..004

Saída:
- UI final;
- fullscreen;
- gestures;
- accessibility.

## Fase 7 — Practice
PRACTICE-001..005

Saída:
- Dominar Trecho;
- progressão;
- resume.

## Fase 8 — Data Features
DATA-001..006

Saída:
- presets;
- biblioteca;
- setlists.

## Fase 9 — Palco
STAGE-001..004

## Fase 10 — Recording
REC-001..006

## Fase 11 — Music Intelligence
MUSIC-001..005

Só iniciar quando Player/Audio/Loop/State/Platform estiverem maduros.

## Fase 12 — Hardening

- segurança;
- performance;
- acessibilidade;
- QA de release;
- beta;
- store/privacy.

## Definition of Done v1

- 0 P0/P1 conhecido;
- player 60 min;
- métricas principais dentro de meta;
- restore >= 99,9%;
- zero áudio duplicado;
- zero autoplay inesperado após recovery;
- Bluetooth disconnect seguro;
- chamada segura;
- sem corrupção de recording;
- UX validada por músicos;
- documentação atualizada.
