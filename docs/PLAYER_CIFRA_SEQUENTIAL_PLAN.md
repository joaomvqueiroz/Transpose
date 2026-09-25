# Player + cifra — contrato e execução sequencial

## Transporte do YouTube e tom — 2026-09-25

Quando a fonte é YouTube, o Transpono não repete Play/Pausa nem os saltos de
10 segundos, que ficam a cargo do player nativo do YouTube. A fila circular
nos Ajustes passa a ser diminuir tom, valor de semitons numa bola ciano e
aumentar tom, nas antigas posições dos botões de transporte. Os ficheiros
locais conservam controles de reprodução próprios. A transposição da cifra
continua a seguir o tom de áudio somente após confirmação da alteração.

## Especificação prevalecente após revisão física — 2026-09-25

No arranque sem vídeo selecionado, abrir diretamente a pesquisa YouTube com
campo de busca focado, mantendo «Restaurar vídeo» no topo se houver sessão
pendente. Reduzir Ponto A/B em cerca de 1/3
na interface principal com tamanho de fonte normal; em acessibilidade, manter
largura/altura suficientes. Compactar a altura dos controles nos Ajustes sem
alterar a disposição de Play e Tom.

O Player principal usa diretamente a superfície fullscreen. Sem Cifra, o vídeo
YouTube ocupa toda a altura disponível, com ou sem Ajustes abertos; o botão
«Ajustes» é flutuante, contornado, com fundo azul-escuro semitransparente. A
mensagem legada não cria faixa preta sob o vídeo. Abrir ficheiro, Cifra e
YouTube pertencem à rolagem interna dos Ajustes, não a uma fila fixa. Na fila
de transporte ficam voltar 10 s, Play/Pausa e avançar 10 s; imediatamente
abaixo, diminuir tom, número de semitons e aumentar tom nas mesmas colunas.
Com Cifra ativa, a cifra segue abaixo do vídeo. Uma rolagem descendente fecha
os Ajustes e retira Play/Tom do ecrã, mesmo se o vídeo estiver fixado; o botão
permite reabrir os controlos. O pin nunca fixa cabeçalho/restauro/cifra.
O overlay dos controlos termina antes do botão flutuante «Ajustes» para que
este não tape a última fila. O YouTube permanece atrás do overlay, mas não
deve ficar descoberto na área inferior do botão quando os Ajustes estão abertos.
A faixa escura e opaca dos Ajustes, quando aberta, continua por trás do botão
até ao rodapé; não pode deixar o YouTube visível nessa zona ou através dos
controlos.
Fechada, a faixa inferior não existe.
A altura máxima do overlay no Player principal passa de 40% a 50% da altura da
superfície; o fullscreen independente mantém a altura anterior.

## Nova direção visual — 2026-09-25

Correção de composição após revisão física: «Ajustes» não pertence entre vídeo
e fontes. Ele substitui a barra inferior de Player/Prática/Acordes/Palco. Essas
quatro áreas ficam exclusivamente na sidebar aberta pelo botão superior
esquerdo. O Player principal deve reutilizar a linguagem/ações do fullscreen,
mantendo a cifra abaixo do vídeo e o pin exclusivo do vídeo. Com Cifra desligada,
o botão inferior abre/fecha os ajustes em faixa logo após o vídeo; com Cifra
ligada, abre/fecha os ajustes sobre o próprio vídeo. A seta do botão inverte.
Executar C1 sidebar/rodapé, C2 estado único do botão de ajustes e Cifra,
C3 verificação de navegação/sessão e no Samsung antes de declarar concluído.

O utilizador quer o aspeto do painel fullscreen como Player principal. Manter
uma única sessão/WebView e os outros separadores; substituir a seta superior
esquerda pela abertura da sidebar. A área de vídeo deve ter pin próprio, sem
prender cabeçalho ou restauro. A ação Cifra e o conteúdo da cifra ficam logo
abaixo do vídeo; em modo Cifra, tom, velocidade e A–B continuam acessíveis na
engrenagem sobre o vídeo. Sem Cifra, apresentar controlos compactos inspirados
no fullscreen, preservando os controlos de transporte sobre o vídeo ao toque.

Executar em ordem: B1 composição/nav fullscreen no Player; B2 controlos
compactos e fontes; B3 Cifra abaixo do vídeo e ajustes sobrepostos; B4 testes,
análise e verificação física Dev. Não alterar o ecrã fullscreen independente
nem o pacote original até os gates do Player principal passarem.

