# ROADMAP

## Prioridade atual — auditoria e reparação funcional, 2026-09-28

Contrato e evidências: `docs/FUNCTIONAL_AUDIT_2026-09-28.md`.
Preservar o visual atual do commit `79ab95f`: sem novos botões, funcionalidades
ou alterações de navegação. As revisões visuais históricas abaixo não são tarefas
para reintroduzir elementos removidos no outro PC. Executar uma etapa de cada
vez, apresentar resultado/testes/limites e perguntar antes da seguinte, conforme
pedido explícito do utilizador. Ideias novas ficam fora da implementação.

- [x] E1 — Diagnóstico inicial: Git/APK/aparelho, scripts de áudio, testes base,
  defeitos confirmados e esclarecimento sobre RAM/direitos/termos. Análise limpa,
  325 testes Flutter aprovados; JavaScript 40/52, com fixture desatualizada.
  F01/F02 reproduzidos em diagnóstico de grafo. Sem implementação/instalação;
  qualidade acústica no aparelho ainda não medida.
- [x] E2 — Corrigir o corte de som ao usar EQ antes de mudar o tom (F01), atualizar
  a fixture Web Audio (F03) e testar todas as ordens/retorno a zero, sem duplicação
  da saída. Autorizada: correção implementada, 61 testes JavaScript/WASM aprovados
  (9 novos). Build Dev instalada e aberta no Samsung em 2026-09-28 09:46:40;
  nenhuma alteração visual. Pacote principal intacto. Qualidade acústica ainda
  não medida; E3 autorizada no pedido seguinte.
- [x] E3 — Corrigir perda/estado incorreto de equalização e efeitos em troca de
  elemento, anúncio e falha (F02). Validar ajustes efetivos e comandos pendentes.
  Reaplicação e snapshots do motor implementados, sem alterações visuais.
  Análise limpa, 326 testes Flutter e 67 JavaScript/WASM aprovados. Dev instalada
  e aberta no Samsung em 2026-09-28 10:08:40; pacote principal preservado.
- [x] E4 — Medir e melhorar tom/velocidade existentes: sinal de teste conhecido,
  mudanças rápidas, bypass, independência entre parâmetros e fontes suportadas.
  Prova digital no Samsung concluída em 2026-09-28: sete combinações aprovadas,
  transição +3→+5 e efeitos; saída medida após filtros, EQ antes do tom e bypass.
  Erro máximo 6,26 cents e 0,00693× de velocidade; 69 testes JavaScript/WASM e
  análise Flutter limpa. Melhorada a instrumentação, sem defeito adicional do
  motor confirmado nem alteração visual. Acústica/Media3 prolongado ficam em E8.
  Prova `.qa` isolada; Transpono principal intacto e Dev reaberto no fim.
- [x] E5 — Auditar e reparar reprodução, seek, A/B e progressão de prática;
  confirmar pausas, troca de faixa e continuidade sem contagens falsas.
  Concluída: 64 testes dirigidos Flutter passaram. Prova `.qa` no Samsung
  concluiu seis repetições locais e confirmou no WebView procura, voltas,
  pausa, procura parcial excluída e suspensão em anúncio simulado. A antiga
  prova com YouTube real usa um botão retirado no layout atual; a prova nova
  do player integrado passou com vídeo real: posição avançou 1,47 s, loop A/B
  confirmado, pausa estável e procura parcial não contada. Nenhum defeito do
  produto foi reproduzido nesta etapa; atualizada apenas a prova de QA.
- [x] E6 — Auditar e reparar cifras, transposição ligada/independente, importação
  existente e coleções/predefinições; preservar conteúdo e dados do utilizador.
  Corrigido o modo ligado já guardado: a cifra acompanha só o tom confirmado;
  controlos aguardam o ACK e respeitam indisponibilidade do áudio. Edição manual
  recusa texto alterado noutro painel e preserva tom/origem mais recentes.
  Importação e coleções passaram nos testes existentes, sem outro defeito
  reproduzido. 330 testes Flutter completos e análise estática aprovados.
  Interface atual mantém importações novas em modo independente; reintroduzir
  escolha visual de ligação exige autorização futura. Teste real do site e
  validação física desta etapa ficam para E8; nenhum pacote foi instalado.
- [x] E7 — Auditar ferramentas atuais: afinador/microfone, referência piano,
  deteção de tonalidade, metrónomo e widgets. Corrigir falhas reproduzíveis.
  Corrigidas atualização fora de ordem dos widgets, pré-escuta de piano tardia
  após suspensão e início tardio do microfone. Notas de piano serializadas para
  o último pedido prevalecer. Quinze testes Flutter dirigidos, 67 JavaScript/WASM
  (incluindo dois novos da deteção de tonalidade) e análise estática passaram.
  Não há medição acústica nesta etapa; fica para E8.
