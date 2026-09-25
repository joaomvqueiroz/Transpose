# Prática YouTube — comandos confirmados e QA do incremento

Data: **2026-09-25**. Pesquisa e limites de produto:
`YOUTUBE_PRACTICE_RESEARCH.md`. A progressão base e a sua primeira evidência
Media3/WebView offline permanecem descritas em `PRACTICE_PROGRESSION_QA.md`.

**Estado desta revisão documental:** correções de confirmação/cancelamento
implementadas, **363 testes automatizados aprovados** e análise Flutter limpa
também após a última revisão do probe. A sexta passagem Android confirmou
playback/pitch e marcadores, mas não iniciou o treino;
**a sétima execução passou o percurso real YouTube descrito abaixo**. Isso
aprova somente esse cenário no Samsung, não todo YouTube/iPhone ou a matriz
acústica. **A nova build release foi instalada por atualização**, com recuperação
visual da sessão anterior conferida. O percurso YouTube completo foi executado
em profile QA; não foi repetido nesta build release.

## Problema tratado

O treino depende de pausar, aplicar uma taxa, posicionar em A e reproduzir nessa
ordem. Enviar JavaScript à WebView não demonstra que uma operação assíncrona
terminou. Uma resposta periódica antiga também não deve substituir o snapshot
confirmado de um comando novo. Finalmente, um Play iniciado antes de Pausar,
trocar de fonte ou fechar a sessão pode resolver posteriormente.

Essas condições podiam quebrar a preparação do treino mesmo quando o adaptador
de contagem identificava corretamente as voltas. A correção não altera o DSP
nem inventa eventos de loop: torna explícitos confirmação, ownership da
operação e intenção de transporte.

## Contrato implementado

### Confirmação assíncrona por comando

`lib/web_media_command.dart` contém `WebMediaCommandRunner`, usado por
`WebViewYouTubeSession.command`:

1. Atribuir ID próprio e enviar `dispatch(id, request)`.
2. Consultar `commandResult(id)` enquanto estiver `pending`.
3. Aceitar `done` somente com snapshot válido; `error` gera exceção tipada que
   pode transportar o estado confirmado, sem apresentar diagnóstico privado
   da página como mensagem ao utilizador.
4. Recusar a resposta se o documento mudar ou a sessão for descartada.
5. Cancelar uma operação não concluída, quando ainda for o mesmo documento, e
   esquecer somente a entrada desse ID.

O prazo padrão é **18 segundos** para a execução, compartilhado por envio,
leituras e espera de polling; o intervalo normal de consulta é **50 ms**.
Nenhum await da ponte pode prolongar indefinidamente o comando. O cleanup tem
um orçamento total separado de **250 ms**, não 250 ms por ação, e não substitui
o resultado original se falhar. Timeout não é meta de latência aceitável nem
garantia de que uma página/binder sem resposta executou o cancelamento.

O parser suporta objeto, JSON textual e o JSON duplamente codificado observado
no transporte Android. Resultado ausente, JSON inválido, status desconhecido ou
snapshot incompatível falha explicitamente. Não reinterpretar resposta
malformada como sucesso.

Na página, a tabela de resultados é limitada a **64 entradas**. Um mesmo ID
retido não dispara duas operações; descarte/cleanup de um ID não recria a sua
entrada quando uma Promise antiga terminar. A tabela remove resultados
concluídos para libertar espaço e recusa sobrecarga de pendentes.

### Snapshots com ordem explícita

Cada snapshot JavaScript tem `snapshotRevision` monotónica no documento.
`WebViewYouTubeSession` aceita apenas revisão inteira, finita, segura e maior
que a última recebida. Navegação cria outra geração de documento e reinicia a
comparação. Assim, um poll antigo não pode reverter o estado de um ACK novo.

Revisão de snapshot ordena observações; não é a mesma coisa que `loopEpoch`,
que invalida a identidade do trecho/fonte, nem que a revisão de intenção de
transporte. Mantê-las separadas impede que uma atualização normal da UI seja
interpretada como uma nova sessão ou uma volta de treino.

