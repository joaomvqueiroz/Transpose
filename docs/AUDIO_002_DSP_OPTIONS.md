# AUDIO-002 — opções DSP para o spike

Estado em 2026-09-24: ADR-014 substitui a escolha de ADR-011 para o produto.
Tom e Velocidade continuam centrais, mas a primeira implementação seguirá
Media3/AVAudioUnitTimePitch **sem Rubber Band**. A tabela abaixo preserva a
comparação histórica de DSP; nenhuma opção aprova o gate acústico por si só.

| Candidato | Razão para testar | Risco a verificar |
|---|---|---|
| [Rubber Band](https://breakfastquay.com/rubberband/code-doc/) — spike interno, não escolhida para produto | API C++/C para pitch e time-stretch em tempo real; permite mudar a razão durante processamento; relatos de developers favorecem qualidade musical | Licença [GPL ou comercial](https://breakfastquay.com/rubberband/license.html), inclusive restrição declarada para distribuição na App Store sob GPL; mudança de parâmetros deve ser coordenada com `process()` e casos extremos podem alocar |
| [SoundTouch](https://soundtouch.surina.net/) | C++ com pitch e tempo independentes; documentação declara Android/iOS e processamento em tempo real | LGPL 2.1 ou licença comercial; confirmar obrigações de distribuição, qualidade musical e latência no hardware-alvo |
| [Signalsmith Stretch](https://signalsmith-audio.com/code/stretch/) | C++11 header-only, MIT, pitch e time-stretch; fornece informação de latência | Integração Android/iOS e custo CPU/latência real ainda não provados para este app |

O port `AudioProcessingPort` mantém a UI independente destes candidatos.
O `PitchController` acrescentado em AUDIO-002 só gere intenção, confirmação e
falha; não faz processamento de PCM. O plugin atual `video_player` não fornece
um caminho de PCM controlado pelo app, portanto um DSP independente não pode
ser simplesmente ligado a ele sem redesenhar o pipeline de reprodução/saída.

Gate de aprovação da implementação: validar direitos de distribuição, compilar Android/iOS,
medir P50/P95/P99 de comando até saída efetiva (meta P95 < 150 ms), clicks,
underruns, CPU e sincronização A/V. Executar primeiro o spike de áudio local
descrito em `codex_project_master/SPIKE_FLUTTER_CPP_RUBBERBAND.md`, adaptando
o processador sob teste sem declarar o gate físico aprovado por antecipação. A medição de
latência deve usar a saída efetiva, não o ACK Dart/FFI.

Recomendação histórica de ADR-011: começar com R2/Faster em tempo real;
comparar R3/Finer no Samsung e num Android médio. Esta rota foi substituída
por ADR-014 para o produto. A
[licença comercial padrão](https://breakfastquay.com/technology/license.html)
tem preço público, mas **não foi comprada** e nenhum binário proprietário com
Rubber Band pode ser distribuído antes de licença válida. Se o custo ou os
gates físicos inviabilizarem uma eventual revisão futura, testar Signalsmith;
não substituir silenciosamente. O probe Media3 do ADR-014 é independente do
player principal e só prova parâmetros/posição no Samsung, não qualidade.
