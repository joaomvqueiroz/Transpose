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
  final GlobalKey _mediaKey = GlobalKey(debugLabel: 'shared-player-surface');
  final GlobalKey<PlayerChordSheetState> _unifiedChordKey = GlobalKey();
  final ScrollController _scroll = ScrollController();
  final ScrollController _tabsScroll = ScrollController();
  ScrollController? _chordTextScroll;
  Timer? _chordAutoTimer;
  bool _chordAutoScroll = false;
  double _chordScrollSpeed = 1;
  StudioTab _tab = StudioTab.player;
  bool _browsing = false;
  bool _chordActive = false;
  bool _mainControlsExpanded = false;
  String? _practiceTool;
  bool _chordSearching = false;
  String _chordSource = '';
  int _chordRevision = 0;
  bool _choosingChord = false;
  bool _browserReadyForSelection = false;
  bool _autoSelectingVideo = false;
  bool _browserOpening = false;
  bool _browserOpenedFromPlayer = false;
  bool _initialBrowserReadyReported = false;
  String _browserOriginVideoId = '';
  double _bassDb = 0, _midDb = 0, _trebleDb = 0, _delayMix = 0;
  double _appliedBassDb = 0, _appliedMidDb = 0;
  double _appliedTrebleDb = 0, _appliedDelayMix = 0;
  YouTubeBrowserSession? _browserOwner;
  Widget? _browser;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _player.addListener(_changed);
    _practice.addListener(_practiceChanged);
    unawaited(_initializeStartPage());
  }

  Future<void> _initializeStartPage() async {
    if (!mounted ||
        !widget.openSearchWhenEmpty ||
        _player.loaded ||
        _player.local.loaded) {
      _reportInitialBrowserReady();
      return;
    }
    _browserOpening = true;
    setState(() {
      _browsing = true;
      _browserReadyForSelection = false;
      _browserOriginVideoId = _player.youtube?.media.videoId ?? '';
    });
    await _player.openYouTube();
    _browserOriginVideoId = _player.youtube?.media.videoId ?? '';
    _browserOpening = false;
    if (mounted && _player.youtube == null) {
      setState(() => _browsing = false);
      _reportInitialBrowserReady();
    }
  }

  void _reportInitialBrowserReady() {
    if (_initialBrowserReadyReported || widget.onInitialBrowserReady == null) {
      return;
    }
    _initialBrowserReadyReported = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onInitialBrowserReady?.call();
    });
  }

  void _changed() {
    final startupSession = _player.youtube;
    if (startupSession != null && startupSession.contentReady) {
      _reportInitialBrowserReady();
    }
    if (_chordSource != _player.sourceKey) {
      _chordSource = _player.sourceKey;
      _chordRevision++;
      _chordActive = false;
      _chordSearching = false;
      _stopChordAutoScroll();
      _mainControlsExpanded = false;
      _bassDb = _midDb = _trebleDb = _delayMix = 0;
      _appliedBassDb = _appliedMidDb = _appliedTrebleDb = _appliedDelayMix = 0;
    }
    if (mounted) setState(() {});
    if (!_browsing ||
        !_player.isYouTube ||
        _autoSelectingVideo ||
        _browserOpening) {
      return;
    }
    final media = _player.youtube?.media;
    if (media == null || media.videoId.isEmpty || !media.hasVideo) {
      _browserReadyForSelection = true;
      return;
    }
    if ((!_browserReadyForSelection &&
            media.videoId == _browserOriginVideoId) ||
        media.isAd) {
      return;
    }
    _autoSelectingVideo = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_browsing ||
          !_player.isYouTube ||
          _player.youtube?.media.videoId != media.videoId) {
        _autoSelectingVideo = false;
        return;
      }
      unawaited(_useVideo());
    });
  }

  void _practiceChanged() {
    _changed();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(_practice.pause());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _player.removeListener(_changed);
    _practice.removeListener(_practiceChanged);
    _practice.dispose();
    if (widget.playerController == null) _player.dispose();
    _scroll.dispose();
    _tabsScroll.dispose();
    _chordAutoTimer?.cancel();
    super.dispose();
  }

  void _stopChordAutoScroll() {
    _chordAutoTimer?.cancel();
    _chordAutoTimer = null;
    _chordAutoScroll = false;
  }

  void _toggleChordAutoScroll() {
    if (_chordAutoScroll) {
      setState(_stopChordAutoScroll);
      return;
    }
    if (!_chordActive) return;
    setState(() => _chordAutoScroll = true);
    _chordAutoTimer?.cancel();
    _chordAutoTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted ||
          !_mainControlsExpanded ||
          !_chordActive ||
          _tab != StudioTab.chords && _tab != StudioTab.player ||
          _chordTextScroll?.hasClients != true) {
        return;
      }
      // Move the entire Cifra interface first; keep the frame pinned once it
      // reaches the video, then scroll its text within that fixed frame.
      if (_scroll.hasClients &&
          _scroll.position.pixels < _scroll.position.maxScrollExtent) {
        _scroll.jumpTo(
          (_scroll.position.pixels + 1.4 * _chordScrollSpeed).clamp(
            0.0,
            _scroll.position.maxScrollExtent,
          ),
        );
        return;
      }
      final position = _chordTextScroll!.position;
      if (position.maxScrollExtent <= position.pixels + .5) {
        setState(_stopChordAutoScroll);
        return;
      }
      final next = (position.pixels + 1.4 * _chordScrollSpeed).clamp(
        0.0,
        position.maxScrollExtent,
      );
      _chordTextScroll!.jumpTo(next);
    });
  }

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 72),
      ),
    );
  }

  void _select(StudioTab tab) {
    if (tab != StudioTab.chords && tab != StudioTab.player) {
      _stopChordAutoScroll();
    }
    setState(() {
      _tab = tab == StudioTab.stage || tab == StudioTab.instruments
          ? StudioTab.chords
          : tab == StudioTab.metronome
          ? StudioTab.practice
          : tab == StudioTab.tuner
          ? StudioTab.audioSettings
          : tab;
      _browsing = false;
      _mainControlsExpanded = true;
    });
    if (tab == StudioTab.tuner) unawaited(_player.pause());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_tabsScroll.hasClients) return;
      final index = _visibleTabs.indexWhere((item) => item.$1 == _tab);
      if (index < 0) return;
      final target = (index * 80.0 - 80).clamp(
        0.0,
        _tabsScroll.position.maxScrollExtent,
      );
      unawaited(
        _tabsScroll.animateTo(
          target,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        ),
      );
    });
  }

  void _toggleMainAdjustments() {
    if (_mainControlsExpanded) _stopChordAutoScroll();
    setState(() {
      _mainControlsExpanded = !_mainControlsExpanded;
    });
  }

  Future<void> _openYouTubeSearch() async {
    if (!mounted) return;
    _browserOpening = true;
    setState(() {
      _browsing = true;
      _browserOpenedFromPlayer = _player.loaded;
      _browserReadyForSelection = false;
      _autoSelectingVideo = false;
      _browserOriginVideoId = _player.youtube?.media.videoId ?? '';
    });
    await _player.openYouTube();
    _browserOriginVideoId = _player.youtube?.media.videoId ?? '';
    _browserOpening = false;
  }

  Future<void> _useVideo() async {
    FocusScope.of(context).unfocus();
    if (!_player.isYouTube || !_player.loaded) return;
    final session = _player.youtube;
    setState(() => _browsing = false);
    _browserReadyForSelection = false;
    _autoSelectingVideo = false;
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
    if (!mounted) return;
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
      _stopChordAutoScroll();
      setState(() {
        _chordActive = false;
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
    if (_choosingChord || _chordSearching) return;
    _stopChordAutoScroll();
    await _player.pause();
    if (!mounted) return;
    setState(() => _chordSearching = true);
  }

  Future<void> _acceptChord(ImportedChord selected) async {
    if (_choosingChord) return;
    _choosingChord = true;
    final source = _player.sourceKey;
    final revision = _chordRevision;
    try {
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
        followAudio: false,
      );
      if (source.isEmpty) {
        _chords.temporarySheet = sheet;
      } else {
        await _chords.save(source, sheet);
      }
      if (!mounted || revision != _chordRevision) return;
      setState(() {
        _chordActive = true;
        _chordSearching = false;
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
    final name = setlist
        ? captured.title.trim().characters.take(55).toString()
        : await showDialog<String>(
            context: context,
            builder: (_) => _PresetNameDialog(
              initialName: _player.title,
              title: 'Guardar predefinição',
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
    if (!mounted) return false;
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

  Future<void> _moveSetlist(int direction) async {
    try {
      final entries = await _presets.list(setlist: true);
      if (!mounted) return;
      if (entries.isEmpty) {
        _notice('A setlist ainda está vazia.');
        return;
      }
      final current = entries.indexWhere(
        (entry) => entry.id == _selectedPresetId,
      );
      final target = current < 0
          ? (direction > 0 ? 0 : entries.length - 1)
          : current + direction;
      if (target < 0 || target >= entries.length) {
        _notice(direction > 0 ? 'Fim da setlist.' : 'Início da setlist.');
        return;
      }
      final restored = await _applyPreset(
        entries[target],
        returnToPlayer: true,
      );
      if (!restored && mounted) _notice('Não foi possível abrir esta música.');
    } on Object {
      _notice('Não foi possível ler a setlist.');
    }
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
            child: _audioSettingsContent(onClose: () => Navigator.pop(sheet)),
          ),
        ),
      ),
    );
  }

  Future<void> _setEqualizer({
    double? bass,
    double? mid,
    double? treble,
    double? delay,
  }) async {
    final nextBass = bass ?? _bassDb;
    final nextMid = mid ?? _midDb;
    final nextTreble = treble ?? _trebleDb;
    final nextDelay = delay ?? _delayMix;
    if (!_player.isYouTube || !_player.loaded) return;
    final source = _player.sourceKey;
    final session = _player.youtube!;
    try {
      final action = bass != null
          ? 'bass'
          : mid != null
          ? 'mid'
          : treble != null
          ? 'treble'
          : 'delay';
      await session.command(action, bass ?? mid ?? treble ?? delay);
      if (!mounted ||
          source != _player.sourceKey ||
          session != _player.youtube) {
        return;
      }
      setState(() {
        _bassDb = nextBass;
        _midDb = nextMid;
        _trebleDb = nextTreble;
        _delayMix = nextDelay;
        _appliedBassDb = nextBass;
        _appliedMidDb = nextMid;
        _appliedTrebleDb = nextTreble;
        _appliedDelayMix = nextDelay;
      });
    } on Object {
      if (mounted &&
          source == _player.sourceKey &&
          session == _player.youtube) {
        setState(() {
          _bassDb = _appliedBassDb;
          _midDb = _appliedMidDb;
          _trebleDb = _appliedTrebleDb;
          _delayMix = _appliedDelayMix;
        });
        _notice('Não foi possível aplicar o equalizador neste vídeo.');
      }
    }
  }

  Widget _audioSettingsContent({VoidCallback? onClose}) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (onClose != null)
        Align(
          alignment: Alignment.centerRight,
          child: IconButton(
            tooltip: 'Fechar configurações de áudio',
            onPressed: onClose,
            icon: const Icon(Icons.close),
          ),
        ),
      const Padding(
        key: Key('audioTuner'),
        padding: EdgeInsets.only(bottom: 12),
        child: MicrophoneTunerTool(),
      ),
      Container(
        decoration: BoxDecoration(
          color: studioCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: studioMuted.withValues(alpha: .2)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '▥  EQUALIZADOR MASTER · 3 BANDAS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: .7,
              ),
            ),
            const SizedBox(height: 10),
            _equalizerSlider(
              'Graves',
              'audioBassSlider',
              _bassDb,
              (value) => _setEqualizer(bass: value),
            ),
            _equalizerSlider(
              'Médios',
              'audioMidSlider',
              _midDb,
              (value) => _setEqualizer(mid: value),
            ),
            _equalizerSlider(
              'Agudos',
              'audioTrebleSlider',
              _trebleDb,
              (value) => _setEqualizer(treble: value),
            ),
            if (!_player.isYouTube || !_player.loaded)
              const Text(
                'Escolha um vídeo do YouTube para ativar o equalizador.',
                style: TextStyle(color: studioMuted, fontSize: 12),
              ),
            TextButton.icon(
              key: const Key('audioResetEqualizer'),
              onPressed: _player.isYouTube && _player.loaded
                  ? () async {
                      await _setEqualizer(bass: 0);
                      await _setEqualizer(mid: 0);
                      await _setEqualizer(treble: 0);
                      await _setEqualizer(delay: 0);
                    }
                  : null,
              icon: const Icon(Icons.restart_alt),
              label: const Text('Repor equalizador'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      const Padding(
        padding: EdgeInsets.fromLTRB(2, 4, 0, 7),
        child: Text(
          'EFEITOS EM TEMPO REAL',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
            color: studioMuted,
          ),
        ),
      ),
      Container(
        decoration: BoxDecoration(
          color: studioCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: studioMuted.withValues(alpha: .2)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Efeito Delay de Ensaio',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
            const Text(
              'Eco curto para prática de áudio.',
              style: TextStyle(fontSize: 10, color: studioMuted),
            ),
            Row(
              children: [
                const Text(
                  '0%',
                  style: TextStyle(fontSize: 9, color: studioMuted),
                ),
                Expanded(
                  child: Slider(
                    key: const Key('audioDelaySlider'),
                    min: 0,
                    max: .35,
                    divisions: 35,
                    value: _delayMix,
                    label: '${(_delayMix * 100).round()}%',
                    onChanged: _player.isYouTube && _player.loaded
                        ? (next) => setState(() => _delayMix = next)
                        : null,
                    onChangeEnd: _player.isYouTube && _player.loaded
                        ? (next) => _setEqualizer(delay: next)
                        : null,
                  ),
                ),
                Text(
                  '${(_delayMix * 100).round()}%',
                  style: const TextStyle(fontSize: 10),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Container(
        decoration: BoxDecoration(
          color: studioCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: studioMuted.withValues(alpha: .2)),
        ),
        padding: const EdgeInsets.all(12),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Isolador de Voz / Playback',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 4),
            Text(
              'Indisponível no YouTube. Não é aplicado ao vídeo.',
              style: TextStyle(fontSize: 10, color: studioMuted),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.restore),
        title: const Text('Repor tom, velocidade e loop'),
        subtitle: const Text('0 st · 1,00× · sem A/B'),
        enabled: _player.loaded,
        onTap: _player.loaded
            ? () {
                onClose?.call();
                unawaited(_player.resetProcessing());
              }
            : null,
      ),
      const Text(
        'No YouTube, o tom é experimental e o loop é aproximado. Ficheiros de vídeo locais ainda não suportam alteração de tom.',
        style: TextStyle(color: studioMuted, fontSize: 12),
      ),
      TextButton.icon(
        key: const Key('audioOpenLocalFile'),
        onPressed: _pickFile,
        icon: const Icon(Icons.folder_open),
        label: const Text('Abrir ficheiro local'),
      ),
      if (onClose != null) ...[
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: onClose,
            child: const Text('Concluir'),
          ),
        ),
      ],
    ],
  );

  Widget _equalizerSlider(
    String label,
    String key,
    double value,
    ValueChanged<double> apply,
  ) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                switch (label) {
                  'Graves' => 'Graves (200 Hz)',
                  'Médios' => 'Médios (1 kHz)',
                  _ => 'Agudos (3 kHz)',
                },
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              '${value >= 0 ? '+' : ''}${value.toStringAsFixed(1)} dB',
              style: const TextStyle(fontSize: 10, color: Colors.white),
            ),
          ],
        ),
        Slider(
          key: Key(key),
          min: -12,
          max: 12,
          divisions: 24,
          value: value,
          onChanged: _player.isYouTube && _player.loaded
              ? (next) => setState(() {
                  if (key == 'audioBassSlider') {
                    _bassDb = next;
                  } else if (key == 'audioMidSlider') {
                    _midDb = next;
                  } else {
                    _trebleDb = next;
                  }
                })
              : null,
          onChangeEnd: _player.isYouTube && _player.loaded ? apply : null,
        ),
      ],
    ),
  );

  Widget _browserPage(Widget media) {
    final session = _player.youtube;
    return Column(
      children: <Widget>[
        if (_browserOpenedFromPlayer)
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
    return LayoutBuilder(
      builder: (_, box) {
        final open = _mainControlsExpanded;
        final localVideo = _player.local.videoController;
        final localVideoHeight =
            localVideo != null &&
                localVideo.value.isInitialized &&
                localVideo.value.aspectRatio > 0
            ? box.maxWidth / localVideo.value.aspectRatio
            : box.maxWidth * 9 / 16;
        final panelTop =
            (_player.isYouTube
                    ? box.maxWidth * 9 / 16 + 100
                    : localVideo != null
                    ? (box.maxHeight + localVideoHeight) / 2
                    : box.maxWidth * 9 / 16 + 36)
                .clamp(0.0, box.maxHeight * (_player.isYouTube ? .55 : .65)) +
            16;
        final chordPanel = _tab == StudioTab.chords || _tab == StudioTab.player;
        final videoBottom = _player.isYouTube
            ? (box.maxWidth * 9 / 16 + 48).clamp(0.0, panelTop)
            : panelTop;
        final chordTopGap = panelTop - videoBottom;
        return Stack(
          children: [
            SizedBox(
              key: const Key('visualMainMediaViewport'),
              height: box.maxHeight,
              width: double.infinity,
              child: MainPlayerFullscreen(
                model: _player,
                media: media,
                mainMode: true,
                showHeader: false,
                controlsOpen: false,
                onExit: () {},
                onTool: _tool,
                youtubeNativeTransport: _player.isYouTube,
                onNativeMediaTouch: _player.isYouTube
                    ? _player.noteNativeVideoTouch
                    : null,
              ),
            ),
            if (open)
              Positioned(
                top: chordPanel
                    ? videoBottom
                    : box.maxHeight < 450
                    ? (panelTop - 48).clamp(0.0, panelTop)
                    : panelTop,
                left: 0,
                right: 0,
                bottom: 0,
                child: Theme(
                  data: studioColumnTheme(Theme.of(context)),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: chordPanel
                            ? ClipRRect(
                                key: const Key('unifiedChordOverlay'),
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(18),
                                ),
                                child: _sectionContent(
                                  media,
                                  topGap: chordTopGap,
                                  viewportHeight: box.maxHeight - videoBottom,
                                ),
                              )
                            : ColoredBox(
                                color: studioBg,
                                child: _sectionContent(media),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  static const _visibleTabs = <(StudioTab, String)>[
    (StudioTab.chords, 'Cifra'),
    (StudioTab.practice, 'Treino'),
    (StudioTab.setlist, 'Setlist'),
    (StudioTab.audioSettings, 'Áudio'),
  ];

  Widget _sectionTabs() {
    final selected = _tab == StudioTab.player ? StudioTab.chords : _tab;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1B1D),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              key: const Key('unifiedSectionStrip'),
              controller: _tabsScroll,
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final (tab, label) in _visibleTabs)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: OutlinedButton(
                        key: Key('unifiedSection${tab.name}'),
                        onPressed: () => _select(tab),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: selected == tab
                              ? const Color(0xFF161618)
                              : const Color(0xFFC4C4C8),
                          side: BorderSide.none,
                          backgroundColor: selected == tab
                              ? Colors.white
                              : Colors.transparent,
                          minimumSize: const Size(70, 34),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          label,
                          maxLines: 1,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            key: const Key('visualMainAdjustments'),
            tooltip: 'Fechar ajustes',
            onPressed: _toggleMainAdjustments,
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF2A2A2C),
              foregroundColor: Colors.white,
              minimumSize: const Size(34, 34),
              padding: EdgeInsets.zero,
            ),
            icon: const Icon(Icons.keyboard_arrow_down, size: 23),
          ),
        ],
      ),
    );
  }

  Widget _practiceToolRow({
    required Key key,
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool expanded = false,
    Widget? trailing,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Material(
      color: const Color(0xFF1B1B1D),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        key: key,
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            children: [
              Icon(icon, size: 15, color: Colors.white),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              trailing ??
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 20,
                    color: studioMuted,
                  ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _sectionContent(
    Widget media, {
    double topGap = 0,
    double viewportHeight = 0,
  }) {
    if (_chordSearching) {
      return ColoredBox(
        color: studioBg,
        child: Column(
          children: [
            _sectionTabs(),
            Expanded(
              child: ChordSearchPanel(
                key: const Key('unifiedChordSearch'),
                initialQuery: _player.loaded ? _player.title : '',
                sessionFactory: widget.chordBrowserFactory,
                onCancel: () => setState(() => _chordSearching = false),
                onSelected: _acceptChord,
              ),
            ),
          ],
        ),
      );
    }
    if (_tab == StudioTab.setlist) {
      return Column(
        children: [
          _sectionTabs(),
          Expanded(
            child: PlayerCollectionsPage(
              key: const Key('unifiedSetlist'),
              store: _presets,
              setlist: true,
              embedded: true,
              onAdd: () => _save(setlist: true),
              onPrevious: () => _moveSetlist(-1),
              onNext: () => _moveSetlist(1),
              onApply: (preset) async {
                final restored = await _applyPreset(
                  preset,
                  returnToPlayer: true,
                );
                if (!restored) {
                  throw StateError(
                    _player.message ?? 'Não foi possível preparar esta música.',
                  );
                }
              },
            ),
          ),
        ],
      );
    }
    if (_tab == StudioTab.audioSettings) {
      return Column(
        children: [
          _sectionTabs(),
          Expanded(
            child: SingleChildScrollView(
              key: const Key('unifiedAudioSettingsScroll'),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 88),
              child: _audioSettingsContent(),
            ),
          ),
        ],
      );
    }
    if (_tab == StudioTab.practice) {
      return SingleChildScrollView(
        key: const Key('unifiedPracticeScroll'),
        padding: const EdgeInsets.only(bottom: 88),
        child: Column(
          children: [
            _sectionTabs(),
            UnifiedPlayerAdjustments(
              model: _player,
              youtubeNativeTransport: _player.isYouTube,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                children: [
                  _practiceToolRow(
                    key: const Key('practiceSavedLoops'),
                    icon: Icons.bookmarks_outlined,
                    title: 'Trechos guardados',
                    onTap: _saved,
                    trailing: IconButton(
                      key: const Key('visualPracticeSaveLoop'),
                      tooltip: 'Guardar trecho atual',
                      onPressed:
                          _player.loaded &&
                              _player.markerA != null &&
                              _player.markerB != null
                          ? () => _save()
                          : null,
                      icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                    ),
                  ),
                  _practiceToolRow(
                    key: const Key('practiceMetronome'),
                    icon: Icons.timer_outlined,
                    title: 'Metrônomo inteligente',
                    onTap: () => setState(
                      () => _practiceTool = _practiceTool == 'metronome'
                          ? null
                          : 'metronome',
                    ),
                    expanded: _practiceTool == 'metronome',
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: _practiceTool == 'metronome'
                        ? Padding(
                            key: const Key('practiceMetronomeContent'),
                            padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
                            child: embeddedStudyTool('metronome'),
                          )
                        : const SizedBox.shrink(),
                  ),
                  _practiceToolRow(
                    key: const Key('practiceProgression'),
                    icon: Icons.trending_up,
                    title: 'Progressão de velocidade',
                    onTap: () => setState(
                      () => _practiceTool = _practiceTool == 'progression'
                          ? null
                          : 'progression',
                    ),
                    expanded: _practiceTool == 'progression',
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: _practiceTool == 'progression'
                        ? Padding(
                            key: const Key('practiceProgressionContent'),
                            padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
                            child: PracticeProgressionCard(
                              controller: _practice,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    final controls = Column(
      children: [
        _sectionTabs(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('unifiedChooseChord'),
                  onPressed: _chordActive ? _searchChord : _toggleChord,
                  style: OutlinedButton.styleFrom(
                    backgroundColor: const Color(0xFF2A2A2C),
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF444447)),
                    minimumSize: const Size.fromHeight(42),
                  ),
                  icon: Icon(
                    _chordActive
                        ? Icons.swap_horiz
                        : Icons.library_music_outlined,
                  ),
                  label: Text(_chordActive ? 'Trocar cifra' : 'Escolher cifra'),
                ),
              ),
            ],
          ),
        ),
        UnifiedPlayerAdjustments(
          model: _player,
          youtubeNativeTransport: _player.isYouTube,
          showPracticeControls: false,
        ),
      ],
    );
    final autoScrollControls = _chordActive
        ? Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: studioCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: studioMuted.withValues(alpha: .25)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    const Icon(Icons.auto_mode, size: 17),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        'Rolagem automática da cifra',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const Key('chordAutoScrollSlower'),
                      tooltip: 'Rolar cifra mais devagar',
                      visualDensity: VisualDensity.compact,
                      onPressed: _chordScrollSpeed > .5
                          ? () => setState(
                              () => _chordScrollSpeed =
                                  (_chordScrollSpeed - .25).clamp(.5, 2),
                            )
                          : null,
                      icon: const Icon(Icons.remove, size: 18),
                    ),
                    Text(
                      '${_chordScrollSpeed.toStringAsFixed(2)}×',
                      key: const Key('chordAutoScrollSpeed'),
                      style: const TextStyle(fontSize: 11),
                    ),
                    IconButton(
                      key: const Key('chordAutoScrollFaster'),
                      tooltip: 'Rolar cifra mais depressa',
                      visualDensity: VisualDensity.compact,
                      onPressed: _chordScrollSpeed < 2
                          ? () => setState(
                              () => _chordScrollSpeed =
                                  (_chordScrollSpeed + .25).clamp(.5, 2),
                            )
                          : null,
                      icon: const Icon(Icons.add, size: 18),
                    ),
                    IconButton.filledTonal(
                      key: const Key('chordAutoScrollToggle'),
                      tooltip: _chordAutoScroll
                          ? 'Pausar rolagem da cifra'
                          : 'Iniciar rolagem da cifra',
                      onPressed: _toggleChordAutoScroll,
                      icon: Icon(
                        _chordAutoScroll ? Icons.pause : Icons.play_arrow,
                        size: 19,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        : const SizedBox.shrink();
    if (_chordActive) {
      return NestedScrollView(
        key: const Key('unifiedChordScroll'),
        controller: _scroll,
        headerSliverBuilder: (context, innerScrolled) => [
          SliverToBoxAdapter(
            child: Column(
              children: [
                if (topGap > 0) SizedBox(height: topGap),
                DecoratedBox(
                  decoration: const BoxDecoration(
                    color: studioBg,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(18),
                    ),
                  ),
                  child: controls,
                ),
              ],
            ),
          ),
        ],
        body: Builder(
          builder: (innerContext) {
            _chordTextScroll = PrimaryScrollController.of(innerContext);
            return ColoredBox(
              key: const Key('unifiedChordBackdrop'),
              color: studioBg,
              child: Padding(
                key: const Key('unifiedChordFrame'),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF101012),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: studioCyan.withValues(alpha: .2)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      autoScrollControls,
                      Expanded(
                        child: NotificationListener<ScrollStartNotification>(
                          onNotification: (notification) {
                            if (notification.dragDetails != null &&
                                _chordAutoScroll) {
                              setState(_stopChordAutoScroll);
                            }
                            return false;
                          },
                          child: SingleChildScrollView(
                            key: const Key('unifiedChordTextScroll'),
                            primary: true,
                            child: PlayerChordSheet(
                              key: _unifiedChordKey,
                              model: _player,
                              sourceKey: _player.sourceKey,
                              store: _chords,
                              onSearch: _searchChord,
                              onHide: _toggleChord,
                              revision: _chordRevision,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
    }
    return SingleChildScrollView(
      key: const Key('unifiedChordScroll'),
      controller: _scroll,
      child: Column(
        children: [
          if (topGap > 0) SizedBox(height: topGap),
          ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (viewportHeight - topGap).clamp(0, double.infinity),
            ),
            child: DecoratedBox(
              key: const Key('unifiedChordControlsBackdrop'),
              decoration: const BoxDecoration(
                color: studioBg,
                borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              ),
              child: controls,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = _mediaSurface();
    return PopScope(
      canPop: !_browsing,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        unawaited(_player.pause());
        setState(() => _browsing = false);
      },
      child: Scaffold(
        body: _browsing
            ? SafeArea(child: _browserPage(media))
            : SafeArea(
                bottom: false,
                child: Stack(
                  children: <Widget>[
                    Column(
                      children: <Widget>[Expanded(child: _mainPanel(media))],
                    ),
                    if (!_mainControlsExpanded)
                      Positioned(
                        bottom: MediaQuery.viewPaddingOf(context).bottom + 8,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: _MainAdjustmentsBar(
                            expanded: false,
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
