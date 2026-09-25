# Validação acústica do loop Android

Estado: **não executada**. Os testes existentes observam eventos e parâmetros
Media3, não a forma de onda emitida. `adb screenrecord --help` no Samsung
SM-A165F lista apenas opções de vídeo; não serve como captura de áudio.

## Preparação necessária

1. Ligar a saída de áudio física do telefone a uma entrada de gravação que
   permita capturar PCM/WAV sem cancelamento de eco, AGC ou compressão. Registrar
   aparelho, rota, sample rate, versão da app e interface usada. Se for preciso
   um adaptador USB-C para áudio, confirmar que ele não redireciona o playback
   para outra rota durante o ensaio.
2. Usar um WAV sintético conhecido e anotar as posições A/B na timeline
   original. Incluir transientes de referência dentro do intervalo, afastados
   dos limites, para identificar cada volta na gravação. Testar também um
   sinal cuja junção A/B seja contínua e outro cuja junção seja descontínua;
   estas condições separam defeito do motor de uma edição intrinsecamente
   audível. Não usar apenas o contador de transições como medida temporal.
3. Gravar a saída por toda a execução: 1000 voltas de 2 s (LOOP-001/002),
   500 voltas de 500 ms (LOOP-003), 500 voltas de 1 s (LOOP-004), além de
   100 alternâncias ON/OFF em playback (LOOP-009). A prova de 60 s/100 voltas
   (LOOP-005) exige faixa e captura mais longas.

## Análise e critérios

- Detectar os transientes na gravação e comparar o intervalo entre voltas com
  a duração esperada, corrigida pela velocidade configurada. Reportar erro
  absoluto P50/P95/P99/máximo, perdas, duplicações e drift entre a primeira e
  a última volta. Confrontar com os critérios específicos de
  `codex_project_master/matriz_qa_app_musical.csv`.
- Inspecionar janelas em torno de A/B e das trocas ON/OFF para descontinuidades
  não presentes no WAV de origem; medir a amplitude e ouvir casos suspeitos.
  Classificar separadamente clicks causados por uma edição A/B naturalmente
  descontínua. Guardar WAV bruto, configuração e método de detecção para
  permitir auditoria.
- Repetir nas rotas relevantes (alto-falante, fio, Bluetooth) e não transferir
  um resultado de uma rota para as demais. Só aprovar o gate acústico depois
  das medições; os testes automatizados atuais permanecem evidência de
  controle/estabilidade, não de qualidade da saída.
