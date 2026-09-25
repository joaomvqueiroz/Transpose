part of 'studio_visual_app.dart';

class _StudioVisualHomeState extends State<StudioVisualHome>
    with WidgetsBindingObserver {
  late final MainPlayerController _player =
      widget.playerController ??
      MainPlayerController(youtubeFactory: widget.youtubeSessionFactory);
  late final PlayerPresetStore _presets =
      widget.presetStore ?? PlayerPresetStore();
  late final PracticeController _practice = PracticeController(_player);
  final ChordSheetStore _chords = ChordSheetStore();
  int _collectionsRevision = 0;
  String? _selectedPresetId;
  late final SessionRecoveryController? _recovery =
      widget.recoveryRepository == null
      ? null
      : SessionRecoveryController(
          player: _player,
          repository: widget.recoveryRepository!,
          presentation: () => SessionPresentation(
            screen: _tab.name,
            fullscreen: _fullscreen,
            activePresetId: _selectedPresetId,
            practice: _practice.snapshot,
            settled: !_practice.busy,
          ),
          onRestored: (snapshot) {
            if (!mounted) return;
            _practice.restore(snapshot.practice);
            setState(() {
              _tab = StudioTab.values.firstWhere(
                (tab) => tab.name == snapshot.screen,
                orElse: () => StudioTab.player,
              );
              _selectedPresetId = snapshot.activePresetId;
              // Restore a useful screen, not an immersive lock or playback.
              _fullscreen = false;
              _browsing = false;
            });
          },
        );
  final TextEditingController _query = TextEditingController();
  final GlobalKey _mediaKey = GlobalKey(debugLabel: 'shared-player-surface');
  final ScrollController _scroll = ScrollController();
  StudioTab _tab = StudioTab.player;
  bool _browsing = false, _fullscreen = false;
  YouTubeBrowserSession? _browserOwner;
  Widget? _browser;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _player.addListener(_changed);
    // Observe loop events before recovery captures progress at the same tick.
    _practice.addListener(_practiceChanged);
    _recovery?.addListener(_changed);
    unawaited(_recovery?.initialize());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _practiceChanged() {
    _changed();
    _recovery?.presentationChanged();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      // The OS need not await us; periodic saves are the crash fallback.
      unawaited(_recovery?.flush());
      unawaited(
        _practice.pause().whenComplete(() async {
          await _recovery?.flush();
        }),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _player.removeListener(_changed);
    _recovery?.removeListener(_changed);
    unawaited(_recovery?.close());
    _practice.removeListener(_practiceChanged);
    _practice.dispose();
    if (widget.playerController == null) _player.dispose();
    _query.dispose();
    _scroll.dispose();
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _select(StudioTab tab) {
    setState(() {
      _tab = tab;
      _browsing = false;
    });
    _recovery?.presentationChanged();
  }

  Future<void> _openYouTubeSearch() async {
    await _recovery?.flush();
    if (!mounted) return;
    _recovery?.beginUserSource();
    setState(() {
      _tab = StudioTab.player;
      _browsing = true;
    });
    await _player.openYouTube();
  }

  Future<void> _search() async {
    if (_query.text.trim().isEmpty) return;
    FocusScope.of(context).unfocus();
    await _recovery?.flush();
    if (!mounted) return;
    _recovery?.beginUserSource();
    await _player.search(_query.text);
  }

  Future<void> _useVideo() async {
    FocusScope.of(context).unfocus();
    final session = _player.youtube;
    setState(() => _browsing = false);
    // Focus in the final viewport, not while a smooth scroll is still running
    // against the full-width search page that is about to be resized.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || _browsing || !identical(session, _player.youtube)) return;
    if (_scroll.hasClients) _scroll.jumpTo(0);
    try {
      await session?.focusVideo();
    } on Object {
      // A page navigation may replace the JS document while scrolling. The
      // selected controller still belongs to this same player surface.
    }
  }

  Future<void> _pickFile() async {
    await _recovery?.flush();
    if (!mounted) return;
    _recovery?.beginUserSource();
    await _player.pickFile();
    if (mounted && !_player.isYouTube) {
      setState(() {
        _browsing = false;
        _tab = StudioTab.player;
      });
    }
  }

  void _openFullscreen() {
    setState(() => _fullscreen = true);
    _recovery?.presentationChanged();
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
  }

  void _exitFullscreen() {
    setState(() => _fullscreen = false);
    _recovery?.presentationChanged();
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
  }

  Widget _mediaSurface() {
    final session = _player.youtube;
    if (session != null && !identical(session, _browserOwner)) {
      _browserOwner = session;
      _browser = session.buildView();
    }
    final video = _player.local.videoController;
    return KeyedSubtree(
      key: _mediaKey,
      child: _player.isYouTube || _browsing
          ? _browser ?? const Center(child: CircularProgressIndicator())
          : video != null && video.value.isInitialized
          ? ColoredBox(
              color: Colors.black,
              child: Center(
                child: AspectRatio(
                  aspectRatio: video.value.aspectRatio > 0
                      ? video.value.aspectRatio
                      : 16 / 9,
                  child: VideoPlayer(video),
                ),
              ),
            )
          : ColoredBox(
              color: studioCardAlt,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      _player.loaded
                          ? Icons.graphic_eq
                          : Icons.library_music_outlined,
                      size: 54,
                      color: studioCyan,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _player.loaded ? 'Áudio local' : 'Escolha a sua música',
                      style: const TextStyle(color: studioMuted),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  void _openMore() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _menuItem(
                sheet,
                Icons.search,
                'Pesquisar no YouTube',
                _openYouTubeSearch,
              ),
              _menuItem(
                sheet,
                Icons.folder_open,
                'Abrir ficheiro local',
                _pickFile,
              ),
              _menuItem(
                sheet,
                Icons.audio_file_outlined,
                'Carregar áudio de demonstração',
                () async {
                  await _recovery?.flush();
                  if (!mounted) return;
                  _recovery?.beginUserSource();
                  await _player.loadSample();
                  if (mounted) {
                    setState(() {
                      _tab = StudioTab.player;
                      _browsing = false;
                    });
                  }
                },
              ),
              _menuItem(
                sheet,
                Icons.bookmark_add_outlined,
                'Guardar predefinição',
                () => _save(),
              ),
              _menuItem(
                sheet,
                Icons.queue_music,
                'Adicionar à setlist',
                () => _save(setlist: true),
              ),
              _menuItem(
                sheet,
                Icons.bookmarks_outlined,
                'Predefinições guardadas',
                () => _saved(),
              ),
              _menuItem(
                sheet,
                Icons.list_alt,
                'Minha setlist',
                () => _saved(setlist: true),
              ),
              _menuItem(sheet, Icons.fullscreen, 'Tela cheia', _openFullscreen),
              _menuItem(
                sheet,
                Icons.tune,
                'Mais ferramentas de áudio',
                _advanced,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuItem(
    BuildContext sheet,
    IconData icon,
    String title,
    VoidCallback action,
  ) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    onTap: () {
      Navigator.pop(sheet);
      action();
    },
  );

  Future<void> _save({bool setlist = false}) async {
    if (!_player.loaded) {
      _notice('Escolha uma música primeiro.');
      return;
    }
    // Capture before opening the dialog: a changing YouTube page cannot silently
    // save a different song under the name the user is currently typing.
    final captured = _player.snapshot(_player.title);
    if (captured == null) {
      _notice('Aguarde a conclusão do ajuste atual.');
      return;
    }
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _PresetNameDialog(
        initialName: _player.title,
        title: setlist ? 'Adicionar à setlist' : 'Guardar predefinição',
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    final preset = PlayerPreset(
      id: captured.id,
      name: name.trim(),
      title: captured.title,
      sourceId: captured.sourceId,
      locator: captured.locator,
      youtube: captured.youtube,
      pitch: captured.pitch,
      speed: captured.speed,
      positionMs: captured.positionMs,
      aMs: captured.aMs,
      bMs: captured.bMs,
      loop: captured.loop,
    );
    try {
      await _presets.save(preset, setlist: setlist);
      if (mounted) setState(() => _collectionsRevision++);
      _notice(
        setlist
            ? 'Música adicionada à setlist neste dispositivo.'
            : 'Tom, velocidade e A/B guardados neste dispositivo.',
      );
    } on Object {
      _notice('Não foi possível guardar. Os ajustes atuais continuam ativos.');
    }
  }

  Future<bool> _applyPreset(
    PlayerPreset preset, {
    bool returnToPlayer = false,
  }) async {
    await _recovery?.flush();
    if (!mounted) return false;
    _recovery?.beginUserSource();
    if (returnToPlayer) {
      setState(() {
        _tab = StudioTab.player;
        _browsing = false;
      });
    }
    await _player.restore(preset);
    if (!mounted) return false;
    if (_player.isYouTube) {
      try {
        await _player.youtube?.focusVideo();
      } on Object {
        /* Page may change while restoring. */
      }
    }
    if (_player.lastRestoreSucceeded) {
      if (!mounted) return false;
      setState(() => _selectedPresetId = preset.id);
      _recovery?.presentationChanged();
    }
    return _player.lastRestoreSucceeded;
  }

  Future<void> _saved({bool setlist = false}) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PlayerCollectionsPage(
          store: _presets,
          setlist: setlist,
          onApply: (preset) async {
            final restored = await _applyPreset(preset, returnToPlayer: true);
            if (!restored) {
              throw StateError(
                _player.message ?? 'Não foi possível preparar esta música.',
              );
            }
          },
        ),
      ),
    );
    if (mounted) setState(() => _collectionsRevision++);
  }

  Future<void> _tool(String tool) async {
    switch (tool) {
      case 'save':
        await _save();
      case 'advanced':
        _advanced();
      default:
        if (tool == 'tuner') await _player.pause();
        if (!mounted) return;
        await showStudyTool(context, tool: tool, pitch: _player.pitch);
    }
  }

  void _advanced() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Expanded(
                      child: Text(
                        'Configurações de áudio',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Fechar configurações de áudio',
                      onPressed: () => Navigator.pop(sheet),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('Mixagem de canais (stems)'),
                const SizedBox(height: 8),
                const Text(
                  'Voz, guitarra, baixo e bateria exigem faixas separadas. A separação automática ainda não está implementada.',
                  style: TextStyle(color: studioMuted),
                ),
                const SizedBox(height: 12),
                const Wrap(
                  spacing: 8,
                  children: <Widget>[
                    Chip(label: Text('Voz · indisponível')),
                    Chip(label: Text('Guitarra · indisponível')),
                    Chip(label: Text('Baixo · indisponível')),
                    Chip(label: Text('Bateria · indisponível')),
                  ],
                ),
                const Divider(height: 28),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.restore),
                  title: const Text('Repor tom, velocidade e loop'),
                  subtitle: const Text('0 st · 1,00× · sem A/B'),
                  enabled: _player.loaded,
                  onTap: _player.loaded
                      ? () {
                          Navigator.pop(sheet);
                          unawaited(_player.resetProcessing());
                        }
                      : null,
                ),
                const Text(
                  'No YouTube, o tom é experimental e o loop é aproximado. Ficheiros de vídeo locais ainda não suportam alteração de tom.',
                  style: TextStyle(color: studioMuted, fontSize: 12),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(sheet),
                    child: const Text('Concluir'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openSidebar() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                title: const Text(
                  'Transpono',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                trailing: IconButton(
                  key: const Key('visualSidebarClose'),
                  tooltip: 'Fechar menu',
                  onPressed: () => Navigator.pop(sheet),
                  icon: const Icon(Icons.close),
                ),
              ),
              _menuItem(
                sheet,
                Icons.play_circle_outline,
                'Em reprodução',
                () => _select(StudioTab.player),
              ),
              _menuItem(
                sheet,
                Icons.folder_open,
                'Abrir ficheiro local',
                _pickFile,
              ),
              _menuItem(
                sheet,
                Icons.bookmarks_outlined,
                'Predefinições e loops guardados',
                () => _saved(),
              ),
              _menuItem(
                sheet,
                Icons.queue_music,
                'Minha setlist',
                () => _saved(setlist: true),
              ),
              _menuItem(
                sheet,
                Icons.timer_outlined,
                'Metrônomo',
                () => _tool('metronome'),
              ),
              _menuItem(
                sheet,
                Icons.tune,
                'Afinador por referência',
                () => _tool('tuner'),
              ),
              _menuItem(
                sheet,
                Icons.music_note,
                'Transpor cifras',
                () => _tool('chords'),
              ),
              _menuItem(
                sheet,
                Icons.settings,
                'Configurações de áudio',
                _advanced,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _browserPage(Widget media) {
    final session = _player.youtube;
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            IconButton(
              key: const Key('youtubeClose'),
              tooltip: 'Voltar ao player',
              onPressed: () {
                unawaited(_player.pause());
                setState(() => _browsing = false);
              },
              icon: const Icon(Icons.close),
            ),
            const Expanded(
              child: Text(
                'YouTube · Transpono',
                style: TextStyle(fontSize: 18),
              ),
            ),
            IconButton(
              tooltip: 'Página anterior',
              onPressed: session?.canGoBack == true
                  ? () => _browserAction(session!.goBack)
                  : null,
              icon: const Icon(Icons.arrow_back),
            ),
            IconButton(
              key: const Key('youtubeReload'),
              tooltip: 'Atualizar',
              onPressed: session == null
                  ? _openYouTubeSearch
                  : () => _browserAction(session.reload),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: TextField(
            key: const Key('youtubeSearchInput'),
            controller: _query,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              hintText: 'Pesquisar música ou artista',
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              suffixIcon: IconButton(
                key: const Key('youtubeSearchSubmit'),
                tooltip: 'Pesquisar',
                onPressed: _search,
                icon: const Icon(Icons.search),
              ),
            ),
          ),
        ),
        if (session != null && session.progress < 100)
          LinearProgressIndicator(value: session.progress / 100),
        if (_player.message != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(_player.message!),
          ),
        Expanded(
          child: SizedBox(
            key: const Key('youtubeBrowserViewport'),
            child: media,
          ),
        ),
        if (_player.isYouTube &&
            _player.loaded &&
            MediaQuery.viewInsetsOf(context).bottom == 0)
          Padding(
            padding: const EdgeInsets.all(10),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('youtubeUseInPlayer'),
                onPressed: _useVideo,
                icon: const Icon(Icons.tune),
                label: const Text('Usar este vídeo no player'),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _browserAction(Future<void> Function() action) async {
    try {
      await action();
    } on Object {
      _notice('Não foi possível carregar a página. Tente novamente.');
    }
  }

  Widget _mainPanel(Widget media) {
    Widget controls({required bool showMedia}) => SingleChildScrollView(
      key: const Key('visualScrollplayer'),
      controller: _scroll,
      child: MainPlayerPanel(
        model: _player,
        media: media,
        showMedia: showMedia,
        onFullscreen: _openFullscreen,
        onSearch: _openYouTubeSearch,
        onOpenFile: _pickFile,
        onTool: _tool,
      ),
    );
    if (!_player.isYouTube) return controls(showMedia: true);
    return _withPinnedMedia(media, controls(showMedia: false));
  }

  Widget _secondaryPanel(Widget media) {
    final controls = switch (_tab) {
      StudioTab.practice => SingleChildScrollView(
        key: const Key('visualScrollpractice'),
        child: PracticePanel(
          model: _player,
          practiceController: _practice,
          onOpenPlayer: () => _select(StudioTab.player),
          onSaveLoop: () => _save(),
          onOpenLoops: () => _saved(),
          onMetronome: () => _tool('metronome'),
        ),
      ),
      StudioTab.chords => ChordsPanel(
        model: _player,
        sourceKey: _player.sourceKey,
        store: _chords,
        onOpenPlayer: () => _select(StudioTab.player),
      ),
      StudioTab.stage => StagePanel(
        model: _player,
        store: _presets,
        sourceKey: _player.sourceKey,
        revision: _collectionsRevision,
        selectedPresetId: _selectedPresetId,
        onApply: _applyPreset,
        onCollections: () => _saved(setlist: true),
        onAdd: () => _save(setlist: true),
        onTool: _tool,
      ),
      StudioTab.player => const SizedBox.shrink(),
    };
    return _player.isYouTube || _player.local.videoController != null
        ? _withPinnedMedia(media, controls)
        : controls;
  }

  Widget _withPinnedMedia(Widget media, Widget controls) {
    // A WebView scrolled fully offscreen can pause its media even while the
    // Flutter route remains visible. Keep YouTube visible instead of defeating
    // the browser's visibility policy or secretly forcing playback to resume.
    return LayoutBuilder(
      builder: (_, box) {
        final surface = Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: media,
          ),
        );
        if (box.maxWidth >= 600 && box.maxWidth > box.maxHeight) {
          return Row(
            children: <Widget>[
              // The mobile watch page reserves horizontal space in landscape.
              // A half-width viewport can reduce its actual video to a tiny
              // thumbnail; give the visible browser room without altering its DOM.
              Expanded(flex: 2, child: surface),
              Expanded(child: controls),
            ],
          );
        }
        final height = ((box.maxWidth - 32) * 9 / 16 + 104).clamp(
          0.0,
          box.maxHeight * .52,
        );
        return Column(
          children: <Widget>[
            SizedBox(
              key: const Key('pinnedYouTubeMedia'),
              height: height,
              child: surface,
            ),
            Expanded(child: controls),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = _mediaSurface();
    return PopScope(
      canPop: !_fullscreen && !_browsing,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_fullscreen) {
          _exitFullscreen();
        } else {
          unawaited(_player.pause());
          setState(() => _browsing = false);
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: _fullscreen
              ? MainPlayerFullscreen(
                  model: _player,
                  media: media,
                  onExit: _exitFullscreen,
                  onTool: _tool,
                )
              : _browsing
              ? _browserPage(media)
              : Column(
                  children: <Widget>[
                    _recoveryBanner(),
                    SizedBox(
                      height: 57,
                      child: Row(
                        children: [
                          IconButton(
                            key: const Key('visualPlayerMenu'),
                            tooltip: 'Menu',
                            onPressed: _openSidebar,
                            icon: const Icon(Icons.menu),
                          ),
                          Expanded(
                            child: Text(
                              switch (_tab) {
                                StudioTab.player => 'Transpono',
                                StudioTab.practice => 'Prática',
                                StudioTab.chords => 'Acordes',
                                StudioTab.stage => 'Palco',
                              },
                              style: const TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          IconButton(
                            key: const Key('visualPlayerSearch'),
                            tooltip: 'Pesquisar no YouTube',
                            onPressed: _openYouTubeSearch,
                            icon: const Icon(Icons.search),
                          ),
                          IconButton(
                            key: const Key('visualPlayerMore'),
                            tooltip: 'Mais opções',
                            onPressed: _openMore,
                            icon: const Icon(Icons.more_vert),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _tab == StudioTab.player
                          ? _mainPanel(media)
                          : _secondaryPanel(media),
                    ),
                    _BottomTabs(selected: _tab, onSelect: _select),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _recoveryBanner() {
    final recovery = _recovery;
    final message = recovery?.message;
    if (recovery == null || message == null) return const SizedBox.shrink();
    final waiting = recovery.initializing || recovery.restoring;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .28,
      ),
      child: SingleChildScrollView(
        child: Material(
          color: studioCardAlt,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        message,
                        key: const Key('recoveryStatus'),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    if (recovery.canDismiss)
                      IconButton(
                        key: const Key('recoveryDismiss'),
                        tooltip: waiting
                            ? 'Cancelar recuperação'
                            : 'Fechar aviso',
                        onPressed: recovery.dismissNotice,
                        icon: const Icon(Icons.close, size: 20),
                      ),
                  ],
                ),
                if (waiting) const LinearProgressIndicator(minHeight: 2),
                if (!waiting &&
                    (recovery.pending != null ||
                        (recovery.saveFailed && !recovery.writeBlocked)))
                  Wrap(
                    spacing: 8,
                    children: [
                      if (recovery.pending != null)
                        TextButton.icon(
                          key: const Key('recoveryRestore'),
                          onPressed: recovery.restorePending,
                          icon: const Icon(Icons.restore),
                          label: Text(
                            recovery.pending!.media.youtube
                                ? 'Restaurar vídeo'
                                : 'Tentar novamente',
                          ),
                        ),
                      if (recovery.pending != null &&
                          !recovery.pending!.media.youtube)
                        TextButton(
                          key: const Key('recoveryOpenFile'),
                          onPressed: _pickFile,
                          child: const Text('Escolher ficheiro'),
                        ),
                      if (recovery.canUseCurrent)
                        TextButton(
                          key: const Key('recoveryUseCurrent'),
                          onPressed: recovery.useCurrentSession,
                          child: const Text('Usar sessão atual'),
                        ),
                      if (recovery.saveFailed && !recovery.writeBlocked)
                        TextButton(
                          key: const Key('recoveryRetrySave'),
                          onPressed: recovery.retrySave,
                          child: const Text('Tentar guardar'),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PresetNameDialog extends StatefulWidget {
  const _PresetNameDialog({required this.initialName, required this.title});
  final String initialName, title;
  @override
  State<_PresetNameDialog> createState() => _PresetNameDialogState();
}

class _PresetNameDialogState extends State<_PresetNameDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      key: const Key('presetName'),
      controller: _name,
      autofocus: true,
      maxLength: 100,
      decoration: const InputDecoration(labelText: 'Nome'),
      onSubmitted: (v) {
        if (v.trim().isNotEmpty) Navigator.pop(context, v);
      },
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        key: const Key('presetSave'),
        onPressed: () {
          if (_name.text.trim().isNotEmpty) Navigator.pop(context, _name.text);
        },
        child: const Text('Guardar'),
      ),
    ],
  );
}
