# QA TELEMETRY & DIAGNOSTICS

## 1. Objetivo

Permitir medir os critérios do produto sem depender de “parece rápido”.

## 2. Debug overlay

Acesso apenas em debug/internal build.

Mostrar:

```text
Session ID
Player State
Media Position
Pitch
Speed
Loop A/B
Audio Route
Estimated Audio Latency
A/V Offset
Underruns
Dropped Frames
CPU
Memory
Temperature when available
Last State Save
Last Restore Duration
```

## 3. Métricas

### Latência

```text
play_apply_ms
pause_apply_ms
pitch_apply_ms
speed_apply_ms
seek_ready_ms
route_recovery_ms
restore_ms
```

### Precisão

```text
loop_error_ms
loop_drift_ms
av_offset_ms
av_drift_ms
restore_position_error_ms
```

### Estabilidade

```text
underrun_count
dropped_frames
state_transition_errors
audio_duplicate_detected
recording_finalize_errors
```

## 4. Percentis

Relatórios devem calcular:

- count;
- min;
- P50;
- P95;
- P99;
- max.

P95 = principal métrica de produto.

Não misturar rotas/hardware/cenários distintos no mesmo percentil primário.

## 5. Evento padrão

```json
{
  "event": "pitch_applied",
  "build": "0.8.0",
  "session_id": "local-random-id",
  "route": "speaker",
  "source_type": "local",
  "pitch": -2,
  "speed": 0.75,
  "latency_ms": 71.4,
  "result": "ok"
}
```

Não incluir:

- nome real do utilizador;
- conteúdo da gravação;
- token;
- path privado completo se desnecessário;
- URL autenticada.

## 6. Ring buffer local

Manter últimos N eventos de diagnóstico em memória/arquivo local limitado.

Exemplo:

```text
500–2000 eventos
```

Exportar apenas por ação explícita do tester.

## 7. Diagnóstico exportável

Pacote de bug:

```text
app build
device/os
feature flags
sanitized event log
QA metrics
error codes
audio route history
state transitions
```

Não incluir áudio/gravações por padrão.

## 8. Alertas internos

Durante desenvolvimento:

- state transition impossível;
- duas sessions tocando;
- loop inválido;
- restore com snapshot inconsistente;
- callback real-time bloqueado acima do orçamento;
- underrun consecutivo.

## 9. Metas

```text
Play/Pause P95 < 100 ms
Pitch P95      < 150 ms
Speed P95      < 150 ms
Loop P95       < 25 ms
Loop P99       < 40 ms
A/V drift      < 50 ms / 30 min
Restore        >= 99.9%
```

## 10. Privacidade

Telemetria de produção deve ser mínima.

Diagnóstico detalhado:
- preferencialmente local;
- opt-in quando enviado;
- retenção limitada;
- sanitização obrigatória.
