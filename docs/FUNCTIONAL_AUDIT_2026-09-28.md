# Auditoria funcional — 2026-09-28

## Etapa 7 — ferramentas atuais concluída

Afinador, microfone, notas de piano, metrónomo, deteção de tonalidade e widgets
foram auditados sem acrescentar controlos ou funções. Corrigida uma corrida
entre snapshots do widget Android: pedidos são entregues em ordem e termina o
estado mais recente; uma falha temporária aguarda novo snapshot, sem criar
tentativas infinitas. A pré-escuta do piano não reabre depois de suspender a
app; operações de notas/Stop são serializadas. O início pendente do microfone
é invalidado quando a app sai de primeiro plano ou o afinador é fechado.

Provas: 15 testes Flutter dirigidos, incluindo suspensão com nota atrasada e
ordenação/falha de widget; 67 testes JavaScript/WASM, incluindo dois novos da
estimativa de tonalidade (maior/menor, silêncio e nota única); análise estática
sem problemas. O metrónomo atual produz cliques em posições calculadas por
amostra e o piano usa WAVs incluídos no APK, mas estes testes não medem latência
acústica, deriva de reprodução nem precisão do microfone num ambiente real.
Essas verificações ficam para E8. Não se instalou APK nesta etapa.

## Etapa 6 — cifras, importação e coleções concluída

O modo independente continua a guardar a tonalidade da cifra sem mudar o áudio.
Foi reparado o modo ligado que ainda pode existir em dados guardados: a cifra
mostra o desvio próprio mais o tom confirmado do player; os botões de tom
ajustam o áudio apenas quando este suporta transposição, aguardam a confirmação
antes de permitir outro pedido e não antecipam a transposição visual.
Registos e texto originais não são reescritos por uma mudança de tom.

No editor de acordes sincronizados, uma gravação já não repõe a tonalidade ou
a origem que outro painel tenha atualizado entretanto. Se o texto da cifra ou
os tempos mudarem durante a edição, a gravação recusa substituir os dados
mais recentes e mantém o rascunho aberto para o utilizador o copiar/rever.
Foram acrescentados quatro testes de regressão para o modo ligado e estes
conflitos. Os testes de importação existente, validação de páginas e proteção
de coleções/predefinições passaram sem outro defeito reproduzido.

Verificação: 330 testes Flutter completos aprovados, incluindo os 24 testes
dirigidos de cifra e painéis; `flutter analyze --no-pub` sem problemas. Não se
instalou APK nesta etapa, nem se modificou o pacote principal, a navegação,
os botões ou o layout. O texto de estado identifica corretamente o modo ligado
quando um registo antigo o usa. A interface atual só cria/importa cifras em
modo independente; recuperar uma opção visual para ativar a ligação exige
autorização posterior, dado o pedido de não alterar o visual agora. Extração
numa página real do Cifras.com.br e verificação desta mudança no hardware
ficam para E8; testes com sessão simulada não garantem o DOM/termos atuais
do site. O utilizador autorizou avançar sem nova pergunta entre etapas.

## Etapa 5 — reprodução, A/B e progressão concluída

Os 64 testes Flutter dirigidos passaram: controlo principal, plano de treino,
persistência, eventos de loop nativo e interrupções. No Samsung, a prova
isolada `tool/run_practice_probe.ps1` passou: áudio local em 60%, 65%, 70%,
duas voltas por etapa, seis confirmações totais e pausa final; procura parcial
não contou, pausa reteve contagem. A prova WebView com WAV gerado confirmou
eventos reais de procura/retorno, duas voltas completas, pausa, procura parcial
excluída e suspensão de contexto em anúncio simulado. APK QA SHA-256:
`5631B4A50D7DD76AA8B55DDE5A3742EF98AAFBFDF311B7D80AFA97D28FE835D0`.

