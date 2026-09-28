# Porta de conformidade — funcionalidades musicais sobre YouTube

Estado em 2026-09-28: **não aprovada para distribuição nem integração no player
principal**. Esta é uma avaliação técnica de risco, não parecer jurídico nem
autorização do YouTube. O app usa páginas WebView; a aplicabilidade precisa de
cada regra das API Services a esse fluxo deve ser confirmada, enquanto os
Termos gerais do YouTube também se aplicam. A prova de metrónomo e de
arbitragem permanece no pacote QA, com linha temporal e áudio sintéticos.

## Fontes oficiais consultadas

- [YouTube API Services Developer Policies](https://developers.google.com/youtube/terms/developer-policies):
  para clientes abrangidos, proíbem descarregar/importar/cachear cópias audiovisuais sem aprovação prévia,
  separar/isolar/modificar componentes de áudio ou vídeo, alterar o player e
  oferecer reprodução em segundo plano.
- [Guia oficial de conformidade](https://developers.google.com/youtube/terms/developer-policies-guide):
  dá exemplos explícitos contra separação ou modificação de áudio, contra
  reprodução em background e recomenda pedir uma avaliação de conformidade
  quando a permissibilidade não estiver clara.
- [Required Minimum Functionality](https://developers.google.com/youtube/terms/required-minimum-functionality):
  veda sobreposições que escondam qualquer parte do player incorporado,
  incluindo os seus controlos.
- [IFrame Player API Reference](https://developers.google.com/youtube/iframe_api_reference):
  documenta os comandos suportados de play/pause/seek e velocidade; estes
  comandos não constituem licença para processar o áudio do conteúdo.
- [YouTube Terms of Service](https://www.youtube.com/t/terms): uso pessoal
  permite ver/ouvir, mas não é uma exceção geral às restrições de modificação.

## Pontos concretos no Transpono

1. `apps/mobile/assets/web/transpono_media.js` contém `captureStream`,
   `AudioContext`, `createMediaElementSource` e processamento de tom/EQ/efeitos
   do elemento de vídeo. Isto apresenta risco direto face à proibição de
   separar ou modificar componentes de áudio do conteúdo YouTube. Não assumir
   que uso privado ou processamento só em RAM elimina este risco.
2. O modo de ajustes que encobre o vídeo em
   `apps/mobile/lib/studio_player_home.dart` pode contrariar a regra de não
   obscurecer o player incorporado. O comportamento visual completo deve ser
   auditado antes de distribuição.
3. Um mapa de batidas inferido por microfone ambiente enquanto o YouTube toca
   não lê o stream digital, mas ainda depende do conteúdo reproduzido; a
   permissibilidade dessa derivação e a mistura de clique local com o vídeo
   **não estão esclarecidas** pelas fontes consultadas. Exigem interpretação
   específica do YouTube, além de consentimento e política de privacidade para
   o microfone. Não rotular este caminho como automaticamente permitido.
4. Os widgets abrem o app, sem reprodução invisível, segundo o código atual;
   preservar essa restrição e não introduzir vídeo em background/PiP oculto.

## Decisão de implementação

- Não ligar `YouTubeBeatScheduler`/`YouTubeNativeBeatOutput` ao WebView, não
  recolher áudio de vídeos reais para o mapa e não apresentar BPM inferido do
  YouTube como funcionalidade do utilizador nesta fase.
- Conservar os testes sintéticos QA, sem download, WebView, vídeo ou microfone.
  A prova acústica QA separada usou apenas cliques gerados pela própria app,
  com autorização temporária do microfone; não valida sincronia com vídeos.
- Não alterar silenciosamente a experiência YouTube existente como parte desta
  tarefa; a análise dos pontos 1–2 precisa de decisão de produto e avaliação
  de conformidade separadas.

## Pedido de esclarecimento recomendado

Antes de oferecer análise rítmica em vídeos YouTube, apresentar ao processo de
[auditoria de conformidade](https://support.google.com/youtube/contact/yt_api_form)
um fluxo e demonstração exatos e perguntar expressamente sobre: (a) clique
metronómico independente sobre vídeo incorporado; (b) mapa de batidas derivado
de microfone ambiente, sem PCM persistido; (c) transformação de tom/EQ atual;
(d) modo que cobre o player; (e) consentimento, privacidade e identificação do
cliente. O formulário requer informações e atestações do titular da conta;
nenhuma submissão foi feita automaticamente.
