# Características rítmicas ambiente — protótipo QA (2026-09-28)

Estado: **base técnica experimental, apenas no pacote `com.example.transpose_mobile.qa`**.
Não foi compilada em APK nem executada em telemóvel após o pedido do utilizador
para não repetir testes. Não há análise de vídeo YouTube em produção, nem
alinhamento comprovado entre música e metrónomo.

## Limite de captação e privacidade

`PhoneRhythmFeatureCapture.kt` usa apenas o microfone local com permissão
`RECORD_AUDIO`, PCM16 mono a 48 kHz. Escolhe `UNPROCESSED` quando o Android o
declara suportado; senão tenta `VOICE_RECOGNITION`. O limite é 10 minutos por
pedido. A app não lê buffers da WebView, stream de rede, ficheiros do YouTube
nem áudio de outro processo. O array de PCM de leitura tem apenas 480 amostras
(10 ms), é apagado após cada leitura e nunca é escrito em disco ou enviado pelo
canal Flutter. `cancel` e suspensão da Activity param a gravação e descartam
as características. A exposição das características paginadas é somente local
ao processo QA; antes de distribuição, será necessária revisão de retenção e
consentimento próprio. A origem do som ambiente pode incluir conversas, ruído
ou outras fontes, e o microfone não identifica a proveniência YouTube.

`QaMicrophoneLease.kt` impede que esta captação e o probe acústico anterior
usem o microfone ao mesmo tempo no processo QA.

`RhythmFeatureExtractor.kt` retém no máximo 60.000 janelas (100 Hz × 10 min):
RMS normalizado, novidade energética positiva e indicador de ataque com
refratário de 80 ms. São indicadores, **não uma transcrição, um mapa rítmico
aprovado, nem uma probabilidade calibrada**. `readFeatures(offset, limit)`
devolve até 1.000 janelas por chamada; `status` devolve resumo, nunca PCM.
Testes Kotlin puros com sinal sintético passaram para 120→90 BPM, pausa,
silêncio, ruído e cauda parcial (1.150 janelas/16 ataques no cenário de
mudança). A fonte Android foi compilada isoladamente contra os jars de SDK e
Flutter; isto não substitui build APK ou teste de microfone real.

## Relógio e contrato QA

O canal `transpose/qa_phone_rhythm_features` expõe `clock` (microsegundos de
`System.nanoTime()`), `start({durationMs})`, `status`, `finish`, `cancel` e
`readFeatures({offset,limit})`. Um `AudioRecord.getTimestamp` válido mapeia
`frameStart` para `monotonicUs` da janela; quando falta timestamp coerente,
`monotonicUs` é nulo. O resultado inclui origem monotónica estimada, dispersão
dos timestamps, fonte, rota/alteração, efeitos, RMS médio/pico, clipping e
qualidade. Só `quality=availableForReview` indica rota integrada estável,
timestamps com dispersão até 5 ms, sem intervalo entre leituras superior a
250 ms, sem clipping superior a 1% nem efeitos AEC/AGC/NS ativos. Mesmo nesse
caso, a latência acústica e o processamento
restante do aparelho não estão calibrados.

O snapshot YouTube expõe tempo de navegador (`performance.now`) e uma amostra
do `Stopwatch` Dart; essas épocas **não são** `System.nanoTime`. Nenhuma janela
mic é associada a `positionMs` de vídeo nesta fase. Uma futura associação
precisa calibrar explicitamente os relógios, descartar amostras durante seek,
anúncio, mudança de velocidade/fonte e buffering, e medir latência de saída
e entrada. Não afirmar sincronia a partir da semelhança visual dos timestamps.

## Scheduler de cliques, ainda sem saída nativa

`youtube_beat_scheduler.dart` é um coordenador Dart puro que aceita um
`RhythmMap` já validado, amostras `YouTubeTimelineSample` e um relógio injetado
da **mesma instância/época `Stopwatch`** da amostra. Produz grades para uma
interface `YouTubeBeatOutput` fictícia; não está ligada ao AudioTrack, à WebView
nem à UI. Exige vídeo/identidade coincidentes, reprodução pronta sem anúncio
ou seek, velocidade 1, confiança do trecho ≥0,55, incerteza ≤20 ms e amostra
com até 1 s. Pausa, buffer, anúncios, seek, mudança de velocidade/fonte, lacuna
entre trechos e amostra vencida desligam a saída. Uma nova época precisa de
segunda observação antes de armar.

Cada agenda contém início e fase da grade, índice da próxima batida e lease
absoluto. O primeiro clique tem no mínimo 200 ms de antecedência, e só se
publica se o fim estimado do clique de 25 ms couber no lease; quando a próxima
batida está demasiado longe, espera-se por amostra fresca. Renovações mantêm
revisão e grade para a saída tratar como idempotentes. A saída real teria de
preparar o sintetizador antes dessa antecedência, rejeitar atrasos, impor o
lease de modo autónomo e arbitrar exclusão com a sessão de banda. Se 200 ms
forem insuficientes para a preparação no aparelho, a política deve ser
redesenhada e medida, não presumida. Testes fake offline passaram em 6 cenários,
incluindo 120→90 BPM, lacuna, pausa/seek/anúncio/buffer, amostra parada,
renovação sem duplicação e polling a 40/120 BPM. Não há prova de precisão
acústica nem de funcionamento durante um vídeo real.

`youtube_native_beat_output.dart` acrescenta uma ponte **QA não ligada à UI**
para `NativeBandAudio`: prepara uma vez por lease, passa BPM fracionário sem
arredondar (por exemplo 90,5), início da grade, compasso, revisão e validade,
e pára a saída ao terminar/errar. O motor Kotlin aceita agora BPM finito
`Double` entre 40 e 240, preservando o protocolo inteiro de `BandSession`.
A ponte recebe predicado de sessão de banda e árbitro de lease injetados;
**ainda não existe árbitro partilhado ligado à sessão de banda**, portanto
não pode ser usada em paralelo com ela. A preparação de AudioTrack em até
200 ms é uma hipótese de interface, não uma medição. Testes fake Dart da ponte,
scheduler e sessão de banda passaram (19 casos); análise estática direcionada
sem problemas. Esta alteração Kotlin não foi compilada em APK nem ouvida em
dispositivo depois do pedido de não repetir testes.

## Distribuição e políticas

A abordagem não faz download/cache nem separa o áudio digital do YouTube, mas
essa distinção técnica **não estabelece autorização de distribuição** ou de
criação de métricas derivadas de conteúdo ouvido. As [Políticas para
desenvolvedores da API do YouTube](https://developers.google.com/youtube/terms/developer-policies)
proíbem download/armazenamento de cópias audiovisuais sem aprovação e impõem
restrições a separar, isolar ou modificar áudio/vídeo; o [guia oficial de
conformidade](https://developers.google.com/youtube/terms/developer-policies-guide)
traz exemplos de funcionalidades vedadas. Antes de integrar com o player ou
publicar, rever os termos aplicáveis, a natureza das características derivadas,
consentimento/privacidade do microfone e experiência de anúncios/playback.
Este documento não conclui que uma integração futura esteja permitida.