A prova antiga de YouTube real falhou antes de abrir vídeo: procura a chave de
interface `visualPlayerSearch`, removida no layout posterior. Não é evidência
de defeito de transporte. A nova prova curta no player integrado atual passou
com vídeo real: `videoSelected`, avanço de 1 470 ms depois do Play, retorno A/B
confirmado, contagem parada durante Pause e procura manual para o meio do
trecho excluída da contagem. Comando:
`tool/run_youtube_practice_probe.ps1 -DeviceId R58YA16NDVM -Probe transport`.
Relatório bruto: `apps/mobile/build/integration_response_data.json`; log:
`apps/mobile/build/audit-2026-09-28/e5-youtube-transport-probe.log` (ambos
locais e substituíveis por provas futuras). APK `.qa` SHA-256:
`A66C09E25C57E43A176E8B99DF5A92E7B492CC01D7EBF8961A3CC188A3A7E46D`.

Não foi reproduzida falha de reprodução, procura ou progressão nesta etapa;
foram atualizados instrumentos de QA, sem alterar lógica ou visual do produto.
Persistem limites de uma prova curta num único aparelho e vídeo: outros vídeos,
anúncios reais, perdas de rede e uso prolongado ainda exigem E8. A prova
histórica de navegação de treino em YouTube continua desatualizada para o
layout atual; as provas nova e sintética cobrem transporte e progressão,
respetivamente. O pacote principal conserva
`lastUpdateTime=2026-09-27 23:44:05`; Dev conserva
`lastUpdateTime=2026-09-28 10:08:40` e foi reaberto. Dados do utilizador
não foram apagados. E6 foi autorizada no pedido seguinte.

## Etapa 4 — medição de tom/velocidade concluída

O utilizador autorizou avançar. A prova isolada usa WAV sintético de 440 Hz,
gerado localmente, sem descarregar músicas. A instrumentação, ativada só em
testes, mede agora também a saída final após mistura/filtros: medir apenas a
saída do processador não detetaria uma ligação posterior interrompida.
Casos executados: +12/1×, −5/0,75×, +3/1,25×, 0/1×, −12/1×,
0/0,5× e +7/1,5×, com EQ criado antes do processador; transição +3→+5.
Limiares: erro de frequência <15 cents, erro de velocidade <0,15×,
sinal final RMS >0,01 e uma única origem de áudio. Estes limiares são de
regressão, não garantias de qualidade acústica nem sincronização de banda.

Primeira execução: cinco casos passaram; 0/0,5× mediu 440,018 Hz e 0,4992×,
mas falhou na asserção de ganho do ramo processado desligado. Inspeção da
fixture no WebView mostrou saída do DSP nula, tom original na saída final e
`wetGain=1` ainda reportado no ramo desconectado. A prova foi corrigida para
verificar `dspConnected=false`, saída DSP nula, rota original ativa e frequência
final correta, em vez de exigir atualização do AudioParam desconectado.
Não se alterou o motor para satisfazer uma asserção de diagnóstico inadequada.
Novo teste de topologia verifica desligamento/religamento sem duplicar saída;
outro verifica pedidos rápidos de tom durante preparação, incluindo cancelamento
para zero e velocidade independente. Suíte JavaScript/WASM: 69 aprovados.

Reexecução completa aprovada no Samsung SM-A165F, WebView 153.0.8010.36,
grafo a 48 kHz, em 2026-09-28 10:27:56. Sete combinações, transição e efeitos
passaram; análise Flutter sem problemas. Não foi confirmado outro defeito do
motor nesta etapa e não se alterou o visual nem acrescentaram funções ao produto.

| Tom (st) | Velocidade pedida | Frequência final (Hz) | Erro (cents) | Velocidade medida |
| --- | --- | --- | --- | --- |
| +12 | 1× | 880,562 | +1,106 | 0,99602× |
| −5 | 0,75× | 330,373 | +3,912 | 0,74463× |
| +3 | 1,25× | 524,588 | +4,417 | 1,25164× |
| 0 | 1× | 440,018 | +0,072 | 0,99420× |
| −12 | 1× | 220,797 | +6,260 | 0,99435× |
| 0 | 0,5× | 440,018 | +0,072 | 0,49735× |
| +7 | 1,5× | 659,252 | −0,008 | 1,49307× |

