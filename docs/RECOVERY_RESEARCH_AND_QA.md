# Recuperação de sessão — pesquisa e verificação

Data: 2026-09-25. Este documento trata da entrega incremental de recuperação;
não declara concluídos o roadmap nem os critérios de release da versão 1.

## Decisão

Manter tom, velocidade, A/B, YouTube integrado e os painéis ligados à mesma
sessão. Antes de acrescentar reconhecimento musical ou mais ferramentas,
garantir que o utilizador consegue voltar à música e aos ajustes depois de o
Android terminar o processo.

Usar SQLite **apenas para o snapshot atual e a cópia anterior válida**, numa
transação. Não migrar nesta etapa predefinições, setlist ou cifras existentes.
Um arquivo JSON com substituição atómica seria uma alternativa razoável para
um único registro, mas exige implementar e verificar as próprias regras de
substituição, sincronização e fallback por plataforma. A transação SQLite
reduz esse código específico e é compatível com a futura biblioteca prevista
no roadmap. Esta é uma avaliação técnica do projeto, não uma votação ou um
consenso atribuído ao Reddit.

Guardar alterações confirmadas de fonte, tom, velocidade, loop e painel;
limitar a frequência das escritas de posição durante a reprodução. Salvar
também ao pausar/sair, mas **não depender exclusivamente de um evento de saída**.
O snapshot não contém uma intenção de iniciar reprodução na próxima abertura.

- Fonte local disponível: preparar automaticamente a sessão em pausa.
- YouTube: apresentar os dados da sessão guardada; não abrir WebView nem fazer
  um pedido de rede para recuperar o vídeo antes de uma ação explícita.
- Fonte ausente/indisponível: explicar a falha e preservar os ajustes.
- Formato futuro ou armazenamento ilegível: preservar os dados, avisar e
  impedir que a versão atual os sobrescreva silenciosamente.
- Arquivo escolhido pelo utilizador: copiar para armazenamento privado
  persistente do app; não apagar/mover o original e não guardar somente o
  caminho temporário devolvido pelo seletor.

## Evidência e limites das conclusões

