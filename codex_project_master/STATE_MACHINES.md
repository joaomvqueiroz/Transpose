# STATE MACHINES

## 1. Player

Estados:

```text
IDLE
LOADING
READY
PLAYING
PAUSED
BUFFERING
INTERRUPTED
ERROR
ENDED
```

### Transições

| Estado | Evento | Próximo | Ação |
|---|---|---|---|
| IDLE | LOAD | LOADING | preparar fonte |
| LOADING | LOAD_OK | READY | emitir metadata |
| LOADING | LOAD_FAIL | ERROR | mapear erro |
| READY | PLAY | PLAYING | iniciar saída |
| PLAYING | PAUSE | PAUSED | pausar saída |
| PAUSED | PLAY | PLAYING | retomar |
| PLAYING | BUFFER_EMPTY | BUFFERING | manter posição |
| BUFFERING | BUFFER_READY | PLAYING | retomar |
| qualquer carregado | SEEK | mesmo lógico | atualizar posição |
| PLAYING | INTERRUPTION_BEGIN | INTERRUPTED | ceder áudio |
| PAUSED | INTERRUPTION_BEGIN | INTERRUPTED | manter intenção de pausa |
| INTERRUPTED | INTERRUPTION_END | PAUSED | default seguro |
| PLAYING | END_OF_MEDIA | ENDED | posição final |
| ENDED | SEEK_VALID | PAUSED | posicionar |
| qualquer | FATAL_ERROR | ERROR | parar pipeline |
| qualquer | UNLOAD | IDLE | libertar recursos |

### Invariantes

- Apenas um estado por sessão.
- `PLAYING` implica saída ativa ou intenção ativa com buffering.
- `PAUSED` implica nenhuma progressão intencional da timeline.
- `INTERRUPTED` nunca é representado apenas por `isPaused=true`.
- UI deve observar o state machine.
- Fullscreen não cria outro state machine.

## 2. Recording

```text
NOT_RECORDING
STARTING
RECORDING
PAUSED
FINALIZING
ERROR
```

| Estado | Evento | Próximo |
|---|---|---|
| NOT_RECORDING | START | STARTING |
| STARTING | MIC_READY | RECORDING |
| STARTING | FAIL | ERROR |
| RECORDING | PAUSE | PAUSED |
| PAUSED | RESUME | RECORDING |
| RECORDING | STOP | FINALIZING |
| PAUSED | STOP | FINALIZING |
| RECORDING | INTERRUPTION | FINALIZING ou PAUSED conforme plataforma/política |
| FINALIZING | WRITE_OK | NOT_RECORDING |
| FINALIZING | WRITE_FAIL | ERROR |
| ERROR | ACK/RESET | NOT_RECORDING |

Invariante: UI nunca mostra "gravando" sem stream de captura ativo.

## 3. Practice

```text
NOT_STARTED
PREPARING
RUNNING
PAUSED
STEP_COMPLETE
COMPLETED
ABORTED
```

Fluxo:

```text
NOT_STARTED
→ PREPARING
→ RUNNING
→ STEP_COMPLETE
→ PREPARING(next speed)
→ RUNNING
...
→ COMPLETED
```

Eventos:

- START
- LOOP_FINISHED
- PAUSE
- RESUME
- SKIP_STEP
- CHANGE_TARGET
- STOP

`LOOP_FINISHED` incrementa repetição apenas quando o loop realmente completou.

## 4. Media loading

```text
EMPTY
RESOLVING
PREPARING
READY
FAILED
```

Separar resolução de fonte e preparação do decoder ajuda a reportar erro corretamente.

## 5. Audio Route

```text
ROUTE_STABLE
ROUTE_CHANGING
ROUTE_UNAVAILABLE
```

Eventos:

```text
DEVICE_CONNECTED
DEVICE_DISCONNECTED
SYSTEM_ROUTE_CHANGED
RECONFIGURE_OK
RECONFIGURE_FAIL
```

Enquanto `ROUTE_CHANGING`, impedir criação de dois outputs simultâneos.

## 6. Entitlement

```text
UNKNOWN
FREE
PRO
EXPIRED
OFFLINE_CACHED
ERROR
```

Nunca esconder comportamento crítico atrás de estado `UNKNOWN` sem fallback.

## 7. Download/Import futuro

```text
QUEUED
VALIDATING
IMPORTING
READY
FAILED
CANCELLED
```

Validação antecede parsing pesado.

## 8. Regras de transição

- Nenhum handler deve alterar 3 state machines diretamente sem passar pelo coordenador.
- Toda transição crítica deve ser logada em debug com monotonic timestamp.
- Transição impossível = erro de programação e teste falha.