Transição +3→+5 manteve rota processada e mediu erro de +2,412 cents após
estabilização. A prova de efeitos confirmou parâmetros aplicados (ganho +3 dB,
chorus 0,2, feedback 0,25, delay 0,15 e reverb 0,2), não qualidade subjetiva.
Erro máximo absoluto de velocidade observado: 0,00693×. Valores são desta
execução curta/sinal único; não garantem estes limites para qualquer música.

Relatório bruto gerado: `apps/mobile/build/integration_response_data.json`;
log: `apps/mobile/build/audit-2026-09-28/e4-pitch-probe-rerun.log` (artefactos
locais ignorados pelo Git, sujeitos a substituição em futuras provas).
APK QA SHA-256:
`DAFFECA5F88194D9E7BC52B67B0FB11BA1DD7F9AEFFADF7361233CBDA201F3D9`.
Pacote principal conserva `lastUpdateTime=2026-09-27 23:44:05`; Dev foi reaberto
no fim, sem nova instalação de produção. QA ficou instalado; dados não apagados.
E5 aguarda a confirmação do utilizador.

Reprodução segura: `apps/mobile/tool/run_pitch_probe.ps1 -DeviceId R58YA16NDVM`.
O script pré-compila, valida identidade `.qa` nos metadados e usa o binário
verificado com `--keep-app-running`; não desinstala nem limpa dados. Não executar
outro build Android em simultâneo. A prova usa fonte sintética compatível:
fontes diretas/cross-origin/protegidas continuam com teste de recusa segura,
não com promessa de transposição. Medição acústica e duração prolongada ficam
em E8; os números desta prova não medem latência de altifalante/Bluetooth.

N1–N4 no fim da fila atual registam os pedidos de metrónomo/reprodução em rede,
mapa de tempo/compasso da música completa, separação de instrumentos e fontes
autorizadas. O utilizador permite deixar bloqueios complexos documentados para
passagem posterior ao Astra; não foi iniciada delegação nem implementação
desses recursos. Continuar a pedir confirmação entre etapas.

## Etapa 3 — equalização confirmada e troca interna de vídeo

Autorizada pelo utilizador após E2. Implementação concluída:

- Reaplicar os oito ajustes existentes ao novo elemento de vídeo da mesma
  música. Durante anúncios, os ajustes ficam em bypass e retomam no conteúdo.
  A restauração não inicia Play e não cria processamento numa fonte incompatível.
- Publicar `audioEffects` no snapshot a partir dos parâmetros do grafo atual.
  Sem grafo aplicável, reportar valores neutros em vez de afirmar aplicação.
  O painel passa a observar esses valores; mantém só a prévia do arrasto atual.
- Invalidar comandos pendentes quando música, elemento, fonte ou anúncio mudam;
  pedidos mais recentes do mesmo ajuste e cancelamentos também invalidam os
  anteriores. Revisão no painel protege navegação de ida e volta à mesma música.
- Após falha de preparação, conservar áudio nativo e permitir nova tentativa
  explícita, sem tentar recriar o grafo indefinidamente a cada snapshot.
- Falha do processador de tom não invalida automaticamente os filtros de EQ
  que continuam na saída original. Valores pretendidos só são atualizados
  depois de o parâmetro aceitar a alteração.