Clarificação posterior de B2: com Cifra desligada, a faixa de tom, velocidade
e A–B fica recolhida por padrão. Uma barra/seta de alto contraste imediatamente
abaixo do vídeo abre-a (seta para cima) e a mesma barra fecha-a (seta para
baixo). Quando aberta, a faixa surge antes dos botões de fonte, encostada ao
vídeo; o tom deve ser o controlo visualmente mais evidente. Com Cifra ligada,
essa faixa não ocupa o espaço sob o vídeo e os ajustes continuam na engrenagem
sobre o vídeo.

Conferência física B4: na WebView de 360 dp, a página m.youtube.com reportou
player de 384×216 CSS px e cabeçalho de 48 CSS px; o espaço extra anterior de
104 dp mostrava o título/metadados abaixo do vídeo antes da seta. Ajustar a
altura do quadro principal a 16:9 + 48 dp para a seta encostar ao player. Isto
é apenas recorte do viewport do app, sem alterar a página/estilos do YouTube;
precisa de nova captura física para confirmar o resultado.

## Adenda de interface — 2026-09-25

Correção visual solicitada nas duas capturas: após «Restaurar vídeo», o
YouTube deve apresentar o vídeo no tamanho normal do seu próprio player, como
na segunda captura, sem mostrar o título/metadados dentro do pequeno quadro.
O indício é a página interna do YouTube numa posição de rolagem que ativa o
mini-player. A5: focar uma vez o topo da página do vídeo selecionado quando o
elemento estiver pronto, também no restauro. Não alterar CSS/DOM do YouTube,
nem ampliar artificialmente o vídeo ou alterar a rolagem externa do Transpono.
Gate: testes de foco sem repetição e observação no Samsung com Transpono Dev.

Clarificação de fixação: quando o botão de pin está ativo, só a superfície do
vídeo é sticky. O cabeçalho «Transpono» e «Restaurar vídeo» pertencem à página
rolável e desaparecem ao descer; restauro bem-sucedido remove o botão. A6:
ajustar composição com um único scroll e testar as posições antes/depois do
pin e do restauro, sem criar uma segunda WebView.

Pedido mais recente: oferecer um botão no próprio vídeo que alterna entre
rolagem normal (padrão) e vídeo fixo enquanto o conteúdo abaixo rola. Esta
escolha substitui a proibição absoluta de vídeo fixo na cláusula 1 original;
continua a existir só uma sessão de vídeo, sem reprodução automática. O aviso
de vídeo recuperável apresenta apenas o botão «Restaurar vídeo», sem o texto
«Última sessão» nem botão de fechar. Retirar do espaço abaixo do vídeo o título
duplicado, a indicação «YouTube · Navegador integrado» e a barra de posição;
posição e ecrã cheio ficam acessíveis sobre o vídeo ao tocar nele. Pesquisa e
seleção de YouTube permanecem acessíveis pelo botão de fonte e pela lupa.

Executar sequencialmente: A1 botão de fixar/soltar e prova de rolagem e sessão
única; A2 simplificação do aviso de recuperação e prova de restauro seguro;
A3 remoção da faixa duplicada e controlo de posição no vídeo, com teste de
acesso e layout. Depois análise, suíte e build/instalação só em Transpono Dev.

A1 aprovado: `studio_player_layout_regression_test.dart` moveu o vídeo com o
scroll solto, manteve-o no mesmo retângulo com o botão ativo e confirmou uma
única montagem da WebView antes/depois da alternância.

A2 aprovado: um snapshot YouTube pendente apresenta apenas «Restaurar vídeo»;
o widget e a recuperação subjacente foram testados sem autoplay.

A3 aprovado: título, rótulo de navegador e seek já não ocupam a área de baixo;
ao tocar no vídeo, seek e ecrã cheio surgem no overlay. Os 22 testes dirigidos
de player, sessão, Prática e recuperação passaram; o gesto de seek suspende o
temporizador de dois segundos até largar a barra.

Pedido corrigido pelo utilizador em 2026-09-25. Substitui a interpretação da
primeira revisão (YouTube fixo, exemplo sempre visível e controlos sempre num modal).

## Prompt de implementação

