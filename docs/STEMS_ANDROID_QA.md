# N3 Android stems — estado da prova

O motor de seis instrumentos corre no processo Android da app, sem enviar áudio
para PC ou servidor. O utilizador escolhe um WAV local com autorização, e a app
faz uma cópia no seu cache privado. O único download é o modelo fixado a uma
revisão do dataset, com tamanho e SHA-256 obrigatórios. O original selecionado
não é alterado.

Limites da entrada: WAV PCM16 mono/estéreo a 44,1 kHz, 1 s–10 min e até 64 MB.
A app verifica RAM e espaço livre antes da inferência. A prova nativa isolada
de 2 s ainda não representa a memória total da app com interface/WebView.

QA no Samsung SM-A165F com pacote isolado `com.example.transpose_mobile.qa`:
o canal JNI carregou e rejeitou uma origem fora do cache privado. O modelo
fixado foi descarregado/verificado. Um tom sintético de 1 s em processo fresco
passou por inferência real, produziu seis WAVs com duração correta e amostras
não nulas. A prova inicial silêncio→tom criou seis WAVs de silêncio, mas o tom
seguinte foi bloqueado pela guarda de 1 GiB acima do limiar Android antes da
correção lazy/purge. Uma prova `profile` com a correção também foi bloqueada
pela guarda antes de iniciar o silêncio: 1.173.913.600 bytes disponíveis,
134.170.624 bytes de limiar Android, margem abaixo de 1 GiB. A sequência
consecutiva e o cancelamento durante inferência permanecem sem validação no
aparelho. A simulação de lifecycle Flutter não prova
recriação real da Activity Android. A medição `dumpsys` durante o tom mostrou
RSS aproximado de 709,519 kB num instante; não é o pico nem inclui WebView
ativa do ecrã principal.

`flutter analyze` passou e `flutter test` concluiu 363 testes. O APK Dev
release com o motor real foi instalado e abriu em `com.example.transpose_mobile.dev`
no Samsung original; a app de produção não foi substituída. Identidade e
assinatura foram verificadas antes de instalar. O processo Dev em arranque frio
tinha aproximadamente 419.718 kB RSS e 316.367 kB PSS, sem inferência.

Cada separação concluída cria seis WAVs na pasta privada `files/stem_outputs`
e atualiza `files/stems/last_result.json`. A app restaura e mostra apenas o
último conjunto concluído. Conjuntos concluídos anteriores continuam no espaço
privado e ocupam armazenamento; ainda não há histórico nem gestão desses
ficheiros na interface. Saídas parciais de falhas/cancelamento são removidas.
A separação é cancelada quando a app sai do primeiro plano; o painel avisa para
manter a app aberta durante o processamento.
As cópias de entrada em `cache/stem_inputs` são temporárias, mas a versão atual
não as elimina logo após uma separação; Android pode limpar o cache. Esta
limitação deve ser resolvida antes de distribuição ampla.

Avisos de licença incluídos no APK em `assets/stems_licenses`: demucs.cpp MIT,
Eigen MPL 2.0/BSD e proveniência do modelo.
