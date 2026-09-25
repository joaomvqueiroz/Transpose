# ROADMAP

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