### Cancelamento de Play e pitch pendentes

O adaptador JavaScript associa Play ao elemento, fonte, vídeo, estado de
anúncio, revisão de transporte e ID do comando. Verifica a validade após
operações assíncronas, incluindo a ativação de `AudioContext` e `video.play()`.
Pausa, descarte e mudanças incompatíveis invalidam a intenção.

`cancelCommand(id)` age apenas sobre a operação ainda pendente daquele ID.
Uma conclusão antiga não deve ressuscitar áudio nem pausar um Play novo válido
que entretanto assumiu o mesmo elemento. O pitch pendente conserva também a
sua revisão/ownership; cancelar a operação vigente mantém a rota original e
não invalida o pedido de tom mais recente.

Esses invariantes têm testes determinísticos. Ainda exigem QA físico em
condições de browser/rede variadas; não constituem prova de silêncio acústico
instantâneo ou de todas as corridas possíveis.

### Play explícito em vez de toggle tardio

O bridge oferece `play` idempotente: pedir Play a um vídeo que já toca não o
pausa nem altera o mute. `playPause` continua disponível para o controle de
toggle da própria página, mas o `MainPlayerController` captura a intenção do
toque antes de enfileirar trabalho e envia `play`, `pause` ou `unmute` explícito.

Isso evita decidir o oposto depois de autoplay ou outra mudança de estado
durante a espera. As revisões de pausa/interrupção continuam a cancelar
intenções antigas. Não introduz autoplay na recuperação ou no regresso do app.

### Pausa prioritária, inclusive durante operações pendentes

Quando existe mídia carregada a reproduzir sem mute, o toque de Pausa no
`MainPlayerController` chama o caminho prioritário `pause()` sem entrar na fila
de comandos. A revisão de pausa invalida Play pendente antes de aguardar o
retorno da ponte. Isso permite interromper reprodução enquanto outro ajuste
assíncrono está ocupado; não reduz o prazo de rede nem transforma ACK em prova
de silêncio acústico.

Player principal, fullscreen, Prática e Palco deixam essa ação de Pausa
disponível durante `busy`, mas não liberam um Play novo nem Ativar som nesse
estado. Locks de fullscreen/Palco continuam respeitados: o atalho de pausa não
contorna um painel explicitamente bloqueado. A configuração do treino e seus
controles de pausa/encerramento conservam o contrato próprio do coordenador.

## Testes automatizados — suíte completa da revisão

Resultados da execução coordenada pelo executor principal:

| Grupo | Resultado final | Evidência/escopo |
| --- | --- | --- |
| Mobile | **260 passaram** | Suíte completa; `apps/mobile/build/unit-tests-youtube-ack.log` termina em `+260: All tests passed!`. |
| Player Core | **56 passaram** | Suíte do núcleo de player. |
| JavaScript/WASM/ponte | **47 passaram** | Suíte do adaptador e processamento web. |
| Flutter analyze | **Limpo** | Nenhum problema; repetido pelo executor principal após a última alteração do probe. |

Total: **363** (260 + 56 + 47). Os grupos direcionados abaixo são subconjuntos
já incluídos, não testes adicionais para somar novamente:

| Grupo | Resultado direcionado | Escopo |
| --- | --- | --- |
| JavaScript/WASM/ponte | 47 passaram | Inclui regressões existentes, ACK por ID, cancelamento, idempotência e transporte pendente. |
| Dart ACK/runner | 34 passaram | 27 casos de `web_media_command_test.dart` e 7 de `webview_command_ack_test.dart`; JSON, erro/snapshot, navegação, deadline, cleanup e ordem. |
| MainPlayerController | 2 regressões novas passaram | Intenção de Play/Pausa capturada antes da fila e mudança assíncrona do estado. |
| Foco/layout | 3 testes direcionados passaram | Ordenação do foco após montagem e comportamento de layout; não substituem o player remoto real. |
| Pausa durante busy — UI | 5 testes direcionados passaram | Exceção de Pausa nos painéis e respeito aos locks; não liberam Play pendente. |

