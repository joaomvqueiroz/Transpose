# Painel principal funcional — 2026-09-25

## Escopo desta entrega

O painel principal deixou de ser uma imagem/maquete com hotspots. Os controlos
Flutter usam `PlayerPanelModel`, implementado por `MainPlayerController`.
O controlador seleciona uma fonte de cada vez: áudio/vídeo local ou a sessão
YouTube existente. O player antigo de diagnóstico continua no código, mas os
botões do painel principal não abrem uma segunda sessão.

| Controlo | Implementação |
| --- | --- |
| Pesquisa | YouTube dentro do app, resultados com título/miniatura e ação «Usar este vídeo no player» |
| Play/pausa | Estado confirmado da fonte; no YouTube mudo, permite ativar o som |
| Timeline / ±10 s | Seek limitado à duração; fora de A/B desliga repetição e preserva marcadores |
| Tom ± / repor | Semitons confirmados, −12…+12; não inventa tonalidade original |
| Velocidade | Slider 0,50…1,50× e presets 0,75/0,85/1,00× |
| A / B / repetição / limpar | Marcadores reais, intervalo mínimo de 250 ms; capability por fonte |
| Tela cheia / sair / cadeado | Mesma sessão e superfície; bloqueio de toques, desbloqueio por pressão longa |
| Dica / ferramentas | Fecha dica; expande/recolhe ferramentas de estudo |
| Metrônomo | Cliques WAV calculados por amostras, BPM/compasso ajustáveis, iniciar/parar |
| Afinador | Notas de referência para afinação **de ouvido**, seis cordas e Lá 440; não usa microfone |
| Acordes | Transpõe cifras introduzidas pelo utilizador, incluindo extensões e baixo invertido |
| Guardar / setlist | Coleções locais de fonte, tom, velocidade, posição e A/B; reaplicação sem autoplay |
| Áudio avançado | Abrir/fechar/concluir e repor processamento; stems explicitamente indisponíveis |

## Propriedade e estado

- `LocalPlayerController` serializa operações e liberta a fonte anterior.
- `WebViewYouTubeSession` mantém o documento e a cadeia de áudio do navegador.
- Uma `GlobalKey` move a superfície entre pesquisa, painel e fullscreen.
- No painel YouTube, o navegador fica visível acima dos ajustes roláveis
  (lado a lado em landscape). Deixar a WebView sair totalmente da área visível
  pausava o HTML video no Samsung; não se força playback escondido para contornar
  esse comportamento. A disposição mantém a mídia visível.
- `MainPlayerController.pause()` interrompe esperas de restauração e não fica
  bloqueado atrás de uma navegação de até 25 s. Retorno ao app não dá play.
- Presets usam `SharedPreferencesAsync` (DataStore no Android), com escritas
  serializadas, validação e erros explícitos. Não substituem o snapshot
  transacional/process-death definido no roadmap.
- Nenhum ficheiro remoto ou stream YouTube é extraído; guardam-se apenas
  identificadores/metadados e ajustes no dispositivo.
- Ficheiros guardados como referência têm de continuar acessíveis; cache do
  seletor/ficheiro movido pode exigir nova seleção.

## Limites que continuam abertos

- Pitch local é suportado no caminho de **áudio Android**; vídeo local e iOS
  não ganham pitch por esta ligação de interface.
- Pitch YouTube continua experimental. CSP, DRM e anúncios não são contornados.
- A/B YouTube e vídeo local são aproximados por seek periódico; não têm a
  garantia de precisão/gapless do alvo nativo. Mesmo o áudio nativo ainda exige
  gates acústicos de longa duração.
- Metrônomo por WAV não é sincronização beat-perfect com a música; a fronteira
  de loop do backend ainda precisa de medição de jitter/gap no dispositivo.
- Separação de stems, deteção de acordes/tom, afinador por microfone,
  treino progressivo, gravação, audio focus/BT e recuperação automática de
  processo não foram declarados concluídos.
- Atualização posterior nesta data: Prática/Palco/Acordes passaram a controles
  reais; detalhes em `FULLSCREEN_AND_STUDY_DELIVERY.md`. Prática é manual e
  cifras/tempos são inseridos pelo utilizador. Não equivalem a treino automático,
  inteligência musical ou biblioteca completa.
- Não houve build/validação em iPhone nesta entrega.

## Verificação reproduzível

Dentro de `apps/mobile`:

```text
flutter analyze
flutter test test
node --test tool/tests/transpono_media_test.cjs tool/tests/transpono_stretch_test.cjs
flutter drive --profile --keep-app-running -d R58YA16NDVM --driver=test_driver/main_panel_probe_test.dart --target=integration_test/main_panel_probe_test.dart
flutter drive --profile --keep-app-running -d R58YA16NDVM --driver=test_driver/main_youtube_probe_test.dart --target=integration_test/main_youtube_probe_test.dart
```

O probe local deixa um item `QA Player <timestamp>` na coleção de predefinições,
sem apagar dados existentes. Provas de comandos/estado não demonstram por si só
qualidade acústica, latência P95 nem robustez em todos os dispositivos.

## Resultado físico

Validação automatizada da entrega inicial deste painel: `flutter analyze` sem problemas, 48 testes Flutter e
24 testes Node/JavaScript aprovados. Executar testes Flutter e build Android
sequencialmente: ambos podem regenerar o registrador nativo de plugins.

A revisão posterior de fullscreen e estudo foi validada separadamente;
resultados atualizados em `FULLSCREEN_AND_STUDY_DELIVERY.md`.

Samsung SM-A165F, APK profile, 2026-09-25:

- Probe local aprovado: reprodução/pausa, pitch −2, três presets e slider de
  velocidade, seek ±10 s, A/B, desativação de loop por seek fora, fullscreen,
  bloqueio, armazenamento/releitura/reaplicação sem autoplay, metrônomo,
  notas de referência, cifras e abertura/fecho do avançado.
- Probe YouTube aprovado: busca com 18 miniaturas, seleção do vídeo da Blender
  Foundation `aqz-KE-bpKQ`, pitch +1 com sinal confirmado, velocidade 0,75×,
  marcadores A=12,156 s/B=22,156 s, loop e transporte.
- Browser → principal → fullscreen → principal: uma factory, um start,
  uma WebView construída, zero reloads; documento e elemento `<video>`
  preservados. Reprodução terminada em pausa.
- Evidência local gerada em `apps/mobile/build/main_panel_evidence.json` e
  `apps/mobile/build/main_youtube_evidence.json`.

Nota do harness: em profile, `tester.enterText` precisa do cliente de teclado
de teste registrado; o atalho de cliente −1 de debug é ignorado. O probe
registra/desregistra esse cliente, não altera o teclado do produto.
