# N1–N4 — execução iniciada em 2026-09-28

Autorização atual: executar a fila antes reservada ao Astra. A escolha posterior
do utilizador é separação **inteiramente no telemóvel**, sem servidor no PC.

## N1a — metrónomo de banda experimental

Implementado dentro da ferramenta de metrónomo: anfitrião cria código com
endereço local, porta e token aleatório de 128 bits; os restantes entram
explicitamente. Não usa internet nem um servidor externo. O código funciona
como convite na rede local de confiança; os datagramas não são cifrados.
Wi-Fi com isolamento de clientes pode impedir a ligação.

Relógios monotónicos, quatro timestamps, filtragem de ida/volta e expiração de
amostras. O som requer três amostras e incerteza estimada <=20 ms. Estados com
sequência antiga são descartados. O anfitrião agenda início 2,5 s no futuro;
adesão tardia espera uma fronteira de compasso. Pausa, perda de ligação,
saída da sessão e suspensão invalidam a reprodução. Fechar o painel de ajustes
mantém a sessão enquanto a página principal está aberta. Até 16 participantes.

AudioTrack PCM mono 48 kHz continuamente preparado com silêncio, timestamps de
apresentação e colocação dos cliques por índice de amostra. Não se agenda som
por Timer Dart. Alterações de rota/underrun exigem nova aquisição de timestamp;
uma autorização curta limita reprodução abandonada. Há correção manual de
latência por saída. A correção não substitui uma medição acústica.

Provas já executadas: relógio com jitter/deriva/expiração, grelha durante uma
hora, duas sessões UDP loopback reais com início, pausa e perda de anfitrião.
Quinze testes dirigidos (incluindo regressões existentes) passaram. Prova nativa
no Samsung SM-A165F: timestamps válidos, 12 cliques antes de expirar a autorização,
zero underruns, erro da grelha interna máximo 0,210 microssegundos nesta execução.
Depois da expiração, contador estável em 13. **Este número não mede a precisão
acústica nem o desvio entre telemóveis.**

QA de dois Samsung na LAN real (`192.168.1.67`/`.68`, APK `.qa` profile SHA-256
`E3E4AD8BA7C256EDDD902E943259EB5ADC0A20658AEB4E952950B3B7DA246792`):
o convite criado por `host()` sem IP forçado escolheu `.67`, o convidado entrou,
e ambos produziram cliques nativos. No ensaio de 5 minutos com 31 amostras a
cada 10 s, o anfitrião passou com 2→688 cliques e zero underruns; pausa,
retoma, perda de anfitrião e reentrada também passaram. O convidado passou
essas transições, mas **falhou o critério de continuidade**: o AudioTrack foi
recriado várias vezes, o contador de cliques reiniciou e houve um underrun.
Os estados amostrados e contadores não provam ausência de falhas entre amostras.
O utilizador relatou perceber os dois aparelhos como sincronizados; isso é
observação subjetiva, não uma medição de desvio acústico.

Uma repetição diagnóstica curta mostrou a incerteza do relógio ultrapassar
20 ms antes da reprodução com RTT assimétrico, mas a ligação ADB do convidado
desapareceu antes do resultado final. Foi ajustada a filtragem para exigir
três inliers precisos e pelo menos um com menos de 3 s, sem relaxar o limite
de 20 ms. Os nove testes Dart de banda passaram, incluindo outlier assimétrico,
perda de frescura e rejeição de apenas dois inliers; **esta correção não foi
revalidada em dois aparelhos**. A pedido do utilizador, não se repetiu o teste.

O probe acústico separado foi integrado apenas no pacote `.qa`. No SM-A165F,
compilação e smoke de permissão/início/cancelamento do microfone passaram (APK
SHA-256 `616561FA6C6E59EC781DEC9674B63B5E96108480578C8E4E732946C4365007FC`).
O PCM permaneceu em RAM no telefone; não houve gravação acústica completa nem
medição de offset entre os dois telefones.

QA adicional: pedido de ligação mais recente cancela um pedido anterior ainda
à espera da paragem do áudio; o teste também confirma que fechar o metrónomo
incorporado mantém a sessão e que suspender a app a encerra. Doze testes
dirigidos de banda e ritmo passaram após estes ajustes; `flutter analyze` dos
ficheiros tocados ficou limpo.

