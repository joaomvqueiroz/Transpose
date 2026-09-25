# Audio spike — execução em 2026-09-24

Plano de referência: `codex_project_master/SPIKE_FLUTTER_CPP_RUBBERBAND.md`.
Este relatório é progresso, não um GO arquitetural.

## S-000 — preparação

- Flutter, Android NDK 28.2.13676358 e CMake 3.22.1 disponíveis no Windows.
- Samsung SM-A165F físico ligado; ABI `arm64-v8a`.
- Host macOS/Xcode e iPhone físico indisponíveis: gate de dois aparelhos **não
  cumprido**.
- Rubber Band foi escolhida depois como alvo técnico em ADR-011, mas ainda não
  foi obtida/incluída nem há licença comercial de distribuição. O spike interno
  pode avaliá-la; qualquer distribuição proprietária fica bloqueada até licença.
- Existe WAV QA local de 12 s; os ativos de precisão e stress do plano completo
  ainda não foram produzidos.

## S-001 — ponte FFI Android

`packages/audio_core` contém uma biblioteca C++ com C ABI (`ac_abi_version`,
`ac_create`, `ac_ping`, `ac_destroy`) e wrapper Dart FFI. O build Android da
aplicação usa CMake/NDK para gerar `libaudio_core.so`; nenhum binário gerado é
guardado no repositório. Um teste de integração no Samsung executou:

```text
Flutter/Dart → FFI → C ABI → C++
ac_abi_version() = 1
ac_create() != null
ac_ping(handle, 41) = 42
ac_destroy(handle)
```

Resultado: APK debug compilada e teste físico passou. Isto valida apenas o
primeiro gate FFI em Android. Não há saída de áudio, pitch, speed, loop,
callback real-time, medição de latência nem build iOS. Um ping não comprova
nenhuma meta P95.
O bloco acima é o resultado histórico S-001; a ABI atual é versão **3** após
as extensões de saída e WAV do S-002.

## S-002 — saída Android parcial

O build Android usa Oboe 1.10.0 para abrir um stream de saída PCM Float stereo
em modo de baixa latência. O callback C++ gera um tom de teste de 440 Hz com
amplitude baixa; não executa I/O, alocação, locks, logs nem chamadas Dart.
`ac_start_tone`/`ac_stop_tone` controlam o stream; frames, sample rate e XRun
são consultados fora do callback. O teste está isolado do player de media da
aplicação e não expõe botão de tom no produto.