Não foi o autor deste documento que executou SDK/testes. Os números acima
correspondem à execução coordenada reportada pelo responsável; o final do log
mobile também foi conferido durante a documentação. Um probe físico é evidência
separada e não aumenta esse total de testes automatizados.

## Android real — primeira tentativa, sem aprovação do treino

O resultado inicial em `apps/mobile/build/youtube_practice_evidence.json`
registou `passed: false`, `isolatedQa: true`, `liveYouTube: true`, início UTC
`2026-09-25T01:54:20.356353Z` e fim `2026-09-25T01:54:45.799749Z`.

Observações efetivas dessa tentativa:

- A pesquisa encontrou **20 miniaturas**.
- Foi selecionado o vídeo `aqz-KE-bpKQ` dentro da WebView.
- O estágio `unmuted playback` expirou antes do início da prática.
- Snapshot de falha: vídeo pausado em **21 ms**, `muted: false`, `isAd: false`,
  taxa 1,0×, tom 0, sem A/B, zero voltas e nenhum evento de prática.

Isso confirma pesquisa/seleção nessa tentativa, **não** confirma reprodução
contínua, pitch, loop ou progressão. O snapshot isolado também não identifica
sozinho a causa da pausa. O incremento trata, entre outros pontos, a inversão
de intenção causada por toggle tardio; a nova prova física deve confirmar o
percurso corrigido, sem atribuir causalidade apenas por coincidência temporal.

Os arquivos abaixo são destinos da execução e podem ser substituídos pela
próxima passagem; este registro de falha preserva os valores observados, mas
não se deve apresentar um arquivo sobrescrito como o log daquela tentativa:

- `apps/mobile/build/youtube-practice-probe-run.log`;
- `apps/mobile/build/youtube_practice_evidence.json`;
- `apps/mobile/build/transpono-youtube-practice-qa.png`.

### Segunda tentativa — prontidão de playback insuficientemente comprovada

O mesmo destino de evidência foi atualizado com outra falha: início UTC
`2026-09-25T02:00:49.958124Z`, fim `2026-09-25T02:01:20.708393Z`,
`passed: false` e **19 miniaturas** na pesquisa.

Depois de montar o player, `afterMainPanelSettled` indicava `playing: true`,
mas `ready: false` e posição **0 ms**. O probe interpretou o estado transitório
como suficiente e registrou `requestedInitialMainPlay: false`. A flag
`unmutedPlaybackConfirmed: true` desse arquivo é, portanto, uma verificação
fraca da versão antiga do probe: não comprovou avanço real da timeline.

O estágio `pitch acknowledged` expirou. Já antes do toque em Pitch, a mídia
estava pausada em **36 ms**; depois o processador permaneceu `loading`, com
“Tom preparado; a aguardar sinal de áudio.” Não houve A/B nem sessão/voltas de
prática. O ACK do comando de pitch retornou com o estado de preparação, não
com uma alegação falsa de tom aplicado. Não considerar essa espera como prova
de incompatibilidade DSP: não havia reprodução contínua confirmada para
produzir sinal.

Para a terceira execução, o probe espera conteúdo pronto e fora de anúncio,
observa novamente a WebView depois de montada e decide **uma única** ação de
Play/Ativar som se necessária. Antes de pedir pitch, exige o mesmo vídeo a
reproduzir, sem mute/anúncio, e avanço de pelo menos **250 ms** ao longo de
uma observação de **1,2 s**. Não faz retries de Play em loop para esconder
falhas de transporte. Esse avanço confirma timeline, não som captado.

### Terceira tentativa — Play explícito seguido de pausa

O executor principal reportou outra falha após enviar Play explícito: o vídeo
iniciou brevemente e voltou a pausar, sem um novo comando Dart de Pausa no
intervalo observado. O critério mais forte de avanço não aprovou o percurso.
Esse resultado reduziu a hipótese de a falha se resumir a um toggle enviado
pelo app; não identifica, por si, quem originou o evento de pausa na página.