Implementar dois modos no player Transpono, preservando a única sessão de vídeo
e o motor de áudio existente. Não executar mudanças simultâneas: concluir e testar
cada etapa antes de começar a seguinte, atualizando este registo e o roadmap.

1. O cabeçalho da app fica fixo, mas o box do vídeo pertence à rolagem do player.
   Não usar vídeo sticky/pinned. Não forçar Play se a WebView pausar por visibilidade.
2. Cifra começa DESATIVADA, sem exemplo nem texto permanente. Neste modo os
   controlos originais de Tom (+/-), Velocidade e Loop A–B aparecem abaixo do vídeo.
3. O botão Cifra, ao lado de Abrir ficheiro, abre pesquisa dentro do app, semelhante
   à pesquisa YouTube, com Cifra Club e alternativa de site de cifras. O utilizador
   escolhe uma página e toca Importar esta cifra. Extrair apenas texto público
   apresentado pela página, com origem/título, pré-visualização e confirmação.
   Sem contornar login, CAPTCHA, paywall ou restrições de acesso; explicar falhas
   e permitir escolher outra página. Não inventar uma cifra a partir do áudio.
4. Após escolher uma cifra, mostrar letra/acordes abaixo do vídeo e tornar Cifra
   ativo. Os cards antigos desaparecem dessa área e passam a um painel de ajustes
   DENTRO do box do vídeo, aberto pela engrenagem. Desativar Cifra volta aos cards
   originais, sem apagar a cifra importada nem reiniciar música/ajustes.
5. Play/Pausa e +/-10 s surgem sobre o vídeo após toque e desaparecem em 2 s.
   O painel de ajustes tem fecho explícito, para permitir editar sem desaparecer.
6. A cifra tem transposição própria +/- semitons e opção de acompanhar o tom
   confirmado do áudio. O texto original não é reescrito em cada mudança. Letras,
   acordes com baixo e alinhamento são preservados. É possível ver vídeo e cifra
   e ajustar ambos, com indicação honesta se a fonte não suportar pitch de áudio.
7. Persistir texto/origem por música, preservar marcações existentes e proteger
   importações atrasadas contra troca de fonte. Cancelar pesquisa não ativa nem
   substitui nada. Não alterar dados do app original; instalar apenas Transpono Dev.

## Etapas e gates

- [x] S0 — Registar este prompt, critérios e sequência no roadmap.
- [x] S1 — Remover pinning do YouTube no player. Testar deslocamento do vídeo,
  cabeçalho fixo e preservação da mesma WebView entre navegação/fullscreen.
- [x] S2 — Dois modos explícitos e controlos inline/overlay do vídeo. Testar estado
  inicial, ativar/desativar, preservação de ajustes e layout pequeno.
- [x] S3 — Pesquisar documentação/sites; implementar navegador de cifras,
  extração/previsão/confirmação, allowlist, cancelamento, erros e persistência.
- [x] S4 — Transposição independente/ligada ao áudio confirmado, alinhamento e
  gestão de troca de fonte. Testar acordes/baixos, letras, resets e ACK do áudio.
- [ ] S5 — Suíte completa, análise, build Dev, conferência física e relatório.

## Evidências / limitações

Preencher em cada gate; não marcar como verificado aquilo que só foi implementado.
Os fornecedores podem mudar HTML ou bloquear importação. O suporte inicial deve
ser listado explicitamente. Não prometer qualidade acústica, iPhone nem aprovação
de distribuição YouTube por causa de testes de interface.

S1: `studio_player_layout_regression_test.dart` + `youtube_focus_layout_test.dart`,
5/5 aprovados. O vídeo desloca-se 100 px no teste enquanto o cabeçalho não muda;
a mesma instância/estado WebView sobrevive a separadores/fullscreen/pesquisa.

S2: 23 testes de `main_player_panel`, `studio_visual_app` e `player_chord_sheet`
aprovados. Cifra desligada no início; cards inline regressam ao desligar; box de
ajustes tem exatamente os limites do vídeo, não desaparece durante edição e não
reinicia pitch/speed. Pesquisa web ainda pertence à etapa S3.

