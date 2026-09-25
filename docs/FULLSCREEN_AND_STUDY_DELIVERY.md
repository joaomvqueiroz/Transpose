# Fullscreen e painéis de estudo — 2026-09-25

## Decisão de produto

O pedido é tornar o app funcional, começando por todos os controles do player
fullscreen, e escolher prioridades com pesquisa e análise técnica. A conclusão
é preservar tom/velocidade/A–B como núcleo e ligar os painéis à mesma sessão.
Esta entrega não equivale à conclusão de todas as fases do roadmap.

### Evidência consultada e interpretação

- [Criador do Music Routine e feedback de músicos](https://www.reddit.com/r/LearnGuitar/comments/16e4w5g/i_made_an_app_to_practice_guitar_seriously_what/):
  relato de complexidade em apps de prática e pedido de ajuste de tempo mais
  acessível. É experiência de utilizadores, não um benchmark. **Nossa decisão:**
  controles diretos, velocidade por slider e passos, sem telas com progresso fictício.
- [Criador de slowdowner e feedback sobre loops](https://www.reddit.com/r/Guitar/comments/1n2b3po/free_tool_for_slowing_down_music_to_help_with/):
  pedidos de progressão de velocidade e relatos de compatibilidade móvel.
  **Nossa decisão:** loops nomeados úteis agora; progressão automática somente
  após eventos de volta reais e recuperação de treino, sem inferir voltas de timers.
- [Experiências contrastantes com Media3](https://www.reddit.com/r/androiddev/comments/1q3yyez/should_i_persist_with_trying_to_make_media3_work/):
  dificuldades de integração e relatos de migração bem-sucedida. Não constituem
  consenso sobre um motor melhor. **Nossa decisão:** manter o motor existente e
  corrigir integração, evitando outra migração sem medidas que a justifiquem.
- [Foco de áudio oficial Android](https://developer.android.com/media/optimize/audio-focus)
  e [MediaSessionService](https://developer.android.com/media/media3/session/background-playback):
  referências técnicas para segurança e eventual background. Serviço não está
  implementado nesta entrega; a política permanece pausar ao sair do app.
- [API oficial do player YouTube](https://developers.google.com/youtube/iframe_api_reference):
  playback rate não equivale a API oficial de pitch. O processamento WebView
  existente continua experimental; não prometer estabilidade da plataforma,
  acesso a mídia protegida, funcionamento durante anúncios ou extração de áudio.

## Funcionalidades ligadas

| Área | Comportamento real |
| --- | --- |
| Fullscreen | Play/pausa/ativar som, ±10 s, seek, tom ±/original, velocidade ±0,05/presets/original, marcar A/B, ativar/desativar/limpar loop |
| Overlay | Mídia mantém área e proporção; controles ocultam após 4 s reproduzindo, aparecem ao toque, não somem durante operações ou acessibilidade |
| Lock | Ambos os cadeados bloqueiam controles e superfície; toque curto não desbloqueia; pressão longa no cadeado superior desbloqueia; ações do SO continuam possíveis |
| Mais opções | Guardar ajustes, metrônomo, transpositor rápido de cifras, afinador por referência, configurações e reset explícito de tom/velocidade/A–B |
| Coleções | Guardar, abrir, renomear, remover com confirmação; ordenar setlist por arraste ou botões acessíveis; sem apagar o arquivo de mídia |
| Prática | A/B e velocidade reais, treino manual, voltar a A, guardar/abrir trechos; nenhum contador de voltas inventado |
| Palco | Nome da mídia atual, semitons confirmados, reprodução, lock, setlist anterior/próxima sem autoplay, ferramentas rápidas |
| Acordes | Cifras com tempos introduzidos pelo utilizador; atual/próximo acompanham posição real; toque faz seek; transposição segue o tom do player |
| Notas | Cifras originais e notas pessoais guardadas por fonte; erro de escrita preserva texto; descarte de edição pede confirmação |

A superfície YouTube permanece visível ao mudar entre Player/Prática/Acordes/
Palco, evitando pausa por ocultação da WebView. Navegar nos painéis não abre outro
player. A mesma superfície é transferida ao fullscreen.

## O que foi retirado da interface funcional

Dados demonstrativos fixos (Gravity, tom original C/Bb, Intro/Verso/Solo,
acordes detectados, porcentagem de domínio e setlist 3 de 12) não aparecem como
dados da música real. As referências originais permanecem nos arquivos do
projeto. Não se retiraram recursos centrais do roadmap.

Gestos decorativos de brilho/volume não foram convertidos em comandos falsos.
O volume do sistema permanece controlável pelos botões físicos. Detecção de
tom/BPM/acordes, diagramas automáticos, stems, gravador e nuvem ficam adiados.
Afinador atual é por nota de referência, não por microfone.

## Limites e próximas prioridades

1. Recuperação de processo/snapshot consistente e restauração sem autoplay.
2. Validar foco/chamadas/retirada de fones em hardware, incluindo WebView.
3. Treino progressivo por eventos reais, progresso persistido e biblioteca.
4. Medir qualidade acústica, latência, repetição longa e A/V sync.
5. Implementar e testar a via iPhone antes de anunciar equivalência.
6. Só depois avançar gravação segura, reconhecimento musical e stems.

Coleções pequenas usam SharedPreferences; não são recuperação transacional do
player. Referências a arquivos locais podem deixar de existir. Chords manuais
não detetam afinação ou harmonia do áudio. Loop WebView/vídeo é aproximado.

## Segurança de áudio local Android

Media3 recebe AudioAttributes de música com gestão de foco e
`setHandleAudioBecomingNoisy(true)`. Perda transitória de foco cancela a intenção
de Play; recuperação de foco não dá autoplay. Uma revisão monotónica acompanha
o evento nativo até ao adapter/core/controllers, invalida Play antigo nas filas
e confirma INTERRUPTED → PAUSED sem libertar a fonte. Recusa de foco não é
tratada como ficheiro corrompido. Teclas físicas controlam volume multimédia.

Testes de contrato/canais simulam interrupção e comandos concorrentes. A build
Android compila e o playback local continua funcional no Samsung. Isso não
substitui chamadas/retirada de fones reais; proteção equivalente no WebView e
no adapter de vídeo continua em aberto. Não há hooks de simulação na release.

## Verificação

Regressões unitárias/widgets cobrem controles, desativação por capability,
mesma fonte, menus, bloqueio, auto-hide, tamanhos pequenos, texto 2×, corrupção
de storage, confirmação de remoção/descarte, seleção e ordem de setlist e
persistência de cifras. Os probes físicos produzem arquivos em `apps/mobile/build`:

- `fullscreen_controls_evidence.json`
- `study_panels_evidence.json`
- `main_youtube_evidence.json`

Resultados físicos desta revisão são registrados após execução, não presumidos
pela existência dos probes. Gates acústicos e a Definition of Done v1 permanecem
abertos.

Fullscreen: probe profile no Samsung SM-A165F aprovado, 42 s de teste; 7 grupos
de cenários, 10 verificações da mesma fonte, estado final pausado. Inclui
ferramentas reais e guardar/reler um preset `QA Fullscreen`; não remove itens
existentes. `fullscreen_controls_evidence.json` contém `passed: true`.

Prática/Acordes/Palco/Coleções: probe profile no mesmo Samsung aprovado em 28 s.
Inclui A/B real, ajuste de velocidade, gravação/releitura de cifras e notas,
transposição, seek por cifra, renomear/reordenar/aplicar setlist sem autoplay,
dois presets da mesma música, transporte/lock do Palco e remoção cancelada e
confirmada. Arquivo de mídia, cifras e dois presets temporários QA criados por
esse probe foram removidos ao final, sem alterar dados anteriores.
`study_panels_evidence.json` contém `passed: true` e `qaArtifactsRemoved: true`.

Regressão YouTube repetida nesta revisão: busca retornou 17 miniaturas; vídeo
real da Blender `aqz-KE-bpKQ`,
pitch +1 confirmado, speed 0,75×, A/B e principal/fullscreen/principal aprovados,
com documento/elemento preservados e zero reloads. Estado final pausado.

Verificação final: `flutter analyze --no-pub` sem problemas; 88 testes Flutter,
56 testes do Player Core e 24 testes Node/JavaScript/WASM aprovados. Total 168
testes automatizados, além dos três percursos físicos acima. Estes números
não substituem os gates de release e medições acústicas.

APK release compilado e instalado com sucesso no Samsung (61.911.574 bytes).
Validação visual da release: abertura, carregamento da amostra e fullscreen,
sem reprodução automática. Capturas locais: `build/transpono-final-release.png`
e `build/transpono-fullscreen-release.png`. Os controles adicionais no rodapé
fullscreen são roláveis em telas pequenas, sem encolher/distorcer a mídia.
