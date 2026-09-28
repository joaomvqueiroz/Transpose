import 'dart:async';

import 'package:flutter/material.dart';

import 'chord_sheet.dart';
import 'player_chord_sheet.dart';
import 'player_panel_model.dart';
import 'studio_native_pages.dart';
import 'studio_appearance.dart';

/// Shared player controls with a reading area and on-demand audio settings.
class MainPlayerPanel extends StatefulWidget {
  const MainPlayerPanel({
    required this.model,
    required this.media,
    required this.onFullscreen,
    required this.onSearch,
    required this.onOpenFile,
    required this.onTool,
    this.showMedia = true,
    this.mediaExtraHeight = 0,
    this.sourceKey = '',
    this.chordStore,
    this.chordActive,
    this.onChordToggle,
    this.onChordSearch,
    this.chordRevision = 0,
    this.videoPinned = false,
    this.onPinToggle,
    this.controlsExpanded,
    this.onControlsToggle,
    this.showControlsToggle = true,
    this.showTip = true,
    this.showSourceButtons = true,
    this.showMessage = true,
    super.key,
  });
  final PlayerPanelModel model;
  final Widget media;
  final VoidCallback onFullscreen, onSearch, onOpenFile;
  final ValueChanged<String> onTool;
  final bool showMedia;
  final double mediaExtraHeight;
  final String sourceKey;
  final ChordSheetStore? chordStore;
  final bool? chordActive;
  final VoidCallback? onChordToggle;
  final VoidCallback? onChordSearch;
  final int chordRevision;
  final bool videoPinned;
  final VoidCallback? onPinToggle;
  final bool? controlsExpanded;
  final VoidCallback? onControlsToggle;
  final bool showControlsToggle;
  final bool showTip;
  final bool showSourceButtons;
  final bool showMessage;
  @override
  State<MainPlayerPanel> createState() => _MainPlayerPanelState();
}

class _MainPlayerPanelState extends State<MainPlayerPanel> {
  bool _showTip = true;
  bool _localChordActive = false;
  bool _controlsExpanded = false;
  bool get _effectiveControlsExpanded =>
      widget.controlsExpanded ?? _controlsExpanded;
  bool get _chordActive => widget.chordActive ?? _localChordActive;
  final _chordKey = GlobalKey<PlayerChordSheetState>();
  late final ChordSheetStore _fallbackChordStore = ChordSheetStore();

  void _toggleChord() {
    setState(() => _controlsExpanded = false);
    if (widget.onChordToggle != null) {
      widget.onChordToggle!();
    } else {
      setState(() => _localChordActive = !_localChordActive);
    }
  }

  Widget _sourceAction({
    required String keyName,
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    bool selected = false,
  }) => Expanded(
    child: OutlinedButton(
      key: Key(keyName),
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: selected
            ? studioCyan.withValues(alpha: .12)
            : const Color(0xFF171717),
        foregroundColor: selected ? studioCyan : Colors.white,
        side: BorderSide(
          color: selected ? studioCyan : const Color(0xFF383838),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 17),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.model,
    builder: (context, _) {
      final model = widget.model;
      return ColoredBox(
        color: Colors.black,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.showMedia)
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: LayoutBuilder(
                    builder: (_, box) => SizedBox(
                      height: box.maxWidth * 9 / 16 + widget.mediaExtraHeight,
                      child: MainPlayerMediaSurface(
                        model: model,
                        settingsEnabled: _chordActive,
                        media: widget.media,
                        onFullscreen: widget.onFullscreen,
                        videoPinned: widget.videoPinned,
                        onPinToggle: widget.onPinToggle,
                        transportInDeck:
                            _effectiveControlsExpanded && !_chordActive,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              if (!_chordActive) ...[
                if (widget.showControlsToggle)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const Key('visualPlayerControlsToggle'),
                      onPressed:
                          widget.onControlsToggle ??
                          () => setState(
                            () => _controlsExpanded = !_controlsExpanded,
                          ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 54),
                        backgroundColor: const Color(0xFF143544),
                        foregroundColor: studioCyan,
                        side: const BorderSide(color: studioCyan, width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: Icon(
                        _effectiveControlsExpanded
                            ? Icons.keyboard_arrow_down
                            : Icons.keyboard_arrow_up,
                        size: 32,
                      ),
                      label: Text(
                        _effectiveControlsExpanded
                            ? 'Fechar ajustes'
                            : 'Abrir ajustes',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                if (_effectiveControlsExpanded) ...[
                  const SizedBox(height: 6),
                  _FullscreenStyleControls(model: model, onTool: widget.onTool),
                ],
                const SizedBox(height: 8),
              ],
              if (widget.showSourceButtons)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sourceAction(
                      keyName: 'visualPlayerEmptyFile',
                      label: 'Abrir ficheiro',
                      icon: Icons.folder_open,
                      onPressed: model.busy ? null : widget.onOpenFile,
                    ),
                    const SizedBox(width: 8),
                    _sourceAction(
                      keyName: 'visualPlayerChordPicker',
                      label: 'Cifra',
                      icon: Icons.library_music_outlined,
                      selected: _chordActive,
                      onPressed: _toggleChord,
                    ),
                    const SizedBox(width: 8),
                    _sourceAction(
                      keyName: 'visualPlayerEmptySearch',
                      label: 'YouTube',
                      icon: Icons.search,
                      onPressed: model.busy ? null : widget.onSearch,
                    ),
                  ],
                ),
              if (model.busy) ...[
                const SizedBox(height: 8),
                const LinearProgressIndicator(color: studioCyan),
              ],
              if (widget.showMessage &&
                  model.message != null &&
                  model.message!.isNotEmpty) ...[
                const SizedBox(height: 10),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    model.message!,
                    key: const Key('visualPlayerMessage'),
                    style: const TextStyle(color: studioMuted, fontSize: 13),
                  ),
                ),
              ],
              SizedBox(height: _chordActive ? 8 : 16),
              if (_chordActive)
                PlayerChordSheet(
                  key: _chordKey,
                  model: model,
                  sourceKey: widget.sourceKey,
                  store: widget.chordStore ?? _fallbackChordStore,
                  onSearch: widget.onChordSearch,
                  onHide: _toggleChord,
                  revision: widget.chordRevision,
                ),
              if (widget.showTip && _showTip) ...[
                const SizedBox(height: 12),
                _Card(
                  padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                  child: Row(
                    children: [
                      const Icon(Icons.touch_app_outlined, color: studioCyan),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Toque no vídeo para mostrar os controlos por 2 segundos. Com Cifra ativa, ajuste tom, velocidade e loop na engrenagem dentro do vídeo.',
                          style: TextStyle(color: studioMuted, fontSize: 12),
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
              ],
            ],
          ),
        ),
      );
    },
  );
}

/// The caller sizes this surface, keeping the shared WebView's viewport intact.
class MainPlayerMediaSurface extends StatefulWidget {
  const MainPlayerMediaSurface({
    required this.model,
    required this.media,
    this.onFullscreen,
    this.settingsEnabled = false,
    this.videoPinned = false,
    this.onPinToggle,
    this.externalSettingsOpen,
    this.onSettingsToggle,
    this.transportInDeck = false,
    super.key,
  });
  final PlayerPanelModel model;
  final Widget media;
  final bool settingsEnabled;
  final VoidCallback? onFullscreen;
  final bool videoPinned;
  final VoidCallback? onPinToggle;
  final bool? externalSettingsOpen;
  final VoidCallback? onSettingsToggle;
  final bool transportInDeck;
  @override
  State<MainPlayerMediaSurface> createState() => _MainPlayerMediaSurfaceState();
}

class _MainPlayerMediaSurfaceState extends State<MainPlayerMediaSurface> {
  Timer? _hideTimer;
  bool _visible = false;
  bool _localSettingsOpen = false;
  bool get _settingsOpen => widget.externalSettingsOpen ?? _localSettingsOpen;