| Fonte | O que sustenta | Aplicação nesta entrega |
| --- | --- | --- |
| [Flutter: AppLifecycleState](https://api.flutter.dev/flutter/dart-ui/AppLifecycleState.html) | A aplicação pode ser terminada sem receber todos os eventos de lifecycle. | Autosave durante o uso; pausa/saída são oportunidades adicionais, não a única estratégia. |
| [Android: processos e lifecycle](https://developer.android.com/guide/components/activities/process-lifecycle) | A duração do processo é gerida pelo sistema; a limpeza final não é garantida. | Testar um processo realmente terminado, não apenas reconstruir um widget. |
| [shared_preferences, documentação oficial do pacote](https://pub.dev/packages/shared_preferences) | Escritas podem ser assíncronas e o pacote não se apresenta como armazenamento de dados críticos. | Não confundir as pequenas coleções já existentes com recuperação transacional do player. |
| [Flutter: persistência com SQLite](https://docs.flutter.dev/cookbook/persistence/sqlite) | SQLite é uma opção documentada para persistência e consultas locais. | Adotar uma interface de repositório e um escopo pequeno, sem reescrever todos os dados do app. |
| [SQLite: atomic commit](https://www.sqlite.org/atomiccommit.html) | Explica transações atómicas, journal e as premissas do sistema de arquivos. | Gravar atual/anterior na mesma transação; não anunciar imunidade universal a falhas de hardware. |
| [FAQ dos mantenedores de file_picker](https://github.com/miguelpruivo/flutter_file_picker/wiki/FAQ) | Arquivos escolhidos podem ser cópias temporárias; a documentação recomenda transferi-los para armazenamento do app quando é necessária persistência. | Importação durável antes de publicar a nova fonte no player. |
| [Android: armazenamento específico do app](https://developer.android.com/training/data-storage/app-specific) | Distingue arquivos persistentes e cache, que pode ser removido. | Não usar cache como única origem de uma música a recuperar. Desinstalar/limpar dados continua a remover dados privados do app. |

Os relatos de desenvolvedores foram usados para identificar problemas de uso
e manutenção, e as decisões técnicas foram verificadas nas fontes primárias:

- [Discussão sobre escolha de banco no Flutter](https://www.reddit.com/r/FlutterDev/comments/tzqwpg/):
  experiências e opiniões sobre persistência, maturidade do SQLite e benefício
  de uma interface isolando o armazenamento. Não demonstra que qualquer opção
  seja sempre superior.
- [Arquivos privados do app versus cache](https://www.reddit.com/r/FlutterDev/comments/1hx8xel/):
  discussão prática sobre os diretórios de `path_provider` e sobre arquivos que
  o sistema pode eliminar. A distinção técnica foi confirmada na documentação
  Android e no FAQ do seletor.
- [Restaurar estado após encerramento pelo sistema](https://www.reddit.com/r/FlutterDev/comments/sxum85/):
  relato e discussão sobre concentrar recuperação nos fluxos em que perder
  estado realmente prejudica o utilizador. No Transpono, isso significa a
  música, o trecho, os ajustes e o painel — não menus transitórios abertos.

## O que acrescentar, manter ou adiar

**Acrescentar agora:** recuperação segura, importação durável, mensagem de erro
útil e teste real de morte de processo. Não introduzir conta ou servidor para
uma funcionalidade que pode operar localmente.

**Manter:** pitch independente da velocidade como função central; A/B; busca
e seleção de YouTube dentro do app; controles acessíveis; predefinições,
cifras manuais e setlist já implementadas. Não substituir o motor de áudio sem
uma medida concreta que justifique a mudança.

**Próxima funcionalidade recomendada:** treino com aumento progressivo da
velocidade, depois de fechar segurança de interrupções e eventos reais de
volta do loop. Há [feedback explícito pedindo progressão](https://www.reddit.com/r/Guitar/comments/1n2b3po/)
e [um relato de desenvolvedor que implementou uma ferramenta desse tipo](https://www.reddit.com/r/Guitar/comments/1ugeobv/i_built_a_tool_to_help_practice_with_youtube/).
São sinais de utilidade, não prova de adequação automática a todos os músicos.
A implementação não deve contar voltas por tempo de relógio nem mostrar
progresso inventado se o vídeo estiver pausado, num anúncio ou carregando.

**Adiar, sem retirar do núcleo:** stems, detecção automática de acordes/tom,
gravação, sincronização na nuvem e background playback. Estas funções precisam
de contratos, qualidade, permissões e testes próprios. Não adicionar autoplay
de recuperação ou botões que confirmem uma ação ainda inexistente.

## Probe físico de morte de processo

Arquivos:

- `apps/mobile/integration_test/recovery_process_probe_test.dart`
- `apps/mobile/test_driver/recovery_process_probe_test.dart`
- `apps/mobile/tool/run_recovery_probe.ps1` (entrada recomendada para executar)

O probe tem duas fases compiladas com `--dart-define`. Usa o mesmo identificador
nas duas fases. Após o incidente descrito abaixo, o Gradle passou a atribuir
automaticamente o application ID `com.example.transpose_mobile.qa` a targets
que contêm `integration_test/`; `lib/main.dart` continua a produzir o pacote
normal `com.example.transpose_mobile`. São sandboxes Android diferentes, não
somente pastas diferentes no mesmo app. O probe também recusa executar se o
caminho Application Support não contiver o ID `.qa` esperado.

Dentro dessa sandbox QA existe uma pasta por execução e o banco injetado
`qa_recovery.sqlite`; **não é o banco padrão da sessão do utilizador**.
O código Dart do probe não escreve predefinições, setlist ou cifras. Esta
separação de arquivos não protege contra uma desinstalação feita pelo runner.
**É obrigatório passar `--keep-app-running` em ambas as fases.** No SDK Flutter
local, o encerramento padrão de `flutter drive` chama
`FlutterDriverService.stop`, que para **e desinstala** o pacote quando o pacote
da aplicação está disponível. Isso também pode ocorrer quando o driver termina
com erro depois do force-stop esperado. A desinstalação remove os dados privados
do app e invalida o teste entre processos.

O comportamento foi confirmado por inspeção de
`packages/flutter_tools/lib/src/commands/drive.dart` (ramo
`_keepAppRunningWhenComplete`) e
`packages/flutter_tools/lib/src/drive/drive_service.dart` (método `stop`) no SDK
utilizado. Não tratar o nome genérico “stop” como garantia de preservar dados.
Antes de qualquer novo probe em um dispositivo com dados do utilizador,
verificar também os efeitos do runner, não somente a limpeza dentro do teste.

Usar o wrapper `run_recovery_probe.ps1`: ele compila primeiro, verifica nos
metadados que o APK pertence exatamente a `com.example.transpose_mobile.qa` e
só então chama o driver com esse arquivo em `--use-application-binary` e com
`--keep-app-running`. Isso evita também a identidade de um APK antigo em cache
ser capturada pelo driver antes de uma recompilação. Não executar outra build
Android concorrente, que poderia substituir o arquivo entre a verificação e a
instalação. O wrapper não limpa dados, não desinstala e não faz force-stop.

Um resumo determinístico das SharedPreferences **da sandbox QA** é comparado
entre as fases sem copiar nomes/conteúdos dos
registros para o relatório. Esse resumo é apenas um detector de alteração,
não um checksum de segurança. O campo `qaPreferencesUnchanged` não representa
uma leitura ou uma validação dos dados privados do aplicativo de produção.

### 1. Seed

Executar em `apps/mobile`, escolhendo um identificador QA novo:

```powershell
.\tool\run_recovery_probe.ps1 -Phase seed -RunId recovery-20260925-b -DeviceId R58YA16NDVM
```

O teste importa a amostra através do importador de produção, configura tom
−2, velocidade 0,8×, A=2s, B=6s e posição=3s, seleciona Prática e espera que
o autosave real confirme esses dados. Só então inicia a reprodução e escreve:

```text
TRANSPONO_RECOVERY_READY_TO_KILL pid=... run=recovery-20260925-b
```

O processo continua ativo, sem chamar dispose/pausa para preparar o encerramento.
Tem um limite de três minutos de espera pelo host, depois do qual o teste falha
e faz a limpeza normal dos recursos de reprodução.

### 2. Encerramento externo

Após o marcador, terminar **somente o processo do Transpono QA**. Não executar
estes comandos contra o ID de produção:

```powershell
adb -s R58YA16NDVM shell pidof com.example.transpose_mobile.qa
adb -s R58YA16NDVM shell am force-stop com.example.transpose_mobile.qa
adb -s R58YA16NDVM shell pidof com.example.transpose_mobile.qa
```

A segunda consulta não deve devolver PID. A desconexão/erro de transporte do
primeiro `flutter drive` é esperada nesta fase e não é o resultado da fase de
verificação. Manter `--keep-app-running` mesmo neste encerramento por erro:
o pacote e seus dados precisam continuar instalados. Confirmar essa condição
antes de iniciar a verificação. Não usar `pm clear`, desinstalar o app, limpar armazenamento ou
apagar dados para simular morte de processo. `force-stop` testa um encerramento
externo real, mas não equivale por si só a todas as situações de low-memory,
reboot, crash durante uma transação ou falha de alimentação.

### 3. Verify

Usar o mesmo identificador, preservando os dados durante a reinstalação normal
do APK de teste:

```powershell
.\tool\run_recovery_probe.ps1 -Phase verify -RunId recovery-20260925-b -DeviceId R58YA16NDVM
```

A verificação exige PID diferente, abre o snapshot sobrevivente e monta uma
nova instância real do player. Confirma:

- mesma fonte durável, tom e velocidade;
- A/B e loop preservados;
- posição dentro de 150 ms do último checkpoint confirmado, inclusive dentro
  do loop, em vez de reiniciar obrigatoriamente no marcador A;
- painel Prática restaurado;
- estado pausado e posição estável durante observação continuada;
- SharedPreferences existentes da sandbox QA inalteradas.

Após aprovação, remove somente o arquivo de amostra QA, banco QA e manifesto
criados pelo probe; diretórios são removidos apenas se estiverem vazios. Arquivos
inesperados são preservados para inspeção. Em falha, os dados QA continuam
disponíveis. Uma nova tentativa de seed não sobrescreve uma execução incompleta:
verificar a existente ou escolher outro identificador.

O driver escreve `apps/mobile/build/recovery_process_evidence.json`. A duração
reportada é uma observação individual, **não P95 nem tempo de cold launch**.
O campo `measurementScope` informa
`mount-to-player-ready; database already read`: o cronómetro começa antes de
montar a interface, depois de o probe já ter aberto e lido o SQLite para
estabelecer os valores esperados. Não inclui o arranque do processo/app nem a
primeira abertura/leitura da base de dados. A tolerância de posição
compara com o último checkpoint, não promete que os últimos segundos ainda
não gravados sobrevivam a qualquer encerramento.

Não executar builds Flutter em paralelo com outros comandos Flutter que
regenerem plugins. Após os probes, compilar e reinstalar o APK release normal;
não entregar ao utilizador o APK cujo ponto de entrada é um teste.

## Estado da verificação

- Verificação final de código: `flutter analyze` sem problemas; 144 testes
  Flutter, 56 de Player Core e 24 JavaScript/WASM passaram (224 no total).
  Incluem parser/SQLite real via FFI, rollback/fallback, erros/concorrência,
  importação durável, autosave confirmado, UI e regressões dos painéis.
- Análise Dart dos dois arquivos do probe: sem problemas.
- Primeira tentativa física: **invalidada pelo runner**, não aprovada. O seed
  chegou ao processo PID 4799 e houve force-stop real, mas os comandos não
  continham `--keep-app-running` e ainda utilizavam o ID de produção
  `com.example.transpose_mobile`. Ao terminar, o driver desinstalou esse pacote
  e removeu seus dados privados, incluindo o manifesto QA. A fase verify falhou na
  pré-condição de manifesto existente, antes de avaliar a recuperação; seu
  encerramento também desinstalou o pacote. A ausência posterior do pacote foi
  confirmada pelo agente responsável pela execução. Este resultado não prova
  falha nem sucesso da recuperação implementada.
- Correção do harness: application ID QA separado automaticamente pelo target
  Gradle, verificação de sandbox antes de manipular os arquivos e
  `--keep-app-running` obrigatório nas duas fases. O wrapper faz pré-build e
  verificação da identidade do APK antes de instalar; o `finally` Dart sempre
  interrompe a reprodução se o teste terminar com o processo ainda vivo.
- Nova tentativa isolada: **percurso aprovado** em Android físico, build
  profile, dispositivo `R58YA16NDVM`, execução `recovery-20260925-b`. O seed
  chegou a `READY_TO_KILL` reproduzindo no pacote `.qa`, PID 7084. O force-stop
  externo terminou esse processo; o pacote permaneceu instalado após a saída
  esperada do driver com código 1. A fase verify, executada pelo wrapper seguro,
  abriu um novo processo PID 8104 e terminou com `passed: true`.
- Recuperação observada: tom −2 semitons, velocidade 0,8×, A=2000 ms,
  B=6000 ms e loop ativo. Posição guardada/restaurada: **3590/3590 ms**.
  Painel Prática restaurado; `playingAfterRestore: false` e posição estável
  durante a observação do teste. Preferências QA preservadas; arquivos criados
  pelo probe removidos ao final (`qaArtifactsRemoved: true`). Isso não é uma
  leitura nem uma verificação dos dados privados do app de produção.
- Tempo registrado: **1037 ms**, somente de montagem da interface até player
  pronto, com base já lida. É uma amostra individual; exclui arranque do app e
  primeira leitura SQLite. **Não é P95**, não estabelece taxa de sucesso de
  99,9% e não conclui a fase STATE do roadmap.
- Evidências lidas após a execução:
  `apps/mobile/build/recovery_force_stop_isolated_evidence.json` documenta o
  encerramento e a preservação do pacote;
  `apps/mobile/build/recovery_process_evidence.json` documenta as asserções da
  nova sessão e o escopo da medição.
- Entrega: APK release normal compilado, `applicationId` de produção validado
  em `output-metadata.json`, 62 879 484 bytes, instalado via `adb install -r`
  com sucesso. Somente o pacote QA separado foi removido deliberadamente após
  a verificação; o app normal foi aberto no Samsung.
- Smoke adicional na build release normal: carregar a amostra pelo menu, ajustar
  tom para −1, encerrar o processo PID 8733 via `am force-stop` (sem desinstalar)
  e reabrir com PID 9734. Inspeção visual confirmou amostra, tom −1, posição
  00:00 e aviso de sessão recuperada aguardando Play. Capturas:
  `apps/mobile/build/transpono-recovery-before-kill.png` e
  `apps/mobile/build/transpono-recovery-release.png`. É uma prova visual adicional,
  não medição acústica nem substituto do probe que compara valores exatos.
- Este documento não presume aprovação pela simples existência do teste.
- Continuam necessários: kill durante autosave/seek, corrupção e migrações,
  reboot, repetições suficientes para metas estatísticas, fonte ausente,
  YouTube online/offline/anúncios e ausência de som inesperado, chamadas/fones,
  qualidade acústica e iPhone físico.

Novos resultados devem ser acrescentados depois da execução, com dispositivo,
build, identificador QA e caminho da evidência. Os gates de
`codex_project_master/AUTOSAVE_RECOVERY.md` permanecem critérios de aceitação,
não promessas satisfeitas por um único percurso.