Não há neste documento uma cópia autônoma do JSON da terceira passagem. Sua
descrição é o registro da observação comunicada pelo executor, não uma
inferência retirada do arquivo da tentativa seguinte. Nenhuma etapa de treino
foi aprovada nessa tentativa.

### Quarta tentativa — geometria e eventos passivos

Foi acrescentada instrumentação passiva de eventos/retângulo/viewport do vídeo,
sem substituir `play()`/`pause()` da página, suprimir eventos ou forçar replay.
A evidência desta passagem foi preservada separadamente em
`apps/mobile/build/youtube_practice_geometry_failure.json`.

O arquivo registra início UTC `2026-09-25T02:07:30.726199Z`, fim
`2026-09-25T02:07:37.595684Z`, **18 miniaturas**, `passed: false` e falha em
`actual content position advances before pitch`.

| Observação | Antes de usar no player | Depois de montar o painel |
| --- | --- | --- |
| Retângulo do vídeo, pixels CSS | x=121, y=48, 494×278 | x=121, y=48, 87×49 |
| Viewport, pixels CSS inteiros | 748×182 | 342×224 |
| Scroll vertical | 0 | aproximadamente 54,76 |
| Prontidão observada | readyState=4 | readyState=4 |
| Documento/elemento | visível e conectado | visível, conectado, mesmo elemento selecionado |

A sequência de eventos contém scroll e resize, seguida de pausa por volta de
0,770 s. O app então enviou **um Play explícito**, cujo ACK mostrou reprodução
em aproximadamente 0,963 s. Houve novo evento de pausa em aproximadamente
1,047 s; a janela de avanço do probe contabilizou somente **84 ms** e terminou
pausada. Fonte/vídeo e epoch permaneceram estáveis no intervalo. Os comandos
Dart registrados foram Pausa antes da pesquisa e esse Play, sem outra Pausa
Dart entre o Play e a falha. Não houve pitch, A/B ou treino concluído.

Isso é uma **correlação observada** entre mudança de geometria/scroll e pausa,
não prova isolada da causa interna do YouTube/WebView. O documento visível e o
elemento conectado também não garantem reprodução contínua. Não concluir que
o app recebeu perda de foco, que um anúncio ocorreu ou que o DSP falhou apenas
com essa sequência.

### Quinto ensaio — scroll corrigido, playback ainda falhou

Com base na observação, `_useVideo` passou a esperar o frame que monta a
viewport final antes de chamar `focusVideo`, validando que ainda se trata da
mesma sessão. `focusVideo` move a página instantaneamente para o topo com
`window.scrollTo`, no lugar de centralizar o elemento com rolagem suave
durante o resize. A alteração não redimensiona/oculta controles do YouTube,
não extrai mídia e não reinicia Play para mascarar a pausa.

A quinta execução **não corrigiu o percurso físico**. O JSON observado registra
início UTC `2026-09-25T02:09:59.26749Z`, fim `2026-09-25T02:10:05.307695Z`,
18 miniaturas e falha no avanço real antes de pitch, terminando pausado em
391 ms. O scroll já estava em **0**, mas o retângulo do vídeo continuava
**87×49** dentro da viewport **342×224**. Os comandos registrados foram Pausa
antes da pesquisa e Ativar som.

Logo, centralização/scroll por si só não explica nem resolve a falha observada.
Não apresentar o ajuste de foco como causa raiz comprovada ou correção física
aprovada. Os testes de layout/foco confirmam o contrato do código, não o
comportamento responsivo interno da página remota.

### Sexta execução — playback e pitch confirmados, treino não iniciado

O executor comparou outra configuração: em paisagem, a WebView fixada
recebe dois terços da largura disponível, em vez de metade. A rolagem dos
controles Flutter é reposicionada depois do frame da nova composição. Não há
remoção de CSS, player ou controles do YouTube, nem reprodução forçada em loop.

Esta passagem registra início UTC `2026-09-25T02:12:44.813084Z`, fim
`2026-09-25T02:13:10.303836Z` e **19 miniaturas**. O resultado global continua
`passed: false`, mas o percurso avançou:

