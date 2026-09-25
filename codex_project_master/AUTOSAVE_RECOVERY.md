# AUTOSAVE & RECOVERY

## 1. Objetivo

O utilizador não deve pensar em “Guardar projeto”.

O app deve recuperar uma sessão útil depois de:

- background;
- lock;
- low-memory;
- process death;
- crash;
- reboot.

## 2. Snapshot

Guardar como unidade atómica.

Campos mínimos:

```text
snapshot_version
session_id
song_id
source_type
source_locator
position_ms
pitch_semitones
speed
loop_id
loop_a_ms
loop_b_ms
loop_enabled
active_preset_id
practice_session_id
practice_current
practice_target
screen
fullscreen
saved_at
```

Não persistir `PLAYING` como intenção automática de relaunch.

Guardar, se útil:

```text
was_playing_before_interruption
```

apenas para lógica controlada no mesmo lifecycle, não para autoplay após relaunch.

## 3. Quando salvar

Imediato:

- troca de música;
- criação/alteração de loop;
- aplicação de preset;
- alteração de pitch concluída;
- alteração de speed concluída;
- início/fim de practice session;
- app vai background;
- recording finalizado;
- setlist reordenada.

Debounced:

- posição de playback;
- scrubbing frequente.

Sugestão:

- snapshot de posição a cada 5–10 s durante playback;
- também ao Pause;
- também em lifecycle event.

Não escrever a cada frame.

## 4. Atomicidade

Estratégia:

```text
BEGIN TRANSACTION
write new snapshot
mark valid
COMMIT
```

ou equivalente atomic replace.

Nunca deixar o único snapshot pela metade.

## 5. Last Known Good

Manter:

- `current_snapshot`
- `previous_valid_snapshot`

Se parse/validation falhar no atual:
- tentar anterior.

## 6. Validação de snapshot

Antes de restaurar:

- version suportada;
- song/source existe;
- posição >= 0;
- pitch dentro da faixa;
- speed dentro da faixa;
- A < B;
- IDs referenciados válidos ou nullable;
- valores finitos.

Campo inválido isolado não deve necessariamente invalidar tudo.

## 7. Recovery flow

```text
App Start
↓
Load snapshot
↓
Validate
↓
Resolve media source
↓
Restore pitch/speed/loop
↓
Seek
↓
READY/PAUSED
```

Nunca:

```text
load snapshot
→ PLAY
```

sem intenção explícita atual do utilizador.

## 8. Process death

Meta:

- P95 < 2 s até estado utilizável, quando fonte local e hardware permitirem;
- posição ±500 ms;
- pitch exato;
- speed exata;
- loop ±10 ms;
- progresso exato.

## 9. Background vivo

Meta:

- P95 < 1 s;
- posição ±100 ms quando aplicável;
- sem rebuild do pipeline se não necessário.

## 10. Crash

No launch seguinte:

- detectar termination não limpa quando possível;
- validar recording parcial;
- restaurar sessão;
- opcionalmente indicar “Sessão recuperada” de forma discreta.

## 11. Recording recovery

Escrever gravação de forma incremental.

Metadata:

```text
CREATING
→ READY
```

Se crash durante `CREATING`:
- tentar recuperar/finalizar container;
- marcar `RECOVERED` se sucesso;
- `CORRUPTED` se não.

Nunca esconder ficheiro corrompido como take válido.

## 12. Migrações

Snapshot tem `snapshot_version`.

Cada versão:
- parser;
- migration;
- fallback.

Não apagar snapshot antigo antes da nova versão validar.

## 13. Testes

Obrigatórios:

- STATE-001 a STATE-009;
- corrupção parcial;
- kill imediatamente depois de mudar pitch;
- kill durante seek;
- kill durante autosave;
- reboot;
- update de schema.