Prova: `integration_test/band_audio_probe_test.dart`, pacote `.qa` isolado.
N1b (YouTube coordenado) ainda não implementado: permanece após o gate de dois
aparelhos previsto no handoff. Não há promessa de áudio YouTube em sincronia.

Referência do agendamento:
[Android AudioTrack](https://developer.android.com/reference/android/media/AudioTrack#getTimestamp(android.media.AudioTimestamp)).

## N2 — análise local e audição com mapa revisto

Implementada primeira versão, inteiramente Dart/offline: WAV PCM16 mono/estéreo,
8–96 kHz, até 64 MB e 10 minutos. A gravação é lida por completo. Energia e
ataques em janelas de 10 ms; inferência em trechos de 16 s, 40–240 BPM,
acentuação candidata de 2/3/4 tempos. O indicador é regularidade do pulso,
**não probabilidade calibrada de compasso correto**. Silêncio/ambiguidade
podem deixar partes sem clique. Cauda com menos de quatro segundos não recebe
novo compasso inferido. Subdivisões, anacruse, rubato, síncope e limites de
mudanças dentro da janela ainda precisam de avaliação com gravações reais.

O utilizador revê BPM, primeira batida acentuada e compasso de cada trecho.
Só após confirmação o app produz uma cópia temporária com clique misturado na
mesma linha de amostras da gravação. O original não é alterado; não usa dois
players concorrentes para prometer alinhamento. No painel incorporado Android,
a cópia aprovada entra no transporte principal: seek, tom e velocidade afetam
gravação e clique juntos. Alterar tom também muda o timbre do clique. A
ferramenta isolada mantém audição local simples. A audição termina ao fim,
sem loop automático. Ficheiros selecionados não são enviados para fora.

A cópia gerada é limitada a 64 MB e pertence à app; é removida após libertar
o decoder. Se a carga falhar, a fonte anterior é reaberta pausada com posição
e ajustes restaurados quando possível. Um decoder que falhe ao libertar mantém
o ficheiro para nova tentativa de fecho. Pedidos recentes de fonte/YouTube
cancelam prévias antigas antes de iniciar som. A prévia temporária não entra na
recuperação automática nem pode ser guardada em predefinição/setlist.

Cinco testes: 3/4 tempos sintéticos, mudança 120→90 BPM, silêncio, WAV inválido,
prévia sem alterar os bytes originais. Não é validação com repertório real.
Foi preparada uma prova Android isolada em
`integration_test/rhythm_audio_probe_test.dart`, executável por
`tool/run_rhythm_probe.ps1`: gera o próprio WAV, verifica análise e bytes
originais, e confirma o avanço do player nativo. Passou no Samsung SM-A165F
com pacote `.qa` verificado: 120 BPM, 3 tempos, posição Media3 920 ms após
1,2 s de espera, sem erro. Não constitui medição acústica.
A prova Android adicional da ligação ao transporte principal passou no mesmo
Samsung e pacote `.qa`: seek para 3 s, tom +2 semitons e velocidade 0,75×
foram aceites. Depois de buffering observado aos 250 ms, Media3 voltou a
`ready=true`/`playing=true` perto de 500 ms, em 3,166 s. A prévia não entrou
no snapshot; pausa e remoção do ficheiro temporário após release passaram.
Os dois testes Android usam apenas WAV sintético e não medem som acústico.
Ainda faltam validação com música real, seguimento dinâmico do mapa no
metrónomo e distribuição do mapa na sessão da banda. N2 completo continua
aberto.

Na revisão final da ligação ao transporte, 68 testes dirigidos passaram,
incluindo falha de decoder, cancelamento após carga, falha de libertação,
último pedido a vencer, YouTube e recuperação. A suíte Flutter completa passou
com 363 testes; `flutter analyze` dos 11 ficheiros tocados ficou limpo.

## N3 — motor nativo e prova no telemóvel

O motor usa nativamente o upstream [demucs.cpp](https://github.com/sevagh/demucs.cpp),
fixado no commit MIT `f1206e9adeea103aef4a636b9e62297cf1f8e34e`, e Eigen
`dd8c71e62852b2fe429edb6682ac91fd1c578a26`. Os headers do Eigen são MPL2,
com avisos BSD, e são compilados com `EIGEN_MPL2_ONLY`; não foi copiado o app
demucs-android GPL. O CMake gera uma cópia completa dos ficheiros `cpp`/`hpp`
upstream e aplica apenas os overlays `layers.cpp` e `conv.hpp`; o upstream
permanece intocado. A implementação mantém os mesmos pesos e contexto: atenção
em blocos de 64 queries, e convoluções normal e transposta por GEMM em blocos
de 256 linhas.

O modelo htdemucs de seis saídas convertido vem do dataset
[demucs.cpp](https://huggingface.co/datasets/Retrobear/demucs.cpp), revisão
`8f58ac0491bbea657275bcd3e38af1ab3a27bfc9`, que declara MIT: ficheiro
`ggml-model-htdemucs-6s-f16.bin`, 54.855.129 bytes, SHA-256
`09704f4ceae204e56e77d5eefd6ac71d7275be81fd507e6913371d59abcee856`.
`tool/setup_stems.ps1` obtém as fontes fixadas e verifica o modelo.

No Samsung SM-A165F (ARM64), as comparações com o original deram erro máximo
absoluto de `7,45e-8` para atenção e `7,45e-9` para convoluções normal e
transposta. As medições com sinais sintéticos próprios — não música pessoal —
foram:

| Medição | Duração | Pico RSS |
| --- | ---: | ---: |
| Baseline, 2 s | 72,6172 s | 1.899.676 kB |
| Final, 2 s | 56,3125 s | 566.532 kB |
| Final, 12 s | 170,137 s | 738.472 kB |

No teste final de 12 s, as seis saídas foram finitas e os RMS foram preservados
na precisão do probe. O pico ficou estável no segundo e terceiro segmentos,
mas `ru_maxrss` não permite concluir que não haja leak.

O motor executa exclusivamente no telefone: não há servidor no PC nem extração
de YouTube. O guard recomendado exige pelo menos 1 GiB disponível **acima** de
`MemoryInfo.threshold` e `!lowMemory`. A integração experimental foi entregue
e a release Dev foi instalada; no APK de QA no Samsung, a prova fresh-tone
passou: um tom sintético de 1 s foi efetivamente inferido, foram produzidos
seis WAVs com os tamanhos esperados e amostras não zero, e o guard de 1 GiB
acima do threshold foi mantido. Antes do job, `available` era 1.311.178.752
bytes e `threshold` 134.170.624 bytes; o modelo de 55 MB teve o hash verificado.

A sequência anterior de WAV inválido seguida de silêncio e seis WAVs passava,
mas bloqueava o tom seguinte por RAM. A correção torna o modelo lazy até ao
primeiro chunk não silencioso, chama `purgeNative` depois do retorno do worker
e usa `M_PURGE` (API 28) ou `M_PURGE_ALL` (API 34) por `dlsym`; a compilação
ARM e os símbolos JNI passaram. A prova da sequência na **mesma sessão** após
esta correção permanece bloqueada pelo guard antes da inferência em Debug e
Profile; não está concluída. A interface de purge é da [fonte Android bionic](https://android.googlesource.com/platform/bionic/+/master/libc/include/malloc.h).

Qualidade em música real, execuções longas (10 min) e coexistência com WebView
também não foram validadas. A integração da app está entregue de modo
experimental; a sequência na mesma sessão e a prova de dois telefones ainda
não estão concluídas.

Os artefactos nativos são `packages/stems_core/native/{CMakeLists.txt,bounded_conv.hpp,attention_check.cpp,transconv_check.cpp,probe.cpp,THIRD_PARTY_NOTICES.md}`.

## N4 — origem dos ficheiros

A análise exige seleção explícita de ficheiro local e confirmação de autorização.
Não existe mecanismo novo de download/captura de YouTube. Guardar na RAM não
altera as permissões da fonte. A escolha atual do utilizador exclui envio de
gravações para PC/cloud. A licença do motor/modelo não concede direitos sobre
as músicas que o utilizador escolhe.
