# Transpono — briefing para Google Stitch

## Objetivo

Redesenhar apenas a apresentação visual do aplicativo móvel Flutter
**Transpono** (Android e iPhone). O código Dart anexado é referência da
interface atual, não um pedido para reescrever a lógica de áudio, a integração
com YouTube ou o armazenamento. Gerar propostas visuais e código de interface
como conceito; a implementação final continuará em Flutter.

## Idioma e identidade

- Interface e textos em português.
- Marca: Transpono.
- Tema escuro, base azul-marinho (`#0B1826`), cartões azul-escuro
  (`#142435`/`#102132`), realce ciano (`#19D9F1`) e texto claro.
- Melhorar hierarquia, tipografia, espaçamento, contraste e acabamento sem
  tornar a tela mais carregada. Estilo musical moderno, limpo e legível.
- Alvos de toque confortáveis (aproximadamente 44–48 dp), incluindo iPhone.

## Telas e estados que quero ver

1. **Player, ajustes fechados:** vídeo em destaque com tamanho estável e um
   único botão centralizado “Abrir ajustes” abaixo. Os controlos próprios do
   YouTube continuam no vídeo.
2. **Player, ajustes abertos / Cifra:** vídeo mantém o mesmo tamanho. Abaixo,
   abas horizontais Cifra, Treino, Setlist e Áudio. Na Cifra, tom do vídeo,
   botão “Escolher cifra” e cifra em moldura arredondada. Ao rolar, os
   controlos saem naturalmente e a moldura da cifra fica logo abaixo do vídeo;
   só o texto da cifra continua a rolar dentro dela.
3. **Escolher cifra:** pesquisa com título do vídeo pré-preenchido e resultados
   nativos dentro da coluna Cifra. Cada resultado mostra apenas o nome, no
   máximo duas linhas, com letra compacta; pequeno espaço interno e separação
   clara entre resultados. Não repetir “Cifras.com.br” em cada item. A escolha
   abre/importa a cifra sem navegador visível.
4. **Treino:** tom, velocidade numa linha arrastável (0,25× a 2×) e marcação
   A–B. Trechos guardados, metrónomo e progressão de velocidade ficam
   recolhidos até serem tocados.
5. **Setlist:** itens com miniatura de vídeo e título de até duas linhas/55
   caracteres; apresentação compacta e fácil de percorrer.
6. **Áudio:** equalização com graves, médios, agudos e delay, e afinador de
   guitarra/violão acessível dentro desta coluna.

## Restrições importantes

- Não acrescentar sidebar esquerda, botão de fullscreen, botão “Tempos” ao
  lado de “Escolher cifra” nem restauro automático de vídeos fechados.
- Não duplicar play/pause/avançar/retroceder do YouTube no Transpono.
- Não reduzir o vídeo quando os ajustes abrem.
- Não criar um segundo painel de player; as abas pertencem ao mesmo player.
- Os botões continuam a dizer “Abrir ajustes” / “Fechar ajustes” em português.
- O título da música e as cifras podem ser longos; nenhum conteúdo importante
  deve ficar cortado lateralmente.
- O projeto visual não precisa de prometer funcionalidades que a fonte de
  áudio não permite; preservar estados de indisponibilidade claros.

## Código de referência no pacote

- `studio_visual_app.dart`: shell, tema e abas.
- `studio_player_home.dart`: disposição atual do player e das colunas.
- `main_player_panel.dart`: vídeo e controlos de tom/velocidade/loop.
- `player_chord_sheet.dart`: leitura e transposição visual da cifra.
- `chord_browser.dart`: pesquisa e cartões da lista de cifras.
- `player_collections.dart`: setlist e predefinições.
- `practice_progression_card.dart`: progressão de treino.
- `microphone_tuner.dart`: afinador em Áudio.
- `studio_native_pages.dart`: paleta e referências antigas; usar apenas a
  paleta, **não** recriar os painéis antigos que já não fazem parte do player.

## Pedido para colar no Stitch

> Redesign the visual UI of my existing Flutter mobile app “Transpono” using
> the attached Dart UI files and briefing as reference. Preserve its current
> product flows and Portuguese labels, but make the screens cleaner, more
> polished, and easier to use on both Android and iPhone. Produce coordinated
> mobile portrait screens for: player with adjustments closed, player/Cifra
> with adjustments open, native chord search results, expanded chord sheet,
> Treino, Setlist, and Áudio with tuner. Keep the YouTube video size unchanged
> when adjustments open. Do not add a sidebar, duplicate YouTube transport,
> fullscreen button, automatic session restoration, or a separate player.
> Make chord result rows compact: title only, at most two lines, no repeated
> source label. Treat the output as a visual design proposal; do not replace
> the existing Flutter functionality.
