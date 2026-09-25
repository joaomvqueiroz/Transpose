# AUDIO ARCHITECTURE

## 1. Objetivo

Construir um pipeline de áudio previsível, mensurável e independente da UI.

## 2. Pipeline conceitual

```text
Media Source
   ↓
Demux / Decode
   ↓
PCM
   ↓
Time Stretch
   ↓
Pitch Shift
   ↓
EQ / Gain
   ↓
Metering
   ↓
Output Buffer
   ↓
Audio Device
```

A ordem exata de pitch/time stretch pode variar conforme a biblioteca escolhida, mas deve produzir:

- speed independente de pitch;
- pitch independente de speed;
- transições sem clicks;
- latência conhecida;
- comportamento estável em longas sessões.

## 3. Vídeo

```text
Video Decode
   ↓
Frame Queue
   ↓
Scheduler
   ↓
Renderer
```

O scheduler deve alinhar frames à timeline do player.

## 4. Master clock

Preferência:

- áudio como relógio master quando áudio está ativo;
- vídeo ajusta apresentação ao áudio;
- UI lê posição consolidada;
- monotonic clock como suporte/fallback.

Nunca usar `DateTime.now()` para medir latência ou controlar playback.

## 5. Latência

Manter um modelo:

```text
decode_latency
dsp_latency
buffer_latency
device_latency
route_latency
```

Nem tudo é controlável pelo app.

Expor diagnóstico interno:

```text
estimated_pipeline_latency_ms
measured_apply_latency_ms
```

## 6. Mudança de pitch/speed

Parâmetros devem mudar com:

- smoothing/ramp curto;
- sem reconstruir toda a sessão quando desnecessário;
- sem bloquear callback de áudio.

Mudanças sucessivas devem ser coalescidas quando seguro.

## 7. Loop

Loop usa posições de mídia, não timers.

Ao chegar a B:

- preparar seek/jump antecipadamente quando o stack permitir;
- evitar buffer vazio;
- aplicar crossfade curtíssimo apenas se necessário para prevenir click;
- não mover A/B devido a arredondamento acumulado.

Persistir A/B em milissegundos ou unidade de precisão superior suportada.

Internamente preferir precisão mais fina que a UI.

## 8. Underrun

Evento:

```text
AudioUnderrun {
  timestamp
  route
  buffer_level
  cpu_load?
  media_position
}
```

Em debug, contabilizar.

Em produção, telemetria agregada/sanitizada.

## 9. Buffering

Separar:

- buffering de rede;
- starvation de decoder;
- underrun de dispositivo;
- preparação inicial.

A UI pode mostrar "A carregar…" sem expor detalhes internos.

## 10. Audio route

Ao trocar rota:

1. receber evento da plataforma;
2. congelar/pausar pipeline se necessário;
3. reconfigurar formato/latência;
4. aplicar política segura;
5. validar que existe somente uma saída ativa;
6. atualizar estado;
7. emitir diagnóstico.

Desconexão de headset não deve causar blast inesperado no speaker.

## 11. Bluetooth

Bluetooth deve ser tratado como classe própria nos testes.

Registrar:

- dispositivo;
- route type;
- codec quando disponível;
- sample rate efetiva quando disponível;
- uso ou não de microfone.

Bluetooth + microfone pode alterar perfil de áudio.

O produto pode informar que monitorização/prática de baixa latência é melhor com cabo quando a latência detectada/esperada for alta.

## 12. Interruption

Chamada ou audio focus:

```text
PLAYING
  → INTERRUPTED
```

Ao terminar:

- retornar a PAUSED por padrão seguro;
- auto-resume apenas se a regra de plataforma/produto estiver explicitamente definida e a interrupção indicar isso.

Nunca inventar autoplay.

## 13. Recording

Playback e recording são pipelines distintos coordenados.

A gravação deve usar escrita resiliente:

- chunks;
- flush periódico seguro;
- finalize;
- recuperação de ficheiro parcial quando possível.

Não manter todo o take em RAM.

## 14. Qualidade adaptativa

Permitido reduzir custo em hardware fraco, desde que:

- não altere silenciosamente pitch/speed;
- não crie clicks;
- qualidade mínima continue aceitável.

Exemplo:

```text
Studio
High
Normal
Economy
```

Default: Normal/Auto.

## 15. Métricas críticas

```text
play_apply_latency
pause_apply_latency
pitch_apply_latency
speed_apply_latency
seek_latency
loop_boundary_error
loop_accumulated_drift
av_offset
av_drift
audio_underruns
dropped_video_frames
route_recovery_time
```

## 16. Regras real-time

No callback:

- nada de DB;
- nada de rede;
- nada de JSON;
- evitar heap;
- evitar locks;
- evitar logging síncrono;
- usar estruturas prealocadas;
- parâmetros atómicos/lock-free quando possível.

## 17. Teste mínimo do motor

Antes de adicionar acordes/IA:

- 60 min playback;
- pitch -2;
- speed 0.75;
- 1000 loops;
- seek;
- fullscreen;
- background;
- BT connect/disconnect;
- chamada;
- restore.

Tem de passar sem crash, duplicação ou estado incoerente.
