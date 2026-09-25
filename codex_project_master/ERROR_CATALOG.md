# ERROR CATALOG

Regra: código interno técnico; mensagem externa humana.

## Formato

```text
code
category
severity
retryable
user_message
developer_context
recommended_action
```

## Catálogo inicial

| Código | Severidade | Retry | Mensagem ao utilizador | Ação |
|---|---|---:|---|---|
| MEDIA_SOURCE_UNAVAILABLE | P1 | sim | Não foi possível abrir esta música. | Tentar novamente / escolher outra fonte |
| MEDIA_FORMAT_UNSUPPORTED | P2 | não | Este formato ainda não é suportado. | Mostrar formatos suportados |
| MEDIA_FILE_MISSING | P1 | não | O ficheiro já não está disponível neste dispositivo. | Localizar novamente |
| MEDIA_PERMISSION_DENIED | P2 | sim | Precisamos de acesso ao ficheiro para o reproduzir. | Pedir permissão contextual |
| PLAYER_LOAD_FAILED | P1 | sim | Não foi possível preparar a reprodução. | Tentar novamente |
| PLAYER_PLAY_FAILED | P1 | sim | Não foi possível iniciar a reprodução. | Tentar novamente |
| PLAYER_PAUSE_FAILED | P1 | sim | Não foi possível pausar a reprodução. | Verificar a saída / tentar novamente |
| PLAYER_SEEK_FAILED | P1 | sim | Não foi possível ir para esse ponto. | Repetir seek |
| AUDIO_OUTPUT_UNAVAILABLE | P1 | sim | Não encontramos uma saída de áudio disponível. | Verificar dispositivo |
| AUDIO_ROUTE_LOST | P1 | sim | O dispositivo de áudio foi desligado. | Selecionar saída / Play |
| AUDIO_ENGINE_INIT_FAILED | P0 | sim | O áudio não pôde ser iniciado. | Reiniciar engine / app |
| AUDIO_UNDERRUN_EXCESSIVE | P1 | sim | O dispositivo está com dificuldade em reproduzir sem interrupções. | Reduzir qualidade |
| PITCH_APPLY_FAILED | P1 | sim | Não foi possível aplicar este tom. | Voltar ao tom anterior |
| SPEED_APPLY_FAILED | P1 | sim | Não foi possível aplicar esta velocidade. | Voltar à anterior |
| LOOP_INVALID_RANGE | P2 | não | O ponto B precisa ficar depois do ponto A. | Corrigir marcador |
| LOOP_SEEK_FAILED | P1 | sim | O loop não pôde ser repetido corretamente. | Desativar loop / retry |
| MIC_PERMISSION_DENIED | P2 | sim | Ative o microfone para gravar a sua execução. | Abrir definições |
| MIC_UNAVAILABLE | P1 | sim | O microfone está a ser usado ou não está disponível. | Tentar depois |
| RECORDING_START_FAILED | P1 | sim | Não foi possível iniciar a gravação. | Retry |
| RECORDING_WRITE_FAILED | P0 | não | A gravação foi interrompida porque não foi possível guardar o ficheiro. | Verificar espaço |
| RECORDING_RECOVERED | INFO | não | Recuperámos uma gravação interrompida. | Abrir take |
| STORAGE_FULL | P0 | não | Não há espaço suficiente para concluir esta operação. | Libertar espaço |
| SNAPSHOT_INVALID | P1 | sim | Recuperámos a sessão a partir do último estado válido. | Telemetria/debug |
| STATE_RESTORE_FAILED | P1 | sim | Não foi possível restaurar toda a sessão anterior. | Abrir sessão limpa |
| NETWORK_OFFLINE | P3 | sim | Sem ligação à internet. As funções locais continuam disponíveis. | Retry |
| REMOTE_TIMEOUT | P2 | sim | O serviço demorou demasiado a responder. | Retry |
| AUTH_EXPIRED | P2 | sim | A sessão da conta expirou. | Reautenticar |
| ENTITLEMENT_UNVERIFIED | P2 | sim | Não foi possível confirmar temporariamente a subscrição. | Usar cache segura/retry |
| WEBVIEW_NAV_BLOCKED | P2 | não | Este endereço não pode ser aberto dentro da aplicação. | Abrir externamente se seguro |
| IMPORT_TOO_LARGE | P2 | não | Este ficheiro é demasiado grande para importar. | Mostrar limite |
| IMPORT_VALIDATION_FAILED | P2 | não | Este ficheiro não parece ser um áudio/vídeo válido. | Escolher outro |
| UNKNOWN_ERROR | P1 | talvez | Ocorreu um problema inesperado. | Retry + diagnóstico |

## Regras

- Nunca mostrar stack trace.
- Nunca mostrar token/URL com credencial.
- Erro P0 deve gerar diagnóstico local seguro.
- Erros retryable precisam de ação clara.
- Não usar “Erro 403” como mensagem principal.
- Não apagar dados porque uma API falhou.
- Falha de recurso opcional não derruba Player Core.

## Error Envelope interno

```text
AppError
- code
- severity
- retryable
- timestamp_monotonic?
- correlation_id
- module
- cause_type
- sanitized_context
```

`sensitive_context` nunca entra no log comum.