- Na janela anterior ao pitch, a posição passou de 1.088 ms para 1.971 ms
  (**883 ms de avanço**), com mesmo vídeo, reprodução ativa, som habilitado,
  prontidão e nenhum anúncio observado nessa janela.
- O processamento confirmou **+1 semitom**, `pitchStatus: active`.
- Os marcadores foram aplicados em **A=20 s / B=22 s**, com loop habilitado e
  capability de contagem disponível.
- A espera por `first complete repetition` expirou: o treino permanecia
  **`notStarted`**, sem mensagem de erro, e não houve comando de preparação
  depois de `markB`. O contador de voltas permaneceu zero.

O probe registrou um toque destinado a `practicePlanStart` logo depois de
recolher a configuração. A hipótese de toque durante a animação de recolhimento
é consistente com a ausência de início/comandos, mas não está demonstrada
apenas por esse registro. A tentativa **não prova falha da contagem de um
treino em execução**, pois a sessão não chegou a começar; também não aprova
automaticamente o botão ou o treino completo.

O resultado favorável de playback/pitch após o ajuste de largura é uma prova
funcional nesta composição/dispositivo, não uma explicação isolada e universal
da lógica interna do YouTube. A dimensão maior não aprova outros aparelhos.

### Sétima execução — percurso real aprovado no cenário testado

O probe agora espera **400 ms** após recolher a configuração, verifica que o
botão é atingível pelo hit test e confirma que o estado saiu de `notStarted`
depois do toque, antes de aguardar voltas. Isso melhora a qualidade da prova
sem iniciar a sessão por chamada direta nem clicar repetidamente para ocultar
um botão que não responde.

A passagem real no Samsung SM-A165F, pacote profile
`com.example.transpose_mobile.qa`, registra:

- `passed: true`, `isolatedQa: true` e `liveYouTube: true`;
- início UTC `2026-09-25T02:15:51.197781Z` e fim
  `2026-09-25T02:16:34.854186Z`, aproximadamente **43,7 s** de percurso;
- **18 miniaturas**, seleção de `aqz-KE-bpKQ` na mesma WebView e **1.084 ms**
  de avanço confirmado na janela anterior ao processamento;
- **+1 semitom** com `pitchStatus: active`, no vídeo real, sem confundir
  preparação do grafo com confirmação de sinal;
- **A=20 s / B=22 s**, plano **60% → 65% → 70%**, duas voltas por etapa,
  **seis voltas completas**, estado `completed` e player pausado a 70%;
- pausa após a primeira volta: contador/estado preservados durante **1,2 s**,
  seguida de retoma explícita;
- entrada e saída do fullscreen **realmente montado** durante prática ativa,
  sem trocar a sessão/controlador;
- novo treino e ajuste manual para **75%** suspendendo a automação, contagem
  estável e ausência de autoplay na navegação posterior.

A instrumentação registrou uma factory, um start, uma pesquisa e uma construção
da WebView; zero reloads. Documento, elemento de mídia e `PracticeController`
foram preservados. Isso prova a identidade observada nesse percurso, não uma
medição acústica de ausência de áudio duplicado.

Artefatos conferidos:

- `apps/mobile/build/youtube_practice_evidence.json`: resultado e sequência;
- `apps/mobile/build/youtube-practice-probe-run.log`: termina com
  `All tests passed.` e `Leaving the application running.`;
- `apps/mobile/build/youtube_practice_geometry_failure.json`: cópia separada
  da quarta tentativa, não substituir pela aprovação final.

**Nenhum anúncio foi registrado nos snapshots/eventos dessa passagem.** Não
houve observação contínua capaz de certificar ausência de anúncios em todo
instante; sobretudo, isso não aprova um cenário com anúncio real. Os testes
simulados anteriores continuam evidência distinta.