S3 — pesquisa de fornecedores: o utilizador pediu priorizar sites
gratuitos. Cifra Club declara acesso gratuito às funções básicas; Cifras.com.br
declara acesso ao acervo sem cadastro. Gratuidade não equivale a licença para
extração/redistribuição. Os termos do Cifra Club restringem extração e framing;
os do Cifras.com.br também restringem cópia e distribuição. A integração é um
protótipo privado de navegação/importação deliberada, não uma integração oficial
nem uma autorização comercial. Revisão/autorizações continuam gate de publicação.

Fontes primárias consultadas em 2026-09-25:
- https://www.cifraclub.com.br/aviso-legal.html
- https://conta.cifras.com.br/termos
- https://pub.dev/packages/webview_flutter

Não usar API privada, backend de scraping ou extração em lote. Pesquisa visível
por site (Google) ou navegação na página inicial; extração só do texto renderizado
da página escolhida, nunca de paywall/challenge. Falhas devem ser explícitas.

S3: 16 testes Flutter e 6 casos DOM sintéticos passaram. Cancelamento mantém
modo anterior; confirmação associa texto/origem à música; trocar fonte durante
seleção recusa a associação; alternância não apaga cifra; URLs maliciosas e
conteúdo inválido são recusados. Navegador pausa áudio antes de abrir, não faz
autoplay ao voltar e mantém o player original. Compatibilidade física de sites
reais ainda não foi declarada: será conferida em S5.

S4: 26 testes Flutter dirigidos passaram. Em modo ligado, +/- da cifra envia
intenção ao player e aguarda pitch confirmado; em modo independente só altera
acordes. Alternar ligação preserva tonalidade/calibração, Repor cifra não altera
áudio, fonte incompatível permite transposição independente. Estado por música
persiste; transposição não reescreve notas originais. Colunas, baixos, etiquetas
de secção e acordes explícitos ChordPro foram cobertos.

S5 — verificação intermédia: `flutter analyze` limpo, build debug Dev instalada
por atualização (sem desinstalar). No Samsung SM-A165F, Cifra começou desligada,
sem exemplo; tocar no botão abriu o navegador e a página inicial real do Cifra
Club. A seleção automatizada da página seguinte foi bloqueada pela ferramenta;
não foi tentado contornar o bloqueio. Importação real e Cifras.com.br no hardware
continuam pendentes de conferência manual. Não confundir esta limitação da
automação com um bloqueio comprovado do fornecedor no Android.

Suíte antes do ajuste final de espaço: 283/283 passaram na repetição completa.
Uma passagem anterior teve 282/283 e falha transitória num teste antigo de timeout
de 25 ms (`never-completing cancellation is bounded and preserves timeout`);
o ficheiro completo passou 27/27 e depois a suíte completa passou, sem alterar
esse teste ou o subsistema de comandos WebView.

O teste adicional de retrato 360×780 revelou que as linhas da cifra ficavam fora
da tela. Correção sequencial: quando Cifra está ativa, esconder cabeçalho de
faixa duplicado, compactar barra de transposição e mover seek para os ajustes no
box do vídeo. Sem reduzir o viewport da WebView nem fixar vídeo. O novo teste e
mais 26 testes dirigidos passaram; confirma vídeo e duas linhas da cifra visíveis
juntos, no tamanho testado e sem aviso de recuperação ocupando espaço.

S5 — revisão final do código: 284/284 testes Flutter passaram em
`apps/mobile/build/cifra-s5-final-tests.log`; `flutter analyze --no-pub` sem
problemas; os 6 testes DOM sintéticos voltaram a passar. Nenhuma medição acústica
nova nem importação de página real foi aprovada por esses testes.

Build final instalada em `com.example.transpose_mobile.dev` às 13:40:45 (hora
do telefone), com `adb install -r`, e aberta sem reprodução automática. SHA-256:
`E26CB4B5B65AB2B4E5451987D6A2C90FDAB9D7C9A4B1F65A3AAD9AFD0261E4DE`.
Smoke visual final: cards originais presentes, Cifra desligada, recuperação
oferecida sem autoplay. Nenhum E/flutter, overflow ou FATAL EXCEPTION nos 300
registos recentes consultados do processo Dev; não equivale a QA prolongada.
`lastUpdateTime` do pacote original continua 2026-09-25 03:18:54, inalterado.

S5 permanece aberto exclusivamente para a conferência end-to-end com página
real: escolher/importar/confirmar, reabrir por música e comparar áudio/cifra no
telemóvel. Não declarar todos os sites compatíveis nem distribuição aprovada.
