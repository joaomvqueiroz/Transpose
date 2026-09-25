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
  bool _chordActive = false;
  bool _videoPinned = false;
  bool _mainControlsExpanded = false;
  bool _mainSettingsOpen = false;
  String _chordSource = '';
  int _chordRevision = 0;
  bool _choosingChord = false;
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
    unawaited(_initializeStartPage());
  }

  Future<void> _initializeStartPage() async {
    await _recovery?.initialize();
    final pending = _recovery?.pending;
    if (!mounted ||
        !widget.openSearchWhenEmpty ||
        _player.loaded ||
        _player.local.loaded ||
        (pending != null && !pending.media.youtube)) {
      return;
    }
    setState(() => _browsing = true);
    await _player.openYouTube();
    if (mounted && _player.youtube == null) {
      setState(() => _browsing = false);
    }
  }

  void _changed() {
    if (_chordSource != _player.sourceKey) {
      _chordSource = _player.sourceKey;
      _chordRevision++;
      _chordActive = false;
      _mainControlsExpanded = false;
      _mainSettingsOpen = false;
    }
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
      _mainSettingsOpen = false;
    });
    _recovery?.presentationChanged();
  }

  void _toggleMainAdjustments() {
    setState(() {
      if (_chordActive) {
        _mainSettingsOpen = !_mainSettingsOpen;
      } else {
        _mainControlsExpanded = !_mainControlsExpanded;
      }
    });
    if (_scroll.hasClients && _scroll.offset > 0) _scroll.jumpTo(0);
  }

  bool _onMainPlayerScroll(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification &&
        notification.depth == 0 &&
        notification.dragDetails != null &&
        (notification.scrollDelta ?? 0) > 0 &&
        _chordActive &&
        _mainSettingsOpen) {
      // Reading the chord sheet must not leave transport and pitch controls
      // pinned over the video. Keep the video pin state; only close Ajustes.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _chordActive && _mainSettingsOpen) {
          setState(() => _mainSettingsOpen = false);
        }
      });
    }
    return false;
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

  Future<void> _toggleChord() async {
    if (_choosingChord) return;
    if (_chordActive) {
      setState(() {
        _chordActive = false;
        _mainSettingsOpen = false;
        _mainControlsExpanded = false;
      });
      return;
    }
    final source = _player.sourceKey;
    final revision = _chordRevision;
    try {
      final sheet = source.isEmpty
          ? _chords.temporarySheet
          : await _chords.read(source);
      if (!mounted || revision != _chordRevision) return;
      if (sheet.notes.trim().isNotEmpty) {
        setState(() {
          _chordActive = true;
          _mainSettingsOpen = false;
          _mainControlsExpanded = false;
        });
      } else {
        await _searchChord();
      }
    } on Object {
      _notice(
        'Não foi possível ler a cifra guardada. Os dados foram preservados.',
      );
    }
  }

  Future<void> _searchChord() async {
    if (_choosingChord) return;
    _choosingChord = true;
    final source = _player.sourceKey;
    final revision = _chordRevision;
    try {
      // Browsing a second website must not start a second audible source.
      await _player.pause();
      if (!mounted || revision != _chordRevision) return;
      final selected = await Navigator.of(context).push<ImportedChord>(
        MaterialPageRoute(
          builder: (_) => ChordBrowserPage(
            initialQuery: _player.loaded ? _player.title : '',
            sessionFactory: widget.chordBrowserFactory,
          ),
        ),
      );
      if (!mounted || selected == null) return;
      if (revision != _chordRevision || source != _player.sourceKey) {
        _notice(
          'A música mudou. Escolha a cifra novamente para a fonte atual.',
        );
        return;
      }
      final latest = source.isEmpty
          ? _chords.temporarySheet
          : await _chords.read(source);
      if (!mounted || revision != _chordRevision) return;
      final sheet = latest.copyWith(
        notes: selected.text,
        sourceTitle: selected.title,
        sourceUrl: selected.url.toString(),
        transpose: 0,
        followAudio: true,
      );
      if (source.isEmpty) {
        _chords.temporarySheet = sheet;
      } else {
        await _chords.save(source, sheet);
      }
      if (!mounted || revision != _chordRevision) return;
      setState(() {
        _chordActive = true;
        _chordRevision++;
      });
    } on Object {
      if (mounted) {
        _notice(
          'Não foi possível guardar a cifra. A cifra anterior foi mantida.',
        );
      }
    } finally {
      _choosingChord = false;
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
    VoidCallback action, {
    Key? key,
  }) => ListTile(
    key: key,
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
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .85,
      ),
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
                'Player',
                () => _select(StudioTab.player),
                key: const Key('visualTabplayer'),
              ),
              _menuItem(sheet, Icons.fullscreen, 'Tela cheia', _openFullscreen),
              _menuItem(
                sheet,
                Icons.graphic_eq,
                'Prática',
                () => _select(StudioTab.practice),
                key: const Key('visualTabpractice'),
              ),
              _menuItem(
                sheet,
                Icons.music_note,
                'Acordes',
                () => _select(StudioTab.chords),
                key: const Key('visualTabchords'),
              ),
              _menuItem(
                sheet,
                Icons.tune,
                'Palco',
                () => _select(StudioTab.stage),
                key: const Key('visualTabstage'),
              ),
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
                Icons.bookmark_add_outlined,
                'Guardar predefinição',
                () => _save(),
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
        if (_recovery?.pending?.media.youtube == true) _recoveryBanner(),
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
            autofocus: true,
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
    final controls = MainPlayerPanel(
      model: _player,
      sourceKey: _player.sourceKey,
      chordStore: _chords,
      chordActive: _chordActive,
      onChordToggle: _toggleChord,
      onChordSearch: _searchChord,
      chordRevision: _chordRevision,
      controlsExpanded: false,
      onControlsToggle: _toggleMainAdjustments,
      showControlsToggle: false,
      showTip: false,
      showSourceButtons: false,
      showMessage: false,
      media: media,
      showMedia: false,
      mediaExtraHeight: _player.isYouTube ? 48 : 0,
      videoPinned: _videoPinned,
      onPinToggle: () => setState(() => _videoPinned = !_videoPinned),
      onFullscreen: _openFullscreen,
      onSearch: _openYouTubeSearch,
      onOpenFile: _pickFile,
      onTool: _tool,
    );
    return LayoutBuilder(
      builder: (_, box) {
        final surface = MainPlayerFullscreen(
          model: _player,
          media: media,
          mainMode: true,
          showHeader: false,
          controlsOpen: _chordActive
              ? _mainSettingsOpen
              : _mainControlsExpanded,
          onExit: _openSidebar,
          onTool: _tool,
          videoPinned: _videoPinned,
          onPinToggle: () => setState(() => _videoPinned = !_videoPinned),
          onOpenFile: _pickFile,
          onChordToggle: _toggleChord,
          onSearch: _openYouTubeSearch,
          chordActive: _chordActive,
          youtubeNativeTransport: _player.isYouTube,
          onNativeMediaTouch: _player.isYouTube
              ? _player.noteNativeVideoTouch
              : null,
        );
        final height = _player.isYouTube
            ? box.maxHeight * (_chordActive ? .72 : 1.0)
            : (box.maxWidth * 9 / 16).clamp(0.0, box.maxHeight * .72);
        if (!_videoPinned) {
          return NotificationListener<ScrollNotification>(
            onNotification: _onMainPlayerScroll,
            child: SingleChildScrollView(
              key: const Key('visualScrollplayer'),
              controller: _scroll,
              child: Column(
                children: [
                  _playerPageHeader(),
                  SizedBox(height: height, child: surface),
                  if (_chordActive) controls,
                ],
              ),
            ),
          );
        }
        return NotificationListener<ScrollNotification>(
          onNotification: _onMainPlayerScroll,
          child: CustomScrollView(
            key: const Key('visualScrollplayer'),
            controller: _scroll,
            slivers: [
              SliverToBoxAdapter(child: _playerPageHeader()),
              SliverPersistentHeader(
                pinned: true,
                delegate: _PlayerVideoHeader(
                  height: height,
                  child: SizedBox(
                    key: const Key('pinnedPlayerMedia'),
                    child: surface,
                  ),
                ),
              ),
              if (_chordActive) SliverToBoxAdapter(child: controls),
            ],
          ),
        );
      },
    );
  }

  Widget _playerPageHeader() => _recoveryBanner();

  Widget _header() => ColoredBox(
    color: _tab == StudioTab.player ? const Color(0xDF040F1C) : studioBg,
    child: SizedBox(
      key: const Key('visualPlayerHeader'),
      height: 57,
      child: Row(
        children: [
          IconButton(
            key: const Key('visualPlayerMenu'),
            tooltip: 'Menu lateral',
            onPressed: _openSidebar,
            icon: const Icon(Icons.menu),
          ),
          Expanded(
            child: Text(
              switch (_tab) {
                StudioTab.player =>
                  _player.loaded && _player.title.isNotEmpty
                      ? _player.title
                      : 'Transpono',
                StudioTab.practice => 'Prática',
                StudioTab.chords => 'Acordes',
                StudioTab.stage => 'Palco',
              },
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: _tab == StudioTab.player ? 17 : 21,
                fontWeight: _tab == StudioTab.player
                    ? FontWeight.w500
                    : FontWeight.w800,
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
  );

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
        final height = ((box.maxWidth - 32) * 9 / 16 + 48).clamp(
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
                  youtubeNativeTransport: _player.isYouTube,
                  onNativeMediaTouch: _player.isYouTube
                      ? _player.noteNativeVideoTouch
                      : null,
                )
              : _browsing
              ? _browserPage(media)
              : Stack(
                  children: <Widget>[
                    Column(
                      children: <Widget>[
                        if (_tab != StudioTab.player) _header(),
                        if (_tab != StudioTab.player) _recoveryBanner(),
                        Expanded(
                          child: _tab == StudioTab.player
                              ? _mainPanel(media)
                              : _secondaryPanel(media),
                        ),
                      ],
                    ),
                    if (_tab == StudioTab.player)
                      Positioned(
                        bottom: 8,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: _MainAdjustmentsBar(
                            expanded: _chordActive
                                ? _mainSettingsOpen
                                : _mainControlsExpanded,
                            onPressed: _toggleMainAdjustments,
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _recoveryBanner() {
    final recovery = _recovery;
    if (recovery == null) return const SizedBox.shrink();
    final waiting = recovery.initializing || recovery.restoring;
    if (!waiting && recovery.pending?.media.youtube == true) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const Key('recoveryRestore'),
          onPressed: () async {
            await recovery.restorePending();
            if (mounted && recovery.pending?.media.youtube == true) {
              final error = recovery.message;
              if (error != null && error.isNotEmpty) _notice(error);
            }
          },
          icon: const Icon(Icons.restore),
          label: const Text('Restaurar vídeo'),
        ),
      );
    }
    final message = recovery.message;
    if (message == null) return const SizedBox.shrink();
    if (recovery.pending == null && message.startsWith('Sessão recuperada')) {
      return const SizedBox.shrink();
    }
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

class _PlayerVideoHeader extends SliverPersistentHeaderDelegate {
  _PlayerVideoHeader({required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => ColoredBox(color: studioBg, child: child);
  @override
  bool shouldRebuild(_PlayerVideoHeader oldDelegate) =>
      height != oldDelegate.height || child != oldDelegate.child;
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
