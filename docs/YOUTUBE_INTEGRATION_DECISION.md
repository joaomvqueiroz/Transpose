# YouTube e processamento de áudio

Atualizado: 2026-09-25.

## Estado implementado

- A pesquisa abre `m.youtube.com` numa WebView dentro do Transpono. A página
  fornece resultados, nomes, miniaturas e escolha do vídeo, sem chave de API.
  Os links YouTube ficam internos; esquemas de abertura da app são convertidos
  em navegação HTTPS quando reconhecidos. Outros destinos são bloqueados.
- A tela do navegador contém controles de reprodução, velocidade, tom
  experimental e loop A/B. O processamento atua no elemento de vídeo existente,
  sem extrair URLs de streams, descarregar media ou iniciar outro player.
- O player local Android continua com Media3. Não recebe o áudio da WebView.
- Vídeo local ainda utiliza `video_player` e não dispõe da mesma mudança de
  tom. No iPhone, o processamento de tom/velocidade ainda não está integrado.

## Restrição do YouTube

As [políticas de desenvolvedor do YouTube](https://developers.google.com/youtube/terms/developer-policies)
proíbem que um cliente da API separe, isole ou modifique as componentes de
áudio/vídeo do conteúdo do YouTube. Também proíbem descarregar ou guardar
o vídeo sem aprovação prévia e alterar o player oficial. A
[IFrame Player API](https://developers.google.com/youtube/iframe_api_reference)
oferece controle de velocidade de reprodução (`setPlaybackRate`), sujeito às
taxas disponíveis para cada vídeo, mas não uma API de mudança de tom.

Isso descreve o contrato da **integração oficial por API**, não uma prova de
impossibilidade técnica de processamento num navegador com página principal.
A implementação atual não usa iframe nem YouTube Data API. A compatibilidade
técnica do navegador não equivale a aprovação comercial do YouTube: a revisão
dos termos aplicáveis e da distribuição permanece pendente.

## Caminho de produto

## Caminho de navegador em 2026-09-25

`WebView -> HTMLVideoElement -> MediaElementAudioSourceNode -> Signalsmith
Stretch Web -> saída Web Audio`. O pitch é independente da velocidade; o
elemento mantém `preservesPitch=true` e controla o avanço da timeline.

O DSP [Signalsmith Stretch Web](https://github.com/Signalsmith-Audio/signalsmith-stretch/blob/main/web/release/README.md)
1.3.2 é MIT, distribuído com o aviso/licença, e não depende de Rubber Band.
O modo de entrada ao vivo aceita semitons; velocidade/loop são controlados no
elemento de vídeo. Há uma só saída selecionada entre áudio original e processado.

O processador é preparado antes de associar o elemento ao grafo. Fontes externas,
HLS direto e media protegida são recusadas antes dessa associação: o
[padrão Web Audio](https://www.w3.org/TR/webaudio-1.1/#MediaElementAudioSourceNode-security)
exige silêncio em recursos CORS-cross-origin. Não se altera CSP nem DRM.
O valor de pitch só é confirmado depois de receber sinal digital no processador;
isso não mede a saída acústica ou a qualidade perceptual.

No Samsung, o YouTube bloqueou o módulo Blob do AudioWorklet pela sua CSP.
A implementação conserva essa política e usa, nesse caso, a mesma biblioteca
WASM por `ScriptProcessorNode`, com buffer de 2048 frames. É uma rota de
compatibilidade experimental, com maior latência e sensibilidade à carga da
thread principal. O bundle tem uma alteração documentada para expor a factory
WASM; o algoritmo/binário DSP não foi alterado. O modo AudioWorklet continua
preferido quando permitido pelo documento.

Pré-visualizações podem iniciar mudas. O botão central passa a “Ativar som” e
habilita o áudio apenas por ação explícita. Pedir tom antes disso mostra uma
mensagem, sem criar o grafo. Não se confunde mute com incompatibilidade DSP.

O navegador pausa ao sair do app e ao fechar. O estado de prática é reiniciado
ao selecionar outro vídeo. Durante anúncios identificados pelo player, o áudio
fica original, o loop fica suspenso e os controles de prática são desativados.
Mudanças futuras no DOM/na rota de media do YouTube podem quebrar esta integração.

iOS continua sem validação física. Os relatos primários
[WebKit 180696](https://bugs.webkit.org/show_bug.cgi?id=180696) e
[WebKit 256445](https://bugs.webkit.org/show_bug.cgi?id=256445) documentam
problemas de processamento de elementos HLS/MSE no Safari; o funcionamento
Android não deve ser apresentado como prova de suporte a iPhone.

## Verificação

- Testes Dart/Flutter: navegação interna, comandos observados, confirmação de
  pitch, pausa de lifecycle, controles em anúncios e tamanhos de tela.
- Testes Node: ligação dry/DSP, falhas, fontes incompatíveis, mudança de vídeo,
  limites de controles, A/B e reinjeção sem duplicar o grafo.
- 15 testes Dart/Flutter e 22 testes Node passaram; `flutter analyze` limpo.
- Probe sintético físico, Samsung SM-A165F / WebView Android, build profile:
  entrada 440 Hz; +12 st -> 880,56 Hz a 0,995×; -5 st -> 330,37 Hz a 0,748×;
  +3 st -> 524,57 Hz a 1,252×. Erro medido de 1,11 a 4,36 cents. Um grafo,
  ganho original 0/processado 1. O teste roda sob CSP que também bloqueia Blob,
  portanto exercita o WASM de compatibilidade. Não mede som no altifalante.
- Probe YouTube: `integration_test/youtube_browser_probe_test.dart`.
  Passou no mesmo Samsung: resultados reais com títulos/miniaturas, escolha
  do vídeo `aqz-KE-bpKQ` dentro da mesma WebView, ativação explícita do som,
  +2 semitons confirmado com sinal de entrada/saída não nulo a 48 kHz,
  ganho original 0/processado 1, velocidade 0,75× e pausa. O percurso não abre
  a aplicação YouTube. Os máximos espectrais de música não são uma medição
  válida de razão de pitch; a precisão foi medida separadamente no tom sintético.
- APK release (56,7 MB) compilado e instalado. Smoke físico com toques reais:
  abrir pesquisa pelo Player, pesquisar o mesmo filme, escolher a miniatura,
  aplicar +1 st e pausar. A UI mostrou “Tom aplicado” e permaneceu no Transpono.
  Capturas em `apps/mobile/build/transpono-youtube-results.png` e
  `apps/mobile/build/transpono-youtube-player.png`.

Permanecem pendentes: escuta crítica prolongada, carga pesada da página,
latência/underruns, anúncios em execução física, loop acústico preciso, outros
aparelhos/versões do YouTube e todo o percurso iPhone. Estes resultados não
garantem compatibilidade com todo vídeo, DRM ou transmissão ao vivo.
