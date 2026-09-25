# Prática progressiva — evidências e limites de QA

Data: 2026-09-25. Decisão: ADR-017. Pesquisa e critérios de aceitação:
`PRACTICE_PROGRESSION_RESEARCH.md`.

**Estado:** implementação funcional com 306 testes automatizados aprovados,
análise estática limpa e dois cenários físicos aprovados no mesmo percurso
Android. A build release foi compilada e instalada no app normal por atualização
sem desinstalação; recuperação e novo painel foram conferidos. Não equivale a aprovação
completa da fase Practice nem a conclusão do roadmap.

## Execução física verificada

- Dispositivo: Samsung SM-A165F, Android API 36, serial QA `R58YA16NDVM`.
- Build: profile de integração, pacote **`com.example.transpose_mobile.qa`**.
- Entradas: `apps/mobile/tool/run_practice_probe.ps1`,
  `apps/mobile/integration_test/practice_progression_probe_test.dart` e
  `apps/mobile/test_driver/practice_progression_probe_test.dart`.
- Log: `apps/mobile/build/practice-probe-run.log`.
- Resultado estruturado: `apps/mobile/build/practice_progression_evidence.json`.
- Resultado: `passed: true`, tanto no ramo `native` como no ramo `webview`.
  O log da segunda execução termina com todos os testes aprovados em cerca de
  **19 s**. Esse tempo é duração do percurso, não latência/P95 do player.

O wrapper compila o target QA, verifica `applicationId`, variante e APK antes
de instalar e fornece o binário validado ao driver com `--keep-app-running`.
Não usa uninstall, limpeza de dados ou force-stop. O fixture usa uma pasta
temporária própria dentro da sandbox `.qa`, não as coleções ou o banco de
recuperação do utilizador. A prova desta entrega não repetiu o incidente de
desinstalação da entrega anterior.

### Áudio local — Media3 real

O percurso usou áudio sintético local, com A=2,000 s e B=2,800 s. O plano
executou **60% → 65% → 70%, duas voltas completas em cada etapa**, total de seis.
O estado final foi `completed`, 70%, duas voltas na etapa final e player pausado.

Também foram verificados:

- seek para 2,600 s: o retorno parcial até A não contou uma volta A–B completa;
- pausa após a primeira volta do treino: o contador permaneceu estável;
- retoma explícita: voltou a A, conservou a volta concluída e continuou o plano;
- novas etapas após confirmação das voltas anteriores, com a pausa de
  preparação prevista no contrato; não se alega transição gapless.

O JSON inclui a sequência de estados e os counters/epochs nativos. Isso prova
o fluxo lógico observado nesse aparelho/fixture. Não mede áudio apresentado ao
ouvido, clicks, precisão acústica, drift longo ou desempenho estatístico.

### WebView real — fixture offline, não YouTube real

O segundo ramo usou WebView Android real e um WAV sintético **offline**, com
eventos de seek do browser. Confirmou duas voltas completas, contador estável
durante pausa, exclusão da volta parcial e suspensão com sinal de anúncio
**simulado**. O estado final da mídia ficou pausado.

Não foi uma reprodução de vídeo real do YouTube, nem um anúncio real, nem uma
prova completa de subida de todas as etapas numa página remota. O resultado
valida a ponte/contagem sob um fixture controlado, sem comprovar políticas,
mudanças de DOM, anúncios, conectividade, CSP ou comportamento de um vídeo
YouTube arbitrário. B igual ao fim da mídia continua conservadoramente sem
capability automática; treino manual permanece disponível.

## Falha encontrada antes da passagem

A primeira tentativa revelou uma corrida de readiness: um Play imediatamente
depois de seek podia encontrar Media3 ainda a preparar a nova posição. A intenção
estava aceita (`playWhenReady`), mas `playing` ainda era falso; o adaptador
interpretava o intervalo curto de buffering como falha do player.

Foi ajustado `NativeAudioLoadedMedia.play()` para aguardar confirmação real com
limite de 40 verificações separadas por 50 ms (aproximadamente 2 s de espera
mais o custo das chamadas). A espera termina se houver release, fim de mídia,
cancelamento de intenção ou revisão de interrupção diferente. Não ignora perda
de foco nem força Play depois dela. A segunda execução física passou.

Essa espera limitada não é prova de latência de aplicação menor que 2 s; também
não altera as metas de produto. O evento de intenção e a confirmação de
reprodução permanecem conceitos distintos.

## Testes automatizados — resultado final da suíte

Resultados da execução coordenada no código final desta revisão:

| Grupo | Resultado | Escopo |
| --- | --- | --- |
| Mobile — suíte completa | 215 passaram | Inclui controller/storage, os quatro testes de integração do home, os sete do card e as regressões existentes. Log: `apps/mobile/build/practice-flutter-tests.log`. |
| Player Core | 56 passaram | Contratos e regressões do núcleo de player. |
| JavaScript/WASM/ponte | 35 passaram | Contagem e regressões do caminho web em testes controlados. |
| Análise estática Flutter | Limpa | `flutter analyze` sem problemas reportados. |

