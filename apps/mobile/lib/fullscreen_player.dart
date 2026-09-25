import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:player_core/player_core.dart';
import 'package:video_player/video_player.dart';

/// Presentation-only route. The parent keeps ownership of both arguments.
/// This route never creates, loads, replaces or disposes a media session.
class FullscreenPlayer extends StatefulWidget {
  const FullscreenPlayer({
    required this.session,
    required this.controller,
    super.key,
  });

  final PlayerSession session;
  final VideoPlayerController controller;

  @override
  State<FullscreenPlayer> createState() => _FullscreenPlayerState();
}

class _FullscreenPlayerState extends State<FullscreenPlayer> {
  static const Duration _overlayTimeout = Duration(milliseconds: 2500);
  static const Color _cyan = Color(0xFF00E5FF);

  StreamSubscription<PlayerState>? _states;
  Timer? _hideTimer;
  bool _controlsVisible = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
    _states = widget.session.states.listen((PlayerState _) {
      if (mounted) setState(() {});
    });
    widget.controller.addListener(_onMediaChanged);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    widget.controller.removeListener(_onMediaChanged);
    unawaited(_states?.cancel());
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  void _onMediaChanged() {
    if (mounted) setState(() {});
  }

  void _toggleControls() {
    if (_controlsVisible) {
      _hideTimer?.cancel();
      setState(() => _controlsVisible = false);
    } else {
      _showControls();
    }
  }

  void _showControls() {
    _hideTimer?.cancel();
    setState(() => _controlsVisible = true);
    _hideTimer = Timer(_overlayTimeout, () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  Future<void> _togglePlayback() async {
    if (_busy) return;
    _showControls();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      switch (widget.session.state) {
        case PlayerState.playing:
          await widget.session.pause();
        case PlayerState.ready || PlayerState.paused:
          await widget.session.play();
        case PlayerState.ended:
          await widget.session.seek(Duration.zero);
          await widget.session.play();
        default:
          break;
      }
    } on Object {
      if (mounted) {
        setState(() => _error = 'Não foi possível alterar a reprodução.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final PlayerState state = widget.session.state;
    final bool hasVideo =
        widget.controller.value.isInitialized &&
        widget.controller.value.size.width > 0 &&
        widget.controller.value.size.height > 0;
    final bool canToggle =
        state == PlayerState.ready ||
        state == PlayerState.playing ||
        state == PlayerState.paused ||
        state == PlayerState.ended;

    return Scaffold(
      backgroundColor: const Color(0xFF040F1C),
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          hasVideo
              ? FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: widget.controller.value.size.width,
                    height: widget.controller.value.size.height,
                    child: VideoPlayer(widget.controller),
                  ),
                )
              : Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.music_note, size: 76, color: _cyan),
                      const SizedBox(height: 16),
                      Text(
                        widget.session.source?.displayName ?? 'Áudio local',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 20,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
          GestureDetector(
            key: const Key('fullscreenSurface'),
            behavior: HitTestBehavior.opaque,
            onTap: _toggleControls,
          ),
          if (_controlsVisible) ...<Widget>[
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        Colors.black.withValues(alpha: .55),
                        Colors.transparent,
                        Colors.black.withValues(alpha: .65),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: IconButton.filledTonal(
                  key: const Key('exitFullscreenButton'),
                  tooltip: 'Voltar do ecrã inteiro',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back),
                ),
              ),
            ),
            Center(
              child: FilledButton.tonalIcon(
                key: const Key('fullscreenPlayPauseButton'),
                onPressed: canToggle && !_busy ? _togglePlayback : null,
                icon: Icon(
                  state == PlayerState.playing
                      ? Icons.pause
                      : state == PlayerState.ended
                      ? Icons.replay
                      : Icons.play_arrow,
                ),
                label: Text(
                  state == PlayerState.playing
                      ? 'Pausar'
                      : state == PlayerState.ended
                      ? 'Recomeçar'
                      : 'Reproduzir',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: _cyan,
                  foregroundColor: const Color(0xFF00363D),
                  minimumSize: const Size(150, 56),
                ),
              ),
            ),
            if (_error != null)
              SafeArea(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Color(0xFFFFB4AB)),
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
