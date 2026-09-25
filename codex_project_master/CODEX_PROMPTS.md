# CODEX PROMPTS

Use um prompt por tarefa. Não pedir “faz o app inteiro”.

## 1. Auditoria inicial

```text
Leia nesta ordem:
PROJECT_MEMORY.md
ARCHITECTURE_DECISIONS.md
TECHNICAL_SPEC.md
AUDIO_ARCHITECTURE.md
STATE_MACHINES.md
BEHAVIOR_CONTRACT.md
DATA_MODEL.md

Não altere código ainda.

Analise o repositório atual e produza CURRENT_ARCHITECTURE.md contendo:
- stack;
- módulos;
- entrypoints;
- player/media libraries;
- storage;
- estado global;
- threading;
- integrações externas;
- dependências críticas;
- riscos;
- diferenças entre código atual e documentação;
- decisões ADR ainda abertas que já podem ser respondidas pelo repositório.

Não invente features. Não faça refactor.
```

## 2. Player State Machine

```text
Implemente somente PLAYER-001.

Leia:
PROJECT_MEMORY.md
TECHNICAL_SPEC.md
STATE_MACHINES.md
BEHAVIOR_CONTRACT.md

Objetivo:
substituir/encapsular estado disperso do player por uma state machine tipada.

Não altere o visual salvo se necessário para conectar o novo estado.
Não implemente pitch, speed ou loop nesta tarefa.

Antes de editar, liste:
- ficheiros;
- estado atual;
- plano.

Depois:
- execute testes;
- adicione testes para transições inválidas;
- prove que UI não pode ficar PLAYING enquanto engine está PAUSED;
- reporte qualquer incompatibilidade.
```

## 3. Pitch

```text
Implemente AUDIO-002 sem alterar outras features.

Leia AUDIO_ARCHITECTURE.md e matriz QA PITCH.

Requisitos:
- pitch em semitons;
- speed não muda;
- smooth transition;
- métricas pitch_apply_ms;
- erro retorna ao valor anterior confirmado;
- nenhuma operação de disco/rede no callback real-time.

Adicione testes PITCH-001 a PITCH-007 aplicáveis à camada automatizável.
Não invente biblioteca DSP se ADR-011 continuar Open; primeiro proponha opções compatíveis com o stack atual.
```

## 4. Speed

```text
Implemente AUDIO-003.

Speed independente de pitch.
Suportar presets e slider conforme UI atual.
Instrumentar speed_apply_ms.
Não mudar layout geral.

Use SPEED-001..007 como critérios.
```

## 5. Loop

```text
Implemente EPIC 3 por etapas.

Comece apenas por LOOPDEV-001 e LOOPDEV-002.

Requisitos:
- A < B;
- posições na timeline de mídia;
- sem timers de UI;
- 1000 loops não podem acumular drift acima da meta;
- métricas loop_error_ms e loop_drift_ms.

Não implemente biblioteca de loops salvos até o motor passar LOOP-001/002.
```

## 6. Autosave/Recovery

```text
Implemente STATEDEV-001..004.

Leia AUTOSAVE_RECOVERY.md e DATA_MODEL.md.

Requisitos:
- snapshot versionado;
- writes atómicos;
- current + previous valid;
- restore sem autoplay;
- posição debounced;
- saves imediatos para pitch/speed/loop/preset;
- corrupção parcial recuperável.

Criar harness para STATE-001/002/007/008.
```

## 7. Bluetooth e chamadas

```text
Implemente adapters de Platform lifecycle sem misturar regras Android/iOS no domínio.

Normalize:
InterruptionBegan
InterruptionEnded
AudioFocusLost
AudioFocusGained
RouteChanged

Aplicar BEHAVIOR_CONTRACT.

Prioridade:
BT disconnect seguro e zero áudio duplicado.

Associar testes BT e INT.
```

## 8. Fullscreen

```text
Implemente fullscreen como uma nova apresentação da mesma MediaSession.

Proibido:
- criar segundo player;
- reload da mídia ao entrar/sair;
- copiar estado manualmente entre dois players.

Quando controls hidden: só vídeo.
Tap: overlay.
Auto-hide ~2–3 s.
Gestos conforme PROJECT_MEMORY.
Lock deliberado.
Acessibilidade exige alternativa por botão.
```

## 9. Practice Mode

```text
Implemente PRACTICE-001..005 usando o Player Core existente.

Practice Engine não processa áudio.
Ele coordena loop + speed + repetitions.

Progressão configurável.
Persistir progresso.
Se usuário alterar speed manualmente durante rotina, aplicar BEHAVIOR_CONTRACT.
```

## 10. Recording

```text
Implemente recording com state machine própria.

Prioridades:
- start/stop confiável;
- escrita incremental;
- chamada não corrompe take;
- crash não deixa take inválido como READY;
- permissões só no contexto.

Não transformar em DAW.
```

## 11. QA overlay

```text
Implemente QA-001/002/006 apenas para debug/internal builds.

Mostrar:
state
position
route
pitch
speed
loop
A/V offset
underruns
dropped frames
restore timing

Nunca expor tokens ou conteúdo de gravação.
```

## 12. Revisão de segurança

```text
Faça auditoria de segurança sem alterar comportamento inicialmente.

Procure:
- secrets hardcoded;
- tokens em storage inseguro;
- logs sensíveis;
- WebView bridge;
- URLs com tokens;
- permissões excessivas;
- import sem validação;
- entitlement confiando em flag local.

Produza SECURITY_AUDIT.md com:
Critical/High/Medium/Low.
Depois espere aprovação para mudanças de alto impacto.
```

## 13. Antes de qualquer tarefa futura

```text
Antes de modificar:
1. leia PROJECT_MEMORY.md;
2. encontre o item no CODEX_BACKLOG.md;
3. leia o spec correspondente;
4. indique ficheiros e testes afetados;
5. mantenha escopo mínimo;
6. não refatore áreas não relacionadas;
7. se uma decisão permanente mudar, atualize PROJECT_MEMORY e ADR.
```
