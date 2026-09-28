# Passagem opcional ao Astra — metrónomo de banda, análise e stems

Este documento regista a sequência e os critérios dos pedidos N1–N4. N1a já
tem um protótipo experimental; N2 tem análise WAV e prévia local. A evidência
atual está em `docs/BAND_AND_RHYTHM_IMPLEMENTATION.md`. Não é uma
autorização para descarregar áudio/vídeo do YouTube ou contornar restrições.
O Transpono principal e os dados do utilizador devem permanecer intactos.

## Estado verificável

- O utilizador autorizou a execução: Astra (médio) fica para análise/revisão,
  Sol (médio) para implementação complexa e Terra (médio) apenas para tarefas
  fáceis. O Dev e o pacote QA são isolados de `com.example.transpose_mobile`;
  a release Dev foi instalada e aberta no Samsung original SM-A165F como
  `com.example.transpose_mobile.dev`, preservando a produção. O APK é
  `apps/mobile/build/artifacts/transpono-dev-release-2026-09-28.apk` (67.075.326
  bytes, SHA-256 `A1DFFF896331FF23784DE36024B0591E657E632A2A2A0490A30BA9D25476BEB2`)
  e tem o mesmo signer do Dev prévio; 363 testes e `flutter analyze` completo
  ficaram limpos.
- Existe metrónomo local e controlo de vídeo YouTube no WebView. N1a acrescentou
  sessão UDP na rede local, relógio monotónico e cliques agendados em AudioTrack.
  Foi testado em loopback e na prova dual: o anfitrião passou, mas o convidado
  falhou continuidade. A correção de clock tem nove testes unitários sem rerun;
  houve smoke do microfone sem offset e registo da perceção do utilizador. Por
  pedido, não repetir a QA. N1b (sincronia do player YouTube) permanece aberto.
- N2 analisa WAV local e produz prévia com clique no mesmo ficheiro após revisão
  do mapa. A prévia aprovada já está integrada no `MainPlayerController`/Media3:
  a QA Android sintética passou no Samsung para seek de 3 s, tom +2 e velocidade
  0,75, com buffering de cerca de 500 ms. Foram aprovados 363 testes Flutter e
  `flutter analyze` completo ficou limpo. WAV é apenas base técnica: a
  prioridade é análise de metrónomo e instrumentos para YouTube. O mapa real e
  a sincronia do player YouTube continuam abertos.
- N3 executa exclusivamente no telefone, sem PC/cloud, com motor nativo de seis
  saídas, incluindo guitarra. A QA da app inferiu um fresh-tone sintético de 1 s
  e produziu seis WAVs; as medições otimizadas foram 0,54 GiB para 2 s e 0,70
  GiB para 12 s. O fluxo na mesma sessão ainda está pendente porque o guard de
  1 GiB acima do threshold bloqueou antes da inferência em Debug e Profile; o
  fresh-tone autónomo passou. Não baixar essa proteção.
- O metrónomo individual gera um WAV PCM de oito compassos em `study_tools.dart`,
  toca-o em ciclo com `VideoPlayerController.file` e reinicia-o quando BPM ou
  compasso muda. Isto é adequado para prática individual, mas não oferece
  instante de início agendado, posição de batida confirmada nem compensação de
  latência. A camada N1a usa AudioTrack com timestamps de apresentação, mas a
  promessa de sincronia audível continua dependente de medição acústica.
- A prova dual não aprovou a continuidade do convidado; N1 permanece aberto e
  não há promessa de sincronia audível.
- O YouTube não é uma fonte autorizada para download/processamento por
  inferência. As notas legais e fontes estão em
  `docs/FUNCTIONAL_AUDIT_2026-09-28.md`.

## Sequência técnica sugerida

1. **N1a: metrónomo em rede, sem YouTube.** Protótipo com adesão explícita
   por código/sessão; anfitrião decide BPM, compasso e início. Sincronizar
   relógios monotónicos por várias trocas de ida/volta, estimar incerteza,
   agendar as batidas no futuro, medir deriva e reconectar sem disparar duas
   batidas. Testar perda de pacotes, suspensão, mudança de rede e saída de um
   membro. O áudio de cada telefone precisa de calibração de latência; comando
   simultâneo não equivale a som simultâneo. Separar transporte de rede do
   motor de áudio. Relógio injetável e sessão loopback têm testes; falta medir
   o instante audível real de cada batida em dois aparelhos.
2. **N1b: vídeo coordenado.** Só após N1a, sincronizar seleção, Play/Pause e
   posição por comandos permitidos do player integrado. Medir diferença real
   entre aparelhos e informar quando buffering/anúncios tornam a sincronia
   impossível; nunca prometer precisão de banda do áudio YouTube. Não capturar,
   transferir nem armazenar o stream para o contornar.
3. **N2: mapa rítmico completo.** Começar com ficheiros fornecidos pelo titular
   e autorizados para análise. Avaliar BPM, pulsações, início de compasso,
   mudanças de métrica e confiança. Definir comportamento para anacruse,
   rubato, silêncios e trechos ambíguos. O metrónomo só segue um mapa aprovado
   pelo utilizador ou uma estimativa com confiança suficiente; nunca apresentar
   uma medição incerta como exata.
4. **N3: separação de stems.** Provar primeiro com gravação local autorizada;
   comparar modelos/licenças, memória, bateria, tempo de processamento e
   qualidade no SM-A165F. A separação de guitarra pode requerer modelo além
   do conjunto vocal/bateria/baixo/outros. Processamento remoto exige escolha
   explícita, termos de privacidade e custo antes de enviar um ficheiro.
5. **N4: direitos/fontes.** Documentar a origem e licença de cada gravação e
   composição; escolher apenas fontes com permissão para transformação e
   armazenamento. RAM temporária não concede licença. Não implementar
   descarregamento do YouTube como solução técnica para direitos autorais.

## Critérios de aceitação antes de anunciar uma função

- Testes automatizados do protocolo e do relógio, mais sessão real em dois
  aparelhos na mesma rede, com desvio e incerteza medidos.
- Controlo de Play/Pause sob anúncios, buffering e reconexão sem começar
  reprodução indevida; distinção visível entre sincronizar comandos e áudio.
- Para análise rítmica, conjunto de gravações licenciadas com compassos
  variáveis e erros medidos; possibilidade de correção manual.
- Para stems, relatório de qualidade, duração, RAM e bateria no Samsung e
  licença de modelo/dados; nenhuma obra de terceiros descarregada sem permissão.

## Prompt de implementação para o Astra

> No repositório `C:\Transpose`, inspeciona primeiro o roadmap e a auditoria
> de 2026-09-28 e o estado atual em `docs/BAND_AND_RHYTHM_IMPLEMENTATION.md`.
> Valida N1a acusticamente em pelo menos dois aparelhos, com saídas distintas;
> documenta o desvio, a deriva e a reconexão. Depois avalia
> N1b com comandos permitidos no player, deixando claro o limite de buffering.
> Mantém N2/N3 dependentes de ficheiros próprios/licenciados e N4 como porta de
> conformidade; não descarregues nem captures o YouTube. Faz cada etapa,
> mede-a, regista resultados e preserva os pacotes principal/Dev/QA e os dados.
