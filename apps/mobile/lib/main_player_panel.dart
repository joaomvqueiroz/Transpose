import 'dart:async';

import 'package:flutter/material.dart';

import 'player_panel_model.dart';
import 'studio_native_pages.dart';

/// Native controls for the selected, shared media session. Values are engine
/// acknowledgements: only a slider's temporary drag preview is held locally.
class MainPlayerPanel extends StatefulWidget {
  const MainPlayerPanel({
    required this.model,
    required this.media,
    required this.onFullscreen,
    required this.onSearch,
    required this.onOpenFile,
    required this.onTool,
    this.showMedia = true,
    super.key,
  });

  final PlayerPanelModel model;
  final Widget media;
  final VoidCallback onFullscreen;
  final VoidCallback onSearch;
  final VoidCallback onOpenFile;
  final ValueChanged<String> onTool;
  final bool showMedia;

  @override
  State<MainPlayerPanel> createState() => _MainPlayerPanelState();
}

class _MainPlayerPanelState extends State<MainPlayerPanel> {
  bool _showTip = true;
  bool _studyExpanded = false;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.model,
    builder: (BuildContext context, Widget? _) {
      final PlayerPanelModel model = widget.model;
      final bool ready = model.loaded && !model.busy;
      return ColoredBox(
        color: studioBg,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (widget.showMedia)
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: ColoredBox(
                    color: Colors.black,
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: widget.media,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      model.loaded ? model.title : 'Escolha uma música',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    key: const Key('visualPlayerFullscreen'),
                    tooltip: 'Tela cheia',
                    onPressed: model.loaded ? widget.onFullscreen : null,
                    icon: const Icon(Icons.fullscreen),
                  ),
                ],
              ),
              if (model.loaded) ...<Widget>[
                Text(
                  model.sourceLabel,
                  style: const TextStyle(color: studioMuted, fontSize: 12),
                ),
                _SeekControl(
                  controlKey: const Key('visualPlayerSeek'),
                  model: model,
                  enabled: ready,
                ),
              ] else ...<Widget>[
                const Text(
                  'Pesquise no YouTube ou abra um ficheiro para começar.',
                  style: TextStyle(color: studioMuted),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    FilledButton.icon(
                      key: const Key('visualPlayerEmptySearch'),
                      onPressed: model.busy ? null : widget.onSearch,
                      icon: const Icon(Icons.search),
                      label: const Text('YouTube'),
                    ),
                    OutlinedButton.icon(
                      key: const Key('visualPlayerEmptyFile'),
                      onPressed: model.busy ? null : widget.onOpenFile,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Abrir ficheiro'),
                    ),
                  ],
                ),
              ],
              if (model.busy) ...<Widget>[
                const SizedBox(height: 8),
                const LinearProgressIndicator(color: studioCyan),
              ],
              if (model.message case final String message
                  when message.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    message,
                    key: const Key('visualPlayerMessage'),
                    style: const TextStyle(color: studioMuted, fontSize: 13),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              if (_showTip) ...<Widget>[
                _Card(
                  padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.touch_app_outlined, color: studioCyan),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Use os botões de 10 s para voltar ou avançar.',
                          style: TextStyle(color: studioMuted, fontSize: 13),
                        ),
                      ),
                      IconButton(
                        key: const Key('visualPlayerDismissTip'),
                        tooltip: 'Fechar dica',
                        onPressed: () => setState(() => _showTip = false),
                        icon: const Icon(Icons.close, size: 18),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const Expanded(child: _Label('TOM')),
                        TextButton(
                          key: const Key('visualPlayerPitchReset'),
                          onPressed:
                              ready &&
                                  (model.canPitch || model.pitchPending) &&
                                  (model.pitch != 0 || model.pitchPending)
                              ? () => model.changePitch(0)
                              : null,
                          child: const Text('Original'),
                        ),
                      ],
                    ),
                    Row(
                      children: <Widget>[
                        _RoundButton(
                          controlKey: const Key('visualPlayerPitchDown'),
                          tooltip: 'Diminuir tom em um semitom',
                          icon: Icons.remove,
                          onPressed:
                              ready && model.canPitch && model.pitch > -12
                              ? () => model.changePitch(
                                  (model.pitch - 1).clamp(-12, 12),
                                )
                              : null,
                        ),
                        Expanded(
                          child: Column(
                            children: <Widget>[
                              Text(
                                _pitchLabel(model.pitch),
                                key: const Key('visualPlayerPitchValue'),
                                style: const TextStyle(
                                  fontSize: 36,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const Text(
                                'semitons',
                                style: TextStyle(
                                  color: studioCyan,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _RoundButton(
                          controlKey: const Key('visualPlayerPitchUp'),
                          tooltip: 'Aumentar tom em um semitom',
                          icon: Icons.add,
                          onPressed: ready && model.canPitch && model.pitch < 12
                              ? () => model.changePitch(
                                  (model.pitch + 1).clamp(-12, 12),
                                )
                              : null,
                        ),
                      ],
                    ),
                    if (model.loaded && !model.canPitch && !model.pitchPending)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text(
                          'A alteração de tom não está disponível nesta fonte.',
                          style: TextStyle(color: studioMuted, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _Card(
                child: _SpeedControl(model: model, enabled: ready),
              ),
              const SizedBox(height: 16),
              _Card(
                child: Column(
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const Icon(Icons.repeat, color: studioMuted, size: 18),
                        const SizedBox(width: 8),
                        const Expanded(child: _Label('REPETIÇÃO A–B')),
                        Switch(
                          key: const Key('visualPlayerLoopToggle'),
                          value: model.loopEnabled,
                          activeThumbColor: studioCyan,
                          onChanged:
                              ready &&
                                  model.canLoop &&
                                  model.markerA != null &&
                                  model.markerB != null
                              ? (_) => model.toggleLoop()
                              : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _MarkerButton(
                            controlKey: const Key('visualPlayerMarkA'),
                            label: 'PONTO A',
                            value: model.markerA,
                            onPressed: ready && model.canLoop
                                ? model.markA
                                : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _MarkerButton(
                            controlKey: const Key('visualPlayerMarkB'),
                            label: 'PONTO B',
                            value: model.markerB,
                            onPressed: ready && model.canLoop
                                ? model.markB
                                : null,
                          ),
                        ),
                      ],
                    ),
                    if (model.markerA != null || model.markerB != null)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          key: const Key('visualPlayerClearLoop'),
                          onPressed: ready && model.canLoop
                              ? model.clearLoop
                              : null,
                          icon: const Icon(Icons.clear, size: 16),
                          label: const Text('Limpar pontos'),
                        ),
                      ),
                    if (model.loaded && !model.canLoop)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'A repetição A–B não está disponível nesta fonte.',
                          style: TextStyle(color: studioMuted, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _Transport(
                model: model,
                enabled: ready,
                pauseEnabled: model.loaded && model.playing && !model.muted,
                fullscreen: false,
              ),
              const SizedBox(height: 20),
              _Card(
                padding: EdgeInsets.zero,
                child: Column(
                  children: <Widget>[
                    InkWell(
                      key: const Key('visualPlayerStudyTools'),
                      borderRadius: BorderRadius.circular(15),
                      onTap: () =>
                          setState(() => _studyExpanded = !_studyExpanded),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: <Widget>[
                            const Icon(
                              Icons.school_outlined,
                              size: 20,
                              color: studioMuted,
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Ferramentas de Estudo',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                            Icon(
                              _studyExpanded
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              color: studioMuted,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_studyExpanded)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            _ToolButton(
                              icon: Icons.timer_outlined,
                              label: 'Metrônomo',
                              tool: 'metronome',
                              onTool: widget.onTool,
                            ),
                            _ToolButton(
                              icon: Icons.music_note_outlined,
                              label: 'Acordes',
                              tool: 'chords',
                              onTool: widget.onTool,
                            ),
                            _ToolButton(
                              icon: Icons.graphic_eq,
                              label: 'Afinador',
                              tool: 'tuner',
                              onTool: widget.onTool,
                            ),
                            _ToolButton(
                              icon: Icons.bookmark_border,
                              label: 'Guardar',
                              tool: 'save',
                              onTool: widget.onTool,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                key: const Key('visualPlayerAdvancedTools'),
                onPressed: () => widget.onTool('advanced'),
                icon: const Icon(Icons.tune, size: 18),
                label: const Text('Ferramentas Áudio Avançado'),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// The parent passes the very same media surface used by [MainPlayerPanel].
/// Locking absorbs platform-view touches as well as native transport controls.
class MainPlayerFullscreen extends StatefulWidget {
  const MainPlayerFullscreen({
    required this.model,
    required this.media,
    required this.onExit,
    this.onTool,
    super.key,
  });

  final PlayerPanelModel model;
  final Widget media;
  final VoidCallback onExit;
  final ValueChanged<String>? onTool;

  @override
  State<MainPlayerFullscreen> createState() => _MainPlayerFullscreenState();
}

class _MainPlayerFullscreenState extends State<MainPlayerFullscreen> {
  static const Duration _hideDelay = Duration(seconds: 4);

  bool _locked = false;
  bool _visible = true;
  bool _menuOpen = false;
  bool _accessibleNavigation = false;
  int _pointersDown = 0;
  Timer? _hideTimer;
  late bool _lastPlaying;
  late bool _lastBusy;
  late bool _lastPending;
  String? _lastMessage;

  @override
  void initState() {
    super.initState();
    _rememberState();
    widget.model.addListener(_onModelChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _accessibleNavigation = MediaQuery.accessibleNavigationOf(context);
    if (_accessibleNavigation) _visible = true;
    _armHideTimer();
  }

  @override
  void didUpdateWidget(MainPlayerFullscreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.model != widget.model) {
      oldWidget.model.removeListener(_onModelChanged);
      widget.model.addListener(_onModelChanged);
      _rememberState();
      _visible = true;
      _armHideTimer();
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    widget.model.removeListener(_onModelChanged);
    super.dispose();
  }

  void _rememberState() {
    _lastPlaying = widget.model.playing;
    _lastBusy = widget.model.busy;
    _lastPending = widget.model.pitchPending;
    _lastMessage = widget.model.message;
  }

  void _onModelChanged() {
    // Position updates must not postpone auto-hide indefinitely. Only a real
    // playback/operation/message change brings the controls back into view.
    final bool changed =
        _lastPlaying != widget.model.playing ||
        _lastBusy != widget.model.busy ||
        _lastPending != widget.model.pitchPending ||
        _lastMessage != widget.model.message;
    _rememberState();
    if (changed || !widget.model.playing) {
      _visible = true;
      _armHideTimer();
    }
    if (mounted) setState(() {});
  }

  void _armHideTimer() {
    _hideTimer?.cancel();
    if (!widget.model.playing ||
        widget.model.busy ||
        widget.model.pitchPending ||
        _locked ||
        _menuOpen ||
        _pointersDown > 0 ||
        _accessibleNavigation ||
        !_visible) {
      return;
    }
    _hideTimer = Timer(_hideDelay, () {
      if (mounted) setState(() => _visible = false);
    });
  }

  void _reveal() {
    if (!_locked && !_visible) setState(() => _visible = true);
    _armHideTimer();
  }

  void _setLocked(bool value) {
    setState(() {
      _locked = value;
      _visible = true;
    });
    _armHideTimer();
  }

  void _menuClosed() {
    _menuOpen = false;
    _reveal();
  }

  @override
  Widget build(BuildContext context) {
    final PlayerPanelModel model = widget.model;
    final bool ready = !_locked && model.loaded && !model.busy;
    return Listener(
      // A raw pointer listener observes taps without stealing gestures from
      // the existing WebView/video. No transparent gesture shield over it.
      onPointerDown: (_) {
        _pointersDown++;
        _hideTimer?.cancel();
      },
      onPointerUp: (_) {
        _pointersDown = (_pointersDown - 1).clamp(0, 100);
        _reveal();
      },
      onPointerCancel: (_) {
        _pointersDown = (_pointersDown - 1).clamp(0, 100);
        _armHideTimer();
      },
      child: ColoredBox(
        key: const Key('visualFullscreenSurface'),
        color: Colors.black,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final bool compact = constraints.maxHeight < 500;
              return Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  AbsorbPointer(
                    absorbing: _locked,
                    child: SizedBox.expand(child: widget.media),
                  ),
                  Align(
                    alignment: Alignment.topCenter,
                    child: IgnorePointer(
                      ignoring: !_visible && !_locked,
                      child: AnimatedOpacity(
                        opacity: _visible || _locked ? 1 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: ColoredBox(
                          color: const Color(0xDF040F1C),
                          child: Row(
                            children: <Widget>[
                              IconButton(
                                key: const Key('visualFullscreenBack'),
                                tooltip: 'Sair da tela cheia',
                                onPressed: _locked ? null : widget.onExit,
                                icon: const Icon(Icons.arrow_back),
                              ),
                              Expanded(
                                child: Text(
                                  _locked
                                      ? 'Bloqueado · mantenha o cadeado pressionado'
                                      : model.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                key: const Key('visualFullscreenLock'),
                                tooltip: _locked
                                    ? 'Mantenha pressionado para desbloquear'
                                    : 'Bloquear toques',
                                // A non-null tap keeps the underlying button enabled
                                // for its long-press recognizer. A short tap never
                                // unlocks the media surface.
                                onPressed: () {
                                  if (!_locked) _setLocked(true);
                                },
                                onLongPress: _locked
                                    ? () => _setLocked(false)
                                    : null,
                                icon: Icon(
                                  _locked ? Icons.lock : Icons.lock_open,
                                  color: _locked ? studioCyan : Colors.white,
                                ),
                              ),
                              PopupMenuButton<String>(
                                key: const Key('visualFullscreenMore'),
                                tooltip: 'Mais opções',
                                enabled: !_locked,
                                onOpened: () {
                                  _menuOpen = true;
                                  _hideTimer?.cancel();
                                },
                                onCanceled: _menuClosed,
                                onSelected: (String value) {
                                  _menuClosed();
                                  if (value == 'reset') {
                                    model.resetProcessing();
                                  } else {
                                    widget.onTool?.call(value);
                                  }
                                },
                                itemBuilder: (_) => <PopupMenuEntry<String>>[
                                  PopupMenuItem<String>(
                                    value: 'reset',
                                    enabled:
                                        ready &&
                                        (model.canPitch ||
                                            model.pitchPending ||
                                            model.canSpeed ||
                                            model.canLoop),
                                    child: const Text(
                                      'Repor tom, velocidade e A–B',
                                    ),
                                  ),
                                  if (widget.onTool !=
                                      null) ...<PopupMenuEntry<String>>[
                                    PopupMenuItem<String>(
                                      value: 'save',
                                      enabled: ready && !model.pitchPending,
                                      child: const Text('Guardar ajustes'),
                                    ),
                                    const PopupMenuItem<String>(
                                      value: 'metronome',
                                      child: Text('Metrônomo'),
                                    ),
                                    const PopupMenuItem<String>(
                                      value: 'chords',
                                      child: Text('Acordes'),
                                    ),
                                    const PopupMenuItem<String>(
                                      value: 'tuner',
                                      child: Text('Afinador por referência'),
                                    ),
                                    const PopupMenuItem<String>(
                                      value: 'advanced',
                                      child: Text('Ferramentas de áudio'),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: IgnorePointer(
                      ignoring: !_visible || _locked,
                      child: AnimatedOpacity(
                        key: const Key('visualFullscreenOverlay'),
                        opacity: _visible && !_locked ? 1 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: ColoredBox(
                          color: const Color(0xEC040F1C),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: constraints.maxHeight * .4,
                            ),
                            child: SingleChildScrollView(
                              key: const Key('visualFullscreenControlsScroll'),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  12,
                                ),
                                child: Column(
                                  children: <Widget>[
                                    if (model.busy || model.pitchPending)
                                      const LinearProgressIndicator(
                                        color: studioCyan,
                                      ),
                                    if (model.message case final String message
                                        when message.isNotEmpty)
                                      Semantics(
                                        liveRegion: true,
                                        child: Padding(
                                          padding: const EdgeInsets.only(
                                            top: 8,
                                          ),
                                          child: Text(
                                            message,
                                            key: const Key(
                                              'visualFullscreenMessage',
                                            ),
                                            style: const TextStyle(
                                              color: studioMuted,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      ),
                                    _SeekControl(
                                      controlKey: const Key(
                                        'visualFullscreenSeek',
                                      ),
                                      model: model,
                                      enabled: ready,
                                      compact: compact,
                                    ),
                                    _Transport(
                                      model: model,
                                      enabled: ready,
                                      pauseEnabled:
                                          !_locked &&
                                          model.loaded &&
                                          model.playing &&
                                          !model.muted,
                                      fullscreen: true,
                                    ),
                                    Wrap(
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      alignment: WrapAlignment.center,
                                      spacing: 4,
                                      children: <Widget>[
                                        IconButton(
                                          key: const Key(
                                            'visualFullscreenPitchDown',
                                          ),
                                          tooltip: 'Diminuir tom',
                                          onPressed:
                                              ready &&
                                                  model.canPitch &&
                                                  model.pitch > -12
                                              ? () => model.changePitch(
                                                  (model.pitch - 1).clamp(
                                                    -12,
                                                    12,
                                                  ),
                                                )
                                              : null,
                                          icon: const Icon(Icons.remove),
                                        ),
                                        Text('${_pitchLabel(model.pitch)} st'),
                                        IconButton(
                                          key: const Key(
                                            'visualFullscreenPitchUp',
                                          ),
                                          tooltip: 'Aumentar tom',
                                          onPressed:
                                              ready &&
                                                  model.canPitch &&
                                                  model.pitch < 12
                                              ? () => model.changePitch(
                                                  (model.pitch + 1).clamp(
                                                    -12,
                                                    12,
                                                  ),
                                                )
                                              : null,
                                          icon: const Icon(Icons.add),
                                        ),
                                        TextButton(
                                          key: const Key(
                                            'visualFullscreenPitchReset',
                                          ),
                                          onPressed:
                                              ready &&
                                                  (model.canPitch ||
                                                      model.pitchPending) &&
                                                  (model.pitch != 0 ||
                                                      model.pitchPending)
                                              ? () => model.changePitch(0)
                                              : null,
                                          child: const Text('Tom original'),
                                        ),
                                      ],
                                    ),
                                    if (model.loaded &&
                                        !model.canPitch &&
                                        !model.pitchPending)
                                      const Text(
                                        'Tom indisponível nesta fonte.',
                                        style: TextStyle(
                                          color: studioMuted,
                                          fontSize: 12,
                                        ),
                                      ),
                                    Wrap(
                                      alignment: WrapAlignment.center,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      spacing: 4,
                                      children: <Widget>[
                                        IconButton(
                                          key: const Key(
                                            'visualFullscreenSpeedDown',
                                          ),
                                          tooltip:
                                              'Diminuir velocidade em 0,05',
                                          onPressed:
                                              ready &&
                                                  model.canSpeed &&
                                                  model.speed > .5
                                              ? () => model.changeSpeed(
                                                  ((model.speed * 20).round() -
                                                              1)
                                                          .clamp(10, 30) /
                                                      20,
                                                )
                                              : null,
                                          icon: const Icon(Icons.fast_rewind),
                                        ),
                                        PopupMenuButton<double>(
                                          key: const Key(
                                            'visualFullscreenSpeed',
                                          ),
                                          tooltip: 'Velocidade',
                                          enabled: ready && model.canSpeed,
                                          initialValue: model.speed,
                                          onOpened: () {
                                            _menuOpen = true;
                                            _hideTimer?.cancel();
                                          },
                                          onCanceled: _menuClosed,
                                          onSelected: (double value) {
                                            _menuClosed();
                                            model.changeSpeed(value);
                                          },
                                          itemBuilder: (_) =>
                                              <PopupMenuEntry<double>>[
                                                for (final double speed
                                                    in <double>[
                                                      .5,
                                                      .75,
                                                      .85,
                                                      1,
                                                      1.25,
                                                      1.5,
                                                    ])
                                                  PopupMenuItem<double>(
                                                    value: speed,
                                                    child: Text(
                                                      '${speed.toStringAsFixed(2)}×',
                                                    ),
                                                  ),
                                              ],
                                          child: Padding(
                                            padding: const EdgeInsets.all(12),
                                            child: Text(
                                              '${model.speed.toStringAsFixed(2)}× ▾',
                                              style: const TextStyle(
                                                color: studioCyan,
                                              ),
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          key: const Key(
                                            'visualFullscreenSpeedUp',
                                          ),
                                          tooltip:
                                              'Aumentar velocidade em 0,05',
                                          onPressed:
                                              ready &&
                                                  model.canSpeed &&
                                                  model.speed < 1.5
                                              ? () => model.changeSpeed(
                                                  ((model.speed * 20).round() +
                                                              1)
                                                          .clamp(10, 30) /
                                                      20,
                                                )
                                              : null,
                                          icon: const Icon(Icons.fast_forward),
                                        ),
                                        TextButton(
                                          key: const Key(
                                            'visualFullscreenSpeedReset',
                                          ),
                                          onPressed:
                                              ready &&
                                                  model.canSpeed &&
                                                  model.speed != 1
                                              ? () => model.changeSpeed(1)
                                              : null,
                                          child: const Text('1,00× original'),
                                        ),
                                      ],
                                    ),
                                    if (model.loaded && !model.canSpeed)
                                      const Text(
                                        'Velocidade indisponível nesta fonte.',
                                        style: TextStyle(
                                          color: studioMuted,
                                          fontSize: 12,
                                        ),
                                      ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: <Widget>[
                                        Expanded(
                                          child: _MarkerButton(
                                            controlKey: const Key(
                                              'visualFullscreenMarkA',
                                            ),
                                            label: 'PONTO A',
                                            value: model.markerA,
                                            onPressed: ready && model.canLoop
                                                ? model.markA
                                                : null,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: _MarkerButton(
                                            controlKey: const Key(
                                              'visualFullscreenMarkB',
                                            ),
                                            label: 'PONTO B',
                                            value: model.markerB,
                                            onPressed: ready && model.canLoop
                                                ? model.markB
                                                : null,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Wrap(
                                      alignment: WrapAlignment.center,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      spacing: 8,
                                      children: <Widget>[
                                        const Text('Repetir A–B'),
                                        Switch(
                                          key: const Key(
                                            'visualFullscreenLoopToggle',
                                          ),
                                          value: model.loopEnabled,
                                          activeThumbColor: studioCyan,
                                          onChanged:
                                              ready &&
                                                  model.canLoop &&
                                                  model.markerA != null &&
                                                  model.markerB != null
                                              ? (_) => model.toggleLoop()
                                              : null,
                                        ),
                                        TextButton.icon(
                                          key: const Key(
                                            'visualFullscreenClearLoop',
                                          ),
                                          onPressed:
                                              ready &&
                                                  model.canLoop &&
                                                  (model.markerA != null ||
                                                      model.markerB != null)
                                              ? model.clearLoop
                                              : null,
                                          icon: const Icon(
                                            Icons.repeat,
                                            size: 18,
                                          ),
                                          label: const Text('Limpar A–B'),
                                        ),
                                      ],
                                    ),
                                    if (model.loaded && !model.canLoop)
                                      const Text(
                                        'Repetição A–B indisponível nesta fonte.',
                                        style: TextStyle(
                                          color: studioMuted,
                                          fontSize: 12,
                                        ),
                                      ),
                                    TextButton.icon(
                                      key: const Key(
                                        'visualFullscreenLockSurface',
                                      ),
                                      onPressed: _locked
                                          ? null
                                          : () => _setLocked(true),
                                      icon: const Icon(Icons.shield_outlined),
                                      label: const Text('Bloquear toques'),
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
                  if (!_visible && !_locked)
                    Align(
                      alignment: Alignment.bottomRight,
                      child: IconButton.filledTonal(
                        key: const Key('visualFullscreenReveal'),
                        tooltip: 'Mostrar controles',
                        onPressed: _reveal,
                        icon: const Icon(Icons.tune),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SeekControl extends StatefulWidget {
  const _SeekControl({
    required this.controlKey,
    required this.model,
    required this.enabled,
    this.compact = false,
  });

  final Key controlKey;
  final PlayerPanelModel model;
  final bool enabled;
  final bool compact;

  @override
  State<_SeekControl> createState() => _SeekControlState();
}

class _SeekControlState extends State<_SeekControl> {
  double? _dragMilliseconds;

  @override
  Widget build(BuildContext context) {
    final double duration = widget.model.duration.inMilliseconds.toDouble();
    final bool seekable =
        widget.enabled && widget.model.canSeek && duration > 0;
    final double position =
        (_dragMilliseconds ?? widget.model.position.inMilliseconds.toDouble())
            .clamp(0, duration > 0 ? duration : 1);
    return Column(
      children: <Widget>[
        Slider(
          key: widget.controlKey,
          min: 0,
          max: duration > 0 ? duration : 1,
          value: position,
          activeColor: studioCyan,
          inactiveColor: const Color(0xFF25384D),
          semanticFormatterCallback: (double value) =>
              _time(Duration(milliseconds: value.round())),
          onChanged: seekable
              ? (double value) => setState(() => _dragMilliseconds = value)
              : null,
          onChangeEnd: seekable
              ? (double value) {
                  setState(() => _dragMilliseconds = null);
                  widget.model.seek(Duration(milliseconds: value.round()));
                }
              : null,
        ),
        Padding(
          padding: EdgeInsets.only(bottom: widget.compact ? 0 : 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                _time(Duration(milliseconds: position.round())),
                style: const TextStyle(color: studioCyan, fontSize: 12),
              ),
              Text(
                _time(widget.model.duration),
                style: const TextStyle(color: studioMuted, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SpeedControl extends StatefulWidget {
  const _SpeedControl({required this.model, required this.enabled});
  final PlayerPanelModel model;
  final bool enabled;

  @override
  State<_SpeedControl> createState() => _SpeedControlState();
}

class _SpeedControlState extends State<_SpeedControl> {
  double? _dragSpeed;

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.enabled && widget.model.canSpeed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: <Widget>[
            const _Label('VELOCIDADE'),
            Text(
              '${(_dragSpeed ?? widget.model.speed).toStringAsFixed(2)}×',
              key: const Key('visualPlayerSpeedValue'),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            ),
          ],
        ),
        Slider(
          key: const Key('visualPlayerSpeed'),
          value: (_dragSpeed ?? widget.model.speed).clamp(.5, 1.5),
          min: .5,
          max: 1.5,
          divisions: 20,
          activeColor: studioCyan,
          inactiveColor: const Color(0xFF25384D),
          semanticFormatterCallback: (double value) =>
              '${value.toStringAsFixed(2)} vezes',
          onChanged: enabled
              ? (double value) => setState(() => _dragSpeed = value)
              : null,
          onChangeEnd: enabled
              ? (double value) {
                  setState(() => _dragSpeed = null);
                  widget.model.changeSpeed(value);
                }
              : null,
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: <Widget>[
            for (final (double, String) preset in <(double, String)>[
              (.75, '075'),
              (.85, '085'),
              (1, '100'),
            ])
              OutlinedButton(
                key: Key('visualPlayerSpeed${preset.$2}'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: (widget.model.speed - preset.$1).abs() < .001
                      ? studioCyan
                      : studioMuted,
                  side: BorderSide(
                    color: (widget.model.speed - preset.$1).abs() < .001
                        ? studioCyan
                        : const Color(0xFF2C4055),
                  ),
                  backgroundColor: const Color(0xFF1B2C40),
                  minimumSize: const Size(76, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: enabled
                    ? () => widget.model.changeSpeed(preset.$1)
                    : null,
                child: Text('${preset.$1.toStringAsFixed(2)}×'),
              ),
          ],
        ),
        if (widget.model.loaded && !widget.model.canSpeed)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'A velocidade não está disponível nesta fonte.',
              style: TextStyle(color: studioMuted, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

class _Transport extends StatelessWidget {
  const _Transport({
    required this.model,
    required this.enabled,
    required this.pauseEnabled,
    required this.fullscreen,
  });
  final PlayerPanelModel model;
  final bool enabled;
  final bool pauseEnabled;
  final bool fullscreen;

  @override
  Widget build(BuildContext context) {
    final String prefix = fullscreen ? 'visualFullscreen' : 'visualPlayer';
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        _RoundButton(
          controlKey: Key('${prefix}Back10'),
          tooltip: 'Voltar 10 segundos',
          icon: Icons.replay_10,
          onPressed: enabled && model.canSeek
              ? () => model.seek(model.position - const Duration(seconds: 10))
              : null,
        ),
        const SizedBox(width: 24),
        _RoundButton(
          controlKey: Key('${prefix}Play'),
          tooltip: model.muted
              ? 'Ativar som e reproduzir'
              : model.playing
              ? 'Pausar'
              : 'Reproduzir',
          icon: model.muted
              ? Icons.volume_off
              : model.playing
              ? Icons.pause
              : Icons.play_arrow,
          primary: true,
          onPressed: enabled || pauseEnabled ? model.playPause : null,
        ),
        const SizedBox(width: 24),
        _RoundButton(
          controlKey: Key('${prefix}Forward10'),
          tooltip: 'Avançar 10 segundos',
          icon: Icons.forward_10,
          onPressed: enabled && model.canSeek
              ? () => model.seek(model.position + const Duration(seconds: 10))
              : null,
        ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.controlKey,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.primary = false,
  });

  final Key controlKey;
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) => IconButton.filled(
    key: controlKey,
    tooltip: tooltip,
    onPressed: onPressed,
    style: IconButton.styleFrom(
      backgroundColor: primary ? studioCyan : const Color(0xFF203146),
      foregroundColor: primary ? studioBg : Colors.white,
      disabledBackgroundColor: const Color(0xFF192838),
      disabledForegroundColor: const Color(0xFF667381),
      fixedSize: Size.square(primary ? 60 : 50),
    ),
    icon: Icon(icon, size: primary ? 30 : 24),
  );
}

class _MarkerButton extends StatelessWidget {
  const _MarkerButton({
    required this.controlKey,
    required this.label,
    required this.value,
    required this.onPressed,
  });
  final Key controlKey;
  final String label;
  final Duration? value;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    key: controlKey,
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      backgroundColor: const Color(0xFF1B2D40),
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    child: Column(
      children: <Widget>[
        Text(label, style: const TextStyle(fontSize: 10, color: studioMuted)),
        const SizedBox(height: 4),
        Text(value == null ? 'Marcar' : _time(value!)),
      ],
    ),
  );
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.tool,
    required this.onTool,
  });
  final IconData icon;
  final String label;
  final String tool;
  final ValueChanged<String> onTool;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    key: Key('visualPlayerTool_$tool'),
    onPressed: () => onTool(tool),
    icon: Icon(icon, size: 18),
    label: Text(label),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: studioCard,
      border: Border.all(color: const Color(0xFF203246)),
      borderRadius: BorderRadius.circular(15),
    ),
    child: child,
  );
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: studioMuted,
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: .9,
    ),
  );
}

String _pitchLabel(double pitch) =>
    '${pitch > 0 ? '+' : ''}${pitch == pitch.roundToDouble() ? pitch.toInt() : pitch.toStringAsFixed(1)}';

String _time(Duration time) {
  final int seconds = time.inSeconds.clamp(0, 359999);
  final String minute = ((seconds ~/ 60) % 60).toString().padLeft(2, '0');
  final String second = (seconds % 60).toString().padLeft(2, '0');
  return seconds >= 3600
      ? '${seconds ~/ 3600}:$minute:$second'
      : '$minute:$second';
}