- [x] E8 — Verificação integrada no Samsung: qualidade/continuidade, segundo
  plano/retoma, recursos, permissões, regressões e instalação segura. APK Dev
  atualizado somente após confirmar ID e assinatura; pacote principal intacto.
  No pacote QA isolado, prática A–B/velocidades passou e a reprodução local
  pausou no segundo plano, sem retoma automática e preservando tom/velocidade.
  Corrigida a pausa de áudio local ao suspender o app. 334 testes Flutter,
  67 JavaScript/WASM e análise estática aprovados. Limites: microfone sem
  permissão no Dev, sem medição acústica ou de uso prolongado, sem validação do
  DOM real de cifras; memória teve apenas uma amostra, não teste de fuga.

Em cada etapa, decompor as correções em alterações pequenas e testar uma a uma.
Suporte novo a fontes, efeitos ou mecanismos de download não faz parte das
reparações E1–E8. O utilizador autorizou continuar as etapas sem nova pergunta.

### Pedidos posteriores, após as correções funcionais

O utilizador autorizou planear estas mudanças para depois das etapas acima.
São exceções explícitas futuras à restrição visual, não parte de E3. O utilizador
autorizou avançar sequencialmente sem pedir confirmação entre estas etapas.

- [x] U1 — Pesquisa de cifras pelo título real do vídeo; nunca usar o texto
  genérico «YouTube» como consulta. Barra de pesquisa com o padrão visual do app.
  Leitura do título reforçada por metadados da página; título genérico deixa
  pesquisa vazia para introdução manual. Barra alinhada à pesquisa YouTube
  interna. Testes JS e Flutter dirigidos aprovados.
- [x] U2 — Aproximar Cifra/Treino/Setlist/Áudio para caberem sem rolagem lateral,
  considerando também a coluna Configurações solicitada e acessibilidade.
  Faixa proporcional à largura disponível, sem scroll nem deslocação automática;
  os quatro destinos cabem num ecrã de 350 px. A futura quinta coluna herdará
  o mesmo cálculo e terá de ser validada na etapa U5.
- [x] U3 — Cores consistentes por nota nas cifras, incluindo acordes transpostos.
  Pedido posterior substituiu a paleta inicial: C azul, D verde, E vermelho,
  F marrom, G amarelo, A roxo, B rosa; as cinco notas alteradas usam variantes
  da respetiva família cromática. Enarmónicos partilham exatamente a cor
  (C♭/B, D♯/E♭, B♯/C, etc.), também em acordes
  entre colchetes; letra e espaçamento preservados. Personalizações guardadas
  pelo utilizador continuam prioritárias sobre as cores originais.
- [x] U4 — Subir a base do ponteiro do afinador para o traço indicado pelo
  utilizador, mantendo correspondência entre afinação e indicação. Pivô e
  raio deslocados em conjunto; teste de geometria e animação aprovado.
- [x] U5 — Coluna Config. com modo claro, estilo glass/vidro e cores das
  notas; preferências persistidas. Cinco abas cabem num ecrã de 350 px sem
  rolagem lateral. Contraste das notas adaptado ao claro. Vistas Escuro,
  Claro e Vidro verificadas no Samsung Dev; última linha alcançável por
  rolagem, acima da barra Android. Outras opções exigem definição prévia.
- [x] U6 — Apresentar sugestões de novas funcionalidades para escolha do
  utilizador; nenhuma sugestão implementada sem autorização.
  Candidatas: contagem de entrada de 1–2 compassos; comparação rápida entre
  som original/ajustado conservando configurações; perfis de áudio por
  instrumento. Priorizar por valor e risco junto do utilizador.

O último pedido terminou com «esse trans»; não inferir uma instrução adicional
a partir desse fragmento.

### Fila final — recursos complexos solicitados

Atualização: o utilizador autorizou executar esta fila e definiu Astra (médio)
para análise/revisão, Sol (médio) para implementação complexa e Terra (médio)
apenas para tarefas fáceis. A separação é exclusivamente no telefone, sem
PC/cloud. A prioridade do utilizador é agora somente vídeos YouTube;
implementação e evidências: `docs/BAND_AND_RHYTHM_IMPLEMENTATION.md`.
N1a está implementado experimentalmente e testado em UDP loopback e no motor
AudioTrack do Samsung; o gate acústico com dois aparelhos permanece aberto.
Na prova dual, o anfitrião passou, mas o convidado falhou continuidade. A
correção de clock tem nove testes unitários sem rerun; houve smoke do microfone
sem offset e registo da perceção do utilizador. Por pedido, não repetir a QA.
N1b (sincronia do player YouTube) ainda não foi implementado e aguarda o gate.

