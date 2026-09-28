# Prompt de refinamento visual — Transpono

Redesenha as quatro colunas do player Flutter Transpono a partir das quatro
referências finais, de maior resolução (Cifra, Treino, Áudio, Setlist). As
referências anteriores servem apenas de contexto; as finais têm prioridade
para proporções, ordem e acabamento. Mantém os fluxos,
estados e funções existentes: não substituas o WebView do YouTube, o motor de
áudio, a pesquisa/importação de cifras nem a persistência da setlist. O
resultado deve ser código Flutter nativo e responsivo, não imagens ampliadas.

## Direção visual

- Monocromático premium: fundo preto quase puro, cartões grafite, bordas
  cinza discretas, relevo/luz especular muito subtil, texto branco e secundário
  cinza. O brilho deve ser desenhado com componentes nativos e adaptar-se ao
  ecrã, nunca ser uma fotografia achatada. Sem botões ciano nas
  colunas; o YouTube conserva o estilo próprio.
- A mesma faixa de abas Cifra, Treino, Setlist e Áudio em todas as colunas,
  com a aba ativa branca, cantos arredondados, ícones discretos onde couberem
  sem truncar os nomes, e o controle compacto de duas
  setas à direita. Não criar sidebar, abas duplicadas no rodapé nem uma
  segunda interface de player.
- Hierarquia apertada mas legível: cabeçalhos de cartões pequenos em caixa
  alta, valores principais claros, grupos separados por 8–12 dp. Alvos de
  toque continuam acessíveis (mínimo aproximado de 44 dp nas ações principais)
  mesmo que os ícones pareçam pequenos. Suportar 320 dp e texto ampliado.
- Transições suaves ao expandir secções e rolar Cifra. Evitar sobreposições,
  cortes laterais e espaços vazios artificiais.

## Cifra

- No modo que cobre o vídeo, fixar no topo uma faixa discreta com tempo,
  recuo/avanço de 10 segundos, play/pause e slider de posição. A faixa ocupa
  no máximo 1/8 da altura; não duplicá-la no modo normal com YouTube visível.
- Depois das abas: botão «Trocar cifra», cartão compacto de modulação do
  vídeo, cartão separado de rolagem automática e cartão da cifra escolhida.
- No cartão da cifra, título, origem discreta, repor/pesquisar/esconder,
  ajuste de tom da cifra separado do tom do vídeo e texto em área escura
  arredondada. A cifra pode ser longa; quebrar/ajustar linhas sem ocultar
  acordes. Os comandos sobem com a rolagem normal e a moldura continua
  arredondada quando alcança o topo.

## Treino

- Cartões para modulação, velocidade 0,25×–2× e trecho A–B. Preservar
  marcação, repetição e limpeza existentes.
- «Trechos guardados», «Metrónomo inteligente» e «Progressão de velocidade»
  são secções recolhíveis compactas. Ao abrir, o conteúdo aparece integrado
  no respetivo cartão, sem painel solto ou controle duplicado. Mostrar BPM,
  batidas por compasso e ações reais do metrónomo; preservar o plano de
  progressão e seus estados de indisponibilidade.

## Áudio

- Afinador cromático no topo: medidor, nota detetada/nota-alvo, cordas de
  referência e botão de microfone. Não mostrar uma leitura inventada quando
  o microfone está desligado.
- Equalizador de três bandas em um cartão, valores em dB e botão repor no
  cabeçalho. Efeitos abaixo: delay com intensidade real, isolador de voz com
  estado honesto de indisponibilidade, reposição de tom/velocidade/loop e
  abertura de ficheiro local. Não prometer separação de instrumentos no
  YouTube.

## Setlist

- Cartão de cabeçalho «Minha setlist» com adicionar música, anterior e
  próxima, seguido de uma explicação curta. Cada faixa mostra miniatura e
  apenas o título, até 55 caracteres/duas linhas, mais um menu discreto de
  opções. Não mostrar metadados, tom ou velocidade nos itens.
- Preservar a reabertura com ajustes guardados sem reprodução automática e
  as opções de ordenar/remover. Não desenhar um botão de repetição se não
  houver função correspondente.

## Comportamento transversal

- Em retrato, abrir/fechar e expandir as colunas conserva a sessão. Em
  horizontal, um vídeo escolhido ocupa o ecrã e «Abrir ajustes» é o único
  comando que revela as colunas; rolar o YouTube não as abre.
- Não reduzir o vídeo ao abrir ajustes em retrato. Manter a interface de
  arranque e o ícone independentes deste redesenho.
- Testar Cifra longa, lista vazia e preenchida, áudio indisponível, 320 dp,
  390 dp, horizontal e texto ampliado. Corrigir overflow e regressões antes
  de instalar no Android.
