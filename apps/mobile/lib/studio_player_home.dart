part of 'studio_visual_app.dart';

class _StudioVisualHomeState extends State<StudioVisualHome>
    with WidgetsBindingObserver {
  Color get _background => widget.appearance.mode == StudioAppearanceMode.light
      ? const Color(0xFFF4F7FB)
      : widget.appearance.mode == StudioAppearanceMode.glass
      ? const Color(0x77080809)
      : studioBg;
  late final MainPlayerController _player =
      widget.playerController ??
      MainPlayerController(
        youtubeFactory: widget.youtubeSessionFactory,
        youtubeHome: widget.youtubeHome,
      );
  late final PlayerPresetStore _presets =
      widget.presetStore ?? PlayerPresetStore();
  late final PracticeController _practice = PracticeController(_player);
  final BandSession _bandSession = BandSession();
  final ChordSheetStore _chords = ChordSheetStore();
  int _collectionsRevision = 0;
  String? _selectedPresetId;
  final GlobalKey _mediaKey = GlobalKey(debugLabel: 'shared-player-surface');
  final GlobalKey<PlayerChordSheetState> _unifiedChordKey = GlobalKey();
  final ScrollController _scroll = ScrollController();
  final GlobalKey _adjustmentButtonAnchorKey = GlobalKey();
  OverlayEntry? _adjustmentChoicesOverlay;
  Size _adjustmentButtonSize = const Size(40, 40);
  ScrollController? _chordTextScroll;
  Timer? _chordAutoTimer;
  bool _chordAutoScroll = false;
  double _chordScrollSpeed = 1;
  StudioTab _tab = StudioTab.player;
  bool _browsing = false;
  bool _chordActive = false;
  bool _mainControlsExpanded = false;
  bool _adjustmentsCoverVideo = false;
  bool _adjustmentChoicesVisible = false;
  bool _landscapeColumnsVisible = false;
  bool _immersiveLandscape = false;
  Orientation? _lastOrientation;
  double _adjustmentsDrag = 0;
  double? _seekPreviewMs;
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
  double _bassDb = 0, _midDb = 0, _trebleDb = 0, _gainDb = 0;
  double _chorusMix = 0, _feedbackMix = 0, _delayMix = 0, _reverbMix = 0;
  final Map<String, int> _audioCommandVersions = <String, int>{};
  final Set<String> _audioDragging = <String>{};
  int _audioSourceRevision = 0;
  YouTubeBrowserSession? _browserOwner;
  Widget? _browser;
  late final HomeWidgetBridge _homeWidgets;
  String? _pendingWidgetAction;
  List<ChordCue> _widgetCues = const [];
  String _widgetChordTitle = '';
  String _widgetChordPreview = '';
  Map<String, Object?>? _lastForegroundWidgetState;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _homeWidgets = HomeWidgetBridge(onAction: _onWidgetAction);
    unawaited(_homeWidgets.initialize());
    _player.addListener(_changed);
    _practice.addListener(_practiceChanged);
    unawaited(_initializeStartPage());
    _lastForegroundWidgetState = _widgetSnapshot();
    _homeWidgets.schedule(_lastForegroundWidgetState!);
  }

  @override
  void didUpdateWidget(covariant StudioVisualHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.appearance.mode != widget.appearance.mode) {
      final light = widget.appearance.mode == StudioAppearanceMode.light;
      SystemChrome.setSystemUIOverlayStyle(
        SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: light ? Brightness.dark : Brightness.light,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: light
              ? Brightness.dark
              : Brightness.light,
          systemNavigationBarContrastEnforced: false,
        ),
      );
      final session = _player.youtube;
      if (session is WebViewYouTubeSession) {
        unawaited(session.setAppearanceMode(widget.appearance.mode));
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final orientation = MediaQuery.orientationOf(context);
    if (_lastOrientation == orientation) return;
    _lastOrientation = orientation;
    _landscapeColumnsVisible = false;
    _adjustmentsCoverVideo = false;
    _hideAdjustmentChoices();
    _syncSystemUi();
  }

  void _syncSystemUi() {
    if (_lastOrientation == null) return;
    final orientation = MediaQuery.maybeOf(context)?.orientation;
    if (orientation == null) return;
    final immersive =
        orientation == Orientation.landscape &&
        MediaQuery.sizeOf(context).aspectRatio >= 1.5 &&
        _player.loaded &&
        !_browsing;
    if (immersive == _immersiveLandscape) return;
    _immersiveLandscape = immersive;
    unawaited(
      SystemChrome.setEnabledSystemUIMode(
        immersive ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      ),
    );
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
    final String query = widget.initialYouTubeQuery?.trim() ?? '';
    if (query.isEmpty) {
      await _player.openYouTube();
    } else {
      // A song handed over from Spotify: open its YouTube results directly.
      await _player.search(query);
    }
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
    if (startupSession is WebViewYouTubeSession) {
      unawaited(startupSession.setAppearanceMode(widget.appearance.mode));
    }
    if (startupSession != null && startupSession.contentReady) {
      _reportInitialBrowserReady();
    }
    if (_chordSource != _player.sourceKey) {
      _hideAdjustmentChoices();
      _chordSource = _player.sourceKey;
      _widgetCues = const [];
      _widgetChordTitle = '';
      _widgetChordPreview = '';
      unawaited(_loadWidgetCues(_chordSource));
      _chordRevision++;
      _chordActive = false;
      _chordSearching = false;
      _stopChordAutoScroll();
      _mainControlsExpanded = false;
      _adjustmentsCoverVideo = false;
      _landscapeColumnsVisible = false;
      _seekPreviewMs = null;
      _bassDb = _midDb = _trebleDb = _gainDb = 0;
      _chorusMix = _feedbackMix = _delayMix = _reverbMix = 0;
      _audioCommandVersions.clear();
      _audioDragging.clear();
      _audioSourceRevision++;
    }
    _syncAudioValues();
    if (mounted) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _lastForegroundWidgetState = _widgetSnapshot();
        _homeWidgets.schedule(_lastForegroundWidgetState!);
      }
      _syncSystemUi();
      setState(() {});
    }
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

  Future<void> _loadWidgetCues(String source) async {
    if (source.isEmpty) return;
    try {
      final sheet = await _chords.read(source);
      if (!mounted || source != _player.sourceKey) return;
      _widgetCues = parseChordCues(sheet.timeline);
      _widgetChordTitle = sheet.sourceTitle;
      final preview = sheet.notes
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .take(4)
          .join('  |  ');
      _widgetChordPreview = preview.length > 240
          ? preview.substring(0, 240)
          : preview;
      _homeWidgets.schedule(_widgetSnapshot());
    } on FormatException {
      // Keep an unreadable sheet untouched; the widget simply omits it.
    }
  }

  String _widgetTime(Duration value) {
    final seconds = value.inSeconds.clamp(0, 359999);
    final minutes = seconds ~/ 60;
    return '$minutes:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  Map<String, Object?> _widgetSnapshot() {
    final active = _player.loaded;
    final duration = _player.duration.inMilliseconds;
    final position = _player.position.inMilliseconds.clamp(0, duration);
    final cueIndex = currentChordIndex(_widgetCues, _player.position);
    final chord = cueIndex >= 0
        ? _widgetCues
              .skip(cueIndex)
              .take(4)
              .map((cue) => cue.chord)
              .join('  ·  ')
        : _widgetChordPreview.isNotEmpty
        ? _widgetChordPreview
        : _widgetChordTitle.isNotEmpty
        ? 'Cifra: $_widgetChordTitle'
        : 'Abra a cifra no app';
    final markerA = _player.markerA;
    final markerB = _player.markerB;
    final loop = markerA == null
        ? 'A–B: não marcado'
        : markerB == null
        ? 'A ${_widgetTime(markerA)} · B por marcar'
        : 'A ${_widgetTime(markerA)} → B ${_widgetTime(markerB)}'
              '${_player.loopEnabled ? ' · repetir' : ''}';
    return {
      'active': active,
      'playing': active && _player.playing,
      'title': active && _player.title.trim().isNotEmpty
          ? _player.title.trim()
          : 'Transpono',
      'subtitle': active ? _player.sourceLabel : '',
      'position': _widgetTime(_player.position),
      'duration': _widgetTime(_player.duration),
      'progress': duration > 0 ? (position * 100 / duration).round() : 0,
      'pitch': _player.pitch.round(),
      'speed': '${_player.speed.toStringAsFixed(2)}x',
      'loop': loop,
      'chord': chord,
    };
  }

  void _onWidgetAction(String action) {
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      _pendingWidgetAction = action;
      return;
    }
    unawaited(_runWidgetAction(action));
  }

  Future<void> _runWidgetAction(String action) async {
    if (!mounted || action == 'open') return;
    if (action == 'tuner') {
      _select(StudioTab.tuner);
      return;
    }
    if (action == 'chord') {
      _select(StudioTab.chords);
      return;
    }
    if (action == 'loop') {
      _select(StudioTab.practice);
      if (_player.canLoop &&
          _player.markerA != null &&
          _player.markerB != null) {
        await _player.toggleLoop();
      }
      return;
    }
    if (!_player.loaded) return;
    switch (action) {
      case 'play':
        await _player.playPause();
      case 'back':
        if (_player.canSeek) {
          await _player.seek(_player.position - const Duration(seconds: 10));
        }
      case 'forward':
        if (_player.canSeek) {
          await _player.seek(_player.position + const Duration(seconds: 10));
        }
      case 'pitchMinus':
        if (_player.canPitch) await _player.changePitch(_player.pitch - 1);
      case 'pitchPlus':
        if (_player.canPitch) await _player.changePitch(_player.pitch + 1);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(_practice.pause());
      unawaited(_player.pause());
      _homeWidgets.schedule({
        ...?_lastForegroundWidgetState,
        'playing': false,
        'subtitle': 'Toque para abrir no Transpono',
      });
    } else {
      _lastForegroundWidgetState = _widgetSnapshot();
      _homeWidgets.schedule(_lastForegroundWidgetState!);
      if (_pendingWidgetAction == null) return;
      final action = _pendingWidgetAction!;
      _pendingWidgetAction = null;
      unawaited(_runWidgetAction(action));
    }
  }

  @override
  void dispose() {
    _adjustmentChoicesOverlay?.remove();
    _adjustmentChoicesOverlay?.dispose();
    if (_immersiveLandscape) {
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    }
    WidgetsBinding.instance.removeObserver(this);
    _player.removeListener(_changed);
    _practice.removeListener(_practiceChanged);
    _practice.dispose();
    _bandSession.dispose();
    _homeWidgets.dispose();
    if (widget.playerController == null) _player.dispose();
    _scroll.dispose();
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
    _hideAdjustmentChoices();
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
      _adjustmentChoicesVisible = false;
    });
    if (tab == StudioTab.tuner) unawaited(_player.pause());
  }

  /// The close control is the small arrow (after scrolling down) rather than
  /// the full "Fechar ajustes" button.
  bool _closeCompact = false;

  void _toggleMainAdjustments() {
    _hideAdjustmentChoices();
    if (_mainControlsExpanded) _stopChordAutoScroll();
    setState(() {
      _closeCompact = false;
      _mainControlsExpanded = !_mainControlsExpanded;
      _adjustmentsCoverVideo = false;
      _adjustmentChoicesVisible = false;
      _seekPreviewMs = null;
    });
    // "Abrir ajustes" brings the page's video list back up to the player;
    // closing the adjustments returns the list to where it was.
    final session = _player.youtube;
    if (_player.isYouTube && session != null) {
      unawaited(session.adjustmentsShown(_mainControlsExpanded));
    }
  }

  void _coverVideoWithAdjustments() {
    setState(() {
      _mainControlsExpanded = true;
      _adjustmentsCoverVideo = true;
    });
  }

  void _lowerAdjustments() {
    if (_adjustmentsCoverVideo) {
      setState(() {
        _adjustmentsCoverVideo = false;
        _seekPreviewMs = null;
      });
    } else if (_isLandscapePlayer && _landscapeColumnsVisible) {
      setState(() => _landscapeColumnsVisible = false);
    } else if (_mainControlsExpanded) {
      _toggleMainAdjustments();
    }
  }

  bool get _isLandscapePlayer =>
      MediaQuery.orientationOf(context) == Orientation.landscape &&
      MediaQuery.sizeOf(context).aspectRatio >= 1.5 &&
      _player.loaded &&
      !_browsing;

  void _openLandscapeAdjustments() {
    setState(() {
      _mainControlsExpanded = true;
      _landscapeColumnsVisible = true;
      _adjustmentsCoverVideo = false;
    });
  }

  void _chooseAdjustmentDirection(bool expand) {
    _hideAdjustmentChoices();
    setState(() {});
    if (expand) {
      _coverVideoWithAdjustments();
    } else {
      _lowerAdjustments();
    }
  }

  void _hideAdjustmentChoices() {
    final entry = _adjustmentChoicesOverlay;
    _adjustmentChoicesOverlay = null;
    entry?.remove();
    entry?.dispose();
    _adjustmentChoicesVisible = false;
  }

  void _showAdjustmentDirections() {
    final button =
        _adjustmentButtonAnchorKey.currentContext?.findRenderObject()
            as RenderBox?;
    final overlay = Overlay.of(context);
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    if (button == null || overlayBox == null) return;
    final center = button.localToGlobal(
      button.size.center(Offset.zero),
      ancestor: overlayBox,
    );
    _adjustmentButtonSize = button.size;
    final left = (center.dx - 18).clamp(0.0, overlayBox.size.width - 36);
    final top = (center.dy - 45).clamp(0.0, overlayBox.size.height - 90);

    _adjustmentChoicesOverlay = OverlayEntry(
      builder: (_) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              key: const Key('adjustmentDirectionDismiss'),
              behavior: HitTestBehavior.translucent,
              onTap: () {
                _hideAdjustmentChoices();
                if (mounted) setState(() {});
              },
            ),
          ),
          Positioned(
            left: left,
            top: top,
            child: Semantics(
              label: 'Cobrir vídeo com ajustes',
              button: true,
              child: GestureDetector(
                key: const Key('adjustmentsExpandVideo'),
                onTap: () => _chooseAdjustmentDirection(true),
                child: const CircleAvatar(
                  radius: 18,
                  backgroundColor: Color(0xFF303034),
                  child: Icon(Icons.keyboard_arrow_up, color: Colors.white),
                ),
              ),
            ),
          ),
          Positioned(
            left: left,
            top: top + 54,
            child: Semantics(
              label: 'Baixar ou fechar ajustes',
              button: true,
              child: GestureDetector(
                key: const Key('adjustmentsClose'),
                onTap: () => _chooseAdjustmentDirection(false),
                child: const CircleAvatar(
                  radius: 18,
                  backgroundColor: Color(0xFF303034),
                  child: Icon(Icons.keyboard_arrow_down, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    overlay.insert(_adjustmentChoicesOverlay!);
    setState(() => _adjustmentChoicesVisible = true);
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
    _syncSystemUi();
    await _player.openYouTube();
    _browserOriginVideoId = _player.youtube?.media.videoId ?? '';
    _browserOpening = false;
  }

  Future<void> _useVideo() async {
    FocusScope.of(context).unfocus();
    if (!_player.isYouTube || !_player.loaded) return;
    final session = _player.youtube;
    setState(() => _browsing = false);
    _syncSystemUi();
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
      unawaited(_loadWidgetCues(source));
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
    if (_player.isRhythmPreview) {
      _notice('Prévia temporária não pode ser guardada.');
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
          appearance: widget.appearance,
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

  void _syncAudioValues() {
    final effects = _player.isYouTube
        ? _player.youtube?.media.audioEffects
        : null;
    for (final action in <String>[
      'bass',
      'mid',
      'treble',
      'gain',
      'chorus',
      'feedback',
      'delay',
      'reverb',
    ]) {
      if (!_audioDragging.contains(action)) {
        _assignAudioValue(action, effects?[action] ?? 0);
      }
    }
  }

  void _previewAudioValue(String action, double value) {
    _audioDragging.add(action);
    _assignAudioValue(action, value);
  }

  void _assignAudioValue(String action, double value) {
    switch (action) {
      case 'bass':
        _bassDb = value;
      case 'mid':
        _midDb = value;
      case 'treble':
        _trebleDb = value;
      case 'gain':
        _gainDb = value;
      case 'chorus':
        _chorusMix = value;
      case 'feedback':
        _feedbackMix = value;
      case 'delay':
        _delayMix = value;
      case 'reverb':
        _reverbMix = value;
      default:
        throw ArgumentError.value(action, 'action');
    }
  }

  Future<void> _setAudioControl(String action, double value) async {
    _audioDragging.remove(action);
    if (!_player.isYouTube || !_player.loaded) return;
    final version = (_audioCommandVersions[action] ?? 0) + 1;
    _audioCommandVersions[action] = version;
    final source = _player.sourceKey;
    final session = _player.youtube!;
    final sourceRevision = _audioSourceRevision;
    try {
      await session.command(action, value);
      if (!mounted ||
          source != _player.sourceKey ||
          session != _player.youtube ||
          sourceRevision != _audioSourceRevision ||
          _audioCommandVersions[action] != version) {
        return;
      }
      setState(_syncAudioValues);
    } on Object {
      if (mounted &&
          source == _player.sourceKey &&
          session == _player.youtube &&
          sourceRevision == _audioSourceRevision &&
          _audioCommandVersions[action] == version) {
        setState(_syncAudioValues);
        _notice('Não foi possível aplicar este ajuste de áudio no vídeo.');
      }
    }
  }

  Future<void> _chooseNoteColor(int pitchClass) async {
    final selected = await showDialog<int?>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Cor da nota ${_noteNames[pitchClass]}'),
        content: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var index = 0; index < playerChordNoteColors.length; index++)
              IconButton(
                key: Key('noteColorChoice$index'),
                tooltip: 'Escolher cor ${index + 1}',
                onPressed: () => Navigator.pop(context, index),
                icon: Icon(
                  Icons.circle,
                  color: playerChordNoteColors[index],
                  size: 32,
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            key: const Key('noteColorDefault'),
            onPressed: () => Navigator.pop(context, -1),
            child: const Text('Cor original'),
          ),
        ],
      ),
    );
    if (!mounted || selected == null) return;
    final colors = Map<int, Color>.of(widget.appearance.noteColors);
    if (selected < 0) {
      colors.remove(pitchClass);
    } else {
      colors[pitchClass] = playerChordNoteColors[selected];
    }
    widget.onAppearanceChanged?.call(
      widget.appearance.copyWith(noteColors: colors),
    );
  }

  static const _noteNames = [
    'C',
    'C♯',
    'D',
    'D♯',
    'E',
    'F',
    'F♯',
    'G',
    'G♯',
    'A',
    'A♯',
    'B',
  ];

  Widget _appearanceSettingsContent() => Container(
    key: const Key('appearanceSettings'),
    decoration: studioPanelDecoration(mode: widget.appearance.mode),
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('APARÊNCIA', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (mode, label) in const [
              (StudioAppearanceMode.dark, 'Escuro'),
              (StudioAppearanceMode.light, 'Claro'),
              (StudioAppearanceMode.glass, 'Vidro'),
            ])
              ChoiceChip(
                key: Key('appearanceMode${mode.name}'),
                label: Text(label),
                selected: widget.appearance.mode == mode,
                onSelected: (_) => widget.onAppearanceChanged?.call(
                  widget.appearance.copyWith(mode: mode),
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        const Text(
          'CORES DAS NOTAS',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        const Text('Toque numa nota para escolher a sua cor nas cifras.'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var index = 0; index < _noteNames.length; index++)
              ActionChip(
                key: Key('appearanceNote$index'),
                tooltip: 'Alterar cor da nota ${_noteNames[index]}',
                label: Text(
                  _noteNames[index],
                  style: TextStyle(
                    color: playerChordDisplayColor(index, widget.appearance),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                onPressed: () => _chooseNoteColor(index),
              ),
          ],
        ),
      ],
    ),
  );

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
      Padding(
        key: const Key('audioTuner'),
        padding: const EdgeInsets.only(bottom: 12),
        child: MicrophoneTunerTool(appearance: widget.appearance),
      ),
      Container(
        decoration: studioPanelDecoration(mode: widget.appearance.mode),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '▥  EQUALIZADOR',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: .7,
              ),
            ),
            const SizedBox(height: 6),
            _audioControlRow(
              'Ganho',
              'audioGainSlider',
              _gainDb,
              -12,
              6,
              (value) => _previewAudioValue('gain', value),
              (value) => _setAudioControl('gain', value),
            ),
            _audioControlRow(
              'Graves',
              'audioBassSlider',
              _bassDb,
              -12,
              12,
              (value) => _previewAudioValue('bass', value),
              (value) => _setAudioControl('bass', value),
            ),
            _audioControlRow(
              'Médios',
              'audioMidSlider',
              _midDb,
              -12,
              12,
              (value) => _previewAudioValue('mid', value),
              (value) => _setAudioControl('mid', value),
            ),
            _audioControlRow(
              'Agudos',
              'audioTrebleSlider',
              _trebleDb,
              -12,
              12,
              (value) => _previewAudioValue('treble', value),
              (value) => _setAudioControl('treble', value),
            ),
            if (!_player.isYouTube || !_player.loaded)
              const Padding(
                padding: EdgeInsets.only(top: 5),
                child: Text(
                  'Ajustes disponíveis num vídeo compatível do YouTube.',
                  style: TextStyle(color: studioMuted, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Container(
        decoration: studioPanelDecoration(mode: widget.appearance.mode),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'EFEITOS EM TEMPO REAL',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: .7,
              ),
            ),
            const SizedBox(height: 6),
            _audioControlRow(
              'Chorus',
              'audioChorusSlider',
              _chorusMix,
              0,
              .5,
              (value) => _previewAudioValue('chorus', value),
              (value) => _setAudioControl('chorus', value),
            ),
            _audioControlRow(
              'Feedback',
              'audioFeedbackSlider',
              _feedbackMix,
              0,
              .55,
              (value) => _previewAudioValue('feedback', value),
              (value) => _setAudioControl('feedback', value),
            ),
            _audioControlRow(
              'Delay',
              'audioDelaySlider',
              _delayMix,
              0,
              .35,
              (value) => _previewAudioValue('delay', value),
              (value) => _setAudioControl('delay', value),
            ),
            _audioControlRow(
              'Reverb',
              'audioReverbSlider',
              _reverbMix,
              0,
              .4,
              (value) => _previewAudioValue('reverb', value),
              (value) => _setAudioControl('reverb', value),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Container(
        decoration: studioPanelDecoration(mode: widget.appearance.mode),
        padding: const EdgeInsets.all(12),
        child: const Row(
          children: [
            Expanded(
              child: Column(
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
            Switch.adaptive(value: false, onChanged: null),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Card(
        key: const Key('audioResetProcessingCard'),
        child: ListTile(
          leading: const Icon(Icons.restore),
          title: const Text(
            'Repor tom, velocidade e loop',
            style: TextStyle(fontSize: 13),
          ),
          subtitle: const Text(
            '0 st · 1,00× · sem A/B',
            style: TextStyle(fontSize: 10),
          ),
          trailing: const Icon(Icons.chevron_right),
          enabled: _player.loaded,
          onTap: _player.loaded
              ? () {
                  onClose?.call();
                  unawaited(_player.resetProcessing());
                }
              : null,
        ),
      ),
      const Text(
        'No YouTube, o tom é experimental e o loop é aproximado. Ficheiros de vídeo locais ainda não suportam alteração de tom.',
        style: TextStyle(color: studioMuted, fontSize: 12),
      ),
      Card(
        key: const Key('audioOpenLocalFileCard'),
        child: ListTile(
          key: const Key('audioOpenLocalFile'),
          onTap: _pickFile,
          leading: const Icon(Icons.folder_open),
          title: const Text(
            'Abrir ficheiro local',
            style: TextStyle(fontSize: 13),
          ),
          trailing: const Icon(Icons.chevron_right),
        ),
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

  Widget _audioControlRow(
    String label,
    String key,
    double value,
    double min,
    double max,
    ValueChanged<double> preview,
    ValueChanged<double> apply,
  ) {
    final enabled = _player.isYouTube && _player.loaded;
    final isDecibels = min < 0;
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Slider(
                key: Key(key),
                min: min,
                max: max,
                divisions: ((max - min) * (isDecibels ? 1 : 100)).round(),
                value: value,
                label: isDecibels
                    ? '${value.toStringAsFixed(0)} dB'
                    : '${(value * 100).round()}%',
                onChanged: enabled
                    ? (next) => setState(() => preview(next))
                    : null,
                onChangeEnd: enabled ? apply : null,
              ),
            ),
          ),
          IconButton(
            key: Key('${key}Reset'),
            tooltip: 'Repor $label a zero',
            onPressed: enabled && value != 0 ? () => apply(0) : null,
            icon: const Icon(Icons.restart_alt, size: 15),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 27, height: 27),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

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
          child: Stack(
            children: [
              Positioned.fill(
                child: SizedBox(
                  key: const Key('youtubeBrowserViewport'),
                  child: media,
                ),
              ),
              if (!_player.loaded)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 8,
                  child: _MainAdjustmentsBar(
                    expanded: false,
                    onPressed: () {
                      setState(() {
                        _browsing = false;
                        _mainControlsExpanded = true;
                        _adjustmentsCoverVideo = false;
                      });
                    },
                  ),
                ),
            ],
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
        final landscapePlayer = _isLandscapePlayer;
        final open = landscapePlayer
            ? _landscapeColumnsVisible
            : _mainControlsExpanded;
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
        final chordTopGap = landscapePlayer ? 0.0 : panelTop - videoBottom;
        final overlayTop = _adjustmentsCoverVideo
            ? 0.0
            : landscapePlayer
            ? box.maxHeight * .58
            : chordPanel
            ? videoBottom
            : box.maxHeight < 450
            ? (panelTop - 48).clamp(0.0, panelTop)
            : panelTop;
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
                top: overlayTop,
                left: 0,
                right: 0,
                bottom: 0,
                child: Theme(
                  data: studioColumnTheme(
                    Theme.of(context),
                    mode: widget.appearance.mode,
                  ),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ClipRect(
                          key: const Key('unifiedAdjustmentsBlurBounds'),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(
                              sigmaX:
                                  widget.appearance.mode ==
                                          StudioAppearanceMode.glass &&
                                      !chordPanel
                                  ? 10
                                  : 0,
                              sigmaY:
                                  widget.appearance.mode ==
                                          StudioAppearanceMode.glass &&
                                      !chordPanel
                                  ? 10
                                  : 0,
                            ),
                            child: _adjustmentsCoverVideo
                                ? Material(
                                    color: _background,
                                    child: Column(
                                      children: [
                                        _coveredVideoTransport(box.maxHeight),
                                        Expanded(
                                          child: _sectionContent(
                                            media,
                                            viewportHeight: box.maxHeight,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : chordPanel
                                ? ClipRRect(
                                    key: const Key('unifiedChordOverlay'),
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(26),
                                    ),
                                    child: _sectionContent(
                                      media,
                                      topGap: chordTopGap,
                                      viewportHeight:
                                          box.maxHeight - overlayTop,
                                    ),
                                  )
                                : ColoredBox(
                                    color: _background,
                                    child: _sectionContent(media),
                                  ),
                          ),
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
    (StudioTab.appearanceSettings, 'Config.'),
  ];

  Widget _coveredVideoTransport(double availableHeight) {
    final durationMs = _player.duration.inMilliseconds;
    final canSeek = _player.canSeek && durationMs > 0;
    final positionMs =
        (_seekPreviewMs ?? _player.position.inMilliseconds.toDouble()).clamp(
          0.0,
          durationMs.toDouble(),
        );
    final height = (availableHeight / 8).clamp(0.0, 76.0);
    final topInset = height >= 64 ? 10.0 : 5.0;
    String stamp(double ms) {
      final seconds = (ms / 1000).floor();
      final minutes = seconds ~/ 60;
      return '$minutes:${(seconds % 60).toString().padLeft(2, '0')}';
    }

    void skip(int seconds) {
      final target = (_player.position.inMilliseconds + seconds * 1000).clamp(
        0,
        durationMs,
      );
      unawaited(_player.seek(Duration(milliseconds: target)));
    }

    return SizedBox(
      key: const Key('coveredVideoTransport'),
      height: height,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        decoration: studioPanelDecoration(
          radius: 28,
          mode: widget.appearance.mode,
        ),
        padding: EdgeInsets.fromLTRB(12, topInset, 12, 0),
        child: Column(
          children: [
            SizedBox(
              height: (height - topInset) * .55,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(stamp(positionMs), style: const TextStyle(fontSize: 10)),
                  const Spacer(),
                  IconButton(
                    key: const Key('coveredVideoBack10'),
                    tooltip: 'Recuar 10 segundos',
                    onPressed: canSeek ? () => skip(-10) : null,
                    icon: const Icon(Icons.replay_10, size: 20),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                  IconButton(
                    key: const Key('coveredVideoPlayPause'),
                    tooltip: _player.playing
                        ? 'Pausar vídeo'
                        : 'Reproduzir vídeo',
                    onPressed: _player.loaded
                        ? () => unawaited(_player.playPause())
                        : null,
                    icon: Icon(
                      _player.playing ? Icons.pause : Icons.play_arrow,
                      size: 23,
                    ),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                  IconButton(
                    key: const Key('coveredVideoForward10'),
                    tooltip: 'Avançar 10 segundos',
                    onPressed: canSeek ? () => skip(10) : null,
                    icon: const Icon(Icons.forward_10, size: 20),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                  const Spacer(),
                  Text(
                    stamp(durationMs.toDouble()),
                    style: const TextStyle(fontSize: 10),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 5,
                  ),
                  overlayShape: SliderComponentShape.noOverlay,
                ),
                child: Slider(
                  key: const Key('coveredVideoTimeline'),
                  min: 0,
                  max: durationMs > 0 ? durationMs.toDouble() : 1,
                  value: canSeek ? positionMs : 0,
                  onChanged: canSeek
                      ? (value) => setState(() => _seekPreviewMs = value)
                      : null,
                  onChangeEnd: canSeek
                      ? (value) {
                          setState(() => _seekPreviewMs = null);
                          unawaited(
                            _player.seek(Duration(milliseconds: value.round())),
                          );
                        }
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTabs() {
    final selected = _tab == StudioTab.player ? StudioTab.chords : _tab;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(4),
      decoration: studioPanelDecoration(
        radius: 26,
        mode: widget.appearance.mode,
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              key: const Key('unifiedSectionStrip'),
              children: [
                for (final (tab, label) in _visibleTabs)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: OutlinedButton(
                        key: Key('unifiedSection${tab.name}'),
                        onPressed: () => _select(tab),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: selected == tab
                              ? widget.appearance.mode ==
                                        StudioAppearanceMode.light
                                    ? Colors.white
                                    : const Color(0xFF161618)
                              : widget.appearance.mode ==
                                    StudioAppearanceMode.light
                              ? const Color(0xFF344054)
                              : const Color(0xFFC4C4C8),
                          side: BorderSide.none,
                          backgroundColor: selected == tab
                              ? widget.appearance.mode ==
                                        StudioAppearanceMode.light
                                    ? const Color(0xFF163E51)
                                    : Colors.white
                              : Colors.transparent,
                          minimumSize: const Size(0, 36),
                          padding: const EdgeInsets.symmetric(horizontal: 1),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(19),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(switch (tab) {
                              StudioTab.chords => Icons.music_note_outlined,
                              StudioTab.practice => Icons.graphic_eq,
                              StudioTab.setlist => Icons.queue_music,
                              StudioTab.audioSettings => Icons.equalizer,
                              StudioTab.appearanceSettings => Icons.tune,
                              _ => Icons.music_note_outlined,
                            }, size: 12),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (_adjustmentChoicesVisible)
            SizedBox(
              key: const Key('adjustmentDirectionChoices'),
              width: _adjustmentButtonSize.width,
              height: _adjustmentButtonSize.height,
            )
          else
            SizedBox(
              key: _adjustmentButtonAnchorKey,
              child: GestureDetector(
                onVerticalDragStart: (_) => _adjustmentsDrag = 0,
                onVerticalDragUpdate: (details) =>
                    _adjustmentsDrag += details.delta.dy,
                onVerticalDragEnd: (details) {
                  final direction = _adjustmentsDrag.abs() >= 20
                      ? _adjustmentsDrag
                      : details.primaryVelocity ?? 0;
                  if (direction < -20) {
                    _coverVideoWithAdjustments();
                  } else if (direction > 20) {
                    _lowerAdjustments();
                  }
                },
                child: IconButton(
                  key: const Key('visualMainAdjustments'),
                  tooltip: 'Expandir ou fechar ajustes',
                  onPressed: _showAdjustmentDirections,
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF303034),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(34, 34),
                    padding: EdgeInsets.zero,
                  ),
                  icon: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.keyboard_arrow_up, size: 15),
                      Icon(Icons.keyboard_arrow_down, size: 15),
                    ],
                  ),
                ),
              ),
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
    Widget? content,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: switch (widget.appearance.mode) {
        StudioAppearanceMode.light => const Color(0xFFF7F9FC),
        StudioAppearanceMode.glass => const Color(0x99303943),
        StudioAppearanceMode.dark => const Color(0xFF202023),
      },
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: widget.appearance.mode == StudioAppearanceMode.light
              ? const Color(0xFFB7C4D2)
              : const Color(0xFF4A4A50),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            key: key,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(icon, size: 16),
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
          if (content != null)
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: expanded ? content : const SizedBox.shrink(),
            ),
        ],
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
        color: _background,
        child: Column(
          children: [
            _sectionTabs(),
            Expanded(
              child: ChordSearchPanel(
                key: const Key('unifiedChordSearch'),
                initialQuery: _player.loaded
                    ? chordQueryFromVideoTitle(_player.title)
                    : '',
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
              appearance: widget.appearance,
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
      return SingleChildScrollView(
        key: const Key('unifiedAudioSettingsScroll'),
        padding: const EdgeInsets.only(bottom: 88),
        child: Column(
          children: [
            _sectionTabs(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _audioSettingsContent(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: StemPanel(onBeforePreview: _player.pause),
            ),
          ],
        ),
      );
    }
    if (_tab == StudioTab.appearanceSettings) {
      return SafeArea(
        top: false,
        child: SingleChildScrollView(
          key: const Key('unifiedAppearanceSettingsScroll'),
          padding: const EdgeInsets.only(bottom: 88),
          child: Column(
            children: [
              _sectionTabs(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: _appearanceSettingsContent(),
              ),
            ],
          ),
        ),
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
              appearanceMode: widget.appearance.mode,
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
                    content: Padding(
                      key: const Key('practiceMetronomeContent'),
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                      child: embeddedStudyTool(
                        'metronome',
                        beforePreview: _player.pause,
                        bandSession: _bandSession,
                        onApprovedRhythm: Platform.isAndroid
                            ? _player.loadApprovedRhythmPreview
                            : null,
                        onStopRhythm: Platform.isAndroid
                            ? _player.stopRhythmPreview
                            : null,
                        rhythmPlaying:
                            _player.isRhythmPreview && _player.playing,
                      ),
                    ),
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
                    content: Padding(
                      key: const Key('practiceProgressionContent'),
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                      child: PracticeProgressionCard(
                        controller: _practice,
                        embedded: true,
                      ),
                    ),
                  ),
                  if (const bool.fromEnvironment('TRANSPONO_PERSONAL_RHYTHM'))
                    AmbientRhythmTrial(appearanceMode: widget.appearance.mode),
                ],
              ),
            ),
          ],
        ),
      );
    }
    final chooseChordButton = DecoratedBox(
      key: const Key('unifiedChooseChordCard'),
      decoration: studioPanelDecoration(mode: widget.appearance.mode),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: const Key('unifiedChooseChord'),
          onTap: _chordActive ? _searchChord : _toggleChord,
          borderRadius: BorderRadius.circular(24),
          child: SizedBox(
            height: 48,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  Icon(
                    _chordActive
                        ? Icons.library_music_outlined
                        : Icons.queue_music,
                    size: 17,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _chordActive ? 'Trocar cifra' : 'Escolher cifra',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (!_chordActive)
                    const Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: studioMuted,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final autoScrollControls = _chordActive
        ? DecoratedBox(
            key: const Key('chordAutoScrollCard'),
            decoration: studioPanelDecoration(mode: widget.appearance.mode),
            child: SizedBox(
              height: 48,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Row(
                  children: [
                    const Icon(Icons.auto_mode, size: 15),
                    const SizedBox(width: 3),
                    const Expanded(
                      child: Text(
                        'Rolar',
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
                      constraints: const BoxConstraints.tightFor(
                        width: 28,
                        height: 36,
                      ),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      onPressed: _chordScrollSpeed > .5
                          ? () => setState(
                              () => _chordScrollSpeed =
                                  (_chordScrollSpeed - .25).clamp(.5, 2),
                            )
                          : null,
                      icon: const Icon(Icons.remove, size: 16),
                    ),
                    Text(
                      '${_chordScrollSpeed.toStringAsFixed(2)}×',
                      key: const Key('chordAutoScrollSpeed'),
                      style: const TextStyle(fontSize: 10),
                    ),
                    IconButton(
                      key: const Key('chordAutoScrollFaster'),
                      tooltip: 'Rolar cifra mais depressa',
                      constraints: const BoxConstraints.tightFor(
                        width: 28,
                        height: 36,
                      ),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      onPressed: _chordScrollSpeed < 2
                          ? () => setState(
                              () => _chordScrollSpeed =
                                  (_chordScrollSpeed + .25).clamp(.5, 2),
                            )
                          : null,
                      icon: const Icon(Icons.add, size: 16),
                    ),
                    IconButton.filledTonal(
                      key: const Key('chordAutoScrollToggle'),
                      tooltip: _chordAutoScroll
                          ? 'Pausar rolagem da cifra'
                          : 'Iniciar rolagem da cifra',
                      constraints: const BoxConstraints.tightFor(
                        width: 36,
                        height: 36,
                      ),
                      padding: EdgeInsets.zero,
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
    final controls = Column(
      children: [
        _sectionTabs(),
        UnifiedPlayerAdjustments(
          model: _player,
          youtubeNativeTransport: _player.isYouTube,
          appearanceMode: widget.appearance.mode,
          showPracticeControls: false,
          compactBottom: true,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Row(
            children: [
              Expanded(flex: _chordActive ? 35 : 1, child: chooseChordButton),
              if (_chordActive) ...[
                const SizedBox(width: 6),
                Expanded(flex: 65, child: autoScrollControls),
              ],
            ],
          ),
        ),
      ],
    );
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
                  key: const Key('unifiedChordControlsBackdrop'),
                  decoration: BoxDecoration(
                    color: _background,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(26),
                    ),
                  ),
                  child: Column(
                    children: [controls, const SizedBox(height: 4)],
                  ),
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
              color: _background,
              child: Padding(
                key: const Key('unifiedChordFrame'),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: Container(
                  key: const Key('unifiedChordFixedBackground'),
                  decoration:
                      studioPanelDecoration(
                        radius: 26,
                        mode: widget.appearance.mode,
                      ).copyWith(
                        gradient:
                            widget.appearance.mode == StudioAppearanceMode.dark
                            ? playerChordDarkGradient
                            : null,
                      ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
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
                              fixedDarkBackground: true,
                              revision: _chordRevision,
                              appearance: widget.appearance,
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
              decoration: BoxDecoration(
                color: _background,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(26),
                ),
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
    final landscapePlayer = _isLandscapePlayer;
    return Listener(
      // A touch outside the page (an app button, the adjustments) takes the
      // focus away from the page's search field, as tapping elsewhere does
      // in a normal browser. Gecko keeps it otherwise, and then tapping the
      // field again opens no keyboard.
      behavior: HitTestBehavior.translucent,
      onPointerDown: _releasePageFocusOutside,
      child: PopScope(
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
                    // Scrolling down in the open adjustments shrinks the close
                    // control to a small arrow; scrolling up brings back the
                    // full "Fechar ajustes" button.
                    NotificationListener<UserScrollNotification>(
                      onNotification: (notification) {
                        if (!_mainControlsExpanded || landscapePlayer) {
                          return false;
                        }
                        final compact =
                            notification.direction == ScrollDirection.reverse
                            ? true
                            : notification.direction == ScrollDirection.forward
                            ? false
                            : null;
                        if (compact != null && compact != _closeCompact) {
                          setState(() => _closeCompact = compact);
                        }
                        return false;
                      },
                      child: Column(
                        children: <Widget>[Expanded(child: _mainPanel(media))],
                      ),
                    ),
                    if (!landscapePlayer &&
                        _mainControlsExpanded &&
                        !_adjustmentsCoverVideo)
                      Positioned(
                        bottom: MediaQuery.viewPaddingOf(context).bottom + 8,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                                  opacity: animation,
                                  child: ScaleTransition(
                                    scale: animation,
                                    child: child,
                                  ),
                                ),
                            child: _closeCompact
                                ? _CompactCloseAdjustments(
                                    key: const ValueKey('compactClose'),
                                    onPressed: _toggleMainAdjustments,
                                  )
                                : _MainAdjustmentsBar(
                                    key: const ValueKey('fullClose'),
                                    expanded: true,
                                    onPressed: _toggleMainAdjustments,
                                  ),
                          ),
                        ),
                      ),
                    if ((landscapePlayer && !_landscapeColumnsVisible) ||
                        (!landscapePlayer && !_mainControlsExpanded))
                      Positioned(
                        bottom: MediaQuery.viewPaddingOf(context).bottom + 8,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: _MainAdjustmentsBar(
                            expanded: false,
                            onPressed: landscapePlayer
                                ? _openLandscapeAdjustments
                                : _toggleMainAdjustments,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    ),
    );
  }

  void _releasePageFocusOutside(PointerDownEvent event) {
    final session = _player.youtube;
    if (session == null || !(_player.isYouTube || _browsing)) return;
    final box = _mediaKey.currentContext?.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      final local = box.globalToLocal(event.position);
      if (box.size.contains(local)) return; // A touch on the page itself.
    }
    unawaited(session.releaseFocus());
  }
}

/// Small round "close adjustments" arrow shown while scrolling down.
class _CompactCloseAdjustments extends StatelessWidget {
  const _CompactCloseAdjustments({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 46,
    height: 46,
    child: IconButton.filled(
      key: const Key('visualCloseAdjustmentsCompact'),
      tooltip: 'Fechar ajustes',
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF161618),
        padding: EdgeInsets.zero,
      ),
      icon: const Icon(Icons.keyboard_arrow_down, size: 30),
    ),
  );
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
