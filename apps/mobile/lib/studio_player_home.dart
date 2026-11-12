part of 'studio_visual_app.dart';

class _StudioVisualHomeState extends State<StudioVisualHome>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  // The adjustments sit on the same colour as the YouTube page behind them
  // (white in its light theme, #0F0F0F in its dark one).
  // On YouTube Music it is the colour of the song's own screen, as on
  // Spotify.
  Color get _background => studioMusicSource && musicPlayerTint.value != null
      ? musicPlayerTint.value!
      : studioYouTubeSkin
      ? youtubeBase
      : studioSpotifySkin
      ? spotifySheetColor
      : widget.appearance.mode == StudioAppearanceMode.light
      ? Colors.white
      : widget.appearance.mode == StudioAppearanceMode.glass
      ? const Color(0x77080809)
      : const Color(0xFF0F0F0F);
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
  ScrollController? _chordTextScroll;
  Timer? _chordAutoTimer;
  bool _chordAutoScroll = false;
  double _chordScrollSpeed = 1;
  StudioTab _tab = StudioTab.player;
  bool _browsing = false;
  bool _chordActive = false;
  bool _mainControlsExpanded = false;
  bool _adjustmentsCoverVideo = false;
  bool _landscapeColumnsVisible = false;
  bool _immersiveLandscape = false;
  Orientation? _lastOrientation;
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
  VelocityTracker? _miniVelocity;
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
    pageAdjustRequests.addListener(_pageAdjust);
    BackgroundPlayback.listen(_backgroundAction);
    musicSongTabs.addListener(_songTabsChanged);
    musicPlayerTint.addListener(_musicTintChanged);
    spotifyPlayerOpen.addListener(_spotifyPlayerChanged);
    _homeWidgets = HomeWidgetBridge(onAction: _onWidgetAction);
    // iPhone's own glass for the bottom bar, where the system has it.
    unawaited(
      GlassBar.checkAvailable().then((_) {
        if (!mounted || !nativeGlassBar.value) return;
        unawaited(_browse?.applyPageRoles());
        unawaited(_player.youtube?.applyPageRoles());
        setState(() {});
      }),
    );
    unawaited(_homeWidgets.initialize());
    _player.addListener(_changed);
    _practice.addListener(_practiceChanged);
    inPictureInPicture.addListener(_pipChanged);
    PictureInPicture.onAction = _pipButton;
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
    // The page that takes over starts at its top: nothing is hidden for a
    // scroll made on the other page.
    pageScrolledDown.value = false;
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
    // The page that takes over starts at its top: nothing is hidden for a
    // scroll made on the other page.
    pageScrolledDown.value = false;
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

  /// This studio browses YouTube Music.
  bool get _musicSource => widget.youtubeHome?.host == 'music.youtube.com';

  /// The bottom bar stands on the player page too (two pages, a YouTube
  /// video open, upright, adjustments closed).
  bool get _playerBarShown =>
      _twoPages &&
      !_browsing &&
      // The big player (YouTube Music, Spotify): no bar under it; the
      // adjustments come up from under the player.
      !_spotifyScroll &&
      !_isLandscapePlayer &&
      !_mainControlsExpanded &&
      _player.loaded &&
      _player.isYouTube;

  /// A tap on the player page's bottom bar: the adjustments open here; the
  /// other three shrink the video and open that page behind it.
  void _playerBarTap(String name) {
    if (name == 'adjust') {
      _toggleMainAdjustments();
      return;
    }
    _minimize();
    // Already on that page: it stays where it was (no jump to its top).
    unawaited(_browse?.openTab(name, keepPlace: true));
  }

  /// The bar's adjustments button: there is nothing to adjust before a
  /// video is chosen, so it only opens with one (false: the button shakes).
  bool _openAdjustmentsFromBar() {
    if (!_player.loaded) return false;
    _finishExpandMini(openAdjustments: true);
    return true;
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

  /// The small window's buttons: the same actions as the home-screen
  /// widget's (play or pause, back and forward 10 seconds).
  void _pipButton(String name) => unawaited(_runWidgetAction(name));

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
    // Spotify goes on in the background with its notification, like its own
    // app; a YouTube video goes to the small window.
    unawaited(
      PictureInPicture.setVideoPlaying(
        _player.isYouTube &&
            _player.loaded &&
            _player.playing &&
            !studioSpotifySource &&
            // YouTube Music goes on in the background like Spotify.
            !studioMusicSource,
      ),
    );
    _updateBackground();
    final startupSession = _player.youtube;
    if (startupSession != null) {
      unawaited(startupSession.setAppearanceMode(widget.appearance.mode));
    }
    if (startupSession != null && startupSession.contentReady) {
      _reportInitialBrowserReady();
    }
    if (_chordSource != _player.sourceKey) {
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
    pageAdjustRequests.removeListener(_pageAdjust);
    BackgroundPlayback.unlisten();
    musicSongTabs.removeListener(_songTabsChanged);
    musicPlayerTint.removeListener(_musicTintChanged);
    unawaited(BackgroundPlayback.stop());
    spotifyPlayerOpen.removeListener(_spotifyPlayerChanged);
    _pull.dispose();
    if (_immersiveLandscape) {
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    }
    WidgetsBinding.instance.removeObserver(this);
    _player.removeListener(_changed);
    inPictureInPicture.removeListener(_pipChanged);
    if (PictureInPicture.onAction == _pipButton) {
      PictureInPicture.onAction = null;
    }
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

  // Where the selection came from, for the tabs' pill to slide from there,
  // and which way the new content comes in.
  StudioTab? _previousTab;
  int _tabDirection = 0;
  // The frame around the tabs differs between the tone tab and the others:
  // that change is applied at once, not animated.
  bool _tabJump = false;

  static int _tabOrder(StudioTab tab) => switch (tab) {
    StudioTab.player || StudioTab.chords => 0,
    StudioTab.practice => 1,
    StudioTab.audioSettings => 2,
    StudioTab.setlist => 3,
    _ => 4,
  };

  /// A tab's content, coming in when the tab is chosen.
  Widget _enter(Widget child) => TabEntrance(
    key: ValueKey('tabEntrance${_tabOrder(_tab)}'),
    direction: _tabDirection,
    child: child,
  );

  void _select(StudioTab tab) {
    if (tab != StudioTab.chords && tab != StudioTab.player) {
      _stopChordAutoScroll();
    }
    _panelAtTop = true;
    // A new tab starts at its top: its bar shows again.
    _handleScroll.value = 0;
    final bool wasTone = _tab == StudioTab.chords || _tab == StudioTab.player;
    final bool toTone =
        tab == StudioTab.chords ||
        tab == StudioTab.player ||
        tab == StudioTab.stage ||
        tab == StudioTab.instruments;
    if (_mainControlsExpanded && wasTone != toTone) {
      _tabJump = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _tabJump = false);
    }
    setState(() {
      _previousTab = _tab;
      _tabDirection = (_tabOrder(tab) - _tabOrder(_tab)).sign;
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
  }

  /// The close control is the small arrow (after scrolling down) rather than
  /// the full "Fechar ajustes" button.
  bool _closeCompact = false;

  // The adjustments sheet at its lowest height: only the tabs and the first
  // card (the tone), with the video and most of the page in sight.
  bool _sheetLow = false;

  /// The page's own adjustments button (Spotify's bottom bar) was tapped.
  void _updateBackground() {
    if (!Platform.isAndroid) return;
    if (!(studioSpotifySource || studioMusicSource) || !_player.loaded) {
      unawaited(BackgroundPlayback.stop());
      return;
    }
    final String title = _player.title;
    final int dash = title.lastIndexOf(' - ');
    unawaited(
      BackgroundPlayback.update(
        title: dash > 0 ? title.substring(0, dash) : title,
        artist: dash > 0 ? title.substring(dash + 3) : '',
        playing: _player.playing,
        position: _player.position,
        duration: _player.duration,
      ),
    );
  }

  /// A tap on the notification or the lock screen.
  void _backgroundAction(String action) {
    if (!mounted) return;
    final session = _player.youtube;
    switch (action) {
      case 'play':
        if (!_player.playing) unawaited(_player.playPause());
      case 'pause':
        if (_player.playing) unawaited(_player.playPause());
      case 'next':
        if (session is SpotifyStudioSession) {
          unawaited(session.next());
        } else if (studioMusicSource) {
          unawaited(session?.musicSkip(forward: true));
        }
      case 'previous':
        if (session is SpotifyStudioSession) {
          unawaited(session.previous());
        } else if (studioMusicSource) {
          unawaited(session?.musicSkip(forward: false));
        }
      default:
        if (action.startsWith('seek:')) {
          final int? ms = int.tryParse(action.substring(5));
          if (ms != null) unawaited(_player.seek(Duration(milliseconds: ms)));
        }
    }
  }

  void _pageAdjust() {
    if (mounted) _toggleMainAdjustments();
  }

  void _toggleMainAdjustments() {
    if (_spotifyScroll) {
      unawaited(
        _pull.animateTo(_pull.value > .5 ? 0 : 1, curve: Curves.easeOutCubic),
      );
      return;
    }
    if (_mainControlsExpanded) _stopChordAutoScroll();
    setState(() {
      _closeCompact = false;
      _sheetLow = false;
      _mainControlsExpanded = !_mainControlsExpanded;
      _adjustmentsCoverVideo = false;
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
      _sheetLow = false;
    });
  }

  // How far the finger has dragged the adjustments' bar (null: no drag).
  double? _sheetDrag;

  /// The finger let go of the bar: settle on the nearest height.
  void _endSheetDrag(double velocity) {
    final double moved = _sheetDrag ?? 0;
    setState(() => _sheetDrag = null);
    final bool up = moved < -40 || (moved <= 0 && velocity < -500);
    final bool down = moved > 40 || (moved >= 0 && velocity > 500);
    // The floating sheet has one more height, the low one, between the
    // medium height and closed.
    final bool floating = _floatingSheet;
    if (up) {
      if (floating && _sheetLow) {
        setState(() => _sheetLow = false);
      } else {
        _coverVideoWithAdjustments();
      }
    } else if (down && floating && !_sheetLow) {
      setState(() => _sheetLow = true);
    } else if (down) {
      // From the top a long pull goes straight to closed.
      final bool farDown =
          _adjustmentsCoverVideo && moved > _lastScreen.height * .6;
      _lowerAdjustments();
      if (farDown && _mainControlsExpanded) _lowerAdjustments();
    }
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
                      style: TextStyle(color: studioMuted),
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

  /// A Spotify filter pill: white with a tick when chosen.
  Widget _spotifyPill({
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback onTap,
    Color? dot,
  }) => Material(
    color: selected ? skinChipOn : skinChip,
    shape: skinChipShape,
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      key: key,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (selected) ...[
              Icon(Icons.check, size: 18, color: skinChipOnInk),
              const SizedBox(width: 6),
            ],
            if (dot != null) ...[
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: selected ? skinChipOnInk : Colors.white,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  /// "Mais" on Spotify: theme pills, then the note colours as dotted pills.
  Widget _spotifyAppearanceSettings() {
    final a = widget.appearance;
    void pick(StudioAppearanceMode mode, bool apple, bool dark) =>
        widget.onAppearanceChanged?.call(
          a.copyWith(mode: mode, apple: apple, darkPanels: dark, native: false),
        );
    final glass = StudioAppearanceMode.glass;
    final bool n = a.native;
    final themes = [
      (
        'native',
        'Nativo',
        n,
        () => widget.onAppearanceChanged?.call(
          a.copyWith(
            mode: glass,
            apple: false,
            darkPanels: false,
            native: true,
          ),
        ),
      ),
      (
        'glass',
        'Escuro',
        !n && a.mode == glass && !a.apple && !a.darkPanels,
        () => pick(glass, false, false),
      ),
      (
        'light',
        'Claro',
        !n && a.mode == StudioAppearanceMode.light,
        () => pick(StudioAppearanceMode.light, false, false),
      ),
      (
        'apple',
        'Apple',
        !n && a.mode == glass && a.apple && !a.darkPanels,
        () => pick(glass, true, false),
      ),
      ('misto1', 'Médio', !n && a.darkPanels, () => pick(glass, false, true)),
    ];
    return Padding(
      key: const Key('appearanceSettings'),
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          skinLabel('Aparência'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (name, label, selected, onTap) in themes)
                _spotifyPill(
                  key: Key('appearanceMode$name'),
                  label: label,
                  selected: selected,
                  onTap: onTap,
                ),
            ],
          ),
          const SizedBox(height: 28),
          skinLabel('Cores das notas'),
          const SizedBox(height: 4),
          Text(
            'Toque numa nota para escolher a sua cor nas cifras.',
            style: TextStyle(fontSize: 13, color: skinSubdued),
          ),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 8,
            childAspectRatio: 1.9,
            children: [
              for (var index = 0; index < _noteNames.length; index++)
                Tooltip(
                  message: 'Alterar cor da nota ${_noteNames[index]}',
                  child: _spotifyPill(
                    key: Key('appearanceNote$index'),
                    label: _noteNames[index],
                    selected: false,
                    dot: playerChordDisplayColor(index, a),
                    onTap: () => _chooseNoteColor(index),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _appearanceSettingsContent() => studioSpotifySkin
      ? _spotifyAppearanceSettings()
      : Container(
          key: const Key('appearanceSettings'),
          decoration: studioPanelDecoration(mode: widget.appearance.mode),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'APARÊNCIA',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  // "Nativo": the YouTube app's own look on YouTube.
                  ChoiceChip(
                    key: const Key('appearanceModenative'),
                    label: const Text('Nativo'),
                    selected: widget.appearance.native,
                    onSelected: (_) => widget.onAppearanceChanged?.call(
                      widget.appearance.copyWith(
                        mode: StudioAppearanceMode.glass,
                        apple: false,
                        darkPanels: false,
                        native: true,
                      ),
                    ),
                  ),
                  // "Escuro" is the dark glass; the old opaque dark theme is gone.
                  for (final (mode, label) in const [
                    (StudioAppearanceMode.glass, 'Escuro'),
                    (StudioAppearanceMode.light, 'Claro'),
                  ])
                    ChoiceChip(
                      key: Key('appearanceMode${mode.name}'),
                      label: Text(label),
                      selected:
                          !widget.appearance.native &&
                          widget.appearance.mode == mode &&
                          !widget.appearance.apple &&
                          !widget.appearance.darkPanels,
                      onSelected: (_) => widget.onAppearanceChanged?.call(
                        widget.appearance.copyWith(
                          mode: mode,
                          apple: false,
                          darkPanels: false,
                          native: false,
                        ),
                      ),
                    ),
                  // The Apple design: glass colours plus the floating sheet.
                  ChoiceChip(
                    key: const Key('appearanceModeapple'),
                    label: const Text('Apple'),
                    selected:
                        !widget.appearance.native &&
                        widget.appearance.apple &&
                        !widget.appearance.darkPanels,
                    onSelected: (_) => widget.onAppearanceChanged?.call(
                      widget.appearance.copyWith(
                        mode: StudioAppearanceMode.glass,
                        apple: true,
                        darkPanels: false,
                        native: false,
                      ),
                    ),
                  ),
                  // The mixed themes: the same backgrounds, darker cards.
                  ChoiceChip(
                    key: const Key('appearanceModemisto1'),
                    label: const Text('Médio'),
                    selected:
                        !widget.appearance.native &&
                        widget.appearance.darkPanels,
                    onSelected: (_) => widget.onAppearanceChanged?.call(
                      widget.appearance.copyWith(
                        mode: StudioAppearanceMode.glass,
                        apple: false,
                        darkPanels: true,
                        native: false,
                      ),
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
                          color: playerChordDisplayColor(
                            index,
                            widget.appearance,
                          ),
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
        decoration: studioSpotifySkin
            ? null
            : studioPanelDecoration(mode: widget.appearance.mode),
        padding: studioSpotifySkin
            ? const EdgeInsets.only(top: 14)
            : const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (studioSpotifySkin)
              Row(
                children: [
                  Expanded(child: skinLabel('Equalizador')),
                  IconButton(
                    key: const Key('audioEqualizerReset'),
                    tooltip: 'Repor o equalizador',
                    onPressed: _player.isYouTube && _player.loaded
                        ? () {
                            for (final name in const [
                              'gain',
                              'bass',
                              'mid',
                              'treble',
                            ]) {
                              _setAudioControl(name, 0);
                            }
                          }
                        : null,
                    icon: const Icon(Icons.restart_alt, color: Colors.white),
                  ),
                ],
              )
            else
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
              Padding(
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
        decoration: studioSpotifySkin
            ? null
            : studioPanelDecoration(mode: widget.appearance.mode),
        padding: studioSpotifySkin
            ? EdgeInsets.zero
            : const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (studioSpotifySkin)
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: skinLabel('Efeitos em tempo real'),
              )
            else
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
      if (studioSpotifySkin) ...[
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Divider(height: 1, color: Color(0x1FFFFFFF)),
        ),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  skinLabel('Isolador de voz / playback'),
                  const SizedBox(height: 2),
                  Text(
                    'Indisponível no YouTube. Não é aplicado ao vídeo.',
                    style: TextStyle(fontSize: 12, color: skinSubdued),
                  ),
                ],
              ),
            ),
            const Switch(value: false, onChanged: null),
          ],
        ),
        const Padding(
          padding: EdgeInsets.only(top: 16, bottom: 4),
          child: Divider(height: 1, color: Color(0x1FFFFFFF)),
        ),
        _spotifyToolRow(
          key: const Key('audioResetProcessingCard'),
          icon: Icons.restore,
          title: 'Repor tom, velocidade e loop',
          subtitle: '0 st · 1,00× · sem A/B',
          onTap: _player.loaded
              ? () {
                  onClose?.call();
                  unawaited(_player.resetProcessing());
                }
              : () {},
        ),
        _spotifyToolRow(
          key: const Key('audioOpenLocalFile'),
          icon: Icons.folder_open,
          title: 'Abrir ficheiro local',
          onTap: _pickFile,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'No YouTube, o tom é experimental e o loop é aproximado. Ficheiros de vídeo locais ainda não suportam alteração de tom.',
            style: TextStyle(color: skinSubdued, fontSize: 12),
          ),
        ),
      ] else ...[
        const SizedBox(height: 12),
        Container(
          decoration: studioPanelDecoration(mode: widget.appearance.mode),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Isolador de Voz / Playback',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
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
        Text(
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
      ],
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
    if (studioSpotifySkin) {
      final shown = isDecibels
          ? '${value > 0 ? '+' : ''}${value.toStringAsFixed(0)} dB'
          : '${(value * 100).round()}%';
      return SizedBox(
        height: 44,
        child: Row(
          children: [
            SizedBox(
              width: 72,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
            Expanded(
              child: Slider(
                key: Key(key),
                min: min,
                max: max,
                divisions: ((max - min) * (isDecibels ? 1 : 100)).round(),
                value: value,
                onChanged: enabled
                    ? (next) => setState(() => preview(next))
                    : null,
                onChangeEnd: enabled ? apply : null,
              ),
            ),
            SizedBox(
              width: 56,
              child: Text(
                shown,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 13, color: Color(0xBFFFFFFF)),
              ),
            ),
          ],
        ),
      );
    }
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
          if (_player.loaded &&
              _player.isYouTube &&
              !_miniClosed &&
              _musicSource)
            ..._musicMiniBar(media, screen, padding)
          else if (_player.loaded && _player.isYouTube && !_miniClosed)
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
    // A little narrower than 16:9: with the slight zoom of the picture (see
    // _miniPlayer) the sides are trimmed instead of leaving dark bands.
    final double full = (screen.width * .58).clamp(220.0, 280.0) * 7 / 8;
    final double width = full * .95;
    final double height = full * 9 / 16;
    final Offset fallback = Offset(
      screen.width - width - 12,
      screen.height - padding.bottom - 76 - height,
    );
    final Offset at = _miniOffset ?? fallback;
    return Rect.fromLTWH(at.dx, at.dy, width, height);
  }

  /// Settles the mini player against the nearest side, inside the screen.
  ///
  /// Thrown with some speed ([velocity], pixels per second), it goes on in
  /// that direction and stays at the side, and the top or bottom, it was
  /// thrown to.
  void _settleMini(
    Size screen,
    EdgeInsets padding, {
    Offset velocity = Offset.zero,
  }) {
    final Rect now = _miniRect(screen, padding);
    final double highest = padding.top + 56;
    final double lowest = screen.height - padding.bottom - 76 - now.height;
    // Where the throw would carry it.
    final Offset centre = now.center + velocity * .22;
    final double left = centre.dx < screen.width / 2
        ? 12
        : screen.width - now.width - 12;
    final double top = velocity.dy < -900
        ? highest
        : velocity.dy > 900
        ? lowest
        : (centre.dy - now.height / 2).clamp(highest, lowest);
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
    _miniVelocity = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
  }

  void _miniPointerMove(PointerMoveEvent event) {
    if (_miniPointerId != event.pointer) return;
    _miniVelocity?.addPosition(event.timeStamp, event.position);
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
    final Offset velocity =
        _miniVelocity?.getVelocity().pixelsPerSecond ?? Offset.zero;
    _miniVelocity = null;
    if (moved) {
      _settleMini(
        screen,
        padding,
        velocity: velocity.distance > 500 ? velocity : Offset.zero,
      );
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
        // The picture fills the window's height with a slight zoom (none at
        // full size), centred, so a video's own dark bands fall outside.
        final double smallNow =
            ((full.width - rect.width) / (full.width - mini.width)).clamp(
              0.0,
              1.0,
            );
        final double scale =
            rect.height / (screen.width * 9 / 16) * (1 + .07 * smallNow);
        final double shiftX = (rect.width - screen.width * scale) / 2;
        final double shiftY = (rect.height - screen.width * 9 / 16 * scale) / 2;
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
                            transform: Matrix4.identity()
                              ..translateByDouble(shiftX, shiftY, 0, 1)
                              ..scaleByDouble(scale, scale, 1, 1),
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
                    top: 9,
                    left: 11,
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
                    top: 9,
                    right: 11,
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

  /// YouTube Music, song shrunk: no small video window (the song's screen
  /// would show as a tiny picture) but a playback bar, as in the YouTube
  /// Music app: cover, title, pause and next, just above the bottom bar.
  /// A tap on it opens the song again. The page keeps playing, kept in the
  /// tree out of sight.
  List<Widget> _musicMiniBar(Widget media, Size screen, EdgeInsets padding) {
    final String title = _player.title;
    final int dash = title.lastIndexOf(' - ');
    final String song = dash > 0 ? title.substring(0, dash) : title;
    final String artist = dash > 0 ? title.substring(dash + 3) : '';
    final String videoId = _player.youtube?.media.videoId ?? '';
    // The bottom bar under it: iPhone's glass (46 high, 34 from the edge)
    // or the flat bar drawn by the app (48).
    final double barHeight = nativeGlassBar.value ? 46 + 22 : 48;
    const Color ink = Color(0xFFF1F1F1);
    return [
      // The player's page stays alive (it plays the song), out of sight.
      Positioned(
        left: 0,
        top: 0,
        width: 1,
        height: 1,
        child: IgnorePointer(
          child: Opacity(
            opacity: 0,
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: screen.width,
              maxWidth: screen.width,
              minHeight: screen.height,
              maxHeight: screen.height,
              child: media,
            ),
          ),
        ),
      ),
      // It follows the bottom bar: down to the edge while that bar is away.
      Positioned.fill(
        child: ValueListenableBuilder<YouTubeBars?>(
          valueListenable: pageYouTubeBars,
          builder: (context, bars, bar) => Stack(
            children: [
              AnimatedPositioned(
                key: const Key('musicMiniBar'),
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                left: 8,
                right: 8,
                bottom:
                    (bars?.hidden == true ? 8 : barHeight + 6) +
                    (nativeGlassBar.value ? 12 : padding.bottom),
                height: 58,
                child: bar!,
              ),
            ],
          ),
          child: Material(
            color: Color.lerp(_background, Colors.white, .1),
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              // Straight back to the song (no window to grow from).
              onTap: () => _finishExpandMini(),
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      width: 42,
                      height: 42,
                      child: videoId.isEmpty
                          ? const ColoredBox(color: Color(0xFF272727))
                          : Image.network(
                              'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  const ColoredBox(color: Color(0xFF272727)),
                            ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: ink,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (artist.isNotEmpty)
                          Text(
                            artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFAAAAAA),
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const Key('musicMiniBarPlay'),
                    tooltip: _player.playing ? 'Pausar' : 'Reproduzir',
                    onPressed: () => unawaited(_player.playPause()),
                    icon: Icon(
                      _player.playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: ink,
                      size: 30,
                    ),
                  ),
                  IconButton(
                    key: const Key('musicMiniBarNext'),
                    tooltip: 'Seguinte',
                    onPressed: () =>
                        unawaited(_player.youtube?.musicSkip(forward: true)),
                    icon: const Icon(
                      Icons.skip_next_rounded,
                      color: ink,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
        ),
      ),
    ];
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
        // Two pages: the player's notices belong to the player page; here
        // they would push the browse page down.
        if (_player.message != null && !_twoPages)
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
                  // iPhone's glass bar carries the adjustments button.
                  if (bars?.hidden == true ||
                      bars?.shorts == true ||
                      bars?.music == true ||
                      (nativeGlassBar.value && bars?.pivot != null)) {
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
                        onPressed: () => _openAdjustmentsFromBar(),
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
        if (_twoPages)
          _GlassBarHost(
            onTap: (name) {
              if (name == 'adjust') {
                if (!_openAdjustmentsFromBar()) GlassBar.shake('adjust');
              } else {
                unawaited(_browse?.openTab(name));
              }
            },
          ),
        // The Shorts page has no bottom bar on the site: the app draws one
        // under the page (the page gets shorter and lays itself out).
        ValueListenableBuilder<YouTubeBars?>(
          valueListenable: pageYouTubeBars,
          builder: (context, bars, _) {
            final browse = _browse;
            // YouTube Music has no bottom bar on a phone: the app draws one.
            if (bars?.music == true && browse != null) {
              // iPhone: the glass bar floats over the page instead.
              if (bars!.hidden || nativeGlassBar.value) {
                return const SizedBox.shrink();
              }
              return _MusicBottomBar(
                current: bars.tab,
                onTab: (name) => unawaited(browse.openTab(name)),
                onAdjustments: _openAdjustmentsFromBar,
              );
            }
            if (bars?.shorts != true || browse == null) {
              return const SizedBox.shrink();
            }
            void open(String path) => unawaited(
              browse.start(Uri.https('m.youtube.com', path)).catchError((_) {}),
            );
            // iPhone's glass bar floats here: only its dark strip is kept.
            if (nativeGlassBar.value) {
              return Container(
                height: 62,
                color: bars!.dark ? const Color(0xFF0F0F0F) : Colors.white,
              );
            }
            return _ShortsBottomBar(
              dark: bars!.dark,
              avatar: bars.avatar,
              onHome: () => open('/'),
              onYou: () => open('/feed/library'),
              onAdjustments: _openAdjustmentsFromBar,
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

  // Spotify: the adjustments live under the song's screen. 0 is closed, 1 is
  // fully up; the finger moves it in between.
  late final AnimationController _pull = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..addListener(_pullMoved);
  double _pullMax = 600;
  bool _spotifyWasOpen = false;

  bool get _spotifyScroll =>
      ((studioSpotifySkin && !studioYouTubeSkin) || studioMusicSource) &&
      !_isLandscapePlayer;

  /// The colour under the scrolled player: Spotify's own, or on YouTube
  /// Music its page's (black in the dark themes, white in the light one).
  Color get _pullSheet => studioMusicSource
      ? (widget.appearance.mode == StudioAppearanceMode.light
            ? Colors.white
            : const Color(0xFF030303))
      : spotifySheetColor;

  /// YouTube Music: the adjustments' sheet in their own colour from the
  /// top, so they join the song's tabs above them with no dark band.
  Color get _musicPanel => _background.a >= 1 ? _background : _pullSheet;

  void _musicTintChanged() {
    if (mounted && studioMusicSource) setState(() {});
  }

  /// YouTube Music's song screen closed (its small bar over the other
  /// pages): the tabs and the adjustments go back down with it.
  void _songTabsChanged() {
    if (!mounted || !studioMusicSource || musicSongTabs.value != null) return;
    if (_pull.value > 0) {
      unawaited(_pull.animateTo(0, curve: Curves.easeOutCubic));
    }
  }

  void _pullMoved() {
    // An opened song tab (Letra, ...) dragged down: back to the player.
    final SongTabs? song = musicSongTabs.value;
    if (song != null &&
        song.selected >= 0 &&
        !_songOpening &&
        _pull.value < .85) {
      musicSongTabs.value = (
        labels: song.labels,
        enabled: song.enabled,
        selected: -1,
      );
      unawaited(_player.youtube?.openSongTab(-1));
      scheduleMicrotask(() {
        if (!mounted) return;
        _pull.stop();
        _pull.value = 0;
      });
    }
    final bool expanded = _pull.value > .001;
    if (expanded != _mainControlsExpanded && mounted) {
      setState(() => _mainControlsExpanded = expanded);
    }
  }

  // One finger on the song's screen: whether it moves the adjustments.
  int? _pullPointer;
  Offset _pullStart = Offset.zero;
  bool? _pulling;
  VelocityTracker? _pullVelocity;

  void _pullPointerDown(PointerDownEvent event) {
    if (_pullPointer != null) {
      _pulling = false;
      return;
    }
    _pullPointer = event.pointer;
    _pullStart = event.position;
    // YouTube Music with a song tab open (Letra, ...): the finger scrolls
    // that panel, it never pulls the adjustments.
    final bool songOpen = (musicSongTabs.value?.selected ?? -1) >= 0;
    // YouTube Music with only its small bar (its other pages): the finger
    // scrolls the page.
    final bool musicAway = studioMusicSource && musicSongTabs.value == null;
    _pulling =
        !songOpen &&
            !musicAway &&
            (spotifyPlayerOpen.value || studioMusicSource || _pull.value > 0)
        ? null
        : false;
    _pullVelocity = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
  }

  void _pullPointerMove(PointerMoveEvent event) {
    if (event.pointer != _pullPointer || _pulling == false) return;
    _pullVelocity?.addPosition(event.timeStamp, event.position);
    if (_pulling == null) {
      final Offset moved = event.position - _pullStart;
      if (moved.distance < 6) return;
      // Clearly vertical: the progress bar and the buttons keep sideways
      // drags and taps.
      _pulling = moved.dy.abs() > moved.dx.abs() * 1.4;
      if (_pulling != true) return;
      _pull.stop();
    }
    _pullBy(-event.delta.dy);
  }

  // Whether the adjustments' own list is at its top (a drag down there
  // lowers the adjustments instead).
  bool _panelAtTop = true;

  // How far the adjustments' list is scrolled (up to 60): their bar on top
  // goes up and fades with it.
  final ValueNotifier<double> _handleScroll = ValueNotifier<double>(0);

  bool _panelScrolled(ScrollNotification note) {
    if (note.metrics.axis == Axis.vertical && note.depth == 0) {
      _panelAtTop = note.metrics.pixels <= note.metrics.minScrollExtent + .5;
    }
    return false;
  }

  /// A finger anywhere on the adjustments: while they are not all the way
  /// up it moves them; all the way up, their list scrolls, and a drag down
  /// from its top brings them down again.
  void _panelPointerDown(PointerDownEvent event) {
    if (_pullPointer != null) return;
    _pullPointer = event.pointer;
    _pullStart = event.position;
    _pulling = null;
    _pullVelocity = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
  }

  void _panelPointerMove(PointerMoveEvent event) {
    if (event.pointer != _pullPointer || _pulling == false) return;
    _pullVelocity?.addPosition(event.timeStamp, event.position);
    if (_pulling == null) {
      final Offset moved = event.position - _pullStart;
      // A tap that shakes a little stays a tap (on the tabs above them).
      if (moved.distance < kTouchSlop) return;
      final bool vertical = moved.dy.abs() > moved.dx.abs() * 1.4;
      _pulling =
          vertical && (_pull.value < .999 || (moved.dy > 0 && _panelAtTop));
      if (_pulling != true) return;
      _pull.stop();
    }
    _pullBy(-event.delta.dy);
  }

  void _pullPointerUp(PointerUpEvent? event) {
    if (event != null && event.pointer != _pullPointer) return;
    if (_pulling == true) {
      final double vy = _pullVelocity?.getVelocity().pixelsPerSecond.dy ?? 0;
      _settlePull(-vy);
    }
    _pullPointer = null;
    _pulling = null;
    _pullVelocity = null;
  }

  void _pullBy(double dy) {
    if (!mounted || !_spotifyScroll) return;
    _pull.stop();
    _pull.value = (_pull.value + dy / _pullMax).clamp(0.0, 1.0);
  }

  /// Let go, the adjustments stay where the finger left them; a flick
  /// carries them on a little and slows down, like any scroll.
  void _settlePull(double velocity) {
    if (!mounted || velocity.abs() < 60 || _pullMax <= 0) return;
    unawaited(
      _pull.animateWith(
        FrictionSimulation(.05, _pull.value, velocity / _pullMax),
      ),
    );
  }

  void _spotifyPlayerChanged() {
    final bool open = spotifyPlayerOpen.value;
    // The song's screen was closed with the adjustments up: they go too.
    if (_spotifyWasOpen && !open && _pull.value > 0) {
      unawaited(_pull.animateTo(0, curve: Curves.easeOutCubic));
    }
    _spotifyWasOpen = open;
  }

  /// Spotify: the song's screen moves up with the finger and the
  /// adjustments come in under it, like the rest of Spotify's player.
  Widget _spotifyPanel(BoxConstraints box, Widget media) {
    // The page ends above Android's own button bar (the black band under
    // it): the adjustments start right where the page's colour ends.
    final double pageEnd =
        box.maxHeight - MediaQuery.viewPaddingOf(context).bottom;
    // All the way up they stop right under the mini player, never over it.
    final double miniHeight = (150 * MediaQuery.textScalerOf(context).scale(1))
        .clamp(150, 260)
        .toDouble();
    // YouTube Music: the app's tabs and the song's tabs, one block on top
    // of the adjustments, hidden under the player until the finger pulls
    // it up.
    final double header = studioMusicSource ? _musicHeaderHeight : 0;
    final double maxPull = (pageEnd - miniHeight).clamp(200, box.maxHeight);
    _songTop = pageEnd - maxPull + header;
    _pullMax = maxPull;
    // Built once per layout, not per frame: while the finger moves, only
    // their positions change, so the scroll stays light and smooth.
    final Widget page = RepaintBoundary(
      child: MainPlayerFullscreen(
        model: _player,
        media: media,
        mainMode: true,
        showHeader: false,
        controlsOpen: false,
        onExit: () {},
        onTool: _tool,
        youtubeNativeTransport: _player.isYouTube,
        onNativeMediaTouch: null,
      ),
    );
    final Widget content = RepaintBoundary(
      child: _sectionContent(media, viewportHeight: maxPull - 8),
    );
    // Built once per layout too: dragging only moves it.
    final Widget block = header > 0
        ? RepaintBoundary(child: _musicTabsBlock())
        : const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _pull,
      builder: (context, _) {
        final double pull = _pull.value * maxPull;
        // A song tab open (Letra, ...): the tabs go up like the adjustments
        // and the page's own panel for it shows under them (the page stays
        // put and leaves that room at its top).
        final bool songOpen =
            header > 0 && (musicSongTabs.value?.selected ?? -1) >= 0;
        final double pageShift = songOpen ? 0 : pull;
        return Stack(
          children: [
            // Under the page's edge, in the adjustments' colour: no band
            // shows between the song and them while they move.
            Positioned.fill(child: ColoredBox(color: _pullSheet)),
            Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: _pullPointerDown,
              onPointerMove: _pullPointerMove,
              onPointerUp: _pullPointerUp,
              onPointerCancel: (_) => _pullPointerUp(null),
              child: SizedBox(
                key: const Key('visualMainMediaViewport'),
                height: box.maxHeight,
                width: double.infinity,
                child: ClipRect(
                  child: Transform.translate(
                    offset: Offset(0, -pageShift),
                    child: page,
                  ),
                ),
              ),
            ),
            // Below Spotify's own player its page is black: that strip is
            // covered in the player's last colour, moving with the page.
            ValueListenableBuilder<double?>(
              valueListenable: spotifyPlayerBottom,
              builder: (context, physical, _) {
                // The page's pixels are not the app's (its own zoom).
                final double? bottom = physical == null
                    ? null
                    : physical / MediaQuery.devicePixelRatioOf(context);
                return bottom == null || bottom >= box.maxHeight - 1
                    ? const SizedBox.shrink()
                    : Positioned(
                        left: 0,
                        right: 0,
                        // From 2 px above: Spotify's thin dotted edge too.
                        top: bottom - 2 - pull,
                        height: box.maxHeight - bottom + 2,
                        child: IgnorePointer(
                          child: ColoredBox(color: spotifySheetColor),
                        ),
                      );
              },
            ),
            // Always built (below the screen while closed): opening them
            // never waits for their first build.
            Positioned(
              key: const Key('spotifyAdjustments'),
              left: 0,
              right: 0,
              top: pageEnd - pull,
              height: songOpen ? header : maxPull + box.maxHeight - pageEnd,
              // Closed, they are kept but not drawn: nothing of them peeks
              // under Android's buttons.
              child: Offstage(
                offstage: pull <= .5,
                child: Listener(
                  onPointerDown: _panelPointerDown,
                  onPointerMove: _panelPointerMove,
                  onPointerUp: _pullPointerUp,
                  onPointerCancel: (_) => _pullPointerUp(null),
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _panelScrolled,
                    // Not all the way up: the finger moves the adjustments,
                    // not their list.
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context).copyWith(
                        physics: _pull.value < .999
                            ? const NeverScrollableScrollPhysics()
                            : null,
                      ),
                      child: Theme(
                        data: studioColumnTheme(
                          Theme.of(context),
                          mode: widget.appearance.mode,
                        ),
                        child: DecoratedBox(
                          // It goes on from where Spotify's own gradient ends.
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: studioMusicSource
                                  ? [_musicPanel, _musicPanel]
                                  : [spotifySheetColor, Color(0xFF161213)],
                            ),
                          ),
                          child: Stack(
                            children: [
                              Positioned.fill(
                                top: header > 0 ? header : 8,
                                // Down, only the tabs show: nothing of the
                                // adjustments under Android's buttons.
                                child: Offstage(
                                  offstage: header > 0 && pull <= header,
                                  child: content,
                                ),
                              ),
                              if (header > 0)
                                Positioned(
                                  top: 0,
                                  left: 0,
                                  right: 0,
                                  height: header,
                                  child: block,
                                ),
                              // "Fechar ajustes", over a fade into the sheet
                              // (not on YouTube Music: its tabs do that).
                              if (header == 0)
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 0,
                                  child: IgnorePointer(
                                    ignoring: _pull.value < .98,
                                    child: Opacity(
                                      opacity: ((_pull.value - .85) / .15)
                                          .clamp(0, 1),
                                      child: Container(
                                        padding: EdgeInsets.fromLTRB(
                                          0,
                                          40,
                                          0,
                                          20 +
                                              MediaQuery.viewPaddingOf(context)
                                                  .bottom,
                                        ),
                                        decoration: const BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                              Color(0x00161213),
                                              Color(0xFF161213),
                                            ],
                                            stops: [0, .5],
                                          ),
                                        ),
                                        alignment: Alignment.center,
                                        child: FilledButton.icon(
                                          key: const Key(
                                            'spotifyCloseAdjustments',
                                          ),
                                          onPressed: () => unawaited(
                                            _pull.animateTo(
                                              0,
                                              curve: Curves.easeOutCubic,
                                            ),
                                          ),
                                          style: FilledButton.styleFrom(
                                            backgroundColor: Colors.white,
                                            foregroundColor: Colors.black,
                                            minimumSize: const Size(0, 48),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 24,
                                            ),
                                            shape: const StadiumBorder(),
                                            textStyle: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          icon: const Icon(
                                            Icons.keyboard_arrow_down,
                                            size: 22,
                                          ),
                                          label: const Text('Fechar ajustes'),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              if (header == 0)
                                Positioned(
                                  top: 0,
                                  left: 0,
                                  right: 0,
                                  child: Center(
                                    child: AdjustmentsHandle(
                                      gestureKey: const Key(
                                        'spotifyPullHandle',
                                      ),
                                      bar: false,
                                      alwaysVisible: true,
                                      light: false,
                                      onDragStart: _pull.stop,
                                      onDragUpdate: (dy) => _pullBy(-dy),
                                      onDragEnd: (velocity) =>
                                          _settlePull(-velocity),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Up: the song as Spotify shows it when its page is scrolled, a
            // bar with the player's title and a mini player.
            // Only near the top, sliding down quickly: it never sits half
            // see-through over the song's own title.
            if (_pull.value > .82)
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: pageEnd - maxPull,
                child: Builder(
                  builder: (context) {
                    final double shown = ((_pull.value - .82) / .18).clamp(
                      0.0,
                      1.0,
                    );
                    return Transform.translate(
                      offset: Offset(0, -(1 - shown) * 40),
                      child: Opacity(
                        opacity: shown,
                        child: _spotifyMiniPlayer(),
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _spotifyMiniPlayer() {
    final String title = _player.title;
    final int dash = title.lastIndexOf(' - ');
    final String song = dash > 0 ? title.substring(0, dash) : title;
    final String artist = dash > 0 ? title.substring(dash + 3) : '';
    final int total = _player.duration.inMilliseconds;
    final double done = total > 0
        ? (_player.position.inMilliseconds / total).clamp(0, 1)
        : 0;
    return GestureDetector(
      // A drag down here brings the song back too.
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (_) => _pull.stop(),
      onVerticalDragUpdate: (details) => _pullBy(-details.delta.dy),
      onVerticalDragEnd: (details) =>
          _settlePull(-(details.primaryVelocity ?? 0)),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              studioMusicSource
                  ? _pullSheet
                  : Color.lerp(spotifyTint, spotifySheetColor, .35) ??
                        spotifySheetColor,
              _pullSheet,
            ],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Fechar ajustes',
                  onPressed: () =>
                      unawaited(_pull.animateTo(0, curve: Curves.easeOutCubic)),
                  icon: const Icon(
                    Icons.keyboard_arrow_down,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const Expanded(
                  child: Text(
                    'Ajustes',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
              decoration: BoxDecoration(
                color: const Color(0x1AFFFFFF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0x33000000),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(
                          Icons.music_note,
                          color: Color(0x99FFFFFF),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              song,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (artist.isNotEmpty)
                              Text(
                                artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xBFFFFFFF),
                                  fontSize: 13,
                                ),
                              ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 40,
                        height: 40,
                        child: IconButton.filled(
                          tooltip: _player.playing ? 'Pausar' : 'Reproduzir',
                          onPressed: () => unawaited(_player.playPause()),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            padding: EdgeInsets.zero,
                          ),
                          icon: Icon(
                            _player.playing ? Icons.pause : Icons.play_arrow,
                            size: 22,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: -8,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(1),
                      child: LinearProgressIndicator(
                        value: done,
                        minHeight: 2,
                        backgroundColor: const Color(0x40FFFFFF),
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _mainPanel(Widget media) {
    return LayoutBuilder(
      builder: (_, box) {
        if (_spotifyScroll) return _spotifyPanel(box, media);
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
        // The adjustments are a floating sheet of glass over the page: inset
        // from the edges, fully rounded, blurring what is behind it.
        final sheet =
            widget.appearance.apple &&
            !_adjustmentsCoverVideo &&
            !landscapePlayer;
        final light = widget.appearance.mode == StudioAppearanceMode.light;
        final sheetRadius = BorderRadius.circular(sheet ? 34 : 0);
        // No side gap on very narrow screens: the controls need the width.
        final double sheetSide = sheet && box.maxWidth >= 370 ? 8 : 0;
        final double sheetBottom = sheet ? 8 : 0;
        // Three heights: low (tabs and the first card), medium (from under
        // the video) and high (over the video, the existing covered state).
        final double sheetTop = sheet && _sheetLow
            ? (box.maxHeight - 204).clamp(overlayTop, box.maxHeight)
            : overlayTop;
        // Where the adjustments' top is right now, drag included.
        final double shownTop = (sheetTop + (_sheetDrag ?? 0)).clamp(
          0.0,
          (box.maxHeight - 72).clamp(0.0, box.maxHeight),
        );
        // Only on the way to closed: from over the video the pull goes to
        // the middle height, where the adjustments stay in full.
        final double pulledDown =
            _adjustmentsCoverVideo || (sheet && !_sheetLow)
            ? 0
            : (_sheetDrag ?? 0).clamp(0.0, double.infinity);
        final double sheetFade =
            (1 - pulledDown / ((box.maxHeight - sheetTop) * .6).clamp(1.0, 1e9))
                .clamp(0.0, 1.0);
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
              AnimatedPositioned(
                // While the bar is dragged the adjustments follow the finger
                // at once; let go, and they glide to where they settle.
                // Between the tone tab and the others only the frame
                // changes, not what is seen: no glide there either.
                duration: _sheetDrag == null && !_tabJump
                    ? const Duration(milliseconds: 240)
                    : Duration.zero,
                curve: Curves.easeOutCubic,
                top: shownTop,
                left: sheetSide,
                right: sheetSide,
                bottom: sheetBottom,
                child: AnimatedOpacity(
                  // Pulled down towards closed, the adjustments fade away
                  // with the finger; let go short of it and they come back.
                  opacity: sheetFade,
                  duration: _sheetDrag == null
                      ? const Duration(milliseconds: 240)
                      : Duration.zero,
                  child: Theme(
                    data: studioColumnTheme(
                      Theme.of(context),
                      mode: widget.appearance.mode,
                    ),
                    child: NotificationListener<ScrollNotification>(
                      // How far the adjustments are scrolled: their bar
                      // goes up with them instead of staying put.
                      onNotification: (note) {
                        if (note.metrics.axis == Axis.vertical &&
                            note.depth == 0) {
                          _handleScroll.value = note.metrics.pixels.clamp(
                            0.0,
                            60.0,
                          );
                        }
                        return false;
                      },
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: ClipRRect(
                              key: const Key('unifiedAdjustmentsBlurBounds'),
                              // The chord tab leaves the page showing above its
                              // own rounded backdrop: only the bottom is clipped.
                              // Every tab has the tone tab's rounded top (the
                              // tone tab draws its own, under the page's strip).
                              borderRadius: sheet && chordPanel
                                  ? const BorderRadius.vertical(
                                      bottom: Radius.circular(34),
                                    )
                                  : !sheet &&
                                        !chordPanel &&
                                        !_adjustmentsCoverVideo &&
                                        !landscapePlayer
                                  ? const BorderRadius.vertical(
                                      top: Radius.circular(34),
                                    )
                                  : sheetRadius,
                              child: BackdropFilter(
                                // Off where there is nothing to blur (the tone
                                // tab blurs its own backdrop): a zero blur
                                // here would hide the page from that one.
                                enabled:
                                    !chordPanel &&
                                    !studioSpotifySkin &&
                                    (sheet ||
                                        widget.appearance.mode ==
                                            StudioAppearanceMode.glass),
                                filter: ImageFilter.blur(
                                  sigmaX: sheet && !chordPanel
                                      ? 22
                                      : widget.appearance.mode ==
                                                StudioAppearanceMode.glass &&
                                            !chordPanel
                                      ? 10
                                      : 0,
                                  sigmaY: sheet && !chordPanel
                                      ? 22
                                      : widget.appearance.mode ==
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
                                            // Room for the bar above the
                                            // transport, clear of it.
                                            const SizedBox(height: 12),
                                            _coveredVideoTransport(
                                              box.maxHeight,
                                            ),
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
                                        borderRadius:
                                            const BorderRadius.vertical(
                                              top: Radius.circular(26),
                                            ),
                                        child: _sectionContent(
                                          media,
                                          topGap: chordTopGap,
                                          viewportHeight:
                                              box.maxHeight -
                                              shownTop -
                                              sheetBottom,
                                        ),
                                      )
                                    : ColoredBox(
                                        color: sheet
                                            ? (light
                                                  ? const Color(0xB8F4F7FB)
                                                  : const Color(0x8C17191E))
                                            : _background,
                                        // Nothing scrolls under the grabber's
                                        // band.
                                        child: Padding(
                                          padding: EdgeInsets.only(
                                            top: sheet ? 14 : 0,
                                          ),
                                          child: _sectionContent(media),
                                        ),
                                      ),
                              ),
                            ),
                          ),
                          if (!sheet)
                            // The bar that raises, lowers or closes the
                            // adjustments. Drawn over them: it moves nothing.
                            Positioned(
                              top: chordPanel && !_adjustmentsCoverVideo
                                  ? chordTopGap
                                  : 0,
                              left: 0,
                              right: 0,
                              child: ValueListenableBuilder<double>(
                                valueListenable: _handleScroll,
                                builder: (context, scrolled, child) =>
                                    Transform.translate(
                                      offset: Offset(0, -scrolled),
                                      child: Opacity(
                                        opacity: (1 - scrolled / 30).clamp(
                                          0,
                                          1,
                                        ),
                                        child: child,
                                      ),
                                    ),
                                child: Center(
                                  child: AdjustmentsHandle(
                                    light: light,
                                    onDragStart: () =>
                                        setState(() => _sheetDrag = 0),
                                    onDragUpdate: (dy) => setState(
                                      () => _sheetDrag = (_sheetDrag ?? 0) + dy,
                                    ),
                                    onDragEnd: _endSheetDrag,
                                  ),
                                ),
                              ),
                            ),
                          if (sheet) ...[
                            // The glass's light rim (in the chord tab, around
                            // the backdrop that starts under the page's strip).
                            Positioned.fill(
                              top: chordPanel ? chordTopGap : 0,
                              child: IgnorePointer(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: sheetRadius,
                                    border: Border.all(
                                      color: light
                                          ? const Color(0x33000000)
                                          : const Color(0x38FFFFFF),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            // The bar of the floating sheet: always in sight,
                            // and the sheet follows the finger on it (low,
                            // medium, over the video; pulled down from low, it
                            // closes).
                            Positioned(
                              top: chordPanel ? chordTopGap : 0,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: AdjustmentsHandle(
                                  gestureKey: const Key('adjustmentsGrabber'),
                                  alwaysVisible: true,
                                  light: light,
                                  onDragStart: () =>
                                      setState(() => _sheetDrag = 0),
                                  onDragUpdate: (dy) => setState(
                                    () => _sheetDrag = (_sheetDrag ?? 0) + dy,
                                  ),
                                  onDragEnd: _endSheetDrag,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  static const _visibleTabs = <(StudioTab, String)>[
    // Tone (with the chord sheet that follows it), practice, sound and the
    // setlist. The app's settings ("Mais") are the gear at the strip's end.
    (StudioTab.chords, 'Tom'),
    (StudioTab.practice, 'Treino'),
    (StudioTab.audioSettings, 'Áudio'),
    (StudioTab.setlist, 'Setlist'),
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

  /// Spotify's filter chips: separate pills, the chosen one white with black
  /// text, the settings a round chip with the gear.
  /// The YouTube app's tabs: text tabs underlined in red, the gear last
  /// for the settings ("Mais").
  static const double _musicHeaderHeight = 98;

  /// Where the song tab's panel starts on the page: under the tabs block
  /// all the way up.
  double _songTop = 0;

  /// The tabs block is going up to open a song tab: it is not a drag down.
  bool _songOpening = false;

  /// YouTube Music: one block of two rows, the app's tabs (Tom, Treino,
  /// Audio, Setlist) over the song's (A seguir, Letra, Comentarios,
  /// Relacionados), in the same look; only one of them is chosen at a time.
  /// A tab on top brings the adjustments up; one below opens the site's own
  /// panel for it, with the adjustments down.
  Widget _musicTabsBlock() => ValueListenableBuilder<SongTabs?>(
    valueListenable: musicSongTabs,
    builder: (context, song, _) {
      final bool light = _musicPanel.computeLuminance() > .5;
      final Color on = light
          ? const Color(0xFF0F0F0F)
          : const Color(0xFFF1F1F1);
      final Color off = light
          ? const Color(0xFF606060)
          : const Color(0xFFAAAAAA);
      final Color line = light
          ? const Color(0x1F000000)
          : const Color(0x1FFFFFFF);
      final int songOpen = song?.selected ?? -1;
      final StudioTab appTab = _tab == StudioTab.player
          ? StudioTab.chords
          : _tab;
      Widget cell({
        required Key key,
        required bool chosen,
        required VoidCallback? onTap,
        required Widget Function(Color ink) body,
        int flex = 10,
      }) {
        final Color ink = onTap == null
            ? off.withValues(alpha: .4)
            : chosen
            ? on
            : off;
        return Expanded(
          flex: flex,
          child: InkWell(
            key: key,
            onTap: onTap,
            child: SizedBox(
              height: 48,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  body(ink),
                  Positioned(
                    left: 10,
                    right: 10,
                    bottom: 0,
                    child: AnimatedOpacity(
                      opacity: chosen ? 1 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: Container(
                        height: 3,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFF0033),
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      Widget label(String text, Color ink) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            text,
            maxLines: 1,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: ink,
            ),
          ),
        ),
      );

      Widget row(List<Widget> cells) => DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: line)),
        ),
        child: Row(children: cells),
      );

      return ColoredBox(
        key: const Key('musicTabsBlock'),
        color: _musicPanel,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            row([
              for (final (value, text) in _visibleTabs)
                cell(
                  key: Key('unifiedSection${value.name}'),
                  chosen: songOpen < 0 && appTab == value,
                  onTap: () => _musicAppTab(value),
                  body: (ink) => label(text, ink),
                ),
              cell(
                key: const Key('unifiedSectionappearanceSettings'),
                flex: 7,
                chosen: songOpen < 0 && appTab == StudioTab.appearanceSettings,
                onTap: () => _musicAppTab(StudioTab.appearanceSettings),
                body: (ink) =>
                    Icon(Icons.settings_outlined, size: 22, color: ink),
              ),
            ]),
            row([
              if (song == null)
                const Expanded(child: SizedBox(height: 48))
              else
                // Only the tabs this song has (no greyed-out Comentários),
                // each as wide as its name needs.
                for (int i = 0; i < song.labels.length; i++)
                  if (song.enabled[i])
                    cell(
                      key: Key('musicSongTab$i'),
                      flex: song.labels[i].length + 4,
                      chosen: songOpen == i,
                      onTap: () => _musicSongTab(i),
                      body: (ink) => label(song.labels[i], ink),
                    ),
            ]),
          ],
        ),
      );
    },
  );

  /// One of the app's tabs in the YouTube Music block: the song's panel (if
  /// open) closes and the adjustments come up on that tab; the chosen tab
  /// again with them up takes them down.
  void _musicAppTab(StudioTab tab) {
    final SongTabs? song = musicSongTabs.value;
    final bool songOpen = (song?.selected ?? -1) >= 0;
    if (song != null && songOpen) {
      musicSongTabs.value = (
        labels: song.labels,
        enabled: song.enabled,
        selected: -1,
      );
      unawaited(_player.youtube?.openSongTab(-1));
    }
    final StudioTab shown = _tab == StudioTab.player ? StudioTab.chords : _tab;
    if (!songOpen && shown == tab && _pull.value > .5) {
      unawaited(_pull.animateTo(0, curve: Curves.easeOutCubic));
      return;
    }
    if (shown != tab) _select(tab);
    unawaited(_pull.animateTo(1, curve: Curves.easeOutCubic));
  }

  /// One of the song's tabs: its panel opens under the tabs, as the
  /// adjustments do; the opened one again goes back to the player.
  void _musicSongTab(int index) {
    final SongTabs? song = musicSongTabs.value;
    if (song == null) return;
    final bool again = song.selected == index;
    // Shown at once, before the page answers.
    musicSongTabs.value = (
      labels: song.labels,
      enabled: song.enabled,
      selected: again ? -1 : index,
    );
    // Opened: the tabs go up and the song's panel opens down under them.
    // Closed again: they go back under the player.
    unawaited(_player.youtube?.openSongTab(again ? -1 : index, top: _songTop));
    if (again) {
      unawaited(_pull.animateTo(0, curve: Curves.easeOutCubic));
    } else {
      _songOpening = true;
      _pull
          .animateTo(1, curve: Curves.easeOutCubic)
          .whenCompleteOrCancel(() => _songOpening = false);
    }
  }

  Widget _youtubeTabs(StudioTab selected) {
    Widget tab(StudioTab value, String label, {bool gear = false}) {
      final bool on = selected == value;
      final Color ink = on ? const Color(0xFFF1F1F1) : const Color(0xFFAAAAAA);
      final Widget body = gear
          ? Icon(Icons.settings_outlined, size: 22, color: ink)
          : Text(
              label,
              maxLines: 1,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: ink,
              ),
            );
      return Expanded(
        flex: gear ? 7 : 10,
        child: InkWell(
          key: Key('unifiedSection${value.name}'),
          onTap: () => _select(value),
          child: SizedBox(
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Tooltip(message: label, child: body),
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 0,
                  child: AnimatedOpacity(
                    opacity: on ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Container(
                      height: 3,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFF0033),
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      key: const Key('unifiedSectionStrip'),
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0x1FFFFFFF))),
          ),
          child: Row(
            children: [
              for (final (value, label) in _visibleTabs) tab(value, label),
              tab(StudioTab.appearanceSettings, 'Mais', gear: true),
            ],
          ),
        ),
      ],
    );
  }

  Widget _spotifyChips(StudioTab selected) {
    Widget chip(StudioTab tab, Widget child, {bool round = false}) {
      final bool on = selected == tab;
      return Material(
        color: on ? spotifyGreen : const Color(0x1AFFFFFF),
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('unifiedSection${tab.name}'),
          onTap: () => _select(tab),
          child: SizedBox(
            height: 36,
            width: round ? 36 : null,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: round ? 0 : 16),
              child: Center(
                child: IconTheme(
                  data: IconThemeData(
                    color: on ? Colors.black : Colors.white,
                    size: 18,
                  ),
                  child: DefaultTextStyle(
                    style: TextStyle(
                      color: on ? Colors.black : Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 2),
      child: SingleChildScrollView(
        key: const Key('unifiedSectionStrip'),
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final (tab, label) in _visibleTabs) ...[
              chip(tab, Text(label)),
              const SizedBox(width: 8),
            ],
            chip(
              StudioTab.appearanceSettings,
              const Icon(Icons.settings_outlined),
              round: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTabs() {
    // YouTube Music: they sit in the block above, with the song's tabs.
    if (studioMusicSource && _spotifyScroll) return const SizedBox.shrink();
    final selected = _tab == StudioTab.player ? StudioTab.chords : _tab;
    if (studioYouTubeSkin) return _youtubeTabs(selected);
    if (studioSpotifySkin) return _spotifyChips(selected);
    final light = widget.appearance.mode == StudioAppearanceMode.light;
    // Spotify's chips: the chosen one green with black text.
    final selectedFill = studioSpotifySkin
        ? spotifyGreen
        : light
        ? const Color(0xFF163E51)
        : Colors.white;
    final selectedInk = studioSpotifySkin
        ? Colors.black
        : light
        ? Colors.white
        : const Color(0xFF161618);
    final idleInk = studioSpotifySkin
        ? Colors.white
        : light
        ? const Color(0xFF344054)
        : const Color(0xFFC4C4C8);
    final settings = selected == StudioTab.appearanceSettings;
    // The floating sheet keeps a band at its top for the grabber.
    // The chord tab scrolls as one piece, so its tabs make the room; the
    // other tabs get it from the sheet itself.
    final sheet =
        widget.appearance.apple &&
        !_adjustmentsCoverVideo &&
        !_isLandscapePlayer &&
        (_tab == StudioTab.chords || _tab == StudioTab.player);
    return Container(
      // Under the bar that drags the adjustments, with a small gap.
      margin: EdgeInsets.fromLTRB(
        16,
        sheet
            ? 20
            : _adjustmentsCoverVideo
            ? 8
            : 16,
        16,
        8,
      ),
      // No padding: the band is exactly as tall as its buttons.
      decoration: studioPanelDecoration(
        radius: 18,
        mode: widget.appearance.mode,
      ),
      child: Row(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                final int index = _visibleTabs.indexWhere(
                  (entry) => entry.$1 == selected,
                );
                final int from = _visibleTabs.indexWhere(
                  (entry) =>
                      entry.$1 ==
                      (_previousTab == StudioTab.player
                          ? StudioTab.chords
                          : _previousTab),
                );
                final double width = box.maxWidth / _visibleTabs.length;
                return Stack(
                  children: [
                    // The selected tab's pill slides from the tab it left.
                    if (index >= 0)
                      Positioned.fill(
                        child: TweenAnimationBuilder<double>(
                          key: ValueKey('unifiedSectionPill$index'),
                          tween: Tween<double>(
                            begin: (from >= 0 ? from : index).toDouble(),
                            end: index.toDouble(),
                          ),
                          duration: const Duration(milliseconds: 280),
                          curve: Curves.easeOutCubic,
                          onEnd: () => _previousTab = _tab,
                          builder: (context, value, _) => Align(
                            alignment: Alignment.centerLeft,
                            child: Transform.translate(
                              offset: Offset(value * width, 0),
                              child: Container(
                                key: const Key('unifiedSectionPill'),
                                width: width,
                                decoration: BoxDecoration(
                                  color: selectedFill,
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    Row(
                      key: const Key('unifiedSectionStrip'),
                      children: [
                        for (final (tab, label) in _visibleTabs)
                          Expanded(
                            child: OutlinedButton(
                              key: Key('unifiedSection${tab.name}'),
                              onPressed: () => _select(tab),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: selected == tab
                                    ? selectedInk
                                    : idleInk,
                                side: BorderSide.none,
                                backgroundColor: Colors.transparent,
                                minimumSize: const Size(0, 36),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.standard,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(switch (tab) {
                                    StudioTab.chords =>
                                      Icons.music_note_outlined,
                                    StudioTab.practice => Icons.graphic_eq,
                                    StudioTab.setlist => Icons.queue_music,
                                    StudioTab.audioSettings => Icons.equalizer,
                                    _ => Icons.music_note_outlined,
                                  }, size: 14),
                                  const SizedBox(width: 3),
                                  Flexible(
                                    child: Text(
                                      label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
          // The app's settings ("Mais"): a gear, icon only.
          IconButton(
            key: const Key('unifiedSectionappearanceSettings'),
            tooltip: 'Configurações',
            onPressed: () => _select(StudioTab.appearanceSettings),
            style: IconButton.styleFrom(
              backgroundColor: settings ? selectedFill : Colors.transparent,
              foregroundColor: settings ? selectedInk : idleInk,
              minimumSize: const Size(40, 36),
              maximumSize: const Size(40, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: EdgeInsets.zero,
            ),
            icon: const Icon(Icons.settings_outlined, size: 19),
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
    String? subtitle,
  }) => studioSpotifySkin
      ? _spotifyToolRow(
          key: key,
          icon: icon,
          title: title,
          subtitle: subtitle,
          onTap: onTap,
          expanded: expanded,
          trailing: trailing,
          content: content,
        )
      : Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: switch (widget.appearance.mode) {
              StudioAppearanceMode.light => const Color(0xFFF7F9FC),
              StudioAppearanceMode.glass => studioGlassToolFill(),
              StudioAppearanceMode.dark => const Color(0xFF202023),
            },
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(
                width: .8,
                color: switch (widget.appearance.mode) {
                  StudioAppearanceMode.light => const Color(0xFFB7C4D2),
                  StudioAppearanceMode.glass => studioGlassToolBorder(),
                  StudioAppearanceMode.dark => const Color(0xFF4A4A50),
                },
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                InkWell(
                  key: key,
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
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

  /// "Rolar" on Spotify: one translucent pill with the speed and a white
  /// play button, as in the design.
  Widget _spotifyAutoScroll() {
    Widget small(Key key, String tip, IconData icon, VoidCallback? onTap) =>
        IconButton(
          key: key,
          tooltip: tip,
          constraints: const BoxConstraints.tightFor(width: 32, height: 32),
          padding: EdgeInsets.zero,
          onPressed: onTap,
          icon: Icon(icon, size: 18, color: Colors.white),
        );
    return Container(
      key: const Key('chordAutoScrollCard'),
      height: 44,
      padding: const EdgeInsets.only(left: 14, right: 4),
      decoration: BoxDecoration(
        color: const Color(0x1AFFFFFF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Rolar',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
          small(
            const Key('chordAutoScrollSlower'),
            'Rolar cifra mais devagar',
            Icons.remove,
            _chordScrollSpeed > .5
                ? () => setState(
                    () => _chordScrollSpeed = (_chordScrollSpeed - .25).clamp(
                      .5,
                      2,
                    ),
                  )
                : null,
          ),
          Text(
            '${_chordScrollSpeed.toStringAsFixed(2)}×',
            key: const Key('chordAutoScrollSpeed'),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          small(
            const Key('chordAutoScrollFaster'),
            'Rolar cifra mais depressa',
            Icons.add,
            _chordScrollSpeed < 2
                ? () => setState(
                    () => _chordScrollSpeed = (_chordScrollSpeed + .25).clamp(
                      .5,
                      2,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 2),
          Material(
            color: Colors.white,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: const Key('chordAutoScrollToggle'),
              onTap: _toggleChordAutoScroll,
              child: SizedBox(
                width: 36,
                height: 36,
                child: Icon(
                  _chordAutoScroll ? Icons.pause : Icons.play_arrow,
                  size: 20,
                  color: Colors.black,
                  semanticLabel: _chordAutoScroll
                      ? 'Pausar rolagem da cifra'
                      : 'Iniciar rolagem da cifra',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A practice tool on Spotify: a list row like its own (square tile,
  /// title, a line under it, an arrow), opening its tool beneath.
  Widget _spotifyToolRow({
    required Key key,
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    String? subtitle,
    bool expanded = false,
    Widget? trailing,
    Widget? content,
  }) => Column(
    children: [
      Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: key,
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                if (studioYouTubeSkin)
                  Padding(
                    padding: const EdgeInsets.only(right: 20),
                    child: Icon(icon, size: 24, color: const Color(0xFFF1F1F1)),
                  )
                else ...[
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0x1AFFFFFF),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Icon(icon, size: 22, color: Colors.white),
                  ),
                  const SizedBox(width: 14),
                ],
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xBFFFFFFF),
                          ),
                        ),
                    ],
                  ),
                ),
                ?trailing,
                AnimatedRotation(
                  turns: expanded ? .25 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(
                    Icons.chevron_right,
                    color: Color(0xBFFFFFFF),
                    size: 22,
                  ),
                ),
              ],
            ),
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
  );

  // The tone tab draws its own backdrop (it starts under the page's strip
  // and scrolls with the content), so it repeats here what the other tabs
  // get from the frame around them: the same fill and the same blur.
  bool get _floatingSheet =>
      widget.appearance.apple && !_adjustmentsCoverVideo && !_isLandscapePlayer;

  Color get _toneFill => _floatingSheet
      ? (widget.appearance.mode == StudioAppearanceMode.light
            ? const Color(0xB8F4F7FB)
            : const Color(0x8C17191E))
      : _background;

  // The pieces of the tone tab no longer blur one by one (two blurs met in
  // a visible seam): [_toneBackdrop] blurs once for the whole tab.
  Widget _toneGlass({required bool rounded, required Widget child}) => child;

  Widget _toneBackdrop(double topGap, Widget child) {
    final double blur = studioSpotifySkin
        ? 0
        : _floatingSheet
        ? 22
        : widget.appearance.mode == StudioAppearanceMode.glass
        ? 10
        : 0;
    if (blur == 0) return child;
    return AnimatedBuilder(
      animation: _scroll,
      child: child,
      builder: (context, content) {
        // The backdrop starts under the page's strip and rises with the
        // scroll until it reaches the top.
        final double scrolled = _scroll.hasClients ? _scroll.offset : 0;
        return ClipPath(
          clipper: TopInsetClipper((topGap - scrolled).clamp(0.0, topGap)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: content,
          ),
        );
      },
    );
  }

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
            child: _enter(
              PlayerCollectionsPage(
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
                      _player.message ??
                          'Não foi possível preparar esta música.',
                    );
                  }
                },
              ),
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
              child: _enter(_audioSettingsContent()),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _enter(StemPanel(onBeforePreview: _player.pause)),
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
                child: _enter(_appearanceSettingsContent()),
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
            _enter(
              Column(
                children: [
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
                          subtitle: studioSpotifySkin
                              ? (studioYouTubeSkin
                                    ? 'Trechos A–B guardados'
                                    : 'Os seus trechos A–B')
                              : null,
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
                            icon: const Icon(
                              Icons.bookmark_add_outlined,
                              size: 18,
                            ),
                          ),
                        ),
                        _practiceToolRow(
                          key: const Key('practiceMetronome'),
                          icon: Icons.timer_outlined,
                          title: 'Metrônomo inteligente',
                          subtitle: studioSpotifySkin && !studioYouTubeSkin
                              ? 'Compasso e andamento'
                              : null,
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
                          subtitle: studioSpotifySkin && !studioYouTubeSkin
                              ? 'Acelere aos poucos'
                              : null,
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
                        if (const bool.fromEnvironment(
                          'TRANSPONO_PERSONAL_RHYTHM',
                        ))
                          AmbientRhythmTrial(
                            appearanceMode: widget.appearance.mode,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    final Widget chooseChordButton = studioSpotifySkin && !_chordActive
        ? Material(
            key: const Key('unifiedChooseChordCard'),
            type: MaterialType.transparency,
            child: InkWell(
              key: const Key('unifiedChooseChord'),
              onTap: _toggleChord,
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 64,
                child: Row(
                  children: [
                    if (studioYouTubeSkin)
                      const Padding(
                        padding: EdgeInsets.only(right: 20),
                        child: Icon(
                          Icons.queue_music,
                          color: Color(0xFFF1F1F1),
                          size: 24,
                        ),
                      )
                    else ...[
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: const Color(0x1AFFFFFF),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(
                          Icons.queue_music,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                    ],
                    const Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Escolher cifra',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Acordes e letra sincronizados com o tom',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xBFFFFFFF),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      color: Color(0xBFFFFFFF),
                      size: 22,
                    ),
                  ],
                ),
              ),
            ),
          )
        : DecoratedBox(
            key: const Key('unifiedChooseChordCard'),
            decoration: studioSpotifySkin
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: const Color(0x99FFFFFF),
                      width: 1.5,
                    ),
                  )
                : studioPanelDecoration(mode: widget.appearance.mode),
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
                      // "Trocar cifra" sits in the middle of its short button; the
                      // wide "Escolher cifra" keeps its label left and its arrow
                      // right.
                      mainAxisAlignment: _chordActive
                          ? MainAxisAlignment.center
                          : MainAxisAlignment.start,
                      children: [
                        Icon(
                          _chordActive
                              ? (studioSpotifySkin
                                    ? Icons.swap_horiz
                                    : Icons.library_music_outlined)
                              : Icons.queue_music,
                          size: studioSpotifySkin ? 18 : 17,
                        ),
                        SizedBox(width: studioSpotifySkin ? 8 : 6),
                        Flexible(
                          fit: _chordActive ? FlexFit.loose : FlexFit.tight,
                          child: Text(
                            _chordActive ? 'Trocar cifra' : 'Escolher cifra',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: studioSpotifySkin ? 15 : 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (!_chordActive)
                          Icon(
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
    final autoScrollControls = _chordActive && studioSpotifySkin
        ? _spotifyAutoScroll()
        : _chordActive
        ? DecoratedBox(
            key: const Key('chordAutoScrollCard'),
            decoration: studioPanelDecoration(mode: widget.appearance.mode),
            child: SizedBox(
              height: 48,
              child: Padding(
                // "Rolar" starts a little in from the card's edge.
                padding: const EdgeInsets.only(left: 18, right: 5),
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
        _enter(
          Column(
            children: [
              UnifiedPlayerAdjustments(
                model: _player,
                youtubeNativeTransport: _player.isYouTube,
                appearanceMode: widget.appearance.mode,
                showPracticeControls: false,
                compactBottom: true,
                compactTone: _chordActive,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: Row(
                  children: [
                    Expanded(
                      flex: _chordActive ? 35 : 1,
                      child: chooseChordButton,
                    ),
                    if (_chordActive) ...[
                      const SizedBox(width: 6),
                      Expanded(flex: 65, child: autoScrollControls),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
    if (_chordActive) {
      return _toneBackdrop(
        topGap,
        NestedScrollView(
          key: const Key('unifiedChordScroll'),
          controller: _scroll,
          headerSliverBuilder: (context, innerScrolled) => [
            SliverToBoxAdapter(
              child: Column(
                children: [
                  if (topGap > 0) SizedBox(height: topGap),
                  _toneGlass(
                    rounded: true,
                    child: DecoratedBox(
                      key: const Key('unifiedChordControlsBackdrop'),
                      decoration: BoxDecoration(
                        color: _toneFill,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(studioSpotifySkin ? 0 : 34),
                        ),
                      ),
                      child: Column(
                        children: [controls, const SizedBox(height: 4)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          body: Builder(
            builder: (innerContext) {
              _chordTextScroll = PrimaryScrollController.of(innerContext);
              return _toneGlass(
                rounded: false,
                child: ColoredBox(
                  key: const Key('unifiedChordBackdrop'),
                  color: _toneFill,
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
                                widget.appearance.mode ==
                                    StudioAppearanceMode.dark
                                ? playerChordDarkGradient
                                : null,
                          ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          Expanded(
                            child:
                                NotificationListener<ScrollStartNotification>(
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
                ),
              );
            },
          ),
        ),
      );
    }
    return _toneBackdrop(
      topGap,
      SingleChildScrollView(
        key: const Key('unifiedChordScroll'),
        controller: _scroll,
        child: Column(
          children: [
            if (topGap > 0) SizedBox(height: topGap),
            ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: (viewportHeight - topGap).clamp(0, double.infinity),
              ),
              child: _toneGlass(
                rounded: true,
                child: DecoratedBox(
                  key: const Key('unifiedChordControlsBackdrop'),
                  decoration: BoxDecoration(
                    color: _toneFill,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(studioSpotifySkin ? 0 : 34),
                    ),
                  ),
                  // Room under the last control so it scrolls clear of the
                  // floating "Fechar ajustes". Inside the backdrop: as padding
                  // of the scroll view it stayed transparent and showed the
                  // page.
                  child: Column(
                    children: [controls, const SizedBox(height: 88)],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Before any card is built: the mixed themes draw them darker.
    studioGlassDarkPanels = widget.appearance.darkPanels;
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
        canPop:
            !_browsing &&
            !(_mainControlsExpanded && !_isLandscapePlayer) &&
            !(_twoPages && _player.loaded) &&
            pageYouTubeBars.value?.searching != true,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          final browse = _browse;
          // The adjustments sheet is open: back closes it (it has no close
          // button; the grabber does the same).
          if (!_browsing && _mainControlsExpanded && !_isLandscapePlayer) {
            _toggleMainAdjustments();
            return;
          }
          // The site's search is open: back closes it first.
          if (pageYouTubeBars.value?.searching == true) {
            final session = _browsing
                ? (browse ?? _player.youtube)
                : _player.youtube;
            if (session != null) unawaited(session.leaveSearch());
            return;
          }
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
                      // The Apple design closes with its grabber instead.
                      if (!widget.appearance.apple &&
                          !studioYouTubeSkin &&
                          !landscapePlayer &&
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
                      // Two pages with a video open: the bottom bar (it has
                      // the adjustments button) instead of the wide
                      // "Abrir ajustes".
                      if (_playerBarShown &&
                          _musicSource &&
                          !nativeGlassBar.value)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: _HideOnScrollDown(
                            child: ColoredBox(
                              color: const Color(0xFF0F0F0F),
                              child: Padding(
                                padding: EdgeInsets.only(
                                  bottom: MediaQuery.viewPaddingOf(context)
                                      .bottom,
                                ),
                                child: _MusicBottomBar(
                                  current: '',
                                  onTab: _playerBarTap,
                                  onAdjustments: () {
                                    _playerBarTap('adjust');
                                    return true;
                                  },
                                ),
                              ),
                            ),
                          ),
                        )
                      else if (_playerBarShown) ...[
                        if (nativeGlassBar.value)
                          _GlassBarHost(
                            playerPage: true,
                            music: _musicSource,
                            onTap: _playerBarTap,
                          )
                        else
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: _HideOnScrollDown(
                              child: ValueListenableBuilder<YouTubeBars?>(
                                valueListenable: pageYouTubeBars,
                                builder: (context, bars, _) => ColoredBox(
                                  color: bars?.dark == false
                                      ? Colors.white
                                      : const Color(0xFF0F0F0F),
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                      bottom: MediaQuery.viewPaddingOf(context)
                                          .bottom,
                                    ),
                                    child: _ShortsBottomBar(
                                      dark: bars?.dark != false,
                                      avatar: bars?.avatar ?? '',
                                      onHome: () => _playerBarTap('home'),
                                      onShorts: () => _playerBarTap('shorts'),
                                      onYou: () => _playerBarTap('you'),
                                      onAdjustments: () {
                                        _playerBarTap('adjust');
                                        return true;
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ] else if ((landscapePlayer &&
                              !_landscapeColumnsVisible) ||
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
                      _adPill(),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  /// While the YouTube being heard plays an ad (also the hidden one behind
  /// Spotify), a small pill says so: the player has not frozen. Only a
  /// label: the ad itself is never muted, hidden or skipped from here (the
  /// page presses YouTube's own «Ignorar» when YouTube offers it).
  Widget _adPill() {
    final YouTubeBrowserSession? session = _player.youtube;
    if (session == null) return const SizedBox.shrink();
    return Positioned(
      top: 8,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: ListenableBuilder(
          listenable: session,
          builder: (context, _) {
            final YouTubeMediaState media = session.media;
            if (!media.isAd) return const SizedBox.shrink();
            return Center(
              child: Container(
                key: const Key('studioAdPill'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xE6212121),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0x33FFFFFF)),
                ),
                child: Text(
                  media.adSkippable
                      ? 'Publicidade em curso · a saltar…'
                      : 'Publicidade em curso…',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          },
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

/// Keeps the iPhone's native glass bar in step with the page being browsed:
/// it shows while the site's bottom bar would (or on the Shorts page) and
/// leaves with this page.
class _GlassBarHost extends StatefulWidget {
  const _GlassBarHost({
    required this.onTap,
    this.playerPage = false,
    this.music,
  });

  /// YouTube Music's bar (home, explore, adjustments, library). Null: as the
  /// page being browsed says.
  final bool? music;

  final void Function(String name) onTap;

  /// Over the player page (a video is open): the bar shows whatever the
  /// page's own bars are doing, with no tab marked as the current one.
  final bool playerPage;

  @override
  State<_GlassBarHost> createState() => _GlassBarHostState();
}

class _GlassBarHostState extends State<_GlassBarHost> {
  late final Listenable _watched = Listenable.merge([
    pageYouTubeBars,
    nativeGlassBar,
    pictureInPictureShown,
    pageInputFocused,
    pageScrolledDown,
  ]);
  bool _iconsSent = false;

  @override
  void initState() {
    super.initState();
    GlassBar.attach(_tap);
    _watched.addListener(_sync);
    _sync();
  }

  bool get _music => widget.music ?? pageYouTubeBars.value?.music ?? false;

  /// The native bar names its buttons as on YouTube; on YouTube Music the
  /// second is "explore" and the fourth the library.
  void _tap(String name) => widget.onTap(
    !_music
        ? name
        : switch (name) {
            'shorts' => 'explore',
            'you' => 'library',
            _ => name,
          },
  );

  Future<Uint8List> _png(Path shape) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(3.5);
    canvas.drawPath(shape, Paint()..color = Colors.white);
    final image = await recorder.endRecording().toImage(84, 84);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  void _sync() {
    if (!nativeGlassBar.value) return;
    if (!_iconsSent) {
      _iconsSent = true;
      unawaited(() async {
        await GlassBar.setIcons({
          'shortsOutline': await _png(_shortsOutlineIconPath()),
          'shortsFilled': await _png(_shortsFilledIconPath()),
        });
      }());
    }
    final bars = pageYouTubeBars.value;
    GlassBar.update(
      // On the player page the bar leaves while the page is scrolled down.
      visible: widget.playerPage
          ? !pictureInPictureShown.value &&
                !pageInputFocused.value &&
                !pageScrolledDown.value
          : bars != null &&
                !bars.hidden &&
                (bars.pivot != null || bars.shorts || bars.music) &&
                !pictureInPictureShown.value &&
                !pageInputFocused.value,
      music: _music,
      selected: widget.playerPage
          ? ''
          : switch (bars?.tab ?? '') {
              'explore' => 'shorts',
              'library' => 'you',
              final String tab => tab,
            },
      avatar: bars?.avatar ?? '',
      dark: bars?.dark ?? true,
    );
  }

  @override
  void dispose() {
    _watched.removeListener(_sync);
    if (GlassBar.isAttached(_tap)) GlassBar.update(visible: false);
    GlassBar.detach(_tap);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Slides its child down and out while the page is scrolled down, and back
/// when it is scrolled up (the bottom bar on the player page).
class _HideOnScrollDown extends StatelessWidget {
  const _HideOnScrollDown({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: pageScrolledDown,
    builder: (context, down, bar) => IgnorePointer(
      ignoring: down,
      child: AnimatedSlide(
        offset: Offset(0, down ? 1.2 : 0),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: bar,
      ),
    ),
    child: child,
  );
}

/// YouTube Music's bottom bar (the site has none on a phone): home,
/// explore, the adjustments button and the library.
class _MusicBottomBar extends StatelessWidget {
  const _MusicBottomBar({
    required this.current,
    required this.onTab,
    required this.onAdjustments,
  });

  final String current;
  final void Function(String name) onTab;
  final bool Function() onAdjustments;

  @override
  Widget build(BuildContext context) {
    const Color ink = Color(0xFFF1F1F1);
    Widget tab(String name, String tooltip, IconData idle, IconData active) =>
        Expanded(
          child: IconButton(
            key: Key('musicBar$name'),
            tooltip: tooltip,
            onPressed: () => onTab(name),
            icon: Icon(current == name ? active : idle, size: 28, color: ink),
          ),
        );
    return Container(
      key: const Key('musicBottomBar'),
      height: 48,
      decoration: const BoxDecoration(
        color: Color(0xFF0F0F0F),
        border: Border(top: BorderSide(color: Color(0x1FFFFFFF))),
      ),
      child: Row(
        children: [
          tab('home', 'Início', Icons.home_outlined, Icons.home_filled),
          tab('explore', 'Explorar', Icons.explore_outlined, Icons.explore),
          Expanded(
            child: Center(
              child: _BarAdjustmentsButton(
                dark: true,
                onPressed: onAdjustments,
              ),
            ),
          ),
          tab(
            'library',
            'Biblioteca',
            Icons.library_music_outlined,
            Icons.library_music,
          ),
        ],
      ),
    );
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
    this.onShorts,
  });

  final bool dark;
  final String avatar;
  final VoidCallback onHome;
  final VoidCallback onYou;
  final bool Function() onAdjustments;

  /// Null on the Shorts page itself (its icon is then the current one);
  /// elsewhere it opens Shorts.
  final VoidCallback? onShorts;

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
            color: pill && onShorts == null
                ? (dark ? const Color(0x29FFFFFF) : const Color(0x1A000000))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(21),
          ),
          child: _BarShapeButton(
            tooltip: 'Shorts',
            shape: onShorts == null
                ? _shortsFilledIconPath()
                : _shortsOutlineIconPath(),
            color: ink,
            onPressed: onShorts,
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
class _BarAdjustmentsButton extends StatefulWidget {
  const _BarAdjustmentsButton({required this.dark, required this.onPressed});

  final bool dark;

  /// Returns false when there is nothing to open (no video chosen yet): the
  /// button then shakes quickly from side to side, like a "no".
  final bool Function() onPressed;

  @override
  State<_BarAdjustmentsButton> createState() => _BarAdjustmentsButtonState();
}

class _BarAdjustmentsButtonState extends State<_BarAdjustmentsButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _no = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  late final Animation<double> _offset = TweenSequence<double>([
    for (final (double from, double to) in const [
      (0.0, -7.0),
      (-7.0, 7.0),
      (7.0, -5.0),
      (-5.0, 5.0),
      (5.0, -2.0),
      (-2.0, 0.0),
    ])
      TweenSequenceItem(
        tween: Tween(begin: from, end: to),
        weight: 1,
      ),
  ]).animate(_no);

  @override
  void dispose() {
    _no.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 44,
    height: 44,
    child: AnimatedBuilder(
      animation: _offset,
      builder: (context, child) =>
          Transform.translate(offset: Offset(_offset.value, 0), child: child),
      child: IconButton(
        key: const Key('barOpenAdjustments'),
        tooltip: 'Abrir ajustes',
        onPressed: () {
          if (widget.onPressed()) return;
          unawaited(HapticFeedback.lightImpact());
          unawaited(_no.forward(from: 0));
        },
        padding: EdgeInsets.zero,
        icon: Icon(
          Icons.tune_rounded,
          size: 28,
          color: widget.dark
              ? const Color(0xFFF1F1F1)
              : const Color(0xFF0F0F0F),
        ),
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
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: pageDrawsAdjustButton,
    builder: (context, inPage, child) =>
        (inPage && open && !(studioSpotifySource && !studioSpotifySkin)) ||
            (studioSpotifySkin && !studioYouTubeSkin) ||
            // YouTube Music: the adjustments come up from under the player
            // and the bottom bar has their button; no arrow over the page.
            studioMusicSource
        ? const SizedBox.shrink()
        : child!,
    child: _button(context),
  );

  Widget _button(BuildContext context) => SizedBox(
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
