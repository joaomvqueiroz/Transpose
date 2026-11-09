import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gecko_view/gecko_view.dart';
import 'package:player_core/player_core.dart';
import 'package:video_player/video_player.dart';

import 'fullscreen_player.dart';
import 'media/native_audio_media_loader.dart';
import 'media/video_player_media_loader.dart';
import 'studio_visual_app.dart';
import 'youtube_browser.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // iOS builds with the Gecko engine kit render YouTube with Gecko.
  await GeckoEngine.ensureInitialized();
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarContrastEnforced: false,
    ),
  );
  runApp(
    const StudioVisualApp(
      openSearchWhenEmpty: true,
      waitForStartupBrowser: true,
      // First screen: choose YouTube (full studio) or Spotify (listening).
      chooseSourceAtStart: true,
      // YouTube and YouTube Music: browse and search on one page while the
      // chosen video plays on another, in the app's own mini player.
      browseSessionFactory: WebViewYouTubeSession.new,
    ),
  );
}

class TransposeApp extends StatelessWidget {
  const TransposeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Transpono',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF051424),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          surface: Color(0xFF0B1B2F),
          onSurface: Colors.white,
        ),
      ),
      home: const PlayerScreen(),
    );
  }
}

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with WidgetsBindingObserver {
  static const Color _muted = Color(0xFF94A3B8);
  static const Color _card = Color(0xFF0B1B2F);
  static const Color _cyan = Color(0xFF00E5FF);

  final VideoPlayerMediaLoader _loader = VideoPlayerMediaLoader();
  late final PlayerSession _session = PlayerSession(
    sessionId: 'main-player',
    loader: _loader,
  );
  late final StreamSubscription<PlayerState> _states = _session.states.listen((
    PlayerState _,
  ) {
    if (mounted) setState(() {});
  });
  VideoPlayerController? _controller;
  NativeAudioLoadedMedia? _audio;
  Timer? _audioRefresh;
  double _pitchSemitones = 0;
  double _speedFactor = 1;
  double? _pitchPreview;
  double? _speedPreview;
  Duration? _markerA;
  Duration? _markerB;
  Duration? _seekPreview;
  bool _busy = false;
  bool _fullscreenOpen = false;
  bool _appActive = true;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    if (!_appActive) unawaited(_pauseForBackground());
  }

  Future<void> _pauseForBackground() async {
    if (_session.state != PlayerState.playing) return;
    try {
      await _session.pause();
    } on Object {
      if (mounted) {
        setState(() => _message = 'Não foi possível pausar ao sair da app.');
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _audioRefresh?.cancel();
    _controller?.removeListener(_refreshVideo);
    unawaited(_states.cancel());
    unawaited(_session.dispose());
    super.dispose();
  }

  void _refreshVideo() {
    if (mounted) setState(() {});
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } on Object {
      if (mounted) {
        setState(
          () => _message = 'Não foi possível concluir a operação. Escolhe outro ficheiro ou tenta novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load(LocalFileSource source) async {
    _audioRefresh?.cancel();
    _controller?.removeListener(_refreshVideo);
    _controller = null;
    _audio = null;
    _seekPreview = null;
    await _session.load(source);
    _controller = _loader.currentController;
    _audio = _loader.currentAudio;
    _pitchSemitones = 0;
    _speedFactor = 1;
    _pitchPreview = null;
    _speedPreview = null;
    _markerA = null;
    _markerB = null;
    _controller?.addListener(_refreshVideo);
    if (_audio != null) {
      _audioRefresh = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (mounted) setState(() {});
      });
    }
    if (mounted) setState(() {});
  }

  Future<void> _loadSample() => _run(() async {
    final ByteData data = await rootBundle.load('assets/qa_tone.wav');
    final File fixture = File(
      '${Directory.systemTemp.path}/transpose-qa-tone.wav',
    );
    await fixture.writeAsBytes(data.buffer.asUint8List(), flush: true);
    await _load(
      LocalFileSource.fromPath(
        id: 'qa-tone',
        displayName: 'Amostra de áudio · 440 Hz',
        path: fixture.path,
      ),
    );
  });

  Future<void> _pickLocalFile() => _run(() async {
    final PlatformFile? picked = await FilePicker.pickFile();
    if (picked == null) return;
    final Uri locator = picked.path == null
        ? picked.uri
        : Uri.file(picked.path!);
    await _load(
      LocalFileSource(
        id: 'picked-${DateTime.now().microsecondsSinceEpoch}',
        displayName: picked.name,
        locator: locator,
      ),
    );
  });

  Future<void> _togglePlayback() => _run(() async {
    if (_session.state == PlayerState.playing) {
      await _session.pause();
    } else if (_session.state == PlayerState.ready ||
        _session.state == PlayerState.paused) {
      await _session.play();
      if (!_appActive) await _session.pause();
    }
  });

  Future<void> _restart() => _run(() async {
    await _session.seek(Duration.zero);
    await _session.play();
    if (!_appActive) await _session.pause();
  });

  Future<void> _seekTo(Duration target) async {
    await _run(() async {
      await _session.seek(target);
    });
    if (mounted) setState(() => _seekPreview = null);
  }

  Future<void> _changeProcessing({double? pitch, double? speed}) =>
      _run(() async {
        final NativeAudioLoadedMedia? audio = _audio;
        if (audio == null) return;
        final double nextPitch = pitch ?? _pitchSemitones;
        final double nextSpeed = speed ?? _speedFactor;
        try {
          await audio.setParameters(semitones: nextPitch, speed: nextSpeed);
          if (mounted) {
            setState(() {
              _pitchSemitones = nextPitch;
              _speedFactor = nextSpeed;
            });
          }
        } finally {
          if (mounted) {
            setState(() {
              _pitchPreview = null;
              _speedPreview = null;
            });
          }
        }
      });

  void _markA() {
    final Duration position = _session.position ?? Duration.zero;
    if (_markerB != null &&
        position.inMilliseconds >= _markerB!.inMilliseconds) {
      setState(
        () => _message = 'O ponto A deve ficar pelo menos 1 ms antes de B.',
      );
      return;
    }
    final NativeAudioLoadedMedia? audio = _audio;
    if (audio?.loopEnabled == true) {
      unawaited(
        _run(() async {
          await audio!.setLoop(LoopRange(start: position, end: _markerB!));
          if (mounted) setState(() => _markerA = position);
        }),
      );
    } else {
      setState(() {
        _markerA = position;
        _message = null;
      });
    }
  }

  void _markB() {
    final Duration position = _session.position ?? Duration.zero;
    if (_markerA == null ||
        position.inMilliseconds <= _markerA!.inMilliseconds) {
      setState(
        () => _message =
            'Marca A primeiro; B deve ficar pelo menos 1 ms depois de A.',
      );
      return;
    }
    final NativeAudioLoadedMedia? audio = _audio;
    if (audio?.loopEnabled == true) {
      unawaited(
        _run(() async {
          await audio!.setLoop(LoopRange(start: _markerA!, end: position));
          if (mounted) setState(() => _markerB = position);
        }),
      );
    } else {
      setState(() {
        _markerB = position;
        _message = null;
      });
    }
  }

  Future<void> _toggleLoop() => _run(() async {
    final NativeAudioLoadedMedia? audio = _audio;
    if (audio == null) return;
    if (audio.loopEnabled) {
      await audio.clearLoop();
    } else {
      final Duration? a = _markerA;
      final Duration? b = _markerB;
      if (a == null || b == null) {
        throw StateError('A/B markers are incomplete.');
      }
      await audio.setLoop(LoopRange(start: a, end: b));
    }
    if (mounted) setState(() {});
  });

  Future<void> _openFullscreen() async {
    final VideoPlayerController? controller = _controller;
    if (_busy || controller == null || _session.source == null) return;
    setState(() => _fullscreenOpen = true);
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) =>
              FullscreenPlayer(session: _session, controller: controller),
        ),
      );
    } finally {
      if (mounted) setState(() => _fullscreenOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final PlayerState state = _session.state;
    final bool canPlay =
        state == PlayerState.ready || state == PlayerState.paused;
    final bool canPause = state == PlayerState.playing;
    final bool canRestart = state == PlayerState.ended;
    final VideoPlayerController? controller = _controller;
    final Duration? mediaDuration = _session.duration;
    final Duration timelinePosition =
        _seekPreview ?? _session.position ?? Duration.zero;
    final int maxMilliseconds = mediaDuration?.inMilliseconds ?? 0;
    final bool canSeek =
        !_busy &&
        _session.source?.capabilities.canSeek == true &&
        maxMilliseconds > 0 &&
        (state == PlayerState.ready ||
            state == PlayerState.playing ||
            state == PlayerState.paused ||
            state == PlayerState.buffering ||
            state == PlayerState.interrupted ||
            state == PlayerState.ended);
    final bool hasVideo =
        controller != null &&
        controller.value.isInitialized &&
        controller.value.size.width > 0 &&
        controller.value.size.height > 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Player'),
        centerTitle: true,
        backgroundColor: const Color(0xFF07121F),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Container(
                height: 245,
                decoration: BoxDecoration(
                  color: const Color(0xFF07121F),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .07),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    if (_fullscreenOpen)
                      const ColoredBox(color: Color(0xFF07121F))
                    else if (hasVideo)
                      Center(
                        child: AspectRatio(
                          aspectRatio: controller.value.aspectRatio,
                          child: VideoPlayer(controller),
                        ),
                      )
                    else
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          const Icon(Icons.music_note, color: _cyan, size: 54),
                          const SizedBox(height: 12),
                          Text(
                            _session.source == null
                                ? 'Áudio e vídeo local'
                                : 'Faixa de áudio carregada',
                            style: const TextStyle(fontSize: 18),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _session.source == null
                                ? 'Escolhe um ficheiro para começar'
                                : 'Sem imagem de vídeo',
                            style: const TextStyle(color: _muted),
                          ),
                        ],
                      ),
                    if (_session.source != null && !_fullscreenOpen)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: IconButton.filledTonal(
                          key: const Key('enterFullscreenButton'),
                          tooltip: 'Abrir ecrã inteiro',
                          onPressed: _busy ? null : _openFullscreen,
                          icon: const Icon(Icons.fullscreen),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Text(
                _session.source?.displayName ?? 'Nenhuma faixa carregada',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _statusLabel(state),
                textAlign: TextAlign.center,
                style: const TextStyle(color: _muted, fontSize: 13),
              ),
              if (maxMilliseconds > 0) ...<Widget>[
                const SizedBox(height: 16),
                Slider(
                  key: const Key('seekSlider'),
                  min: 0,
                  max: maxMilliseconds.toDouble(),
                  value: timelinePosition.inMilliseconds
                      .clamp(0, maxMilliseconds)
                      .toDouble(),
                  label: _formatPosition(timelinePosition),
                  semanticFormatterCallback: (double value) =>
                      _formatPosition(Duration(milliseconds: value.round())),
                  onChanged: canSeek
                      ? (double value) => setState(
                          () => _seekPreview = Duration(
                            milliseconds: value.round(),
                          ),
                        )
                      : null,
                  onChangeEnd: canSeek
                      ? (double value) => unawaited(
                          _seekTo(Duration(milliseconds: value.round())),
                        )
                      : null,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Text(
                        _formatPosition(timelinePosition),
                        key: const Key('currentPosition'),
                        style: const TextStyle(color: _muted),
                      ),
                      Text(
                        _formatPosition(mediaDuration!),
                        key: const Key('totalDuration'),
                        style: const TextStyle(color: _muted),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Center(
                child: FilledButton.icon(
                  key: const Key('playPauseButton'),
                  onPressed: !_busy && (canPlay || canPause || canRestart)
                      ? (canRestart ? _restart : _togglePlayback)
                      : null,
                  icon: Icon(
                    canPause
                        ? Icons.pause
                        : canRestart
                        ? Icons.replay
                        : Icons.play_arrow,
                    size: 30,
                  ),
                  label: Text(
                    canPause
                        ? 'Pausar'
                        : canRestart
                        ? 'Recomeçar'
                        : 'Reproduzir',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: _cyan,
                    foregroundColor: const Color(0xFF00363D),
                    minimumSize: const Size(190, 56),
                  ),
                ),
              ),
              const SizedBox(height: 30),
              if (_audio != null) ...<Widget>[
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: _card,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        'Tom: ${_pitchSemitones >= 0 ? '+' : ''}${_pitchSemitones.toStringAsFixed(0)} semitons',
                        key: const Key('pitchValue'),
                      ),
                      Slider(
                        key: const Key('pitchSlider'),
                        min: -12,
                        max: 12,
                        divisions: 24,
                        value: _pitchPreview ?? _pitchSemitones,
                        onChanged: _busy
                            ? null
                            : (double value) =>
                                  setState(() => _pitchPreview = value),
                        onChangeEnd: _busy
                            ? null
                            : (double value) =>
                                  unawaited(_changeProcessing(pitch: value)),
                      ),
                      Text(
                        'Velocidade: ${_speedFactor.toStringAsFixed(2)}×',
                        key: const Key('speedValue'),
                      ),
                      Slider(
                        key: const Key('speedSlider'),
                        min: 0.5,
                        max: 2,
                        divisions: 30,
                        value: _speedPreview ?? _speedFactor,
                        onChanged: _busy
                            ? null
                            : (double value) =>
                                  setState(() => _speedPreview = value),
                        onChangeEnd: _busy
                            ? null
                            : (double value) =>
                                  unawaited(_changeProcessing(speed: value)),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Loop A/B: ${_markerA == null ? '--:--' : _formatPosition(_markerA!)} → ${_markerB == null ? '--:--' : _formatPosition(_markerB!)}',
                        key: const Key('loopMarkers'),
                      ),
                      Row(
                        children: <Widget>[
                          TextButton(
                            key: const Key('markAButton'),
                            onPressed: _busy ? null : _markA,
                            child: const Text('Marcar A'),
                          ),
                          TextButton(
                            key: const Key('markBButton'),
                            onPressed: _busy ? null : _markB,
                            child: const Text('Marcar B'),
                          ),
                          const Spacer(),
                          FilledButton.tonal(
                            key: const Key('loopToggleButton'),
                            onPressed:
                                _busy || (_markerA == null || _markerB == null)
                                ? null
                                : () => unawaited(_toggleLoop()),
                            child: Text(
                              _audio?.loopEnabled == true
                                  ? 'Loop ligado'
                                  : 'Ativar loop',
                            ),
                          ),
                        ],
                      ),
                      const Text(
                        'Android experimental: precisão do loop, clicks e latência ainda não validados.',
                        style: TextStyle(color: _muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
              ],
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .06),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const Text(
                      'Fonte local',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      key: const Key('openFileButton'),
                      onPressed: _busy ? null : _pickLocalFile,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Abrir áudio ou vídeo'),
                    ),
                    TextButton(
                      key: const Key('sampleButton'),
                      onPressed: _busy ? null : _loadSample,
                      child: const Text('Ouvir amostra de teste'),
                    ),
                  ],
                ),
              ),
              if (_busy) ...<Widget>[
                const SizedBox(height: 18),
                const Center(child: CircularProgressIndicator()),
              ],
              if (_message != null) ...<Widget>[
                const SizedBox(height: 18),
                Text(
                  _message!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFFFFB4AB)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _statusLabel(PlayerState state) => switch (state) {
    PlayerState.idle => 'Pronto para escolher uma fonte',
    PlayerState.loading => 'A carregar…',
    PlayerState.ready => 'Pronto para reproduzir',
    PlayerState.playing => 'A reproduzir',
    PlayerState.paused => 'Em pausa',
    PlayerState.buffering => 'A preparar áudio…',
    PlayerState.interrupted => 'Reprodução interrompida',
    PlayerState.error => 'Erro de reprodução',
    PlayerState.ended => 'Faixa terminada',
  };

  String _formatPosition(Duration position) {
    final int minutes = position.inMinutes;
    final int seconds = position.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
