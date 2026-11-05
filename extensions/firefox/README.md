# Transpono — extensão para Firefox / Reynard (experimental)

Muda o **tom**, a **velocidade**, o **EQ** (graves, médios, agudos), o **ganho** e os efeitos
(**chorus, feedback, delay, reverb**) do vídeo do YouTube que estás a ver.

- Usa a mesma ponte de áudio da app (`apps/mobile/assets/web/transpono_media.js` com o
  Signalsmith Stretch, MIT). O `build.py` copia esses ficheiros, por isso a app e a extensão
  ficam iguais.
- O áudio é processado localmente, dentro da página, enquanto o vídeo toca. Nada é
  descarregado, guardado em cache nem extraído. Não contorna login, anúncios nem proteções.
- Existe para o iPhone: lá o WebKit não deixa o Web Audio ler o áudio do YouTube (HLS), por
  isso o tom não funciona na app. No Reynard, que usa o Gecko do Firefox, o YouTube deve usar
  MSE, e aí o Web Audio funciona. **Isto ainda tem de ser confirmado no iPhone.**

## Construir

```
python -I extensions/firefox/build.py
```

Gera `extensions/firefox/dist/transpono-firefox-<versão>.xpi`. Verificação:
`npx web-ext lint --source-dir extensions/firefox/build` (0 erros).

## Teste no iPhone, por ordem

1. **AltStore ou SideStore** (iOS 17.4 ou mais recente). A instalação usa o teu Apple ID e
   tem de ser feita por ti. No Windows: AltServer + iTunes/iCloud (versões do site da Apple,
   não as da Microsoft Store).
2. **Reynard**: instala `C:\Users\joaom\Downloads\Reynard-0.20.0\Reynard.ipa` (0.20.0, SHA-256
   `6ebc5383…a1c1ea`, verificado) pelo AltStore/SideStore. Marca **«Keep App Extensions»**,
   senão o Reynard não funciona. Com uma conta Apple gratuita, a app expira ao fim de 7 dias e
   tem de ser renovada no AltStore.
3. **Teste de base com uma extensão pública**: no Reynard, abre
   `addons.mozilla.org/firefox/addon/tuneshift/`, instala a TuneShift, abre um vídeo e muda o tom.
   - Se o tom mudar, o Gecko no iPhone processa o áudio do YouTube e o caminho é viável.
   - Se não mudar, o mesmo vale para esta extensão: vê o ponto 5.
4. **Extensão do Transpono**: passa o `.xpi` para o iPhone (Ficheiros/iCloud) e instala-o no
   Reynard («instalar a partir de ficheiro», se existir). O Firefox normal só aceita extensões
   assinadas. Se o Reynard recusar o `.xpi`:
   - assina-o como «unlisted» no addons.mozilla.org (precisa da tua conta Mozilla e das tuas
     chaves de API: `npx web-ext sign --channel unlisted`); ou
   - publica-o lá e instala-o pela página.
   Depois abre um vídeo, toca no play e abre o Transpono no menu de extensões.
5. **Se falhar**: no popup, a linha de estado mostra a mensagem da ponte (por exemplo «Este
   vídeo não disponibiliza áudio para efeitos neste dispositivo» quando o YouTube serve HLS).
   Anota a mensagem e envia-ma.

## Notas

- Começa sempre com play tocado na página. O navegador só deixa o áudio arrancar depois de
  uma interação.
- Velocidade: 1x fica no centro, com snap subtil. O tom mantém-se ao mudar a velocidade.
- Não mexe nos controlos do YouTube nem desenha nada por cima do vídeo; tudo fica no popup.
- `strict_min_version` 128: os 2 avisos do lint sobre `data_collection_permissions` são
  inofensivos.
