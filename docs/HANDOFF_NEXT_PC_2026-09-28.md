# Handoff para o próximo PC — 2026-09-28

## Prioridade e estado

A prioridade do utilizador é agora **somente vídeos YouTube**. Não repetir a
QA de dois telefones: foi pedido explicitamente que não se repita.

- E1–E8 e U1–U6 foram feitos. A release Dev foi instalada no Samsung original
  como `com.example.transpose_mobile.dev`; a produção ficou intacta.
- N1: na prova dual anterior, o anfitrião passou e o convidado falhou
  continuidade. A correção de clock tem nove testes unitários, sem novo rerun
  em hardware. Houve smoke do microfone sem offset e registo da perceção do
  utilizador. N1 não está concluído.
- N2: a análise WAV é uma base técnica, mas não satisfaz a prioridade YouTube.
  O mapa real de metrónomo e a integração para YouTube continuam abertos.
- N3: seis stems on-device para WAV local são experimentais. O guard de RAM de
  1 GiB acima de `MemoryInfo.threshold` permanece; há limites de memória e a
  sequência na mesma sessão ainda não está concluída.
- Os recursos QA-only de timeline, microfone, mapa e scheduler não têm UI nem
  output real para o utilizador, e não há prova acústica. N1b (YouTube em
  múltiplos dispositivos) não foi implementado.
- N4, direitos e fonte do conteúdo, permanece pendente. Não descarregar,
  capturar stream nem guardar áudio como contorno de direitos. O protótipo de
  microfone ambiente é QA-only e requer revisão de conformidade antes da
  distribuição.

## Próximos passos

1. A cadeia mapa sintético QA → scheduler → `NativeBandAudio` passou num
   Samsung (5 cliques, pausa remove lease). Próximo: só após revisão de
   conformidade/consentimento, decidir se e como associar um mapa revisto a
   conteúdo real. O árbitro partilhado com `BandSession` tem testes unitários,
   mas ainda não foi exercitado em hardware com as duas sessões.
2. Validar com conteúdo permitido somente se o utilizador pedir para retomar a
   QA em aparelhos.
3. Rever compliance antes de qualquer distribuição.

Os seis scripts de probe Android que invocam Flutter Drive verificam agora a
substituição do APK QA com `adb install -r` antes de iniciar o Driver; uma
assinatura incompatível aborta sem desinstalar a instalação existente. A
proteção foi revista por análise estática e parsing PowerShell, não por uma
nova execução no telemóvel.

Não declarar N1–N4 prontos nem baixar o guard de RAM.

## Verificação antes do commit

`flutter analyze --no-pub` passou sem issues. `flutter test --no-pub
--concurrency=1` passou 385 testes. Uma corrida paralela teve uma falha
intermitente em `native_audio_interruption_test.dart` (o caso passou isolado e
na corrida sequencial); investigar se voltar a ocorrer. Os testes JavaScript
passaram: 65/65 em `transpono_media_test.cjs` e 2/2 em
`transpono_key_detector_test.cjs`. Não houve nova execução nos telemóveis após
o pedido do utilizador.

Após o árbitro comum, `flutter analyze --no-pub` voltou a passar e a suíte
sequencial completa passou 389 testes numa repetição. Duas corridas completas
anteriores falharam apenas no teste temporal `web_media_command_test.dart:
never-completing cancellation is bounded and preserves timeout`; o mesmo
teste e o ficheiro inteiro passaram isolados. Tratar como potencial
instabilidade de temporização, não como garantia de regressão resolvida.

## Preparação no outro PC

```powershell
git pull origin main
& .\apps\mobile\tool\setup_stems.ps1
Set-Location apps\mobile
flutter analyze
flutter test
```

O modelo obtido por `setup_stems.ps1` é ignorado pelo Git; o artefacto Dev
também não é versionado. APK Dev verificado:
`apps/mobile/build/artifacts/transpono-dev-release-2026-09-28.apk`, 67.075.326
bytes, SHA-256
`A1DFFF896331FF23784DE36024B0591E657E632A2A2A0490A30BA9D25476BEB2`.
