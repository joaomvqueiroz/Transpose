# Prática progressiva — pesquisa, decisão e critérios de QA

Pesquisa consultada em 2026-09-25. Este documento é uma especificação de decisão
e de testes; **não declara que a implementação, os testes ou os gates abaixo já
passaram**. Evidências da entrega devem ser registadas separadamente, com build,
dispositivo, cenário e resultado.

Atualização: resultados concretos posteriores estão em
`PRACTICE_PROGRESSION_QA.md`. O relatório distingue o percurso Media3 físico,
fixture WebView offline e gates ainda abertos; os critérios abaixo continuam
normativos, não uma declaração de aprovação automática de todos eles.

## Decisão recomendada

Acrescentar uma progressão configurável de velocidade ao loop A/B existente:
início, alvo, incremento e voltas por etapa. O motor de prática coordena o player
existente, sem abrir outro player ou processar áudio. Contar somente voltas
confirmadas pelo adaptador da fonte; nunca derivar repetições do tempo decorrido.

Ponto de partida de produto: 60% → 100%, incremento de **5 pontos percentuais**,
três voltas por etapa, incluindo três voltas na velocidade-alvo. Todos os valores
devem ser editáveis antes de começar. É uma escolha nossa para uma configuração
simples, não uma prescrição pedagógica nem consenso demonstrado pelo Reddit.
A faixa admitida deve continuar limitada à capability já suportada pelo player
principal (atualmente 50–150%), sem prometer mais por causa da UI de treino.

Ao completar o plano, pausar. Mostrar “Plano concluído” e as voltas realmente
reproduzidas, não “Trecho dominado”, “Precisão 100%” ou uma avaliação da execução
do músico: não existe análise do instrumento/microfone que justifique isso.

## Evidência externa e limites