As seis passagens anteriores não aprovadas incluem problemas observados de
layout/transporte e fragilidades do próprio probe. São **seis tentativas de QA
sem aprovação antes de uma passagem aprovada**, não seis falhas universais do
app nem uma amostra válida para taxa de confiabilidade. A aprovação final não
apaga as observações históricas ou fecha seus limites automaticamente.

Permanecem abertos: outros vídeos/aparelhos/WebViews, anúncios reais,
conectividade intermitente e B próximo do EOF em produção; iPhone, chamadas/BT,
acessibilidade física, precisão acústica/qualidade musical, P50/P95/P99,
sincronização A/V e uso prolongado. O tempo total de 43,7 s não mede latência
de processamento. A fonte remota foi exercitada de verdade, diferentemente do
fixture offline anterior, mas o gate de distribuição ADR-013 continua aberto.

## Isolamento e atualização

O wrapper `apps/mobile/tool/run_youtube_practice_probe.ps1` constrói primeiro
o target `integration_test/youtube_practice_probe_test.dart`, valida a metadata
`com.example.transpose_mobile.qa`/profile/APK e fornece o binário validado ao
driver com `--keep-app-running`. O wrapper não desinstala, limpa dados nem
force-stopa qualquer app. O probe espera anúncios naturalmente; não os remove
ou contorna.

### Build release e smoke de recuperação

O executor principal compilou release com target `lib/main.dart`. A metadata
conferida identifica **`com.example.transpose_mobile`**, variante `release`,
APK único. Arquivo:

`apps/mobile/build/app/outputs/flutter-apk/app-release.apk`

Tamanho: **63.177.124 bytes**. SHA-256 conferido novamente na documentação:

```text
8348F483478BB736BA9252ADCA29F7CE828A793C125AF20AD715BB1290D2D1AD
```

`adb install -r` retornou `Success`. A metadata do aparelho conservou
`firstInstallTime = 2026-09-25 02:14:50` e passou a registrar
`lastUpdateTime = 2026-09-25 03:18:54`, nos horários reportados pelo dispositivo.
O app normal abriu a sessão anterior no painel Prática, com a amostra de
440 Hz e aviso “Sessão recuperada · toque em reproduzir para continuar”.

O executor inspecionou a captura
`apps/mobile/build/transpono-release-youtube-ack.png`. O teste YouTube isolado
não substituiu a sessão anterior do utilizador. Esse smoke comprova a abertura
e recuperação visual observadas nessa atualização, sem autoplay aparente;
não é um novo ensaio de process death ou medição acústica.

**O percurso YouTube de seis voltas passou na build profile `.qa`, não foi
repetido em release.** A instalação e o smoke release são evidências distintas;
não inferir equivalência completa de todos os cenários pela build ter compilado.

Após conferir o pacote exato, o executor removeu somente
`com.example.transpose_mobile.qa`, com retorno `Success`, apagando sua sandbox
e os dados descartáveis de testes. O pacote normal continuou instalado, sem
desinstalação/limpeza, e os arquivos de evidência permaneceram no workspace.
Nenhum teste usou o armazenamento de produção como fixture.

## Decisão arquitetural do incremento

O registro **ADR-018 — Comandos WebView confirmados e intenção de reprodução
cancelável** foi acrescentado a `codex_project_master/ARCHITECTURE_DECISIONS.md`
com arquitetura aceita, suíte automatizada e percurso real restrito aprovados;
build/instalação release e smoke de recuperação concluídos, com os demais
gates explicitamente abertos. A decisão mantém a sessão única e acrescenta ACK
assíncrono por ID, snapshots ordenados por documento e ownership cancelável
das operações. Estado aplicado continua separado de intenção enviada; erros e
timeouts não viram sucesso nem desbloqueiam comandos abandonados.

O repositório mantém ADRs em `codex_project_master/ARCHITECTURE_DECISIONS.md`,
não em `docs/decisions/`; não foi criada uma segunda árvore de decisões.

Não muda ADR-013, não aprova distribuição do processamento YouTube, não
acrescenta download/extração/captura e não resolve por si iOS, acessibilidade,
chamadas/BT, precisão acústica, latência estatística ou uso prolongado.