N2 tem análise WAV offline e prévia aprovada integrada em
`MainPlayerController`/Media3. A QA Android sintética passou no Samsung para
seek de 3 s, tom +2 e velocidade 0,75, com buffering de cerca de 500 ms;
363 testes Flutter e `flutter analyze` completo ficaram limpos. WAV é apenas
base técnica: a prioridade é análise de metrónomo e instrumentos para YouTube.
O mapa real e a sincronia do player YouTube permanecem abertos.

N3 usa o motor nativo de seis saídas, incluindo guitarra. A QA da app inferiu
um fresh-tone sintético de 1 s e produziu seis WAVs; as medições otimizadas
foram 0,54 GiB para 2 s e 0,70 GiB para 12 s. O fluxo na mesma sessão permanece
pendente: o guard de 1 GiB acima do threshold bloqueou antes da inferência em
Debug e Profile; o fresh-tone autónomo passou. O guard de 1 GiB permanece. A
release Dev foi instalada e aberta no Samsung original SM-A165F como
`com.example.transpose_mobile.dev`; a produção permaneceu intacta. O APK é
`apps/mobile/build/artifacts/transpono-dev-release-2026-09-28.apk` (67.075.326
bytes, SHA-256 `A1DFFF896331FF23784DE36024B0591E657E632A2A2A0490A30BA9D25476BEB2`),
com signer igual ao Dev prévio. Os 363 testes e `flutter analyze` completo
ficaram limpos. Não interpretar estas entregas parciais como conclusão dos
itens N1–N4.

Registo histórico substituído pela autorização atual: o pedido de 2026-09-28
para deixar nesta fila reprodução, evidências, tentativas e próximo passo para
eventual execução pelo Astra já não é uma ordem ativa. Não declarar concluído
nem delegar automaticamente.

- [ ] N1 — Metrónomo de banda e reprodução coordenada entre telemóveis na mesma
  rede: definir anfitrião, adesão explícita à sessão, relógio comum, início
  agendado, reconexão e correção de deriva. Medir latência por aparelho/saída
  (incluindo Bluetooth) em pelo menos dois dispositivos antes de prometer
  sincronização. O YouTube tem buffering e restrições próprios; separar
  sincronização de comandos da sincronização efetiva do áudio.
- [ ] N2 — Analisar a música completa para obter mapa de pulsações, BPM e
  compassos (binário/ternário/quaternário e mudanças), e alinhar o metrónomo.
  Usar ficheiros próprios/licenciados, indicar confiança/ambiguidades e definir
  comportamento em rubato, silêncios, anacruse e mudanças de velocidade/tom.
  Não prometer identificação perfeita de compasso a partir de qualquer áudio.
- [ ] N3 — Separação de voz, bateria, baixo, guitarra e outros instrumentos:
  avaliar modelos/licenças, qualidade, duração, RAM, bateria e armazenamento
  no Samsung; guitarra isolada pode exigir modelo diferente do de quatro stems.
  Processamento remoto exige consentimento antes de enviar ficheiros e decisão
  sobre custos. Validar primeiro com áudio próprio ou expressamente autorizado.
- [ ] N4 — Definir fontes e permissões para análise/separação e eventual download.
  O pedido de descarregar vídeos/áudio foi registado, mas armazenamento temporário
  ou em RAM não concede autorização. Verificar termos da plataforma e direitos
  da gravação/composição; não implementar contorno técnico de restrições.
  Resolver esta dependência antes de ligar N2/N3 a fontes online.

Detalhes técnicos, critérios de aceitação e prompt de passagem opcional ao
Astra: `docs/ASTRA_HANDOFF_BAND_SYNC_AND_STEMS.md`. N1–N4 continuam abertos;
a prova dual ainda não aprovou sincronização de banda nem separação, e o
YouTube não é uma fonte de download autorizada por se guardar em RAM.

Esta fila foi solicitada, mas fica depois das reparações e U1–U6. Avançar nas
partes locais e seguras; pedir uma decisão apenas se forem necessários direitos,
serviços pagos, envio de ficheiros ou escolhas de produto ainda indefinidas.
Não instalar modelos nem serviços pagos antecipadamente. Bloqueios concretos da
auditoria serão acrescentados aqui.

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