No Samsung SM-A165F, o teste curto de start/stop passou. A primeira execução
de 30 segundos em APK debug reportou 48.000 Hz, 1.441.024 frames e **1 XRun**.
Foi então pedido um buffer de dois bursts, seguindo a [orientação do Oboe](https://github.com/google/oboe/wiki/TechNote_BufferTerminology);
uma segunda execução de 30 segundos reportou 48.000 Hz, 1.440.768 frames e
**0 XRuns**. A instrumentação seguinte confirmou, numa terceira execução de
30 segundos, burst de 256 frames, buffer efetivo de 512 frames, 1.440.768
frames gerados e **0 XRuns**. As execuções terminaram sem crash. Isto comprova avanço do
callback, não que o som foi medido acusticamente. O gate S-002 de 10 minutos
sem underrun audível permanece **aberto**. Nessa fase, a APK profile compilou
com o backend nativo, mas o teste de áudio no aparelho tinha sido executado
apenas em debug.
Após acrescentar amostragem de contadores a cada 30 segundos, o teste de
integração com `flutter drive --profile` passou 30 segundos e depois **600
segundos** no mesmo Samsung. Na execução longa, o stream reportou 48.000 Hz,
burst de 256 frames, buffer de 512 frames, **28.803.328 frames** e **0 XRuns**
em todas as 20 amostras e no resultado final; o runner terminou com todos os
testes aprovados. Isto valida estabilidade observável do tom em **profile**
neste aparelho, não ausência acústica de clicks nem latência de Play/Pause.
Até essa etapa, release em dispositivo ainda não tinha sido testado.
Como `flutter drive` não suporta release, foi criada uma entrada de diagnóstico
separada (`lib/audio_stress_main.dart`), compilada apenas com target explícito.
No mesmo Samsung, essa entrada passou primeiro 30 segundos e depois **600
segundos** em release. A execução longa reportou 48.000 Hz, burst de 256
frames, buffer de 512 frames, **28.800.512 frames** e **0 XRuns** nas 20
amostras e no resultado final (`S-002 release PASS`). O APK de diagnóstico
foi substituído pela entrada normal da aplicação após o teste.
O caminho de QA WAV PCM16 local foi acrescentado à biblioteca nativa, sem
passar buffers de áudio pelo FFI: o teste copia o ativo de 12 s para um
ficheiro temporário, envia apenas o caminho e C++ carrega/converte o PCM antes
de abrir Oboe. O callback lê amostras pré-carregadas e para no fim. No Samsung,
o teste debug confirmou **576.000 frames**, `finished=true` e **0 XRuns**.
Em cinco execuções profile do mesmo WAV, todas terminaram com 576.000 frames;
a primeira reportou **1 XRun** e as seguintes **0 XRuns**. O tom de 30 s
também teve execuções profile com **2**, **0** e **1 XRun**. A geração do tom
foi alterada para tabela de seno pré-calculada, evitando `sin()` por frame,
mas um XRun posterior mostra que isso não eliminou a variabilidade. O contador
intermitente impede de declarar o gate sem underrun cumprido. Ficheiros ausentes ou inválidos são
rejeitados, sem bloquear uma reprodução válida seguinte. Este decoder é
deliberadamente limitado a RIFF PCM16 mono/stereo, até 64 MiB, na sample rate
aceite pelo stream; não é ainda o decoder geral do produto.
Para localizar os XRuns, a ABI passou à versão **5**: mede chamadas, máximo
tempo de trabalho e callbacks acima do tempo de um buffer. No Samsung, com
burst de 256 frames a 48 kHz (orçamento aproximado **5.333 µs**), duas
execuções profile com buffer de **2 bursts / 512 frames** reportaram:

- WAV: XRuns **1** (primeiros ~500 ms) e **0**; máximos **211** e **295 µs**;
- tom 30 s: XRuns **0** e **1** (este nos primeiros ~5 s); máximos **408** e
  **318 µs**;
- **0 callbacks acima do orçamento** em todas as quatro reproduções.

Uma comparação com **3 bursts / 768 frames** deu, em duas execuções profile:
WAV **0** e **1 XRun** (este também nos primeiros ~500 ms), tom **0** e **0
XRuns**, máximos entre **275 e 490 µs**, sem callbacks acima do orçamento.
Assim, 3 bursts **não eliminou** o XRun observado e aumenta o buffer em 256
frames (~5,3 ms a 48 kHz); **2 bursts permanece o padrão**. A hipótese de
arranque/agendamento do stream ou preempção é plausível, mas não demonstrada:
o cronómetro mede apenas a execução dentro do callback, não a espera para ele
ser agendado. A [nota do Oboe](https://github.com/google/oboe/wiki/TechNote_WhyGlitches)
lista outras causas possíveis. A medição acústica continua indispensável.
Ainda não há métricas P95 de Play/Pause nem política de áudio focus/interruption.

## Decisão de sequência — 2026-09-24

**Prosseguir com S-003 como spike interno, sem fechar S-002 nem distribuir a
APK de DSP.** S-002 e S-003 investigam riscos diferentes: os XRuns curtos da
saída nativa continuam pendentes de investigação/acústica, enquanto o
processamento pitch/speed precisa de uma prova técnica própria. Esperar por um
gate acústico que depende de captação externa atrasaria essa prova sem resolver
o motivo dos XRuns. Nenhum resultado de S-003 poderá ser usado como GO de
produto enquanto S-002, latência, qualidade, sincronização e licença estiverem
abertos.

Manter **2 bursts** como base comparativa. O [Oboe](https://github.com/google/oboe/wiki/TechNote_BufferTerminology)
recomenda dois como ponto de partida e permite ajustar após glitches; a nossa
comparação curta mostrou XRun também com três. Um [relato técnico de outro
Samsung](https://github.com/google/oboe/issues/769) igualmente mostra que
aumentar o buffer pode não resolver todos os XRuns: é sinal de cautela, não
prova para este modelo. A causa específica do SM-A165F continua desconhecida.

Começar S-003 com Rubber Band R2/Faster em modo real-time, atrás de
`DspProcessor`, e comparar R3/Finer no hardware antes de fixar preset. A
[documentação do autor](https://www.breakfastquay.com/rubberband/code-doc/)
suporta ratios independentes de pitch/tempo e define as restrições de thread;
[relatos de developers do Mixxx](https://www.reddit.com/r/DJs/comments/dv1d2b/)
favorecem a qualidade Rubber Band, mas são opinião, não benchmark da app.
A [licença do autor](https://breakfastquay.com/rubberband/license.html) impede
distribuição proprietária sem licença comercial; nenhuma foi adquirida.

Próximas frentes: S-003 interno no Android com comparação R2/R3; em separado,
captação/escuta da saída física e investigação dos XRuns de arranque para
fechar S-002. iPhone/macOS e licenciamento de publicação continuam gates.

## S-003 — primeiro render DSP interno, parcial

Rubber Band v4.0.0 foi obtida do espelho oficial no commit
`1d95888bec3ae0a17c0c4af791810d5a63f6bc35` para avaliação local. A fonte
fica em `.third_party/` ignorada pelo Git. CMake só a compila quando
`TRANSPOSE_RUBBERBAND_SOURCE_DIR` é fornecida; a build normal mantém
`dspAvailable=false` (confirmado por teste no Samsung). O adapter
`RubberBandProcessor` implementa a fronteira C++ `DspProcessor` e usa modo
real-time, com R2/Faster como primeiro alvo e R3/Finer para comparação.

Um render **síncrono, fora do callback de áudio**, processou o WAV local de
12 s. Teste profile no Samsung SM-A165F:

| Caso | Duração renderizada | Frequência central estimada |
|---|---:|---:|
| R2, 0 semitons, 1× | 12,000 s | 439 Hz |
| R2, −2 semitons, 1× | 11,997 s | 392 Hz |
| R2, 0 semitons, 0,75× | 16,007 s | 442 Hz |
| R2, −2 semitons, 0,75× | 16,004 s | 393 Hz |
| R3, −2 semitons, 0,75× | 16,113 s | 392 Hz |

O WAV R2 combinado foi enviado à saída Oboe no mesmo teste e terminou com
768.215 frames e 0 XRuns nessa passagem. Isso confirma alteração digital de
Tom/Velocidade de modo aproximadamente independente **neste fixture**, não
qualidade audível nem processamento DSP no callback. R3 foi renderizado, mas
não houve comparação de CPU/latência/qualidade. Não há comandos dinâmicos,
P95, click test, iOS nem ligação ao player Flutter. **S-003 permanece parcial e
sem GO.** Nenhuma licença comercial foi adquirida; a APK de spike não deve
ser distribuída.

O passo seguinte ao render síncrono foi a fila nativa descrita abaixo. Em
paralelo, S-002 requer medição acústica e investigação dos XRuns de arranque.

### S-003 — reprodução por fila nativa, ainda experimental

A ABI 6 acrescenta um worker C++ que processa o WAV com Rubber Band e envia
PCM estéreo para uma fila SPSC pré-alocada de 48.000 frames. O callback Oboe
apenas consome frames ou escreve silêncio quando a fila esvazia; não invoca
Rubber Band, Dart, I/O, alocação ou mutex. Há pré-buffer mínimo de 4.096
frames antes de abrir a saída. A fonte WAV continua inteiramente pré-carregada
e a via existe só no build interno opt-in.

Teste profile no Samsung SM-A165F, mesmo fixture de 12 s, −2 semitons,
0,75×, 48 kHz, dois bursts, uma passagem por configuração:

| Configuração | Frames emitidos | Fila vazia | XRuns | Callback máximo | Acima do orçamento |
|---|---:|---:|---:|---:|---:|
| R2/Faster | 768.215 | 0 | 0 | 279 µs | 0/3.001 |
| R3/Finer | 773.402 | 0 | 0 | 448 µs | 0/3.022 |

Isto comprova apenas que a fila acompanhou **este** fixture e dispositivo
nessas passagens; não mede latência ponta a ponta, P95, carga de CPU do worker,
artefactos acústicos, consumo de energia ou estabilidade prolongada. Nem há
alteração dinâmica de parâmetros, loop, ficheiros musicais reais, iOS ou
integração no player do produto. **S-003 continua sem GO.** O próximo ensaio
deve medir latência/CPU e qualidade com música real, testar paragem antecipada
e condições de carga, mantendo S-002 acústico como gate independente.

## S-004 — alternativa sem Rubber Band: probe Media3 Android

Após a decisão do utilizador de continuar sem a licença Rubber Band,
ADR-014 substitui o alvo de produto de ADR-011/012. Um probe isolado por
MethodChannel usa Media3 1.9.2 no Android; não está ligado ao player principal
e não cria saída paralela para o mesmo recurso no produto. No Samsung SM-A165F,
o teste profile com o WAV QA de 12 s aceitou −2 semitons/0,75× e alterou
durante a reprodução para +3 semitons/1,25×. O fator de pitch reportado foi
0,890899 e depois 1,189207; a posição avançou 1.491 ms nos primeiros 2 s e
mais 2.125 ms nos 2 s seguintes. O teste passou.

O resultado confirma API, preparação, comando e posição reportada neste
dispositivo. **Não comprova o pitch/fidelidade da saída acústica**, latência
comando→som, loop preciso nem iPhone. Próximo passo: conectar uma API de
processamento ao mesmo player que controla a reprodução, sem duplicar output;
medir saída acústica e comparar música real. Manter a build normal sem Rubber
Band e o probe fora da UI de produto.

## S-005 — integração Android áudio local na UI, parcial

Ficheiros de áudio locais Android (`wav`, `mp3`, `m4a`, `aac`, `flac`, `ogg`,
`opus`) usam agora um único player Media3 nativo para carregar, tocar, pausar,
procurar e alterar Tom/Velocidade; a mesma `PlayerSession` Dart continua dona
do recurso. Vídeo e iPhone mantêm o adapter anterior sem esses controlos. A
UI mostra sliders de −12…+12 semitons e 0,5…2× apenas no caminho suportado.
Os valores exibidos após comando são os aceites pelo Media3, **não confirmação
acústica**. O probe S-004 continua separado do recurso da UI.

O teste de integração profile no Samsung carregou a amostra via botão da app,
alterou Tom para −2 e Velocidade para 0,75×, tocou, alterou Tom para +3
durante a reprodução e pausou pelo mesmo player.
Passaram também os testes Flutter existentes. Ainda faltam medição acústica,
P95, loops A/B, interrupções, ficheiros musicais reais, iPhone e validação do
comportamento durante arrasto rápido dos controlos. S-005 não é release GO.

## S-006 — loop A/B nativo inicial, parcial

`LoopRange` no domínio exige `0 <= A < B` na timeline original. Áudio local
Android usa `MediaItem.ClippingConfiguration` e `REPEAT_MODE_ONE` no **mesmo**
player Media3; não há timer Flutter a disparar seeks nas fronteiras. O adapter
devolve posição/duração da faixa original. A UI permite marcar A e B, ligar e
desligar o loop e editar marcadores mesmo enquanto está ativo. A UI rejeita
um intervalo inferior a 1 ms e só atualiza o marcador depois da confirmação
do player. Se a posição corrente ficar fora do novo intervalo, o Media3
recomeça em A. Seek fora do intervalo desliga a repetição, mantendo A/B.

No Samsung SM-A165F, teste profile com WAV de 12 s, A=2 s e B=4 s:
o Media3 contou **duas repetições** e reportou posição 2,094 s após a segunda.
Tom −2 e Velocidade 0,75× foram aceites no mesmo player; um Seek para 8 s
desligou o loop sem apagar o intervalo. Um segundo teste usou os botões da UI
para marcar A/B, ativar e desativar por Seek. Os testes passaram.

Ensaio adicional no mesmo Samsung: A=2,000 s/B=2,500 s (**500 ms**),
**100 transições** contadas pelo Media3 em profile. Durante a repetição, o
player aceitou Tom −2/Velocidade 1×, depois Tom +3/Velocidade 0,75× e depois
Tom −5/Velocidade 2×. Ao desligar o loop, o snapshot Media3 ainda reportou
Tom −5/Velocidade 2×; os marcadores permaneceram. O teste automatizado está
em `apps/mobile/integration_test/android_ab_loop_stress_test.dart`. Contar
transições e ler parâmetros do player não mede o áudio efetivamente emitido.

Um segundo ensaio profile no Samsung alternou loop ON/OFF **100 vezes**
durante playback. Cada alternância terminou com estado coerente, intervalo
A/B retido e Tom +2/Velocidade 0,75× ainda reportados pelo Media3; não houve
exceção no teste. Isto não demonstra ausência de áudio duplicado, lacunas ou
clicks: ativar/desativar continua a re-preparar o item. O `screenrecord` deste
aparelho não oferece captura de áudio e não há retorno físico do telefone
ligado a uma interface de gravação no ambiente atual. O gate acústico requer
captura de saída com interface/loopback, conforme
`docs/LOOP_ACOUSTIC_VALIDATION.md`.

Edição ativa A/B: teste de UI no Samsung moveu A e B com o loop ligado e
rejeitou B inválido sem alterar o intervalo anterior. Outro ensaio profile
executou **200 alterações de A e 200 de B** durante playback, com intervalos
de 30–70 ms, mantendo loop e parâmetros reportados consistentes e sem
exceção. Estas 400 reconfigurações levaram vários minutos; a operação atual
troca e prepara novamente o clip Media3 a cada alteração. Ainda faltam
medição de latência por edição, lacunas/clicks e confirmação de continuidade
audível. LOOP-006/007 continuam parciais.

Seek fora do loop: teste profile no Samsung executou **100 ciclos** de ativar
A/B, Seek para dentro (manteve repetição) e Seek para 8 s, fora de A/B
(desligou repetição). Marcadores e Tom −3/Velocidade 0,75× continuaram nos
snapshots Media3; a posição final foi reportada entre 8 e 9 s. O teste está em
`apps/mobile/integration_test/android_ab_seek_stress_test.dart`. É evidência
de estado/controle para LOOP-008, não de ausência de lacunas ou precisão
acústica do Seek.

Isto valida lógica inicial e o caminho de controlo, **não** as metas LOOP-001/002:
faltam 1000 voltas, erro P50/P95/P99 e drift medidos na saída física,
clicks, música real, loop longo, qualidade de edição A/B ao vivo, iPhone e
persistência.
Ativar/desativar recorta e prepara novamente o item Media3, operação que pode
introduzir uma lacuna ainda não medida. S-006 continua sem release GO.

## S-007 — política inicial de background Android, parcial

Enquanto o player ainda pertence à atividade Flutter e não existe
`MediaSessionService`, a app **pausa** ao receber `inactive`, `paused` ou
`detached` e não retoma automaticamente ao voltar. O mesmo cuidado cobre um
Play/Restart que estava pendente quando a app saiu do primeiro plano. Esta é
uma política segura provisória, não suporte a reprodução contínua em
background nem persistência após morte do processo.

Teste de integração profile no Samsung simulou o evento de ciclo de vida
`paused` durante 10 s com Tom −2, Velocidade 0,75× e A/B ativo. Ao simular
`resumed`, o estado estava pausado, sem autoplay; posição, controles e
marcadores ficaram dentro das verificações do teste. Ainda faltam eventos
reais de Home/bloqueio/chamada, 500 ciclos BG-001, memória/process death e
sincronização de audio focus com a state machine. S-007 é parcial.
