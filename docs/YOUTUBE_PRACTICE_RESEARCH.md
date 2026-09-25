# Prática no YouTube — decisão e limites de validação

Pesquisa consultada em **2026-09-25**. Este documento recomenda o próximo
incremento; **não declara que YouTube real, anúncios, iPhone ou qualquer gate
físico tenha passado**. Resultados de execução devem identificar separadamente
build, aparelho/WebView, vídeo, cenário e resultado.

## Decisão recomendada

Consolidar a prática progressiva já implementada na mesma WebView que contém a
pesquisa e o vídeo. Não criar outro player nem acrescentar extração, gravação,
cache offline, bypass de anúncios, login automático ou serviços de terceiros.
O resultado desejado deste incremento é o percurso real de vídeo → A/B → plano
→ voltas confirmadas → conclusão pausada, com cancelamento seguro quando a
fonte deixa de ser controlável.

Manter tom, velocidade, A/B e controles manuais: são o núcleo pedido pelo
utilizador. Uma falha de capability deve desativar somente o recurso que não
pode ser confirmado, com motivo e ação possível; não apresentar um botão ativo
que apenas anuncia sucesso. Aumentar o número de funcionalidades antes desta
prova não é a melhor prioridade para este turno.

Esta escolha é uma análise de engenharia do Transpono. Os relatos seguintes
mostram necessidades e riscos, mas não estabelecem consenso, qualidade sonora
ou compatibilidade entre plataformas.

## Relatos considerados

