# iOS com Gecko: passagem para a sessão do portátil

Escrito a 2026-11-06 pela sessão do PC de casa, a pedido do João. Branch: `ios-gecko`.
Ler isto antes de mexer no iOS. Regras do João mantêm-se: sem commit nem push sem pedido
dele, não mexer em dados nem apps do telemóvel, instalar IPAs só com ordem direta dele,
escrever-lhe em português europeu.

## O problema

No iPhone, o WebKit (todos os navegadores do iOS usam-no) toca o YouTube por HLS nativo e
não entrega esse áudio ao Web Audio (WebKit bugs 180696 e 231656). Por isso a ponte de
tom/EQ/efeitos (`apps/mobile/assets/web/transpono_media.js`) recebe silêncio. A tentativa
com MSE (`f405855`) foi revertida. O caminho YouTubeKit (`ad3b0ff`, descarregar o áudio)
viola os Termos do YouTube e as regras do próprio João, e parte sempre que o YouTube muda.

## O que foi feito (commits `dfb3ceb`, `2b38dbc`, `aa70bf6` e o deste documento)

O YouTube da app passa a ser mostrado pelo **Gecko** (motor do Firefox), onde o YouTube usa
MSE e o Web Audio recebe o áudio, como no Android.

- **Motor:** o do Reynard 0.20.0 (Firefox 159, MPL-2.0; camada Swift GeckoView do Reynard,
  GPL-3.0; serve para uso pessoal, nunca para a App Store). Não se recompila o Gecko: o CI
  gera só os cabeçalhos (`mach build pre-export export`), tira o `XUL`, as dylibs e os
  recursos do `Reynard.ipa` oficial (SHA-256 fixado) e compila a camada GeckoView e a
  extensão Helper. Ver `.github/gecko/build-engine-kit.sh`. O kit fica em cache.
- **`packages/gecko_view`:** plugin Flutter que implementa a interface do `webview_flutter`
  (`PlatformWebViewController`, `PlatformNavigationDelegate`, `PlatformWebViewWidget`). A
  sessão do YouTube (`lib/youtube_browser.dart`) usa-o quando `GeckoEngine.isAvailable`;
  em todos os outros casos (Android, iOS sem Gecko) tudo fica como antes. Não liga ao
  Gecko em tempo de compilação: encontra a classe `TransponoGeckoBridge` em tempo de
  execução.
- **`apps/mobile/ios/gecko/`:** `TransponoGeckoBridge.swift` (o único código que liga ao
  GeckoView; compilado no CI como `TransponoGecko.framework`) e uma extensão interna MV2
  (`extension/relay.js`) que avalia os scripts da app na sandbox de content script — faz o
  papel do `evaluateJavaScript` do WebKit.
- **Arranque:** `ios/Runner/AppDelegate.swift` tem um `@main` que, se existir
  `TransponoGecko.framework`, arranca o Gecko primeiro (o `AppShellDelegate` do Gecko passa
  a ser o delegate da app) e o `SceneDelegate` mostra o Flutter com um motor próprio e
  regista os plugins. Sem o framework, arranca como uma app Flutter normal.
- **Sem JIT:** o Gecko do Reynard desliga o JIT, a não ser com o emparelhamento de depurador
  do Reynard (que não incluímos). Sem JIT não há WebAssembly, logo o Signalsmith não corre.
  `assets/web/transpono_stretch.js` tem agora uma terceira via de tom feita só com nós
  nativos de Web Audio (duas linhas de atraso com varrimento em dente de serra e janelas em
  seno). Medido num OfflineAudioContext: 440 Hz → 880/660/220 Hz a +12/+7/−12; quedas de
  nível até 20%. Qualidade inferior ao Signalsmith (ondulação em notas longas). O
  equalizador e os efeitos já eram nós nativos e não precisam de JIT. No Android nada muda.
- A ponte avisa logo cada processo de conteúdo do Gecko de que não há JIT (em vez de esperar
  até 5 s) e pede as páginas em pt-PT.