Validação: 67 testes JavaScript/WASM aprovados, incluindo seis cenários
novos de substituição, anúncios, fonte incompatível, comandos antigos/cancelados
e falha/repetição; 13 testes Flutter dirigidos passaram, incluindo parser de
valores finitos/limitados e sincronização de sliders/arrasto/rejeição.
Análise Flutter sem problemas e suíte completa com 326 testes aprovados.
Build Dev atualizada e aberta no Samsung em 2026-09-28 10:08:40, preservando
`firstInstallTime=2026-09-28 09:46:40`. APK SHA-256:
`452FC6E005999FABCEEA2209A100A5BAEF894556639F265204507A1C9422540F`.
O pacote principal mantém a atualização de 2026-09-27 23:44:05. A qualidade
acústica no hardware permanece para E4/E8. E4 foi autorizada no pedido seguinte.

Os pedidos posteriores de título na pesquisa de cifras, padrão da barra,
espaçamento das colunas, cores fixas por nota (pedido inicial: G laranja,
posteriormente substituído por G amarelo), ponteiro do afinador
e Configurações com temas claro/glass e cores foram registados como U1–U6 no
roadmap. O utilizador pediu executá-los depois das correções funcionais; não
foram misturados com a reparação de áudio de E3. Sugestões novas dependem de
escolha do utilizador.

## Etapa 2 — reparação autorizada

O utilizador autorizou E2 após a entrega do diagnóstico. F01 foi corrigido:
o ganho do áudio processado liga-se aos filtros quando o grafo é criado,
independentemente de o processador de tom ser criado nesse momento ou depois.
O processador continua a ser ligado apenas quando necessário. Nenhum widget,
texto do produto, botão, layout ou função nova foi alterado.

A fixture Web Audio foi atualizada com os nós/parâmetros dos efeitos já
existentes (F03). A expectativa antiga de um único delay foi corrigida para
validar os dois nós distintos existentes: eco 280 ms e chorus 18 ms.

Regressão demonstrada antes da alteração do motor: os oito novos cenários
EQ/efeito antes de pitch falharam por não existir caminho até à saída. Depois
da correção, os 61 testes JavaScript/WASM passaram (52 anteriores + 9 novos).
As regressões abrangem graves, médios, agudos, ganho, chorus, feedback, delay e
reverb antes do tom; a sequência +3, 0, -4, +6, 0, +2 conserva uma fonte e um
processador, sem perder nem duplicar rotas. O cenário inverso também passa,
incluindo fallback para áudio original após erro do processador.

Comando: `node --test tool/tests/transpono_media_test.cjs
tool/tests/transpono_stretch_test.cjs test_web/key_detector.test.js`.
`git diff --check` sem erros. Os 325 testes Flutter e análise limpa da etapa 1
continuam a referência do código Dart, que não foi modificado nesta etapa.

Build Dev gerada, instalada e aberta no Samsung em 2026-09-28 09:46:40;
`com.example.transpose_mobile.dev`, arranque confirmado pelo Android e captura
`apps/mobile/build/audit-2026-09-28/e2-dev-installed.png`. APK SHA-256:
`1A8EE4170BA5B606F0A31D4A03B629B999FFD71359060F0FD7D5C8432EE5F343`.
O pacote principal conserva `lastUpdateTime=2026-09-27 23:44:05` e seus dados.
A Dev é uma instalação separada, com armazenamento próprio.

A primeira build falhou ao descarregar AGP 7.3.1 e Kotlin Gradle Plugin 1.7.10.
Os dois JARs foram obtidos nos mesmos endereços oficiais, conferidos com SHA-1
publicados e colocados no cache local do Gradle. A repetição concluiu sem mudar
versões nem configuração do projeto.

A medição acústica no aparelho não é substituída por testes de ligações/sinal
WASM. F02 permanece para E3 e não foi corrigido por arrasto. Aguardar autorização
do utilizador antes de E3.

## Contrato desta revisão

Pedido: melhorar as funcionalidades existentes, especialmente tom e equalização,
sem alterar visual, navegação, botões ou acrescentar funcionalidades. Trabalhar
por etapas e pedir ao utilizador autorização antes da etapa seguinte. Uma ideia
de funcionalidade nova deve ser apresentada separadamente, nunca implementada
por arrasto. A etapa 1 é diagnóstico, inventário e roadmap; não inclui reparação
do motor nem instalação de uma build.