- O criador de **Practice Hero** descreve uma progressão automática de velocidade
  para loops de YouTube até um alvo. Explica que queria deixar de ajustar a
  velocidade manualmente. É um relato de quem criou e mantém uma ferramenta,
  não uma auditoria da sua implementação nem prova de superioridade musical.
  [Relato do desenvolvedor](https://www.reddit.com/r/Guitar/comments/1ugeobv/i_built_a_tool_to_help_practice_with_youtube/).
- Na publicação do criador de **Music Slowdowner**, um utilizador pede
  explicitamente uma sequência como 80, 82, 84… até 100%, e o autor responde que
  considerará a ideia. Há também relatos de incompatibilidade de captura entre
  navegadores/iPad. Isso apoia pequenos passos configuráveis e validação por
  plataforma, não importar automaticamente as soluções técnicas do outro app.
  [Publicação e feedback](https://www.reddit.com/r/Guitar/comments/1n2b3po/free_tool_for_slowing_down_music_to_help_with/).
- Na publicação do criador de **SlowTube**, um utilizador pede incrementos de
  cerca de 5%; o autor relata adicionar uma taxa personalizada. Outros comentários
  destacam a utilidade de repetir trechos e a conveniência da busca integrada.
  A discussão é de 2019: serve como sinal de necessidade duradoura, não como
  fonte sobre as limitações atuais de browsers ou YouTube.
  [Relato e pedidos do SlowTube](https://www.reddit.com/r/Guitar/comments/dp89bk/oc_i_made_slowtube_a_web_app_to_learn_songs_from/).
- A documentação do próprio **Anytune** descreve um treino com valores inicial e
  final, etapas, repetições por etapa e ação final escolhida. É um precedente
  verificável de interação. Para o primeiro incremento do Transpono, escolher
  apenas a ação final segura de pausar reduz estados e casos de erro; repetição
  infinita, reiniciar plano e avançar trecho podem ser opções futuras.
  [Guia oficial Step-It-Up](https://anytune.zendesk.com/hc/en-us/articles/360025666651-Step-It-Up-Loop-Trainer).

Conclusão da análise: a progressão adiciona utilidade à função central de
pitch/speed/loop e exige menos novas dependências que gravação, cloud ou IA.
Os relatos são amostras de feedback autoselecionadas; não permitem afirmar que
“todos os desenvolvedores recomendam” essa decisão.

## Contrato operacional

| Ação / estado | Resultado esperado |
| --- | --- |
| Configurar | Validar números finitos, intervalo suportado, alvo ≥ início, incremento positivo e repetições inteiras positivas. Mostrar erro junto do campo. |
| Início = alvo | Plano de uma etapa, com o número configurado de voltas; sem divisão por zero. |
| Último incremento ultrapassa o alvo | Usar exatamente o alvo, sem exceder nem criar duas etapas iguais. |
| Começar | Exigir fonte pronta, A/B válido e capability de contagem; aplicar velocidade, posicionar em A e só então iniciar. Toques repetidos não iniciam sessões concorrentes. |
| Contar | Somente fronteira de loop confirmada, da fonte e revisão de A/B da sessão atual; nunca timer, atualização de UI ou seek manual. |
| Subir velocidade | Depois das N voltas da etapa atual, fazer uma breve pausa, aplicar e confirmar a próxima taxa, voltar a A e iniciar a nova etapa. A pausa/recomeço deve ser explicada na UI; não prometer transição contínua nem anunciar etapa como tocada durante comando pendente. |
| Pausar treino | Parar áudio e progressão; guardar voltas completas. Uma volta parcial não se transforma numa volta completa. |
| Retomar treino | Exigir toque, mesma fonte e loop compatível; retomar etapa e contagem guardadas. Reiniciar a volta parcial em A é uma política simples e previsível. |
| Encerrar treino | Cancelar incrementos e callbacks pendentes, pausar, conservar os ajustes e marcadores úteis. Não apagar predefinições ou trechos. |
| Voltar a A / seek manual | Não contabilizar o salto como volta; suspender/rearmar a progressão com mensagem clara. |
| Alterar velocidade manualmente | Suspender progressão automática, explicar “Ajuste manual”; nenhum incremento escondido depois. |
| Alterar A/B, fonte ou abrir predefinição | Invalidar eventos antigos e encerrar a sessão incompatível, mesmo se já estava pausada. Voltar à faixa/trecho anterior não ressuscita o plano: exige iniciar/recomeçar. Não transferir voltas para outra música. |
| Mudar entre painéis/fullscreen | Manter o mesmo controller e sessão; mudar a tela não reinicia contagem. |
| Background, interrupção, anúncio, erro | Não avançar etapas. Respeitar a pausa segura do app; nunca iniciar áudio por conta de um callback atrasado. |
| Completar | Só depois das N voltas na etapa-alvo. Pausar uma única vez, manter a taxa final e apresentar o total confirmado. |
| Recuperar após processo morto | Restaurar plano/progresso num estado pausado, validar fonte/loop, pedir toque para continuar. Não carregar YouTube automaticamente. |

Durante preparação/troca de velocidade, Pausar/Encerrar devem continuar
operacionais. Uma geração/token de operação invalida o Play e os incrementos
de uma operação abandonada. O listener de UI não deve ser o dono da sessão.

## Eventos reais e o que não medem

No Media3, o motivo `MEDIA_ITEM_TRANSITION_REASON_REPEAT` distingue repetição
de troca automática de item, seek ou alteração da playlist. O guia também
documenta callbacks específicos de seek e a ordem de `onEvents`. A contagem deve
usar essa distinção no adaptador, não inferir repetição porque a posição diminuiu.
[Eventos oficiais do Media3](https://developer.android.com/media/media3/exoplayer/listening-to-player-events),
[contrato Player](https://developer.android.com/reference/androidx/media3/common/Player).

Para mídia web, `currentTime` pode mudar por seek e o padrão define eventos
separados de seeking/seeked. Portanto, observar apenas `timeupdate`, relógio de
parede ou posição a recuar não comprova uma reprodução completa. O adaptador
precisa distinguir o seu retorno A/B confirmado de um seek do utilizador,
troca do elemento, anúncio ou troca de vídeo.
[HTML Standard — mídia e seeking](https://html.spec.whatwg.org/multipage/media.html#seeking).

Contrato recomendado do sinal: identificador de fonte/sessão, revisão do loop,
sequência monotónica e confirmação da fronteira. Repetições duplicadas ou de
gerações antigas não aumentam o progresso. Se um snapshot agrega várias voltas,
elas podem representar reprodução real na **mesma taxa**; não podem justificar
atravessar etapas cujas taxas ainda nem foram aplicadas. Perder a fronteira de
troca exige ressincronização/pausa segura, não inventar etapas concluídas.

Um evento de Media3/WebView confirma uma transição lógica do player. **Não é
medição acústica** da precisão de B/A, silêncio, clicks, qualidade do time-stretch
ou execução do músico. Os gates LOOP/PITCH/SPEED da matriz de QA continuam
separados e exigem as suas próprias capturas/medidas.

## Persistência e acessibilidade

Persistir como unidade consistente: fonte, A/B, plano inicial/alvo/incremento,
voltas por etapa, etapa/taxa confirmada, voltas concluídas, estado seguro e versão.
Guardar nas transições relevantes e em cada volta concluída, sem escrever por
frame. Não confiar apenas no fechamento da tela. Uma falha de escrita deve ser
visível e nunca converter progresso pendente em progresso durável alegado.
Recuperar esquema antigo sem prática continua válido; esquema futuro/ilegível
segue a política não destrutiva de recuperação existente.

Manter configuração avançada recolhida, resumo do plano visível e botões de
pausa/retoma/encerrar com rótulos claros. Não depender apenas de cor, slider ou
long press: disponibilizar controles discretos de ajuste, semântica dos valores,
foco e leitura coerentes, texto ampliado sem overflow, além de alvos táteis
adequados à plataforma. Validar TalkBack/VoiceOver em hardware; um teste de widget
não substitui essa validação. [Orientação oficial Flutter sobre acessibilidade](https://docs.flutter.dev/ui/accessibility).

## Gates propostos — não executados neste documento

| Gate | Prova requerida |
| --- | --- |
| PRACTICE-QA-001 — plano | Testes início=alvo, incremento não divisível, limites 50/150, números inválidos, repetições inválidas e representação sem erro acumulado de ponto flutuante. |
| PRACTICE-QA-002 — contagem | Duplicado, evento antigo, reset de contador, seek até B, voltar a A, primeira volta parcial, A/B alterado, fonte trocada e deltas agrupados. Nenhuma volta falsa. |
| PRACTICE-QA-003 — fluxo | Plano curto 60→65→70%, duas voltas por etapa: seis voltas, duas mudanças de taxa, término pausado; também testar etapa única. |
| PRACTICE-QA-004 — corrida | Pausar/Encerrar durante aplicação de taxa, seek de arranque e Play; callback antigo não pode reproduzir nem incrementar. |
| PRACTICE-QA-005 — ajustes manuais | Mudar taxa no player principal/fullscreen suspende automação imediatamente e preserva a taxa escolhida. |
| PRACTICE-QA-006 — interrupções | Pausa, buffering, anúncio, background e perda de foco não produzem voltas por tempo decorrido; continuação exige a política explícita da sessão. |
| PRACTICE-QA-007 — navegação | Prática→Player→fullscreen→Prática conserva sessão/contagem e não cria outro player. |
| PRACTICE-QA-008 — recovery | Snapshot consistente de plano e progresso; relaunch pausado, YouTube metadata-only, erro e fallback sem perda de coleções. Kill físico apenas no pacote QA isolado, sem uninstall/pm clear. |
| PRACTICE-QA-009 — capacidades | Fonte sem sinal confiável oferece treino manual e motivo; não mostra progressão funcional falsa. Testar cada adaptador individualmente. |
| PRACTICE-QA-010 — UI | Todos os controles por toque/teclado/semântica quando aplicável; valores grandes/texto ampliado, retrato/paisagem, erro, preparando, pausado e concluído sem overflow. |
| PRACTICE-QA-011 — físico | Contar fronteiras e mudanças de taxa no dispositivo, conferir estado nativo e áudio ouvido. Separar áudio local, vídeo local e YouTube, identificando o que passou e o que não foi testado. |
| PRACTICE-QA-012 — prolongado | Sessões longas e loops mínimos/máximos; medir precisão, drift, clicks e latência pela matriz existente. Uma demonstração curta não aprova P95, 99,9% ou 1000 voltas. |

Telemetria local de QA suficiente: sessão anonimizada, revisão de loop,
sequência recebida, etapa, voltas, taxa pedida/confirmada e motivo de pausa.
Não incluir áudio do utilizador, URL autenticada ou caminhos privados completos;
não enviar telemetria para servidor por causa deste recurso.

## O que manter, acrescentar, adiar ou retirar

- **Manter:** tom independente da velocidade, A/B e trechos guardados, escolha de
  YouTube no app, sessão única, controles manuais e recuperação pausada.
- **Acrescentar agora:** plano simples editável, contagem verificável, resumo do
  próximo passo, pausa/retoma/encerrar, tratamento de capability e recuperação.
- **Adiar:** curvas arbitrárias, metronome sincronizado, delay/count-in entre
  loops, sequência automática de vários trechos, histórico estatístico amplo,
  avaliação do músico, gravação, stems, nuvem e social. Não apagar itens do
  roadmap: cada um tem requisitos e provas próprios. Um timer de UI não seria
  um metrónomo de precisão.
- **Retirar deste fluxo:** dados demonstrativos apresentados como análise real,
  progresso por timer, botões que só mostram sucesso sem aplicar ação e
  reprodução automática após recuperação. Preservar o desenho original como
  referência; mudar somente o que for necessário para estados e ações reais.

## Rastreabilidade interna

- `codex_project_master/CODEX_BACKLOG.md`: PRACTICE-001..005.
- `codex_project_master/PROJECT_MEMORY.md`: Dominar Trecho e configuração recolhida.
- `codex_project_master/BEHAVIOR_CONTRACT.md`: §§24–26, tela não é dona da sessão,
  ajuste manual suspende automação, capability transparente.
- `codex_project_master/DATA_MODEL.md`: PracticeSession e PracticeEvent.
- `codex_project_master/AUTOSAVE_RECOVERY.md`: snapshot atómico e sem autoplay.
- `codex_project_master/QA_TELEMETRY.md` e `matriz_qa_app_musical.csv`: métricas,
  privacidade e distinção entre teste funcional e gates de release.
- `docs/RECOVERY_RESEARCH_AND_QA.md`: isolamento obrigatório do pacote QA e
  proibição de procedimentos que apaguem os dados do app de produção.