- **CI:** `.github/workflows/ios-gecko.yml` (corre em push para `ios-gecko` ou à mão).
  Gera `Transpono-iOS-gecko-unsigned` (IPA sem assinatura, ~114 MB).

## Verificação feita

- `flutter analyze` sem problemas; 407 testes da app, 5 do plugin `gecko_view` e 70 testes
  JavaScript (`apps/mobile/tool/tests/*.cjs`) a passar, incluindo um novo para a via nativa.
- Build iOS no GitHub Actions com sucesso; o `Runner.app` contém `GeckoView.framework`,
  `XUL`, dylibs do Gecko, `TransponoGecko.framework`, `PlugIns/Transpono Helper.appex` e a
  extensão em `GeckoView.framework/Frameworks/extensions/transpono/`.
- **Nada disto foi ainda executado num iPhone.**

## IPAs

Estão na Release `ios-gecko-test-1` do repositório (não cabem num commit, >100 MB):

```
gh release download ios-gecko-test-1 -R joaomvqueiroz/Transpose -D <pasta>
```

- `Transpono-Gecko.ipa` — o Transpono com Gecko (build do commit `aa70bf6` ou posterior,
  ver notas da Release).
- `Reynard.ipa` — Reynard 0.20.0 oficial (SHA-256
  `6ebc53836a232d0bb1b655c97dd7b44156e1ee6ca0889ef383069fc7b0a1c1ea`), para o teste de
  referência com a extensão TuneShift. Fonte: github.com/minh-ton/reynard-browser (GPL-3.0).

## Instalação (no portátil)

No PC de casa o AltServer (1.8.00, iCloud com sessão) falhou duas vezes com `−80046`.
Desde ~22/10/2026 a Apple recusa o token de desenvolvedor a pedidos que se identificam como
Android; no portátil o AltServer funcionou. Não insistir: tentativas repetidas podem
bloquear a conta temporariamente.

1. iPhone ligado por cabo ao portátil, desbloqueado.
2. Shift + clique no ◆ do AltServer → **Sideload .ipa…** → iPhone → `Transpono-Gecko.ipa`.
3. Manter as **App Extensions** (sem a `Transpono Helper.appex` o Gecko não arranca).
4. Conta gratuita: no máximo 3 apps ativas contando com o AltStore.

## O que testar e o que pode falhar

1. **A app abre?** É o ponto mais novo (Gecko a arrancar antes do Flutter). Se fechar logo,
   pedir ao João o relatório em Definições → Privacidade e segurança → Análise e melhorias →
   Dados de análise (entrada `Runner-…`). Suspeitos: o `SceneDelegate` em modo Gecko, o
   storyboard `Main` na configuração da cena, ou a Helper.
2. **O YouTube aparece e toca dentro da app?** O Reynard apresenta-se como Firefox para
   Android, por isso o YouTube deve servir MSE.
3. **TOM +:** anotar a mensagem por baixo do botão TOM. Se disser que o áudio não está
   disponível, a ponte não se ligou (ver relay/porta nativa); se o tom mudar com ondulação,
   está a usar a via nativa (esperado sem JIT).
4. **EQ e efeitos**, **loop A–B**, **velocidade**: devem funcionar como no Android.
5. **Cifras** continuam no WebKit (já funcionavam).

## Próximos passos possíveis

- Se a app fechar: corrigir o arranque (recolher o relatório de falha primeiro).
- Se o tom tiver qualidade fraca: investigar o JIT do Reynard (emparelhamento por
  `idevice`/DDI, ver `browser/Reynard/JIT/` no Reynard) para voltar ao Signalsmith.
- Retirar o caminho YouTubeKit (`packages/youtube_native_audio`) quando o Gecko estiver
  confirmado; na sessão Gecko já não é usado.
- Considerar `com.apple.developer.kernel.increased-memory-limit` (o Reynard usa-o) se o
  Gecko for terminado por memória.