O layout atual do commit `79ab95f` e do aparelho é a referência. As decisões
visuais antigas do roadmap não autorizam reintroduzir sidebar, recuperação,
fullscreen próprio ou outras opções removidas na sessão do outro PC.

## Base inspecionada

- Git: `main`, commit `79ab95f`, sincronizado com `origin/main` após fetch;
  inclui `c7b81fe` e `79ab95f`, posteriores ao commit desta máquina `cdcffef`.
- Samsung SM-A165F conectado. Pacote presente: `com.example.transpose_mobile`,
  versão `0.1.0+1`, atualização em 2026-09-27 23:44:05, segundo o Android.
- APK instalado copiado para a pasta de build para leitura, sem reinstalar ou
  apagar dados. SHA-256:
  `5FDF9263CF366EA0C76308488BF3473532259AF25BC85CB2FF1FFCE1E041145F`.
- `transpono_media.js`, `transpono_stretch.js` e `transpono_key_detector.js`
  do APK são iguais aos locais após normalizar CRLF/LF. Isto confirma os scripts
  de áudio, não a identidade byte a byte de todo o código Dart/Kotlin compilado.
- Capturas locais em `apps/mobile/build/audit-2026-09-28/initial.png` e
  `audio-panel.png`: interface atual, Cifra, Áudio, afinador e equalizador.
  Esta inspeção visual não comprova a qualidade acústica dos efeitos.
- Dependências locais estavam desatualizadas em relação ao lockfile:
  `record`/`audioplayers` faltavam na configuração deste PC. `flutter pub get
  --enforce-lockfile` sincronizou o ambiente sem atualizar versões do projeto.

## Achados confirmados

### F01 — Tom aplicado sem caminho de saída após usar equalização

Prioridade alta. `apps/mobile/assets/web/transpono_media.js:715` liga o caminho
original aos filtros. A ligação `wet → low` em 716 só existe se o processador
de tom foi criado junto com o grafo. EQ/ganho/efeitos usam `prepareGraph(...,
false)`. Ao mudar o tom depois, `attachStretch` em 787–795 conecta o processador
até `wet`, sem ligar `wet` aos filtros. A confirmação de sinal mede a saída
anterior a essa ligação e pode informar `active` apesar do caminho interrompido.

Reprodução determinística com a fixture existente e APIs Web Audio atualizadas
apenas em memória:

| Ordem | Estado informado | Ganhos original/processado | Processado chega à saída? |
| --- | --- | --- | --- |
| Tom +3 primeiro | active, +3 | 0 / 1 | Sim |
| Graves +6, depois tom +3 | active, +3 | 0 / 1 | Não |

Diagnóstico executável local:
`apps/mobile/build/audit-2026-09-28/audio-topology-audit.cjs`.
O teste verifica ligações do grafo; não é uma gravação acústica no telemóvel.

Correção prevista na etapa 2: completar a ligação única do caminho processado,
verificar ambas as ordens, repor tom 0, repetir alterações e testar que nenhum
caminho fica duplicado. Sem mudança no layout.

### F02 — Equalização perde efeito quando o elemento de vídeo é substituído

Prioridade alta. Em `transpono_media.js:518–550`, a troca do elemento mantendo
o mesmo ID retira o grafo antigo, mas não prepara o grafo de efeitos no novo.
O diagnóstico confirma: fonte antiga desconectada e nenhuma fonte criada para
o elemento novo. O snapshot em 592 não publica os ajustes de EQ/efeitos.
`studio_player_home.dart:143–163` só limpa valores quando `sourceKey` muda;
`_setAudioControl` guarda o valor após o comando. Assim, uma troca interna do
elemento pode deixar o painel a mostrar um ajuste que já não está no áudio.