- O criador de **Practice Hero** descreve uma extensão para estudar no YouTube,
  com loop, pitch e uma progressão de velocidade. A motivação que relata é
  evitar ajustes manuais repetidos. Isso reforça a utilidade da progressão, mas
  uma extensão Chrome não comprova o mesmo percurso numa WebView Android ou
  WKWebView. [Relato do criador](https://www.reddit.com/r/Guitar/comments/1ugeobv/i_built_a_tool_to_help_practice_with_youtube/).
- Na discussão do **Music Slowdowner**, um utilizador pede pequenos incrementos
  automáticos, como 80%, 82%, 84%; o autor considera a sugestão. O produto inclui
  outra estratégia de entrada de áudio, que não devemos importar como solução
  do Transpono. O sinal útil aqui é o pedido de configuração simples, não uma
  autorização para copiar o mecanismo de captura.
  [Publicação do criador e feedback](https://www.reddit.com/r/Guitar/comments/1n2b3po/free_tool_for_slowing_down_music_to_help_with/).
- Um desenvolvedor de aplicação híbrida relata diferenças de reprodução entre
  browser e WebView no mesmo aparelho. A discussão é de 2021, portanto não
  diagnostica o Transpono atual. Serve como aviso para não transformar um teste
  Chrome, desktop ou Android em garantia para todos os runtimes.
  [Relato de desenvolvimento WebView](https://www.reddit.com/r/webdev/comments/p85gok/video_playback_support_in_browser_vs_native_app/).

## O que as fontes primárias permitem afirmar

### Comando enviado não é estado aplicado

A API oficial do YouTube trata a taxa pedida como sugestão: ela pode não mudar
ou ser ajustada a um valor suportado. A referência orienta observar a mudança
efetiva. Também documenta bloqueio de autoplay e comportamento de seek
dependente do estado anterior. Não existe nela uma operação de transposição
independente de tom. Esses contratos são da **IFrame API**, não uma promessa
sobre a página móvel ou o acesso ao seu DOM.
[Referência oficial da IFrame API](https://developers.google.com/youtube/iframe_api_reference).

Aplicação ao projeto: a implementação atual usa a página principal numa
WebView, não essa API. Mesmo assim, só deve publicar taxa/estado confirmados
pelo seu adaptador. Migrar automaticamente para iframe não seria uma troca
equivalente: exigiria reavaliar pitch, taxas disponíveis, pesquisa e capabilities.

### Seek, buffering e relógio de UI são sinais diferentes

O HTML Standard distingue `seeking`, `seeked`, `waiting`, `playing`, `ended` e
`readyState`. `timeupdate` é limitado e varia com a carga; um seek pode produzir
mudanças de posição sem reprodução do trecho. O estado final do seek não prova
que uma passagem A→B ocorreu antes dele.
[HTML Standard — media](https://html.spec.whatwg.org/multipage/media.html#seeking).

Aplicação ao projeto: contar somente o retorno B→A iniciado pelo adaptador e
confirmado para a mesma fonte, epoch e intervalo, depois de uma passagem armada
em A. Seek externo, troca de vídeo/elemento, anúncio, callbacks antigos ou
preparação cancelada não podem completar uma repetição. O polling de 200 ms
existente pode disparar a fronteira; não é evidência de precisão acústica nem
um metrónomo.

### Reprodução normal não garante áudio processável

O padrão Web Audio exige silêncio de `MediaElementAudioSourceNode` quando o
recurso é classificado como CORS-cross-origin. Portanto, ouvir um elemento
normalmente não comprova que os seus samples estarão disponíveis ao grafo DSP.
[Web Audio — segurança de fontes cross-origin](https://www.w3.org/TR/webaudio-1.1/#MediaElementAudioSourceNode-security).

Aplicação ao projeto: manter as recusas atuais a fontes incompatíveis e a
confirmação de sinal. Não remover CORS, CSP ou DRM para transformar uma falha
num resultado aparente. A evidência digital de entrada/saída também não mede
a qualidade ou latência no altifalante.

### Ponte nativa deve continuar restrita

A orientação Android identifica riscos de pontes JavaScript em WebViews e
recomenda limitar conteúdo/destinos confiáveis, validação de origem e HTTPS.
[Android — riscos de pontes WebView](https://developer.android.com/privacy-and-security/risks/insecure-webview-native-bridges).

Aplicação ao projeto: não alargar a navegação ou os comandos expostos por causa
de um vídeo que não carregue. Telemetria de QA deve conter apenas estado
necessário, sem cookies, tokens, URLs de streams ou dados autenticados. Confirmar
o host de topo não torna automaticamente todo frame interno confiável.

### Viabilidade técnica não fecha o gate de distribuição

As políticas para clientes das APIs YouTube restringem cópias/offline,
interferência em anúncios, modificações do player e componentes audiovisuais,
e reprodução em player não visível. A implementação atual não usa a IFrame API
nem a Data API; isso **não demonstra uma isenção** dos termos aplicáveis à sua
distribuição. A revisão permanece aberta no ADR-013.
[Políticas oficiais, III.E e III.I](https://developers.google.com/youtube/terms/developer-policies).

Não tratar este documento como parecer jurídico ou autorização do YouTube.
Um teste físico bem-sucedido prova apenas aquele percurso técnico; o gate de
produto/distribuição exige revisão própria. Não substituir esse gate por
camuflagem de cliente, extração de streams ou contorno de restrições.

## Critérios incrementais de aceitação

| Cenário | Evidência requerida | O que não permite concluir |
| --- | --- | --- |
| Pesquisa e seleção | Resultado real com nome/miniatura, escolha e vídeo na mesma WebView. | Todos os vídeos, países ou contas funcionam. |
| Plano curto real | 60→65→70%, duas voltas por etapa, seis voltas confirmadas, taxa final e pausa. | Precisão acústica, gapless ou uso prolongado. |
| Troca de etapa | Pausa, taxa confirmada, seek para A concluído, Play válido; sem incremento enquanto pendente. | Um ACK de comando equivale a áudio audível. |
| Seek manual | Seek para perto de B, seek durante retorno e seek fora do intervalo não creditam voltas; controle manual prevalece. | Uma queda de posição sozinha é repetição. |
| Pausa/encerramento | Durante preparação e retorno, invalidar operação pendente; ausência de Play tardio. | Pausa da UI equivale à ausência acústica de áudio. |
| Buffering/rede | Espera não avança contadores; timeout explica falha e não fabrica etapas. Retoma não contorna pausa explícita. | Desligar a rede no fixture reproduz todo comportamento de produção. |
| Anúncio | Áudio original e player/anúncio preservados; suspender prática sem contagem nem seek de loop. | Um anúncio simulado aprova todos os formatos reais. |
| B perto do fim | Testar B igual à duração e B ligeiramente anterior; `ended` antes do polling não deve ser contado como loop. | Apenas `B < duration` garante retorno a A. |
| Navegação | Player, prática e fullscreen conservam a mesma sessão; outra fonte invalida o plano. | Android aprova WKWebView/iPhone. |
| Recuperação | Snapshot consistente, metadata-only para YouTube, retomada por toque e volta parcial reiniciada em A. | Restauro local prova restauro online. |

Em particular, `B == duration` já desativa a contagem automática web na revisão
analisada. O caso `B < duration` com uma margem menor que o polling ainda merece
prova própria; não aumentar tolerâncias nem creditar a volta por aproximação
para fazer o teste passar. Se a fonte terminar antes do retorno, mostrar a
interrupção e conservar somente as voltas confirmadas.

Não provocar anúncios ou introduzir bloqueadores para tornar o resultado
determinístico. Se nenhum anúncio real ocorrer no teste, marcar o cenário como
**não observado**, conservando os testes simulados como evidência distinta.

## Prioridade de produto neste turno

- **Manter:** pesquisa interna, vídeo visível, sessão única, pitch/speed/loop,
  plano configurável, controles manuais e recuperação pausada.
- **Acrescentar se a prova revelar necessidade:** mensagens de preparação,
  espera, retomada por toque e capability indisponível; regressões para o
  defeito efetivamente observado.
- **Adiar:** IA musical, avaliação do desempenho, gravação, stems, nuvem,
  background YouTube, curvas arbitrárias e mudança de engine. Não são requisitos
  para fechar o percurso de prática atual.
- **Eliminar deste fluxo:** contagem por relógio, sucesso presumido, autoplay
  após cancelamento/recovery e promessa de compatibilidade universal. Não
  remover funcionalidades centrais apenas porque exigem validação adicional.

## Execução segura e rastreabilidade

Testes físicos devem usar apenas o pacote `.qa`, com APK previamente construído
e `applicationId` verificado. Manter `--keep-app-running`; não desinstalar,
limpar dados nem substituir o armazenamento do pacote normal. A atualização
normal usa `adb install -r`, depois das verificações do responsável pela build.

Contexto interno consultado: `CURRENT_ARCHITECTURE.md` §§14–18,
`YOUTUBE_INTEGRATION_DECISION.md`, `PRACTICE_PROGRESSION_RESEARCH.md`,
`PRACTICE_PROGRESSION_QA.md` e o adaptador
`apps/mobile/assets/web/transpono_media.js`. A presente pesquisa não executou
SDK, testes físicos, instalação nem alteração de código de produção.
