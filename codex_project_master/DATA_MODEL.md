# DATA MODEL

## 1. Princípios

- IDs estáveis UUID/string.
- Datas em UTC internamente.
- Dinheiro, se existir, nunca em float.
- Posições de mídia em `int` de milissegundos no domínio público; engine pode usar precisão superior.
- Migrações versionadas.
- Soft-delete apenas onde sync futuro justificar.
- Ficheiros grandes fora da DB.
- Não persistir dados que podem ser derivados de forma barata sem necessidade.

## 2. Song

```text
Song
- id: string PK
- source_type: enum
- source_locator: string
- title: string
- artist: string?
- album: string?
- duration_ms: int?
- artwork_ref: string?
- original_key: string?
- bpm: float?
- created_at: datetime
- updated_at: datetime
- last_opened_at: datetime?
```

`source_locator` nunca deve armazenar segredo.

## 3. PlaybackSession

Snapshot recuperável:

```text
PlaybackSession
- id
- song_id
- position_ms
- pitch_semitones
- speed
- loop_id?
- loop_enabled
- active_preset_id?
- practice_session_id?
- screen
- fullscreen
- playback_state_at_save
- snapshot_version
- saved_at
```

Nunca restaurar `PLAYING` automaticamente após relaunch; converter para estado seguro/PAUSED.

## 4. Loop

```text
Loop
- id
- song_id
- name
- start_ms
- end_ms
- default_speed?
- notes?
- created_at
- updated_at
```

Invariant:

```text
0 <= start_ms < end_ms <= duration_ms
```

## 5. Preset

```text
Preset
- id
- name
- pitch_semitones
- speed
- eq_profile_id?
- metronome_enabled?
- metronome_bpm?
- count_in_bars?
- volume?
- created_at
- updated_at
```

## 6. Setlist

```text
Setlist
- id
- name
- notes?
- created_at
- updated_at
```

## 7. SetlistItem

```text
SetlistItem
- id
- setlist_id
- song_id
- position_index
- preset_id?
- pitch_override?
- speed_override?
- notes?
```

`position_index` deve ser reordenável transacionalmente.

## 8. PracticeSession

```text
PracticeSession
- id
- song_id
- loop_id?
- started_at
- ended_at?
- starting_speed
- target_speed
- increment
- repetitions_per_step
- current_speed
- current_repetition
- total_repetitions
- status
```

Status:

```text
ACTIVE
PAUSED
COMPLETED
ABANDONED
```

## 9. PracticeEvent

Para histórico leve:

```text
PracticeEvent
- id
- practice_session_id
- event_type
- media_position_ms?
- speed?
- created_at
```

Não gerar eventos a cada frame.

## 10. SongSection

```text
SongSection
- id
- song_id
- type
- label
- start_ms
- end_ms?
- source
- confidence?
- analysis_version?
```

Source:

```text
USER
AUTO
IMPORTED
```

## 11. ChordEvent

```text
ChordEvent
- id
- song_id
- start_ms
- end_ms?
- chord_original
- confidence?
- source
- analysis_version?
```

A UI aplica transposição sobre `chord_original`; não duplicar todos os acordes para cada pitch.

## 12. Recording

```text
Recording
- id
- song_id?
- practice_session_id?
- name
- file_path
- duration_ms?
- format
- sample_rate?
- channels?
- created_at
- finalized_at?
- status
```

Status:

```text
CREATING
READY
RECOVERED
CORRUPTED
DELETED
```

## 13. UserSettings

Preferir typed settings.

Categorias:

```text
General
Player
Audio
Practice
Fullscreen
Gestures
Controls
Appearance
Library
Advanced
```

Campos importantes:

```text
background_playback
resume_policy
fullscreen_auto_hide_ms
double_tap_seek_ms
gesture_volume
gesture_brightness
reduce_motion
high_quality_audio
preferred_audio_mode
```

## 14. AudioDiagnosticSession

Debug/local, não necessariamente sincronizado:

```text
AudioDiagnosticSession
- id
- app_build
- device
- os
- route
- started_at
- ended_at
- underrun_count
- dropped_frames
- avg_cpu?
- max_temperature?
```

## 15. Entitlement

Se houver Premium:

```text
Entitlement
- feature
- status
- source
- verified_at
- expires_at?
```

Cliente nunca é autoridade final para compras server-verified.

## 16. Sync metadata

Se cloud existir:

```text
sync_version
server_updated_at
local_updated_at
sync_status
```

Conflitos de setlists/presets devem ser resolvidos explicitamente.

## 17. Migrações

Cada alteração de schema:

- número de versão;
- migration up;
- teste de migração;
- backup/snapshot quando necessário;
- não apagar campos/dados sem estratégia.

Teste obrigatório:

```text
N -> N+1
N-1 -> N+1
```

quando builds em produção justificarem.

## 18. Índices recomendados

```text
Loop(song_id)
SetlistItem(setlist_id, position_index)
ChordEvent(song_id, start_ms)
SongSection(song_id, start_ms)
PracticeSession(song_id, started_at)
Recording(created_at)
```

## 19. Dados que NÃO vão para secure storage

Não colocar toda a DB no Keychain/Keystore.

Secure storage deve guardar apenas secrets pequenos:

- refresh token;
- device credential;
- chaves criptográficas.

## 20. Integridade

Transações para:

- reordenar setlist;
- substituir snapshot;
- finalizar recording metadata;
- aplicar migration;
- delete de song com dependências.
