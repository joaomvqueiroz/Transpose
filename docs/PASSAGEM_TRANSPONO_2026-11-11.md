# Passagem de trabalho — Transpono (11/11/2026)

Escrito pela sessão «PC de casa» para a sessão que continuar (Manager Roadmap). O dono (João) decidiu continuar aí.

## Onde está o código

- Ramo de trabalho: `toque-video-wip`. O ramo `ios-gecko` está igual (avanço direto a cada commit). Último commit: ver `git log -1`.
- App Flutter em `apps/mobile`. Quase tudo o que mexe nas páginas do YouTube está em `apps/mobile/assets/web/transpono_media.js`; a parte da app em `lib/studio_player_home.dart` (parte de `studio_visual_app.dart`), `lib/youtube_browser.dart`, `lib/source_picker.dart`, `lib/home_button_visibility.dart`, `lib/glass_bar.dart`.
- iPhone nativo: `ios/Runner/SceneDelegate.swift` (barra de vidro) e `ios/gecko/TransponoGeckoBridge.swift` (motor de páginas).
- Relatório do dia anterior: `docs/RELATORIO_SESSAO_TOQUE_VIDEO_2026-11-10.md`.

## Como compilar e testar

- Android (variante do dono): `flutter build apk --release --target=lib/main.dart --dart-define=TRANSPONO_PERSONAL_RHYTHM=true --android-project-arg=transponoPersonal=true`, assinado com a keystore de depuração de casa. Instalar com `adb install -r` (nunca desinstalar).
- Inspeção das páginas no telemóvel: acrescentar `--dart-define=TRANSPONO_WEB_DEBUG=true`, e depois `adb forward tcp:9222 localabstract:webview_devtools_remote_<pid>`. Voltar a instalar a versão normal no fim.
- iPhone: `gh workflow run ios-gecko.yml --ref ios-gecko`; o IPA sai como artefacto, por assinar. Os commits levam `[skip ci]` para não compilar a cada push.
- Testes: `flutter test` (426) e `node tool/tests/transpono_media_test.cjs` (67).
- Não correr duas compilações Gradle ao mesmo tempo: uma falhou assim e deixou um `.hprof` de 2 GB (agora ignorado no `.gitignore`).

## O que foi feito (10 e 11/11)

- Perda de toque depois de encolher o vídeo: corrigida e validada no A16.
- Páginas do YouTube ao estilo da app oficial: barra de baixo só com ícones e botão dos ajustes no meio; separadores Início/Inscrições/Música/Ao vivo/Mais; barras a esconder ao rolar; botão do menu inicial desenhado pela página na barra de cima; painel «Você»; Inscrições; pesquisa (com saída garantida pelo botão de voltar); Shorts na vertical em alta definição.
- Mini leitor: só pausar e fechar; anima a partir do vídeo; pode ser lançado; ligeiro zoom.
- Página do vídeo: barra de baixo em vez do «Abrir ajustes»; some ao rolar para baixo; «início» encolhe o vídeo sem levar a página ao topo.
- Ajustes: separadores Tom/Treino/Áudio/Mais; tom com o nome da nota; tema novo «Apple» (folha de vidro flutuante com pega e três alturas), escolhível em Mais → Aparência.
- iPhone: barra de baixo em vidro nativo do iOS 26 (`UIGlassEffect`), que o dono testou e pediu mais pequena e escurecida (feito).
- Android: botões na janela pequena do sistema (recuar, pausar, avançar); widgets novos (pesquisa e «a tocar»).
- YouTube Music: primeira parte (sem «Abrir o app», botão de início na barra de cima, barra de baixo própria, esconder ao rolar).
- Teste intermitente `web_media_command_test`: causa real encontrada e corrigida.

## O que falta, por ordem do que o dono pediu por último

1. **Janela pequena fora da app no iPhone (pedido em aberto, aprovado para avançar).** Hoje não existe: ao sair da app só o som continua. O dono quer a janela do sistema, com botões redondos, recuar/avançar 10 s, pausar e barra de tempo. Plano combinado com ele: a página copia imagens do vídeo para um `canvas`, envia-as à parte nativa pela extensão que já existe, e a parte nativa mostra-as numa `AVSampleBufferDisplayLayer` com `AVPictureInPictureController` (fonte de conteúdo por amostras, com o delegado de reprodução para pausar e saltar). Atrás de um interruptor «Janela pequena, experimental» em Ajustes → Mais, desligado de origem. Incertezas ditas ao dono: se o motor continua a produzir imagens em segundo plano, e a fluidez; contar com duas a quatro voltas de IPA. Nada disto foi começado.
2. YouTube Music: separadores do topo, painel de perfil, pesquisa, barra de vidro no iPhone; trocar de página pela barra recarrega a página.
3. Ajustes: «Cifra» separada de «Tom»; barra de tempo única no fundo da folha; folha com o vidro nativo no iPhone.
4. Página do vídeo ao estilo da app (falta uma captura de referência do dono).
5. iPhone: ecrã preto e instantes com o aspeto antigo ao carregar (aplicar o estilo mais cedo).
6. Widget de pesquisa: abrir já com o teclado.
7. «O vídeo para quando escrevo na pesquisa»: no A16 não se reproduz; por saber se é só no iPhone.

## Por confirmar pelo dono (só visto por capturas, ou nem isso)

Animação do mini leitor; pega e alturas da folha no tema Apple; encolher com os ajustes abertos; janela pequena do Android com os botões novos (nunca vista num telemóvel); widgets no ecrã inicial; quase tudo no iPhone.

## Limites conhecidos

- O site móvel do YouTube não tem mensagens, notificações nem o «+» de criar.
- Todo o estilo depende dos nomes internos do site; uma mudança do YouTube pode desfazer partes sem aviso.
- A distorção verdadeira do vidro só existe onde é o sistema a desenhar (barra de baixo do iPhone); o resto é simulado.

## Regras do dono

Escrever-lhe em português europeu simples. Nada é instalado num telemóvel sem ordem dele; nunca desinstalar nem apagar dados. Apagar só para a Reciclagem. Entregas (IPA, APK) em `Downloads\Transpono`, nunca no Desktop. Não tocar em `C:\Yunex-Radar`, `C:\YunexSombra` nem `C:\Transpose`. Sem segredos no Git.