  void _setSettingsOpen(bool value) {
    if (_settingsOpen == value) return;
    if (widget.onSettingsToggle != null) {
      widget.onSettingsToggle!();
    } else {
      setState(() => _localSettingsOpen = value);
    }
  }

  @override
  void didUpdateWidget(MainPlayerMediaSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.settingsEnabled) _localSettingsOpen = false;
  }

  void _reveal() {
    _hideTimer?.cancel();
    if (!_visible) setState(() => _visible = true);
    _hideTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Vídeo. Toque para mostrar os controlos',
    onTap: _reveal,
    child: Listener(
      key: const Key('visualPlayerMediaSurface'),
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _reveal(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: Colors.black, child: widget.media),
          if (_visible && !_settingsOpen && !widget.transportInDeck)
            ListenableBuilder(
              listenable: widget.model,
              builder: (context, _) {
                final model = widget.model;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _reveal,
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: .38),
                    child: Stack(
                      children: [
                        Center(
                          child: _Transport(
                            model: model,
                            enabled: model.loaded && !model.busy,
                            pauseEnabled:
                                model.loaded && model.playing && !model.muted,
                            fullscreen: false,
                          ),
                        ),
                        if (widget.onFullscreen != null)
                          Align(
                            alignment: Alignment.topRight,
                            child: IconButton(
                              key: const Key('visualPlayerFullscreen'),
                              tooltip: 'Tela cheia',
                              onPressed: model.loaded
                                  ? widget.onFullscreen
                                  : null,
                              icon: const Icon(
                                Icons.fullscreen,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        if (model.loaded)
                          Positioned(
                            left: 4,
                            right: widget.settingsEnabled ? 56 : 4,
                            bottom: 0,
                            child: _SeekControl(
                              controlKey: const Key('visualPlayerSeek'),
                              model: model,
                              enabled: !model.busy,
                              showTimes: false,
                              onDragStart: () => _hideTimer?.cancel(),
                              onDragEnd: _reveal,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          if (widget.transportInDeck && widget.onFullscreen != null)
            Positioned(
              right: 4,
              top: 4,
              child: IconButton.filledTonal(
                key: const Key('visualPlayerFullscreen'),
                tooltip: 'Tela cheia',
                onPressed: widget.model.loaded ? widget.onFullscreen : null,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black.withValues(alpha: .72),
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.fullscreen),
              ),
            ),
          if (widget.settingsEnabled && !_settingsOpen)
            Positioned(
              right: 4,
              bottom: 4,
              child: IconButton.filled(
                key: const Key('visualPlayerSettings'),
                tooltip: 'Ajustar tom, velocidade e loop no vídeo',
                onPressed: () => _setSettingsOpen(true),
                icon: const Icon(Icons.settings, color: studioCyan),
              ),
            ),
          if (widget.settingsEnabled && _settingsOpen)
            Positioned.fill(
              child: _VideoSettings(
                model: widget.model,
                onClose: () => _setSettingsOpen(false),
              ),
            ),
          if (widget.onPinToggle != null && !_settingsOpen)
            Positioned(
              left: 4,
              top: 4,
              child: IconButton.filledTonal(
                key: const Key('visualPlayerPinVideo'),
                tooltip: widget.videoPinned
                    ? 'Soltar vídeo da tela'
                    : 'Fixar vídeo durante a rolagem',
                onPressed: widget.onPinToggle,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black.withValues(alpha: .72),
                  foregroundColor: widget.videoPinned
                      ? studioCyan
                      : Colors.white,
                ),
                icon: Icon(
                  widget.videoPinned ? Icons.push_pin : Icons.push_pin_outlined,
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _PlayerControlCards extends StatefulWidget {
  const _PlayerControlCards({required this.model, required this.onTool});
  final PlayerPanelModel model;
  final ValueChanged<String> onTool;
  @override
  State<_PlayerControlCards> createState() => _PlayerControlCardsState();
}

class _PlayerControlCardsState extends State<_PlayerControlCards> {
  bool _studyExpanded = false;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.model,
    builder: (context, _) {
      final model = widget.model;
      final ready = model.loaded && !model.busy;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                      onPressed: ready && model.canPitch && model.pitch > -12
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
                        onPressed: ready && model.canLoop ? model.markA : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _MarkerButton(
                        controlKey: const Key('visualPlayerMarkB'),
                        label: 'PONTO B',
                        value: model.markerB,
                        onPressed: ready && model.canLoop ? model.markB : null,
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
          _Card(
            padding: EdgeInsets.zero,
            child: Column(
              children: <Widget>[
                InkWell(
                  key: const Key('visualPlayerStudyTools'),
                  borderRadius: BorderRadius.circular(15),
                  onTap: () => setState(() => _studyExpanded = !_studyExpanded),
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
      );
    },
  );
}

/// The main player uses the fullscreen control language in a scrollable deck.
/// The detailed cards remain available without taking space by default.
class _FullscreenStyleControls extends StatefulWidget {
  const _FullscreenStyleControls({required this.model, required this.onTool});

  final PlayerPanelModel model;
  final ValueChanged<String> onTool;

  @override
  State<_FullscreenStyleControls> createState() =>
      _FullscreenStyleControlsState();
}

class _FullscreenStyleControlsState extends State<_FullscreenStyleControls> {
  bool _toolsOpen = false;
  bool _detailsOpen = false;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.model,
    builder: (context, _) {
      final model = widget.model;
      final ready = model.loaded && !model.busy;
      return DecoratedBox(
        decoration: const BoxDecoration(
          color: Color(0xFF171717),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'CONTROLOS',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: studioMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                ),
              ),
              _SeekControl(
                controlKey: const Key('visualPlayerMainSeek'),
                model: model,
                enabled: ready,
                compact: true,
              ),
              _Transport(
                model: model,
                enabled: ready,
                pauseEnabled: model.loaded && model.playing && !model.muted,
                fullscreen: false,
              ),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF122B35),
                  border: Border.all(color: studioCyan, width: 1.5),
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 12),
                child: Column(
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text(
                          'TOM · SEMITONS',
                          style: TextStyle(
                            color: studioCyan,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        TextButton(
                          key: const Key('visualPlayerPitchReset'),
                          onPressed:
                              ready &&
                                  (model.canPitch || model.pitchPending) &&
                                  (model.pitch != 0 || model.pitchPending)
                              ? () => model.changePitch(0)
                              : null,
                          child: const Text('Tom original'),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        IconButton.filledTonal(
                          key: const Key('visualPlayerPitchDown'),
                          tooltip: 'Diminuir tom',
                          onPressed:
                              ready && model.canPitch && model.pitch > -12
                              ? () => model.changePitch(
                                  (model.pitch - 1).clamp(-12, 12),
                                )
                              : null,
                          icon: const Icon(Icons.remove, size: 28),
                        ),
                        Expanded(
                          child: Text(
                            _pitchLabel(model.pitch),
                            key: const Key('visualPlayerPitchValue'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 36,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton.filledTonal(
                          key: const Key('visualPlayerPitchUp'),
                          tooltip: 'Aumentar tom',
                          onPressed: ready && model.canPitch && model.pitch < 12
                              ? () => model.changePitch(
                                  (model.pitch + 1).clamp(-12, 12),
                                )
                              : null,
                          icon: const Icon(Icons.add, size: 28),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (model.loaded && !model.canPitch && !model.pitchPending)
                const Text(
                  'A alteração de tom não está disponível nesta fonte.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: studioMuted, fontSize: 12),
                ),
              const Divider(color: Colors.white12),
              _SpeedControl(model: model, enabled: ready),
              const Divider(color: Colors.white12),
              Row(
                children: [
                  const Icon(Icons.repeat, color: studioMuted, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Repetir A–B')),
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
              Row(
                children: [
                  Expanded(
                    child: _MarkerButton(
                      controlKey: const Key('visualPlayerMarkA'),
                      label: 'PONTO A',
                      value: model.markerA,
                      onPressed: ready && model.canLoop ? model.markA : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MarkerButton(
                      controlKey: const Key('visualPlayerMarkB'),
                      label: 'PONTO B',
                      value: model.markerB,
                      onPressed: ready && model.canLoop ? model.markB : null,
                    ),
                  ),
                ],
              ),
              if (model.markerA != null || model.markerB != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    key: const Key('visualPlayerClearLoop'),
                    onPressed: ready && model.canLoop ? model.clearLoop : null,
                    icon: const Icon(Icons.clear, size: 16),
                    label: const Text('Limpar A–B'),
                  ),
                ),
              if (model.loaded && !model.canLoop)
                const Text(
                  'A repetição A–B não está disponível nesta fonte.',
                  style: TextStyle(color: studioMuted, fontSize: 12),
                ),
              const SizedBox(height: 8),
              TextButton.icon(
                key: const Key('visualPlayerStudyTools'),
                onPressed: () => setState(() => _toolsOpen = !_toolsOpen),
                icon: Icon(_toolsOpen ? Icons.expand_less : Icons.expand_more),
                label: const Text('Ferramentas de Estudo'),
              ),
              if (_toolsOpen)
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
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
              TextButton.icon(
                key: const Key('visualPlayerAdvancedTools'),
                onPressed: () => widget.onTool('advanced'),
                icon: const Icon(Icons.tune, size: 18),
                label: const Text('Ferramentas Áudio Avançado'),
              ),
              TextButton(
                key: const Key('visualPlayerDetailedControls'),
                onPressed: () => setState(() => _detailsOpen = !_detailsOpen),
                child: Text(
                  _detailsOpen
                      ? 'Ocultar controlos detalhados'
                      : 'Controlos detalhados',
                ),
              ),
              if (_detailsOpen)
                _PlayerControlCards(model: model, onTool: widget.onTool),
            ],
          ),
        ),
      );
    },
  );
}

/// Compact, scrollable adjustments clipped to the existing video box.
class _VideoSettings extends StatelessWidget {
  const _VideoSettings({required this.model, required this.onClose});
  final PlayerPanelModel model;
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context) => ColoredBox(
    key: const Key('visualPlayerSettingsSheet'),
    color: studioBg.withValues(alpha: .96),
    child: Column(
      children: [
        Row(
          children: [
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Ajustes do vídeo',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              key: const Key('visualPlayerSettingsClose'),
              tooltip: 'Fechar ajustes',
              onPressed: onClose,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        Expanded(
          child: SingleChildScrollView(
            key: const Key('visualPlayerSettingsScroll'),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: ListenableBuilder(
              listenable: model,
              builder: (context, _) {
                final ready = model.loaded && !model.busy;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      children: [
                        const Text('Tom'),
                        IconButton(
                          key: const Key('visualPlayerPitchDown'),
                          tooltip: 'Diminuir tom',
                          onPressed:
                              ready && model.canPitch && model.pitch > -12
                              ? () => model.changePitch(model.pitch - 1)
                              : null,
                          icon: const Icon(Icons.remove),
                        ),
                        Text(
                          _pitchLabel(model.pitch),
                          key: const Key('visualPlayerPitchValue'),
                        ),
                        IconButton(
                          key: const Key('visualPlayerPitchUp'),
                          tooltip: 'Aumentar tom',
                          onPressed: ready && model.canPitch && model.pitch < 12
                              ? () => model.changePitch(model.pitch + 1)
                              : null,
                          icon: const Icon(Icons.add),
                        ),
                        TextButton(
                          key: const Key('visualPlayerPitchReset'),
                          onPressed:
                              ready && (model.canPitch || model.pitchPending)
                              ? () => model.changePitch(0)
                              : null,
                          child: const Text('Original'),
                        ),
                      ],
                    ),
                    if (model.loaded && !model.canPitch && !model.pitchPending)
                      const Text(
                        'Tom de áudio indisponível nesta fonte.',
                        style: TextStyle(color: studioMuted, fontSize: 12),
                      ),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      children: [
                        const Text('Velocidade'),
                        IconButton(
                          key: const Key('visualPlayerSpeedDown'),
                          tooltip: 'Diminuir velocidade',
                          onPressed: ready && model.canSpeed && model.speed > .5
                              ? () => model.changeSpeed(
                                  (model.speed - .05).clamp(.5, 1.5),
                                )
                              : null,
                          icon: const Icon(Icons.remove),
                        ),
                        Text('${model.speed.toStringAsFixed(2)}×'),
                        IconButton(
                          key: const Key('visualPlayerSpeedUp'),
                          tooltip: 'Aumentar velocidade',
                          onPressed:
                              ready && model.canSpeed && model.speed < 1.5
                              ? () => model.changeSpeed(
                                  (model.speed + .05).clamp(.5, 1.5),
                                )
                              : null,
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 4,
                      children: [
                        TextButton(
                          key: const Key('visualPlayerMarkA'),
                          onPressed: ready && model.canLoop
                              ? model.markA
                              : null,
                          child: Text(
                            'A: ${model.markerA == null ? "Marcar" : _time(model.markerA!)}',
                          ),
                        ),
                        TextButton(
                          key: const Key('visualPlayerMarkB'),
                          onPressed: ready && model.canLoop
                              ? model.markB
                              : null,
                          child: Text(
                            'B: ${model.markerB == null ? "Marcar" : _time(model.markerB!)}',
                          ),
                        ),
                        const Text('Loop'),
                        Switch(
                          key: const Key('visualPlayerLoopToggle'),
                          value: model.loopEnabled,
                          onChanged:
                              ready &&
                                  model.canLoop &&
                                  model.markerA != null &&
                                  model.markerB != null
                              ? (_) => model.toggleLoop()
                              : null,
                        ),
                        TextButton(
                          key: const Key('visualPlayerClearLoop'),
                          onPressed: ready && model.canLoop
                              ? model.clearLoop
                              : null,
                          child: const Text('Limpar'),
                        ),
                      ],
                    ),
                    _SeekControl(
                      controlKey: const Key('visualPlayerSeek'),
                      model: model,
                      enabled: ready,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    ),
  );
}

/// Ajustes compartilhados do player unificado. O transporte do YouTube fica
/// exclusivamente no próprio vídeo; ficheiros locais mantêm transporte aqui.
class UnifiedPlayerAdjustments extends StatelessWidget {
  const UnifiedPlayerAdjustments({
    required this.model,
    required this.youtubeNativeTransport,
    this.appearanceMode = StudioAppearanceMode.dark,
    this.showPracticeControls = true,
    this.compactBottom = false,
    super.key,
  });

  final PlayerPanelModel model;
  final bool youtubeNativeTransport;
  final StudioAppearanceMode appearanceMode;
  final bool showPracticeControls;
  final bool compactBottom;

  String _detectedKeyLabel() {
    if (!model.loaded) return 'Tom: escolha uma música';
    final root = model.detectedKeyRoot;
    if (root != null &&
        (model.detectedKeyMode == 'major' ||
            model.detectedKeyMode == 'minor')) {
      const names = <String>[
        'C',
        'C♯',
        'D',
        'E♭',
        'E',
        'F',
        'F♯',
        'G',
        'A♭',
        'A',
        'B♭',
        'B',
      ];
      final transposed = (root + model.pitch.round()) % 12;
      final mode = model.detectedKeyMode == 'major' ? 'maior' : 'menor';
      return 'Tom estimado: ${names[transposed]} $mode';
    }
    return switch (model.keyDetectionStatus) {
      'analyzing' => 'Tom: a analisar áudio…',
      'unavailable' => 'Tom: indisponível nesta fonte',
      _ => 'Tom: a aguardar reprodução',
    };
  }

  Widget _card({Key? key, required Widget child, EdgeInsets? padding}) =>
      Container(
        key: key,
        margin: const EdgeInsets.only(bottom: 8),
        padding: padding ?? const EdgeInsets.all(10),
        decoration: studioPanelDecoration(mode: appearanceMode),
        child: child,
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) {
      final ready = model.loaded && !model.busy;
      return Padding(
        padding: EdgeInsets.fromLTRB(16, 4, 16, compactBottom ? 0 : 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!youtubeNativeTransport) ...[
              _SeekControl(
                controlKey: const Key('unifiedLocalSeek'),
                model: model,
                enabled: ready,
                compact: true,
              ),
              _Transport(
                model: model,
                enabled: ready,
                pauseEnabled: model.loaded && model.playing && !model.muted,
                fullscreen: false,
              ),
            ],
            _card(
              key: const Key('unifiedPitchCard'),
              padding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.music_note,
                        color: appearanceMode == StudioAppearanceMode.light
                            ? const Color(0xFF182636)
                            : Colors.white,
                        size: 14,
                      ),
                      const SizedBox(width: 5),
                      const Expanded(
                        child: Text(
                          'MODULAÇÃO CROMÁTICA',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .7,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      IconButton.filledTonal(
                        key: const Key('unifiedPitchDown'),
                        tooltip: 'Diminuir tom',
                        style: IconButton.styleFrom(
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          minimumSize: const Size(32, 32),
                          maximumSize: const Size(32, 32),
                        ),
                        constraints: const BoxConstraints.tightFor(
                          width: 32,
                          height: 32,
                        ),
                        padding: EdgeInsets.zero,
                        iconSize: 17,
                        onPressed: ready && model.canPitch && model.pitch > -12
                            ? () => model.changePitch(
                                (model.pitch - 1).clamp(-12, 12),
                              )
                            : null,
                        icon: const Icon(Icons.remove),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              '${_pitchLabel(model.pitch)} semitons',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              _detectedKeyLabel(),
                              key: const Key('unifiedDetectedKey'),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 9,
                                color: studioMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton.filledTonal(
                        key: const Key('unifiedPitchUp'),
                        tooltip: 'Aumentar tom',
                        style: IconButton.styleFrom(
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          minimumSize: const Size(32, 32),
                          maximumSize: const Size(32, 32),
                        ),
                        constraints: const BoxConstraints.tightFor(
                          width: 32,
                          height: 32,
                        ),
                        padding: EdgeInsets.zero,
                        iconSize: 17,
                        onPressed: ready && model.canPitch && model.pitch < 12
                            ? () => model.changePitch(
                                (model.pitch + 1).clamp(-12, 12),
                              )
                            : null,
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (model.loaded && !model.canPitch)
              const Text(
                'Tom indisponível nesta fonte.',
                style: TextStyle(color: studioMuted),
              ),
            if (showPracticeControls)
              _card(
                padding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
                child: _SpeedControl(
                  model: model,
                  enabled: ready,
                  compact: true,
                  appearanceMode: appearanceMode,
                  minSpeed: youtubeNativeTransport ? .25 : .5,
                  maxSpeed: 2,
                ),
              ),
            if (showPracticeControls)
              _card(
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.repeat, color: studioCyan, size: 16),
                        const SizedBox(width: 5),
                        const Expanded(
                          child: Text(
                            'TRECHO DE ENSAIO (A–B)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'Repetir',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(
                          width: 48,
                          height: 36,
                          child: Transform.scale(
                            scale: .7,
                            child: Switch(
                              key: const Key('unifiedLoopToggle'),
                              value: model.loopEnabled,
                              onChanged:
                                  ready &&
                                      model.canLoop &&
                                      model.markerA != null &&
                                      model.markerB != null
                                  ? (_) => model.toggleLoop()
                                  : null,
                            ),
                          ),
                        ),
                        IconButton(
                          key: const Key('unifiedClearLoop'),
                          tooltip: 'Limpar trecho',
                          style: IconButton.styleFrom(
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            minimumSize: const Size(32, 32),
                          ),
                          constraints: const BoxConstraints.tightFor(
                            width: 32,
                            height: 32,
                          ),
                          padding: EdgeInsets.zero,
                          onPressed:
                              ready &&
                                  model.canLoop &&
                                  (model.markerA != null ||
                                      model.markerB != null)
                              ? model.clearLoop
                              : null,
                          icon: const Icon(Icons.close, size: 16),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _MarkerButton(
                            controlKey: const Key('unifiedMarkA'),
                            label: 'INÍCIO',
                            value: model.markerA,
                            onPressed: ready && model.canLoop
                                ? model.markA
                                : null,
                            compact: true,
                            appearanceMode: appearanceMode,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _MarkerButton(
                            controlKey: const Key('unifiedMarkB'),
                            label: 'FIM',
                            value: model.markerB,
                            onPressed: ready && model.canLoop
                                ? model.markB
                                : null,
                            compact: true,
                            appearanceMode: appearanceMode,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
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
    this.mainMode = false,
    this.showHeader = true,
    this.controlsOpen,
    this.onPinToggle,
    this.videoPinned = false,
    this.onOpenFile,
    this.onChordToggle,
    this.onSearch,
    this.chordActive = false,
    this.youtubeNativeTransport = false,
    this.onNativeMediaTouch,
    super.key,
  });

  final PlayerPanelModel model;
  final Widget media;
  final VoidCallback onExit;
  final ValueChanged<String>? onTool;
  final bool mainMode;
  final bool showHeader;
  final bool? controlsOpen;
  final VoidCallback? onPinToggle;
  final bool videoPinned;
  final VoidCallback? onOpenFile;
  final VoidCallback? onChordToggle;
  final VoidCallback? onSearch;
  final bool chordActive;
  final bool youtubeNativeTransport;
  final VoidCallback? onNativeMediaTouch;

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
    final bool controlsVisible = widget.controlsOpen ?? _visible;
    final bool headerVisible = widget.mainMode || _visible || _locked;
    final bool compactMarkers =
        widget.mainMode && MediaQuery.textScalerOf(context).scale(1) <= 1.3;
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
                    child: Listener(
                      onPointerDown: (_) => widget.onNativeMediaTouch?.call(),
                      child: SizedBox.expand(child: widget.media),
                    ),
                  ),
                  if (widget.showHeader)
                    Align(
                      alignment: Alignment.topCenter,
                      child: IgnorePointer(
                        ignoring: !headerVisible,
                        child: AnimatedOpacity(
                          opacity: headerVisible ? 1 : 0,
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
                                if (widget.mainMode &&
                                    widget.onPinToggle != null)
                                  IconButton(
                                    key: const Key('visualPlayerPinVideo'),
                                    tooltip: widget.videoPinned
                                        ? 'Soltar vídeo da tela'
                                        : 'Fixar vídeo durante a rolagem',
                                    onPressed: _locked
                                        ? null
                                        : widget.onPinToggle,
                                    icon: Icon(
                                      widget.videoPinned
                                          ? Icons.push_pin
                                          : Icons.push_pin_outlined,
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
                  if (!widget.showHeader && widget.onPinToggle != null)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: IconButton.filledTonal(
                        key: const Key('visualPlayerPinVideo'),
                        tooltip: widget.videoPinned
                            ? 'Soltar vídeo da tela'
                            : 'Fixar vídeo durante a rolagem',
                        onPressed: _locked ? null : widget.onPinToggle,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black.withValues(alpha: .72),
                          foregroundColor: widget.videoPinned
                              ? studioCyan
                              : Colors.white,
                        ),
                        icon: Icon(
                          widget.videoPinned
                              ? Icons.push_pin
                              : Icons.push_pin_outlined,
                        ),
                      ),
                    ),
                  if (widget.mainMode && controlsVisible)
                    const Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 68,
                      child: IgnorePointer(
                        child: ColoredBox(
                          key: Key('visualMainAdjustmentsBackdrop'),
                          color: Color(0xFF040F1C),
                        ),
                      ),
                    ),
                  if (!widget.mainMode || controlsVisible)
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: EdgeInsets.only(
                          bottom: widget.mainMode ? 68 : 0,
                        ),
                        child: IgnorePointer(
                          key: widget.mainMode
                              ? const Key('visualMainControlsOverlay')
                              : null,
                          ignoring: !controlsVisible || _locked,
                          child: AnimatedOpacity(
                            key: const Key('visualFullscreenOverlay'),
                            opacity: controlsVisible && !_locked ? 1 : 0,
                            duration: const Duration(milliseconds: 180),
                            child: ColoredBox(
                              color: widget.mainMode
                                  ? const Color(0xFF040F1C)
                                  : const Color(0xEC040F1C),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxHeight:
                                      constraints.maxHeight *
                                      (widget.mainMode &&
                                              widget.youtubeNativeTransport
                                          ? .47
                                          : widget.mainMode
                                          ? .5
                                          : .4),
                                ),
                                child: SingleChildScrollView(
                                  key: const Key(
                                    'visualFullscreenControlsScroll',
                                  ),
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
                                        if (model.message
                                            case final String message
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
                                        if (!widget.youtubeNativeTransport)
                                          _SeekControl(
                                            controlKey: const Key(
                                              'visualFullscreenSeek',
                                            ),
                                            model: model,
                                            enabled: ready,
                                            compact: compact || widget.mainMode,
                                          ),
                                        if (widget.youtubeNativeTransport)
                                          _YouTubePitchTransport(
                                            model: model,
                                            enabled: ready,
                                          )
                                        else ...[
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
                                          Center(
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: <Widget>[
                                                SizedBox(
                                                  width: 208,
                                                  child: Row(
                                                    children: <Widget>[
                                                      SizedBox(
                                                        width: 50,
                                                        child: IconButton(
                                                          key: const Key(
                                                            'visualFullscreenPitchDown',
                                                          ),
                                                          tooltip:
                                                              'Diminuir tom',
                                                          onPressed:
                                                              ready &&
                                                                  model
                                                                      .canPitch &&
                                                                  model.pitch >
                                                                      -12
                                                              ? () => model
                                                                    .changePitch(
                                                                      (model.pitch -
                                                                              1)
                                                                          .clamp(
                                                                            -12,
                                                                            12,
                                                                          ),
                                                                    )
                                                              : null,
                                                          icon: const Icon(
                                                            Icons.remove,
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 24),
                                                      SizedBox(
                                                        width: 60,
                                                        child: FittedBox(
                                                          fit: BoxFit.scaleDown,
                                                          child: Text(
                                                            '${_pitchLabel(model.pitch)} st',
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 24),
                                                      SizedBox(
                                                        width: 50,
                                                        child: IconButton(
                                                          key: const Key(
                                                            'visualFullscreenPitchUp',
                                                          ),
                                                          tooltip:
                                                              'Aumentar tom',
                                                          onPressed:
                                                              ready &&
                                                                  model
                                                                      .canPitch &&
                                                                  model.pitch <
                                                                      12
                                                              ? () => model
                                                                    .changePitch(
                                                                      (model.pitch +
                                                                              1)
                                                                          .clamp(
                                                                            -12,
                                                                            12,
                                                                          ),
                                                                    )
                                                              : null,
                                                          icon: const Icon(
                                                            Icons.add,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                        TextButton(
                                          key: const Key(
                                            'visualFullscreenPitchReset',
                                          ),
                                          style: widget.mainMode
                                              ? TextButton.styleFrom(
                                                  minimumSize: const Size(
                                                    0,
                                                    32,
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                      ),
                                                  tapTargetSize:
                                                      MaterialTapTargetSize
                                                          .shrinkWrap,
                                                )
                                              : null,
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
                                                      ((model.speed * 20)
                                                                      .round() -
                                                                  1)
                                                              .clamp(10, 30) /
                                                          20,
                                                    )
                                                  : null,
                                              icon: const Icon(
                                                Icons.fast_rewind,
                                              ),
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
                                                padding: const EdgeInsets.all(
                                                  12,
                                                ),
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
                                                      ((model.speed * 20)
                                                                      .round() +
                                                                  1)
                                                              .clamp(10, 30) /
                                                          20,
                                                    )
                                                  : null,
                                              icon: const Icon(
                                                Icons.fast_forward,
                                              ),
                                            ),
                                            TextButton(
                                              key: const Key(
                                                'visualFullscreenSpeedReset',
                                              ),
                                              style: widget.mainMode
                                                  ? TextButton.styleFrom(
                                                      minimumSize: const Size(
                                                        0,
                                                        32,
                                                      ),
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 8,
                                                          ),
                                                      tapTargetSize:
                                                          MaterialTapTargetSize
                                                              .shrinkWrap,
                                                    )
                                                  : null,
                                              onPressed:
                                                  ready &&
                                                      model.canSpeed &&
                                                      model.speed != 1
                                                  ? () => model.changeSpeed(1)
                                                  : null,
                                              child: const Text(
                                                '1,00× original',
                                              ),
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
                                        SizedBox(
                                          height: widget.mainMode ? 2 : 8,
                                        ),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: <Widget>[
                                            SizedBox(
                                              width: compactMarkers
                                                  ? ((constraints.maxWidth -
                                                                32) /
                                                            3)
                                                        .clamp(96.0, 220.0)
                                                  : (constraints.maxWidth -
                                                            40) /
                                                        2,
                                              child: _MarkerButton(
                                                controlKey: const Key(
                                                  'visualFullscreenMarkA',
                                                ),
                                                label: 'PONTO A',
                                                value: model.markerA,
                                                compact: compactMarkers,
                                                onPressed:
                                                    ready && model.canLoop
                                                    ? model.markA
                                                    : null,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            SizedBox(
                                              width: compactMarkers
                                                  ? ((constraints.maxWidth -
                                                                32) /
                                                            3)
                                                        .clamp(96.0, 220.0)
                                                  : (constraints.maxWidth -
                                                            40) /
                                                        2,
                                              child: _MarkerButton(
                                                controlKey: const Key(
                                                  'visualFullscreenMarkB',
                                                ),
                                                label: 'PONTO B',
                                                value: model.markerB,
                                                compact: compactMarkers,
                                                onPressed:
                                                    ready && model.canLoop
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
                                        if (widget.mainMode &&
                                            widget.onOpenFile != null &&
                                            widget.onChordToggle != null &&
                                            widget.onSearch != null) ...[
                                          const Divider(color: Colors.white24),
                                          Row(
                                            children: [
                                              for (final action
                                                  in <
                                                    ({
                                                      String key,
                                                      String label,
                                                      IconData icon,
                                                      VoidCallback? onPressed,
                                                    })
                                                  >[
                                                    (
                                                      key: 'visualPlayerEmptyFile',
                                                      label: 'Abrir ficheiro',
                                                      icon: Icons.folder_open,
                                                      onPressed: model.busy
                                                          ? null
                                                          : widget.onOpenFile,
                                                    ),
                                                    (
                                                      key: 'visualPlayerChordPicker',
                                                      label: 'Cifra',
                                                      icon: Icons
                                                          .library_music_outlined,
                                                      onPressed:
                                                          widget.onChordToggle,
                                                    ),
                                                    (
                                                      key: 'visualPlayerEmptySearch',
                                                      label: 'YouTube',
                                                      icon: Icons.search,
                                                      onPressed: model.busy
                                                          ? null
                                                          : widget.onSearch,
                                                    ),
                                                  ])
                                                Expanded(
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 3,
                                                        ),
                                                    child: OutlinedButton.icon(
                                                      key: Key(action.key),
                                                      onPressed:
                                                          action.onPressed,
                                                      style: OutlinedButton.styleFrom(
                                                        foregroundColor:
                                                            action.key ==
                                                                    'visualPlayerChordPicker' &&
                                                                widget
                                                                    .chordActive
                                                            ? studioCyan
                                                            : Colors.white,
                                                        backgroundColor:
                                                            const Color(
                                                              0xB3143544,
                                                            ),
                                                        side: BorderSide(
                                                          color:
                                                              action.key ==
                                                                      'visualPlayerChordPicker' &&
                                                                  widget
                                                                      .chordActive
                                                              ? studioCyan
                                                              : const Color(
                                                                  0xFF607080,
                                                                ),
                                                        ),
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 3,
                                                            ),
                                                        minimumSize: const Size(
                                                          0,
                                                          44,
                                                        ),
                                                      ),
                                                      icon: Icon(
                                                        action.icon,
                                                        size: 16,
                                                      ),
                                                      label: FittedBox(
                                                        fit: BoxFit.scaleDown,
                                                        child: Text(
                                                          action.label,
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 12,
                                                              ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                        ],
                                        TextButton.icon(
                                          key: const Key(
                                            'visualFullscreenLockSurface',
                                          ),
                                          onPressed: _locked
                                              ? null
                                              : () => _setLocked(true),
                                          icon: const Icon(
                                            Icons.shield_outlined,
                                          ),
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
                    ),
                  if (!_visible && !_locked && !widget.mainMode)
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
    this.showTimes = true,
    this.onDragStart,
    this.onDragEnd,
  });

  final Key controlKey;
  final PlayerPanelModel model;
  final bool enabled;
  final bool compact;
  final bool showTimes;
  final VoidCallback? onDragStart, onDragEnd;

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
        SizedBox(
          height: widget.compact ? 34 : 48,
          child: Slider(
            key: widget.controlKey,
            min: 0,
            max: duration > 0 ? duration : 1,
            value: position,
            activeColor: studioCyan,
            inactiveColor: const Color(0xFF414145),
            semanticFormatterCallback: (double value) =>
                _time(Duration(milliseconds: value.round())),
            onChangeStart: seekable ? (_) => widget.onDragStart?.call() : null,
            onChanged: seekable
                ? (double value) => setState(() => _dragMilliseconds = value)
                : null,
            onChangeEnd: seekable
                ? (double value) {
                    setState(() => _dragMilliseconds = null);
                    widget.model.seek(Duration(milliseconds: value.round()));
                    widget.onDragEnd?.call();
                  }
                : null,
          ),
        ),
        if (widget.showTimes)
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
  const _SpeedControl({
    required this.model,
    required this.enabled,
    this.compact = false,
    this.appearanceMode = StudioAppearanceMode.dark,
    this.minSpeed = .5,
    this.maxSpeed = 1.5,
  });
  final PlayerPanelModel model;
  final bool enabled;
  final bool compact;
  final StudioAppearanceMode appearanceMode;
  final double minSpeed, maxSpeed;

  @override
  State<_SpeedControl> createState() => _SpeedControlState();
}

class _SpeedControlState extends State<_SpeedControl> {
  double? _dragSpeed;
  double? _pendingSpeed;
  Timer? _pendingSpeedTimeout;

  @override
  void dispose() {
    _pendingSpeedTimeout?.cancel();
    super.dispose();
  }

  double _positionForSpeed(double speed) => speed <= 1
      ? (speed - widget.minSpeed) / (1 - widget.minSpeed) * .5
      : .5 + (speed - 1) / (widget.maxSpeed - 1) * .5;

  double _speedForPosition(double position) {
    // A small resting zone makes returning to the original speed feel precise.
    if ((position - .5).abs() <= .035) return 1;
    return position < .5
        ? widget.minSpeed + (1 - widget.minSpeed) * position * 2
        : 1 + (widget.maxSpeed - 1) * (position - .5) * 2;
  }

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.enabled && widget.model.canSpeed;
    if (widget.compact) {
      if (_pendingSpeed != null &&
          (widget.model.speed - _pendingSpeed!).abs() < .005) {
        _pendingSpeed = null;
        _pendingSpeedTimeout?.cancel();
      }
      final speed = (_dragSpeed ?? _pendingSpeed ?? widget.model.speed).clamp(
        widget.minSpeed,
        widget.maxSpeed,
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.speed, color: studioCyan, size: 15),
              const SizedBox(width: 5),
              const Expanded(
                child: Text(
                  'VELOCIDADE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .6,
                  ),
                ),
              ),
              Text(
                '${speed.toStringAsFixed(2)}×',
                key: const Key('unifiedSpeedValue'),
                style: TextStyle(
                  color: widget.appearanceMode == StudioAppearanceMode.light
                      ? const Color(0xFF193244)
                      : studioCyan,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: SizedBox(
              height: 24,
              child: Slider(
                key: const Key('unifiedSpeedSlider'),
                value: _positionForSpeed(speed),
                min: 0,
                max: 1,
                activeColor: studioCyan,
                inactiveColor: const Color(0xFF39393E),
                semanticFormatterCallback: (position) =>
                    '${_speedForPosition(position).toStringAsFixed(2)} vezes',
                onChanged: enabled
                    ? (position) {
                        _pendingSpeedTimeout?.cancel();
                        setState(() {
                          _pendingSpeed = null;
                          _dragSpeed = _speedForPosition(position);
                        });
                      }
                    : null,
                onChangeEnd: enabled
                    ? (position) {
                        final target = _speedForPosition(position);
                        setState(() {
                          _dragSpeed = null;
                          _pendingSpeed = target;
                        });
                        _pendingSpeedTimeout?.cancel();
                        _pendingSpeedTimeout = Timer(
                          const Duration(seconds: 5),
                          () {
                            if (mounted) setState(() => _pendingSpeed = null);
                          },
                        );
                        widget.model.changeSpeed(target);
                      }
                    : null,
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${widget.minSpeed.toStringAsFixed(2)}×',
                style: const TextStyle(color: studioMuted, fontSize: 9),
              ),
              const Text(
                '1,00×',
                style: TextStyle(color: studioMuted, fontSize: 9),
              ),
              Text(
                '${widget.maxSpeed.toStringAsFixed(2)}×',
                style: const TextStyle(color: studioMuted, fontSize: 9),
              ),
            ],
          ),
          if (widget.model.loaded && !widget.model.canSpeed)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Velocidade indisponível nesta fonte.',
                style: TextStyle(color: studioMuted, fontSize: 10),
              ),
            ),
        ],
      );
    }
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
          inactiveColor: const Color(0xFF414145),
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
                        : const Color(0xFF444447),
                  ),
                  backgroundColor: const Color(0xFF2A2A2C),
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

class _YouTubePitchTransport extends StatelessWidget {
  const _YouTubePitchTransport({required this.model, required this.enabled});

  final PlayerPanelModel model;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: <Widget>[
      _RoundButton(
        controlKey: const Key('visualFullscreenPitchDown'),
        tooltip: 'Diminuir tom',
        icon: Icons.remove,
        onPressed: enabled && model.canPitch && model.pitch > -12
            ? () => model.changePitch((model.pitch - 1).clamp(-12, 12))
            : null,
      ),
      const SizedBox(width: 24),
      Semantics(
        key: const Key('visualFullscreenPitchValue'),
        label: 'Tom ${_pitchLabel(model.pitch)} semitons',
        child: Container(
          width: 60,
          height: 60,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: studioCyan,
            shape: BoxShape.circle,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                _pitchLabel(model.pitch),
                style: const TextStyle(
                  color: studioBg,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
              const Text(
                'st',
                style: TextStyle(
                  color: studioBg,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(width: 24),
      _RoundButton(
        controlKey: const Key('visualFullscreenPitchUp'),
        tooltip: 'Aumentar tom',
        icon: Icons.add,
        onPressed: enabled && model.canPitch && model.pitch < 12
            ? () => model.changePitch((model.pitch + 1).clamp(-12, 12))
            : null,
      ),
    ],
  );
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
      backgroundColor: primary ? studioCyan : const Color(0xFF2A2A2C),
      foregroundColor: primary ? studioBg : Colors.white,
      disabledBackgroundColor: const Color(0xFF202022),
      disabledForegroundColor: const Color(0xFF77777D),
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
    this.compact = false,
    this.appearanceMode = StudioAppearanceMode.dark,
  });
  final Key controlKey;
  final String label;
  final Duration? value;
  final VoidCallback? onPressed;
  final bool compact;
  final StudioAppearanceMode appearanceMode;

  @override
  Widget build(BuildContext context) {
    final light = appearanceMode == StudioAppearanceMode.light;
    return OutlinedButton(
      key: controlKey,
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: light
            ? const Color(0xFFE8EEF4)
            : const Color(0xFF232326),
        foregroundColor: light ? const Color(0xFF193244) : Colors.white,
        disabledForegroundColor: light ? const Color(0xFF526577) : studioMuted,
        fixedSize: compact ? const Size.fromHeight(36) : null,
        minimumSize: compact ? const Size(0, 36) : null,
        tapTargetSize: compact ? MaterialTapTargetSize.shrinkWrap : null,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 8,
          vertical: compact ? 2 : 12,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Column(
        children: <Widget>[
          Text(
            label,
            style: TextStyle(
              fontSize: compact ? 9 : 10,
              color: light ? const Color(0xFF526577) : studioMuted,
            ),
          ),
          SizedBox(height: compact ? 0 : 4),
          Text(
            value == null ? 'Marcar' : _time(value!),
            style: compact ? const TextStyle(fontSize: 12) : null,
          ),
        ],
      ),
    );
  }
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