Total: **306 testes automatizados** (215 + 56 + 35). O subconjunto de 93
controller/storage e os grupos de quatro home/sete card foram executados antes,
mas já estão incluídos nos 215; não são somados novamente. Os **dois cenários
físicos QA** são adicionais e descritos acima. O `+3` exibido no log do driver
inclui `tearDownAll`, não um terceiro cenário funcional.

Os testes do home cobrem mesma instância/progresso entre Prática, Player e
fullscreen, pausa de lifecycle sem autoresume, cancelamento de Play pendente
e save/restauro do plano pausado. A invalidação também alcança um plano já
pausado se a fonte ou A/B mudar: regressar depois à mesma faixa não o ressuscita;
é necessário iniciar/recomeçar explicitamente.

O teste estreito do card teve uma falha inicial no próprio teste: após editar
um valor inválido para válido, faltava uma atualização de frame antes de
acionar Iniciar. A validação e o callback continuavam os do frame anterior.
Foi acrescentado o pump e verificações explícitas de habilitação/início;
os sete testes direcionados passaram depois da correção.

## Build release e atualização no aparelho

APK final: `apps/mobile/build/app/outputs/flutter-apk/app-release.apk`,
**63.110.292 bytes**. SHA-256 verificado no arquivo:

```text
77A2014AAC9080DCDA639786670EBC69180122EA6410DB4C1C265F23269A393B
```

A instalação por `adb install -r` retornou `Success` para o pacote normal
`com.example.transpose_mobile`, sem desinstalar ou limpar seus dados. A metadata
Android conservou `firstInstallTime = 2026-09-25 02:14:50` e mostrou
`lastUpdateTime = 2026-09-25 02:42:28`. O app foi aberto no painel Prática
(PID observado 14512; identificador transitório, não um critério persistente).

A sessão da amostra anterior foi recuperada pausada na atualização v1→v2 e o
card de progressão e seus controles foram conferidos na versão release.
Capturas locais:

- `apps/mobile/build/transpono-practice-release-card.png`;
- `apps/mobile/build/transpono-practice-release-controls.png`.

Isso comprova este percurso de atualização/abertura da sessão anterior, **não**
um novo ensaio de kill físico com plano de treino nem aprovação estatística de
migração. Depois das provas, somente o pacote de teste
`com.example.transpose_mobile.qa` foi desinstalado (`Success`), removendo sua
sandbox e dados descartáveis de QA. O pacote normal permaneceu instalado e em
execução; não foi usada desinstalação/limpeza contra ele. Artefatos de evidência
e screenshots permanecem no workspace. Roadmap completo continua aberto.

## Mapeamento dos gates

Os IDs completos e cenários estão no documento de pesquisa. Estado parcial:

- PRACTICE-QA-001/003/004/005/007/010: cobertura automatizada direcionada
  aprovada, sem substituir hardware/acessibilidade nos casos aplicáveis.
- PRACTICE-QA-002: fluxo nativo físico curto e contagem WebView offline passaram;
  isso não demonstra comportamento de todas as fontes/plataformas.
- PRACTICE-QA-006: pausa e eventos controlados cobertos; anúncio simulado não
  equivale a anúncio real, e chamadas/BT físicos continuam pendentes.
- PRACTICE-QA-008: save/restauro em widget/storage passou. **Não houve nesta
  entrega um novo kill físico com plano de treino persistido**; não transferir a
  aprovação antiga do player para esse estado novo.
- PRACTICE-QA-009: capabilities/fallback cobertos parcialmente por testes;
  YouTube real e vídeo local exigem provas específicas.
- PRACTICE-QA-011: percurso Media3 e fixture WebView aprovados no Samsung
  identificado; não aprova a matriz inteira.
- PRACTICE-QA-012: permanece aberto.

## O que permanece por validar

- YouTube real com anúncio real, navegação, rede intermitente e troca de vídeo.
- Novo process death/reboot/update físico contendo plano e contagem de treino.
- iPhone/iOS, e equivalência dos adapters de cada plataforma.
- Chamadas, perda de foco e rotas Bluetooth em hardware.
- TalkBack/VoiceOver e operação real com fontes/texto ampliados; o teste de
  layout não certifica acessibilidade.
- Precisão acústica de loop, clicks, qualidade musical do time-stretch,
  latência P50/P95/P99, A/V sync, bateria e sessões longas.
- Biblioteca completa de seções, sequência de vários trechos e demais fases
  do roadmap. Não há avaliação da execução do músico, IA, stems ou nuvem
  acrescentados por este recurso.