Correção prevista na etapa 3: definir e testar a conservação/reaplicação dos
ajustes válidos e a sua confirmação no estado. Incluir troca de elemento,
anúncio, navegação, erro e comandos pendentes. Não ocultar falhas nem anunciar
como aplicado um valor apenas solicitado.

### F03 — Testes do grafo Web Audio não acompanham os efeitos atuais

A fixture de `tool/tests/transpono_media_test.cjs` não implementa as APIs de
oscilador/convolver/buffer e agendamento de parâmetros agora usadas pelo grafo.
Resultado inicial: 52 testes JavaScript, 40 aprovados e 12 falhados. As falhas
da fixture não provam 12 defeitos no Android; impedem validar adequadamente os
caminhos de áudio. Os testes WASM e do detetor incluídos neste comando passaram.

Na etapa 2, atualizar a fixture apenas para representar as APIs realmente usadas
e acrescentar regressões para F01. Não alterar expectativas para esconder bugs.

## Limites e verificações ainda necessárias

- Análise Flutter após sincronização: sem problemas.
- Suíte Flutter: 325 testes aprovados (`flutter test --no-pub --reporter expanded`).
  Os testes de widgets/controladores não anulam F01/F02 nem as 12 falhas da
  suíte JavaScript, que verifica outro componente.
- EQ e efeitos atuais só têm caminho Web Audio; ficheiros locais não têm a
  mesma implementação. Tratar isso como limite existente, não como autorização
  para criar suporte novo sem consultar o utilizador.
- Som audível, precisão em cents, independência tom/velocidade, distorção,
  latência, níveis extremos, pausas, anúncios e uso prolongado precisam de
  verificações próprias; um ACK ou um slider a mover não comprova áudio correto.
- Cifra/importação, prática, setlists, afinador, deteção de tom e widgets serão
  auditados nas respetivas etapas; não estão todos aprovados por esta inspeção.
- O aparelho contém o pacote principal, não o antigo Dev. Antes de instalar
  correções, verificar identidade e assinatura e preservar os dados. A cópia
  do APK não é um backup dos dados. Não desinstalar nem limpar dados como solução
  para conflitos de assinatura. A versão Dev isolada continua a opção de teste.

## YouTube, RAM e cifras — pesquisa solicitada

Guardar em RAM não concede licença e não elimina, por si, questões de direitos
autorais ou termos da plataforma. Há exceções legais para certas cópias
temporárias; na UE o artigo 5(1) da Diretiva 2001/29 exige condições cumulativas,
incluindo o propósito de transmissão por intermediário ou utilização lícita,
e ausência de significado económico independente. Não é uma autorização geral
para descarregar um vídeo e processá-lo fora do serviço.

Os termos gerais do YouTube restringem download, reprodução e modificação fora
das permissões expressas do serviço ou autorização escrita aplicável. Para
clientes que utilizem as APIs, as políticas proíbem cache/download de conteúdo
audiovisual sem aprovação escrita e restringem modificar/separar áudio e vídeo.
São camadas distintas: direitos sobre a obra e condições de acesso à plataforma.
Não declarar o processamento atual aprovado para distribuição por ser local,
temporário, educativo ou por não gravar um ficheiro.

Alternativas a avaliar, sem implementação nesta revisão: ficheiros originais
fornecidos pelo próprio titular com autorização para processamento; obras e
gravações com licenças adequadas; autorização/parceria com titulares e serviços;
YouTube através do player e das funções autorizadas. A licença de uma composição
não implica automaticamente licença sobre uma gravação ou arranjo específico.

Para cifras, acesso gratuito não concede automaticamente direito de importar,
armazenar e redistribuir texto/letra/arranjo. Os termos do Cifras.com.br não
transferem direitos de propriedade intelectual pelo uso do serviço. Não foi
identificada nesta auditoria uma licença que autorize a integração atual.
Usar conteúdo próprio/autorizado ou negociar autorização é uma opção concreta;
colocar apenas o crédito não substitui a permissão necessária. O endereço antigo
de aviso legal do Cifra Club devolveu uma página genérica, sem texto jurídico
útil; não inferir autorização desse resultado.

