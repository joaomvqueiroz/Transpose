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

  // Two-page mode: [_browse] browses and searches; the player session plays
  // the chosen video, full screen or in the app's mini player over it.
  YouTubeBrowserSession? _browse;
  Widget? _browseView;
  final GlobalKey _browseKey = GlobalKey(debugLabel: 'browse-surface');
  Offset? _miniOffset;
  bool _miniDragging = false;

  // The mini player is drawn at the full-size video's place: the first frame
  // after shrinking (it then moves to its corner) and while it grows back.
  bool _miniFull = false;
  bool _browsePlayerPlaying = false;
  bool _miniExpanding = false;

  // Closed with its "x": paused and out of sight until another video is
  // chosen or the player is opened again.
  bool _miniClosed = false;

  // The mini player's two buttons: 0 = on a dark disc, 1 = hollow (only the
  // icon), 2 = gone. Three seconds in each of the first two; a tap on the
  // mini player brings them back and the count starts again.
  int _miniControls = 0;
  Timer? _miniControlsTimer;
  int? _miniPointerId;
  Offset? _miniPointerOrigin;
  Offset _miniPointerDelta = Offset.zero;
  bool get _twoPages => _browse != null;

  // Fingers currently down on the player surface, and a minimize request
  // that waits for them to lift (see _minimize).
  final Set<int> _mediaPointers = <int>{};
  bool _minimizeWhenReleased = false;

  void _mediaPointerReleased(PointerEvent event) {
    _mediaPointers.remove(event.pointer);
    if (_mediaPointers.isNotEmpty || !_minimizeWhenReleased) return;
    // After this event finished its dispatch (the platform view gets its
    // "up" through the pointer router, after the hit-test targets).
    scheduleMicrotask(() {
      if (mounted && _minimizeWhenReleased && _mediaPointers.isEmpty) {
        _minimize();
      }
    });
  }

  // Screen size outside picture-in-picture: the page keeps that layout and
  // the small window shows its video area, scaled.
  Size _lastScreen = const Size(400, 800);
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
    inPictureInPicture.addListener(_pipChanged);
    final browseFactory = widget.browseSessionFactory;
    if (browseFactory != null && widget.playerController == null) {
      final browse = browseFactory()
        ..browseOnly = true
        ..onOpenRequest = _playChosen
        // A Short playing in the browse page: the chosen video pauses, so
        // the two are never heard together.
        ..onShortsPlaying = () {
          if (_player.loaded && _player.playing) unawaited(_player.pause());
        };
      // Same light or dark look as the player page.
      unawaited(browse.setAppearanceMode(widget.appearance.mode));
      browse.addListener(_browseChanged);
      _browse = browse;
      _browseView = browse.buildView();
    }
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
      if (session != null) {
        unawaited(session.setAppearanceMode(widget.appearance.mode));
      }
      final browse = _browse;
      if (browse != null) {
        unawaited(browse.setAppearanceMode(widget.appearance.mode));
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
    final browse = _browse;
    if (browse != null) {
      if (!mounted) return;
      setState(() => _browsing = true);
      _syncPageRoles();
      try {
        await browse.start(
          widget.youtubeHome ?? Uri.https('m.youtube.com', '/'),
        );
        final String query = widget.initialYouTubeQuery?.trim() ?? '';
        if (query.isNotEmpty && mounted) await browse.search(query);
      } on Object {
        // The page shows its own error; the studio stays usable.
      }
      return;
    }
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

  /// Which page drives the floating controls, and the player page's
  /// drag-down (it asks the app for the mini player).
  void _syncPageRoles() {
    final browse = _browse;
    if (browse == null) return;
    browse.publishesPageState = _browsing;
    final player = _player.youtube;
    if (player == null) return;
    player.publishesPageState = !_browsing;
    if (!player.appMini) {
      player
        ..appMini = true
        ..onMinimizeRequest = _minimize;
      unawaited(player.applyPageRoles());
    }
  }

  bool? _browseCanGoBack;
  bool? _browsePlayerLoaded;
  bool? _browsePlayerIsYouTube;
  String? _browsePlayerMessage;

  /// The browse page changed: only what the studio shows of it (first page
  /// ready, the back arrow). Rebuilding the whole studio on every page
  /// snapshot made scrolling stutter.
  void _browseChanged() {
    final browse = _browse;
    if (browse == null) return;
    if (browse.contentReady) _reportInitialBrowserReady();
    if (browse.canGoBack != _browseCanGoBack) {
      _browseCanGoBack = browse.canGoBack;
      if (mounted) setState(() {});
    }
  }

  /// A video chosen in the browse page: play it full screen in the player.
  void _playChosen(Uri watch) {
    if (!mounted) return;
    final player = _player.youtube;
    if (player != null) unawaited(player.setAppMiniSurface(false));
    setState(() {
      _browsing = false;
      _miniFull = false;
      _miniExpanding = false;
      _miniClosed = false;
      _mainControlsExpanded = false;
      _adjustmentsCoverVideo = false;
    });
    _syncPageRoles();
    unawaited(_player.playWatch(watch));
  }

  /// The video shrinks to the app's mini player and the browse page (with
  /// the search the video came from) comes back behind it; it keeps playing.
  void _minimize() {
    if (!mounted || !_twoPages || _browsing) return;
    // Never move the player's platform view while a finger is still on it
    // (the drag that asks for the mini player is exactly that). Moving it
    // re-parents its render object, which detaches it: Flutter then resets
    // the view's gesture recognizer and the finger's "up" never reaches the
    // native WebView, while Flutter's Android motion-event converter keeps
    // that pointer as down. Every later touch is then sent as a second
    // finger of a gesture that never ends, so taps and scrolling stop
    // working. Wait for the finger to lift.
    if (_mediaPointers.isNotEmpty) {
      _minimizeWhenReleased = true;
      return;
    }
    _minimizeWhenReleased = false;
    _hideAdjustmentChoices();
    final player = _player.youtube;
    if (player != null) unawaited(player.setAppMiniSurface(true));
    setState(() {
      _browsing = true;
      // Starts where the full-size video was and moves to its corner.
      _miniFull = true;
      _miniExpanding = false;
      _miniClosed = false;
      _mainControlsExpanded = false;
      _adjustmentsCoverVideo = false;
      _landscapeColumnsVisible = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _browsing && !_miniExpanding) {
        setState(() => _miniFull = false);
      }
    });
    _showMiniControls();
    _syncPageRoles();
  }

  void _showMiniControls() {
    _miniControlsTimer?.cancel();
    if (!mounted) return;
    if (_miniControls != 0) setState(() => _miniControls = 0);
    _miniControlsTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _miniControls = 1);
      _miniControlsTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _miniControls = 2);
      });
    });
  }

  /// A tap on the mini player: it grows back to the full-size video's place,
  /// and only then the player page takes over.
  void _expandMini() {
    if (!mounted || !_browsing || _miniExpanding) return;
    if (_miniClosed) {
      _finishExpandMini();
      return;
    }
    setState(() {
      _miniExpanding = true;
      _miniFull = true;
    });
  }

  void _miniMoveEnded() {
    if (_miniExpanding) _finishExpandMini();
  }

  void _finishExpandMini({bool openAdjustments = false}) {
    _miniControlsTimer?.cancel();
    if (!mounted) return;
    final player = _player.youtube;
    if (player != null) unawaited(player.setAppMiniSurface(false));
    setState(() {
      _browsing = false;
      _miniFull = false;
      _miniExpanding = false;
      _miniClosed = false;
      if (openAdjustments) {
        _mainControlsExpanded = true;
        _adjustmentsCoverVideo = false;
      }
    });
    _syncPageRoles();
  }

  /// The mini player's "x": the video pauses and the small window goes away.
  void _closeMini() {
    _miniControlsTimer?.cancel();
    if (!mounted) return;
    unawaited(_player.pause());
    setState(() {
      _miniClosed = true;
      _miniFull = false;
      _miniExpanding = false;
    });
  }

  void _pipChanged() {
    // In the system's small window the page shows only the video, from its
    // top-left corner (the same page mode as the app's mini player), so the
    // picture is never cut by the page's own top bar or scroll position.
    // Back in the app, the page returns to what the screen was showing.
    final player = _player.youtube;
    if (player != null && _twoPages) {
      unawaited(
        player.setAppMiniSurface(inPictureInPicture.value || _browsing),
      );
    }
    if (mounted) setState(() {});
  }

  void _changed() {
    _syncPageRoles();
    unawaited(
      PictureInPicture.setVideoPlaying(
        _player.isYouTube && _player.loaded && _player.playing,
      ),
    );
    final startupSession = _player.youtube;
    if (startupSession != null) {
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
    final browsePresentationChanged =
        _browsePlayerLoaded != _player.loaded ||
        _browsePlayerIsYouTube != _player.isYouTube ||
        _browsePlayerMessage != _player.message ||
        // The mini player's pause/play icon.
        _browsePlayerPlaying != _player.playing;
    _browsePlayerPlaying = _player.playing;
    _browsePlayerLoaded = _player.loaded;
    _browsePlayerIsYouTube = _player.isYouTube;
    _browsePlayerMessage = _player.message;
    if (mounted) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _lastForegroundWidgetState = _widgetSnapshot();
        _homeWidgets.schedule(_lastForegroundWidgetState!);
      }
      _syncSystemUi();
      // The player reports its timeline several times per second. While the
      // browse page is visible, rebuilding the whole two-page stack for those
      // snapshots makes the second WebView's scrolling stutter. Only rebuild
      // when something actually displayed by that page changes.
      if (!_twoPages || !_browsing || browsePresentationChanged) {
        setState(() {});
      }
    }
    if (_twoPages ||
        !_browsing ||
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
      // The cover of the "now playing" widget: the video's own thumbnail.
      'art': () {
        final String id = _player.youtube?.media.videoId ?? '';
        return active &&
                _player.isYouTube &&
                RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id)
            ? 'https://i.ytimg.com/vi/$id/mqdefault.jpg'
            : '';
      }(),
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
      // A YouTube video keeps playing with the app in the background (iPhone:
      // background audio; Android: the system's picture-in-picture window).
      // The practice pause also pauses the player, so only when practising
      // or on another source.
      if (!_player.isYouTube) {
        unawaited(_practice.pause());
        unawaited(_player.pause());
      } else if (_practice.running) {
        unawaited(_practice.pause());
      }
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
    adjustmentsCoverScreen.value = false;
    _adjustmentChoicesOverlay?.remove();
    _adjustmentChoicesOverlay?.dispose();
    if (_immersiveLandscape) {
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    }
    WidgetsBinding.instance.removeObserver(this);
    _player.removeListener(_changed);
    inPictureInPicture.removeListener(_pipChanged);
    unawaited(PictureInPicture.setVideoPlaying(false));
    _browse?.removeListener(_browseChanged);
    _browse?.dispose();
    _practice.removeListener(_practiceChanged);
    _practice.dispose();
    _bandSession.dispose();
    _miniControlsTimer?.cancel();
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
          ? Listener(
              // Observes only (see _minimize): which fingers are down here.
              onPointerDown: (event) => _mediaPointers.add(event.pointer),
              onPointerUp: _mediaPointerReleased,
              onPointerCancel: _mediaPointerReleased,
              child:
                  _browser ?? const Center(child: CircularProgressIndicator()),
            )
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

  /// Two-page mode while browsing: the browse page fills the screen and,
  /// once a video was chosen, it plays on in the mini player over it.
  Widget _twoPageBrowse(Widget media) => LayoutBuilder(
    builder: (context, box) {
      final screen = Size(box.maxWidth, box.maxHeight);
      final padding = MediaQuery.paddingOf(context);
      return Stack(
        children: [
          Positioned.fill(
            child: SafeArea(
              child: _browserPage(
                KeyedSubtree(
                  key: _browseKey,
                  child: _browseView ?? const SizedBox.shrink(),
                ),
              ),
            ),
          ),
          if (_player.loaded && _player.isYouTube && !_miniClosed)
            _miniPlayer(media, screen, padding),
        ],
      );
    },
  );

  // The watch page's video starts under YouTube's 48 px top bar.
  static const double _miniVideoTop = 48;

  Rect _miniRect(Size screen, EdgeInsets padding) {
    // One eighth smaller than the first size (58% of the width, 220 to 280).
    // The page itself keeps its full size and is only drawn smaller, so
    // YouTube's player never sees a width below its 220 px minimum.
    final double width = (screen.width * .58).clamp(220.0, 280.0) * 7 / 8;
    final double height = width * 9 / 16;
    final Offset fallback = Offset(
      screen.width - width - 12,
      screen.height - padding.bottom - 76 - height,
    );
    final Offset at = _miniOffset ?? fallback;
    return Rect.fromLTWH(at.dx, at.dy, width, height);
  }

  /// Settles the mini player against the nearest side, inside the screen.
  void _settleMini(Size screen, EdgeInsets padding) {
    final Rect now = _miniRect(screen, padding);
    final double left = now.center.dx < screen.width / 2
        ? 12
        : screen.width - now.width - 12;
    final double top = now.top.clamp(
      padding.top + 56,
      screen.height - padding.bottom - 76 - now.height,
    );
    setState(() {
      _miniDragging = false;
      _miniOffset = Offset(left, top);
    });
  }

  void _miniPointerDown(PointerDownEvent event, Rect rect) {
    if (_miniPointerId != null) return;
    _miniPointerId = event.pointer;
    _miniPointerOrigin = _miniOffset ?? rect.topLeft;
    _miniPointerDelta = Offset.zero;
  }

  void _miniPointerMove(PointerMoveEvent event) {
    if (_miniPointerId != event.pointer) return;
    _miniPointerDelta += event.delta;
    if (!_miniDragging && _miniPointerDelta.distance < 8) return;
    final Offset origin = _miniPointerOrigin ?? Offset.zero;
    setState(() {
      _miniDragging = true;
      _miniOffset = origin + _miniPointerDelta;
    });
  }

  void _miniPointerEnd(
    PointerEvent event,
    Size screen,
    EdgeInsets padding, {
    bool expandIfTap = true,
  }) {
    if (_miniPointerId != event.pointer) return;
    final bool moved = _miniDragging;
    _miniPointerId = null;
    _miniPointerOrigin = null;
    _miniPointerDelta = Offset.zero;
    if (moved) {
      _settleMini(screen, padding);
    } else if (expandIfTap) {
      // With the buttons gone, the first tap only brings them back.
      if (_miniControls == 2) {
        _showMiniControls();
      } else {
        _expandMini();
      }
    }
  }

  /// Android picture-in-picture: only the video, filling the small window.
  Widget _pipView(Widget media) => ColoredBox(
    color: Colors.black,
    child: LayoutBuilder(
      builder: (context, box) {
        final Size page = _lastScreen;
        final double scale = box.maxWidth / page.width;
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: page.width,
            maxWidth: page.width,
            minHeight: page.height,
            maxHeight: page.height,
            child: Transform(
              alignment: Alignment.topLeft,
              // Two pages: the page is in its video-only mode (see
              // _pipChanged). One page: the video sits under the site's
              // top bar.
              transform: Matrix4.diagonal3Values(scale, scale, 1)
                ..translateByDouble(0, _twoPages ? 0 : -_miniVideoTop, 0, 1),
              child: SizedBox.fromSize(size: page, child: media),
            ),
          ),
        );
      },
    ),
  );

  /// Where the video sits at full size: the mini player grows to and shrinks
  /// from this, so the change between the two reads as one movement.
  Rect _miniFullRect(Size screen, EdgeInsets padding) => Rect.fromLTWH(
    0,
    padding.top + _miniVideoTop,
    screen.width,
    screen.width * 9 / 16,
  );

  Widget _miniPlayer(Widget media, Size screen, EdgeInsets padding) {
    final Rect mini = _miniRect(screen, padding);
    final Rect full = _miniFullRect(screen, padding);
    final Rect target = _miniFull ? full : mini;
    return TweenAnimationBuilder<Rect?>(
      key: const Key('appMiniPlayer'),
      tween: RectTween(end: target),
      duration: _miniDragging
          ? Duration.zero
          : const Duration(milliseconds: 280),
      curve: Curves.easeInOutCubic,
      onEnd: _miniMoveEnded,
      builder: (context, animated, _) {
        final Rect rect = animated ?? target;
        final double scale = rect.width / screen.width;
        // 0 at full size, 1 as the small window: corners, shadow and the
        // two buttons come in with it.
        final double small =
            ((full.width - rect.width) / (full.width - mini.width)).clamp(
              0.0,
              1.0,
            );
        final BorderRadius corners = BorderRadius.circular(12 * small);
        return Positioned.fromRect(
          rect: rect,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: corners,
              boxShadow: [
                BoxShadow(
                  color: Color.fromRGBO(0, 0, 0, .6 * small),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: corners,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    child: Listener(
                      key: const Key('appMiniPlayerTouch'),
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: (event) => _miniPointerDown(event, mini),
                      onPointerMove: _miniPointerMove,
                      onPointerUp: (event) =>
                          _miniPointerEnd(event, screen, padding),
                      onPointerCancel: (event) => _miniPointerEnd(
                        event,
                        screen,
                        padding,
                        expandIfTap: false,
                      ),
                      // The native view remains full-size; only its pixels
                      // are transformed and clipped. A tap anywhere but the
                      // two buttons expands the video, avoiding scaled
                      // native hit-test coordinates.
                      child: IgnorePointer(
                        child: OverflowBox(
                          alignment: Alignment.topLeft,
                          minWidth: screen.width,
                          maxWidth: screen.width,
                          minHeight: screen.height,
                          maxHeight: screen.height,
                          child: Transform(
                            alignment: Alignment.topLeft,
                            transform: Matrix4.diagonal3Values(scale, scale, 1),
                            child: SizedBox.fromSize(
                              size: screen,
                              child: media,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Like the YouTube app's mini player: only pause on the
                  // left and close on the right.
                  Positioned(
                    top: 4,
                    left: 4,
                    child: Opacity(
                      opacity: small,
                      child: _MiniPlayerButton(
                        key: const Key('appMiniPlayerPause'),
                        phase: _miniControls,
                        tooltip: _player.playing ? 'Pausar' : 'Reproduzir',
                        icon: _player.playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        onPressed: () {
                          _showMiniControls();
                          unawaited(_player.playPause());
                        },
                      ),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Opacity(
                      opacity: small,
                      child: _MiniPlayerButton(
                        key: const Key('appMiniPlayerClose'),
                        phase: _miniControls,
                        tooltip: 'Fechar vídeo',
                        icon: Icons.close_rounded,
                        onPressed: _closeMini,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _browserPage(Widget media) {
    // Back and reload act on the page being browsed (two-page mode: _browse).
    final session = _browse ?? _player.youtube;
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
              // On YouTube's own pages the button sits in the middle of the
              // site's bottom bar, where the YouTube app has its "+".
              ValueListenableBuilder<YouTubeBars?>(
                valueListenable: pageYouTubeBars,
                builder: (context, bars, pill) {
                  // Scrolled down: the site's bars slid away, and the
                  // button with them. On the Shorts page the app draws the
                  // whole bottom bar itself, under the page.
                  if (bars?.hidden == true || bars?.shorts == true) {
                    return const Positioned(
                      left: 0,
                      top: 0,
                      child: SizedBox.shrink(),
                    );
                  }
                  // YouTube itself, before the page reported its bars (the
                  // app just opened, a page is loading): nothing yet, instead
                  // of the wide button flashing over the page.
                  final Uri? home = widget.youtubeHome;
                  if (bars == null &&
                      _twoPages &&
                      (home == null || home.host == 'm.youtube.com')) {
                    return const Positioned(
                      left: 0,
                      top: 0,
                      child: SizedBox.shrink(),
                    );
                  }
                  final double? centre = bars?.pivot;
                  if (centre == null) return pill!;
                  final double? x = bars!.pivotX;
                  return Positioned(
                    left: x == null ? 0 : x - 22,
                    right: x == null ? 0 : null,
                    bottom: centre - 22,
                    child: Center(
                      widthFactor: x == null ? null : 1,
                      child: _BarAdjustmentsButton(
                        dark: bars.dark,
                        onPressed: () =>
                            _finishExpandMini(openAdjustments: true),
                      ),
                    ),
                  );
                },
                child: _player.loaded
                    ? const Positioned(
                        left: 0,
                        top: 0,
                        child: SizedBox.shrink(),
                      )
                    : Positioned(
                        left: 0,
                        right: 0,
                        bottom: 8,
                        // Browsing without a video (home, search, YouTube Music,
                        // SoundCloud…): the same arrow on scrolling down as with a
                        // video open.
                        child: ValueListenableBuilder<bool>(
                          valueListenable: pageScrolledDown,
                          builder: (context, scrolledDown, _) {
                            void open() => setState(() {
                              _browsing = false;
                              _mainControlsExpanded = true;
                              _adjustmentsCoverVideo = false;
                            });
                            return AnimatedSwitcher(
                              duration: const Duration(milliseconds: 180),
                              transitionBuilder: (child, animation) =>
                                  FadeTransition(
                                    opacity: animation,
                                    child: ScaleTransition(
                                      scale: animation,
                                      child: child,
                                    ),
                                  ),
                              child: scrolledDown
                                  ? Center(
                                      key: const ValueKey('browseCompactOpen'),
                                      child: _CompactCloseAdjustments(
                                        open: true,
                                        onPressed: open,
                                      ),
                                    )
                                  : _MainAdjustmentsBar(
                                      key: const ValueKey('browseFullOpen'),
                                      expanded: false,
                                      onPressed: open,
                                    ),
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
        // The Shorts page has no bottom bar on the site: the app draws one
        // under the page (the page gets shorter and lays itself out).
        ValueListenableBuilder<YouTubeBars?>(
          valueListenable: pageYouTubeBars,
          builder: (context, bars, _) {
            final browse = _browse;
            if (bars?.shorts != true || browse == null) {
              return const SizedBox.shrink();
            }
            void open(String path) => unawaited(
              browse.start(Uri.https('m.youtube.com', path)).catchError((_) {}),
            );
            return _ShortsBottomBar(
              dark: bars!.dark,
              avatar: bars.avatar,
              onHome: () => open('/'),
              onYou: () => open('/feed/library'),
              onAdjustments: () => _finishExpandMini(openAdjustments: true),
            );
          },
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
              // Room under the last control so it scrolls clear of the
              // floating "Fechar ajustes". Inside the backdrop: as padding of
              // the scroll view it stayed transparent and showed the page.
              child: Column(children: [controls, const SizedBox(height: 88)]),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = _mediaSurface();
    if (inPictureInPicture.value && _player.loaded && _player.isYouTube) {
      return _pipView(media);
    }
    _lastScreen = MediaQuery.sizeOf(context);
    final landscapePlayer = _isLandscapePlayer;
    // The floating start-screen button hides while the adjustments cover the
    // whole screen.
    final cover = _mainControlsExpanded && _adjustmentsCoverVideo;
    if (adjustmentsCoverScreen.value != cover) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        adjustmentsCoverScreen.value =
            mounted && _mainControlsExpanded && _adjustmentsCoverVideo;
      });
    }
    return Listener(
      // A touch outside the page (an app button, the adjustments) takes the
      // focus away from the page's search field, as tapping elsewhere does
      // in a normal browser. Gecko keeps it otherwise, and then tapping the
      // field again opens no keyboard.
      behavior: HitTestBehavior.translucent,
      onPointerDown: _releasePageFocusOutside,
      child: PopScope(
        canPop: !_browsing && !(_twoPages && _player.loaded),
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          final browse = _browse;
          if (browse != null) {
            // Two pages: back shrinks the video (it keeps playing); while
            // browsing it goes back in the browse page.
            if (!_browsing) {
              _minimize();
            } else if (browse.canGoBack) {
              unawaited(browse.goBack());
            }
            return;
          }
          unawaited(_player.pause());
          setState(() => _browsing = false);
        },
        child: Scaffold(
          body: _browsing
              ? _twoPages
                    ? _twoPageBrowse(media)
                    : SafeArea(child: _browserPage(media))
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
                              : notification.direction ==
                                    ScrollDirection.forward
                              ? false
                              : null;
                          if (compact != null && compact != _closeCompact) {
                            setState(() => _closeCompact = compact);
                          }
                          return false;
                        },
                        child: Column(
                          children: <Widget>[
                            Expanded(child: _mainPanel(media)),
                          ],
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
                            // Like "Fechar ajustes": scrolling the page down
                            // shrinks it to a small arrow, scrolling up
                            // brings back the full button.
                            child: ValueListenableBuilder<bool>(
                              valueListenable: pageScrolledDown,
                              builder: (context, scrolledDown, _) {
                                final open = landscapePlayer
                                    ? _openLandscapeAdjustments
                                    : _toggleMainAdjustments;
                                return AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 180),
                                  transitionBuilder: (child, animation) =>
                                      FadeTransition(
                                        opacity: animation,
                                        child: ScaleTransition(
                                          scale: animation,
                                          child: child,
                                        ),
                                      ),
                                  child: scrolledDown && !landscapePlayer
                                      ? _CompactCloseAdjustments(
                                          key: const ValueKey('compactOpen'),
                                          open: true,
                                          onPressed: open,
                                        )
                                      : _MainAdjustmentsBar(
                                          key: const ValueKey('fullOpen'),
                                          expanded: false,
                                          onPressed: open,
                                        ),
                                );
                              },
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

/// The bottom bar under the Shorts page, like the YouTube app's: home,
/// Shorts (the page being shown), the adjustments button and the account.
class _ShortsBottomBar extends StatelessWidget {
  const _ShortsBottomBar({
    required this.dark,
    required this.avatar,
    required this.onHome,
    required this.onYou,
    required this.onAdjustments,
  });

  final bool dark;
  final String avatar;
  final VoidCallback onHome;
  final VoidCallback onYou;
  final VoidCallback onAdjustments;

  @override
  Widget build(BuildContext context) {
    final Color ink = dark ? const Color(0xFFF1F1F1) : const Color(0xFF0F0F0F);
    // iPhone: a floating pill on a dark strip, like the YouTube app there;
    // the page being shown (Shorts) stands on a lighter patch.
    final bool pill = Platform.isIOS;
    final Widget row = _row(ink, pill);
    if (pill) {
      return Container(
        key: const Key('shortsBottomBar'),
        color: dark ? const Color(0xFF0F0F0F) : Colors.white,
        padding: const EdgeInsets.fromLTRB(24, 6, 24, 10),
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF121212) : const Color(0xFFF7F7F7),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: dark ? const Color(0x1FFFFFFF) : const Color(0x1F000000),
            ),
          ),
          child: row,
        ),
      );
    }
    return Container(
      key: const Key('shortsBottomBar'),
      height: 48,
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF0F0F0F) : Colors.white,
        border: Border(
          top: BorderSide(
            color: dark ? const Color(0x1FFFFFFF) : const Color(0x1F000000),
          ),
        ),
      ),
      child: row,
    );
  }

  Widget _row(Color ink, bool pill) => Row(
    children: [
      Expanded(
        child: _BarShapeButton(
          key: const Key('shortsBarHome'),
          tooltip: 'Início',
          shape: _homeOutlineIconPath(),
          color: ink,
          onPressed: onHome,
        ),
      ),
      Expanded(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: pill
                ? (dark ? const Color(0x29FFFFFF) : const Color(0x1A000000))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(21),
          ),
          child: _BarShapeButton(
            tooltip: 'Shorts',
            shape: _shortsFilledIconPath(),
            color: ink,
            onPressed: null,
          ),
        ),
      ),
      Expanded(
        child: Center(
          child: _BarAdjustmentsButton(dark: dark, onPressed: onAdjustments),
        ),
      ),
      Expanded(
        child: IconButton(
          key: const Key('shortsBarYou'),
          tooltip: 'Você',
          onPressed: onYou,
          icon: avatar.isEmpty
              ? Icon(Icons.account_circle_outlined, size: 28, color: ink)
              : ClipOval(
                  child: Image.network(
                    avatar,
                    width: 26,
                    height: 26,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stack) => Icon(
                      Icons.account_circle_outlined,
                      size: 28,
                      color: ink,
                    ),
                  ),
                ),
        ),
      ),
    ],
  );
}

/// A bar icon drawn from a shape of the site's own icon set (24 x 24 box).
class _BarShapeButton extends StatelessWidget {
  const _BarShapeButton({
    super.key,
    required this.tooltip,
    required this.shape,
    required this.color,
    required this.onPressed,
  });

  final String tooltip;
  final Path shape;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed ?? () {},
    icon: CustomPaint(
      size: const Size(28, 28),
      painter: _ShapePainter(shape, color),
    ),
  );
}

class _ShapePainter extends CustomPainter {
  const _ShapePainter(this.shape, this.color);

  final Path shape;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    canvas.drawPath(shape, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ShapePainter old) => old.color != color;
}

/// One of the mini player's two buttons: a white icon on a dark disc.
class _MiniPlayerButton extends StatelessWidget {
  const _MiniPlayerButton({
    super.key,
    required this.phase,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  /// 0 = on a dark disc, 1 = hollow (only the icon), 2 = gone.
  final int phase;
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: phase == 2,
    child: AnimatedOpacity(
      opacity: phase == 2 ? 0 : 1,
      duration: const Duration(milliseconds: 350),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: phase == 0 ? const Color(0x73000000) : Colors.transparent,
        ),
        child: Material(
          type: MaterialType.transparency,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: IconButton(
            tooltip: tooltip,
            onPressed: onPressed,
            icon: Icon(icon, size: 20),
            color: Colors.white,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 30, height: 30),
          ),
        ),
      ),
    ),
  );
}

/// The adjustments button inside YouTube's bottom bar, in the slot where
/// the YouTube app has its "+": a plain sliders icon, the size of the bar's
/// own icons (no ring around it, and it does not change).
class _BarAdjustmentsButton extends StatelessWidget {
  const _BarAdjustmentsButton({required this.dark, required this.onPressed});

  final bool dark;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 44,
    height: 44,
    child: IconButton(
      key: const Key('barOpenAdjustments'),
      tooltip: 'Abrir ajustes',
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      icon: Icon(
        Icons.tune_rounded,
        size: 28,
        color: dark ? const Color(0xFFF1F1F1) : const Color(0xFF0F0F0F),
      ),
    ),
  );
}

/// Small round "close adjustments" arrow shown while scrolling down.
class _CompactCloseAdjustments extends StatelessWidget {
  const _CompactCloseAdjustments({
    super.key,
    required this.onPressed,
    this.open = false,
  });

  final VoidCallback onPressed;

  /// The same small arrow for "Abrir ajustes" (pointing up) while the page
  /// is scrolled down.
  final bool open;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 46,
    height: 46,
    // Hollow: transparent with a white outline, so it hides little of the
    // adjustments underneath.
    child: IconButton.outlined(
      key: Key(
        open ? 'visualOpenAdjustmentsCompact' : 'visualCloseAdjustmentsCompact',
      ),
      tooltip: open ? 'Abrir ajustes' : 'Fechar ajustes',
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.white, width: 1.6),
        padding: EdgeInsets.zero,
      ),
      icon: Icon(
        open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
        size: 30,
      ),
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