Fontes consultadas em 2026-09-28:

- [Termos do YouTube](https://www.youtube.com/static?template=terms), permissões
  e restrições e licença a outros utilizadores.
- [Políticas de APIs YouTube](https://developers.google.com/youtube/terms/developer-policies),
  III.E.1 e III.I.7.
- [Diretiva 2001/29, artigo 5](https://eur-lex.europa.eu/legal-content/EN/ALL/?uri=CELEX%3A32001L0029).
- [Termos Cifras.com.br](https://conta.cifras.com.br/termos), secção 9.

São bases para decisões do produto, não uma conclusão jurídica sobre todas as
obras, jurisdições ou licenças possíveis. Nenhum mecanismo de download/cópia foi
adicionado; qualquer alternativa que constitua funcionalidade nova exige decisão
do utilizador.

## Fecho da etapa E8 — Samsung SM-A165F

O APK Dev foi compilado, conferido como `com.example.transpose_mobile.dev`
com a mesma assinatura da instalação Dev existente e atualizado sem tocar no
pacote principal. O APK de integração foi conferido como
`com.example.transpose_mobile.qa` antes da instalação. A prática isolada no
aparelho passou seis repetições A–B a 60/65/70%, com pausa e busca parcial,
além do cenário Web simulado. O novo ensaio físico de áudio local confirmou
que ao sair do app a reprodução pausa, não recomeça sozinha e mantém +2
semitons e velocidade 0,8×. A falha anterior — o player comum continuava a
tocar em segundo plano, enquanto só a prática parava — foi corrigida.

Regressão completa: 334 testes Flutter, 67 testes JavaScript/WASM, análise
estática Flutter e verificação de espaços do diff aprovados. O Dev não recebeu
permissão de microfone sem intervenção do utilizador; por isso não se mediu o
afinador com áudio real. Também não se mediram latência acústica, Bluetooth,
uso prolongado ou mudanças no DOM do serviço externo de cifras. Uma leitura
de memória de cerca de 538 MB PSS logo após abrir WebView é só uma amostra,
não demonstra fuga nem estabilidade. O ensaio antigo de recuperação automática
está obsoleto: esse mecanismo já foi removido do produto, logo não se
reintroduziu uma funcionalidade apenas para fazer passar o ensaio.

## Etapas U1–U6 — interface pedida depois da auditoria

U1: a consulta de cifras deriva do título do vídeo, com cabeçalho e metadados
como fontes; o texto genérico «YouTube» produz consulta vazia, não uma pesquisa
errada. A barra segue o padrão da pesquisa interna. U2: Cifra, Treino,
Setlist, Áudio e a posterior Config. partilham a largura disponível sem
rolagem horizontal em 350 px. U3: as doze classes cromáticas têm cores
estáveis em acordes normais, entre colchetes e transpostos. A paleta inicial
com G laranja foi substituída pelo pedido posterior: C azul, D verde,
E vermelho, F marrom, G amarelo, A roxo e B rosa, com variantes para
acidentes e contraste específico nos temas Escuro e Claro.
U4: o pivô do afinador subiu junto com o raio, sem mudar a correspondência em
cents. U5: Config. oferece Escuro, Claro, Vidro e cores individuais; a escolha
persiste, e o modo claro usa uma paleta de maior contraste para notas. O Dev
foi atualizado com ID/assinatura conferidos e os três estilos foram vistos
no Samsung, sem atualizar o app principal. U6: ideias documentadas no roadmap,
sem implementar novas funções sem decisão do utilizador.

Após U1–U5: 338 testes Flutter, 68 JavaScript/WASM e análise estática
aprovados. A cifra externa real e microfone acústico continuam fora desta
medição. N1–N4 permanecem abertos; a passagem técnica opcional ao Astra está
em `docs/ASTRA_HANDOFF_BAND_SYNC_AND_STEMS.md`.
