import 'package:flutter/material.dart';

import 'player_panel_model.dart';
import 'player_presets.dart';
import 'studio_native_pages.dart';

/// Stage is a presentation of the existing player, never a second output.
class StagePanel extends StatefulWidget {
  const StagePanel({
    super.key,
    required this.model,
    required this.store,
    required this.sourceKey,
    required this.onApply,
    required this.onCollections,
    required this.onAdd,
    required this.onTool,
    this.revision = 0,
    this.selectedPresetId,
  });
  final PlayerPanelModel model;
  final PlayerPresetStore store;
  final String sourceKey;
  final Future<bool> Function(PlayerPreset) onApply;
  final VoidCallback onCollections, onAdd;
  final ValueChanged<String> onTool;
  final int revision;
  // Owned by the home/controller so two presets of the same media stay
  // distinguishable after this panel is unmounted while changing tabs.
  final String? selectedPresetId;

  @override
  State<StagePanel> createState() => _StagePanelState();
}

class _StagePanelState extends State<StagePanel> {
  List<PlayerPreset> _entries = [];
  String? _selectedId, _error;
  bool _locked = false, _loading = true, _applying = false;
  int _readRevision = 0;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.selectedPresetId;
    _read();
  }

  @override
  void didUpdateWidget(StagePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedPresetId != widget.selectedPresetId) {
      _selectedId = widget.selectedPresetId;
    }
    if (oldWidget.revision != widget.revision ||
        oldWidget.store != widget.store) {
      _read();
    }
  }

  Future<void> _read() async {
    final revision = ++_readRevision;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await widget.store.list(setlist: true);
      if (mounted && revision == _readRevision) {
        setState(() {
          _entries = entries;
          _loading = false;
          _error = null;
        });
      }
    } on Object {
      if (mounted && revision == _readRevision) {
        setState(() {
          _loading = false;
          _error = 'Não foi possível ler a setlist.';
        });
      }
    }
  }

  String _key(PlayerPreset p) =>
      '${p.youtube ? 'youtube' : 'local'}:${p.locator}';
  int get _index {
    final selected = _entries.indexWhere(
      (p) => p.id == _selectedId && _key(p) == widget.sourceKey,
    );
    return selected >= 0
        ? selected
        : _entries.indexWhere((p) => _key(p) == widget.sourceKey);
  }

  Future<void> _apply(int index) async {
    if (_locked ||
        _loading ||
        _applying ||
        index < 0 ||
        index >= _entries.length) {
      return;
    }
    final preset = _entries[index];
    setState(() {
      _applying = true;
      _error = null;
    });
    try {
      final applied = await widget.onApply(preset);
      if (mounted) {
        setState(() {
          if (applied) {
            _selectedId = preset.id;
          } else {
            _error = 'Não foi possível preparar esta música. Verifique a fonte e tente novamente.';
          }
        });
      }
    } on Object {
      if (mounted) {
        setState(() => _error = 'Não foi possível preparar esta música.');
      }
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.model,
    builder: (context, _) {
      final m = widget.model;
      final ready = m.loaded && !m.busy && !_loading && !_applying && !_locked;
      final index = _index;
      return SingleChildScrollView(
        key: const Key('visualScrollstage'),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'MODO PALCO',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('visualStageLock'),
                  tooltip: _locked
                      ? 'Mantenha pressionado para desbloquear'
                      : 'Bloquear controles do palco',
                  onPressed: () {
                    if (!_locked) setState(() => _locked = true);
                  },
                  onLongPress: _locked
                      ? () => setState(() => _locked = false)
                      : null,
                  icon: Icon(
                    _locked ? Icons.lock : Icons.lock_open,
                    color: studioCyan,
                  ),
                ),
              ],
            ),
            if (_locked)
              const Text(
                'Controles bloqueados · mantenha o cadeado pressionado.',
                style: TextStyle(color: studioCyan),
              ),
            if (_loading || _applying) const LinearProgressIndicator(),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.orangeAccent)),
            const SizedBox(height: 12),
            Text(
              index < 0
                  ? 'SETLIST · ${_entries.length} MÚSICAS'
                  : 'SETLIST · ${index + 1} DE ${_entries.length}',
              style: const TextStyle(color: studioCyan, fontSize: 12),
            ),
            const SizedBox(height: 16),
            Text(
              m.loaded ? m.title : 'Prepare a sua primeira música',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: studioCard,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: studioCyan.withValues(alpha: .25)),
              ),
              child: Column(
                children: [
                  const Text(
                    'TRANSPOSIÇÃO ATUAL',
                    style: TextStyle(color: studioMuted, letterSpacing: 1),
                  ),
                  Text(
                    '${m.pitch > 0 ? '+' : ''}${m.pitch.toStringAsFixed(0)} st',
                    style: const TextStyle(
                      fontSize: 54,
                      color: studioCyan,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    '${m.speed.toStringAsFixed(2)}× · ${m.loopEnabled ? 'A/B ativo' : 'Sem repetição'}',
                  ),
                  if (m.pitchPending)
                    const Text('A aplicar tom…')
                  else if (m.loaded && !m.canPitch)
                    const Text(
                      'Esta fonte não permite alterar o tom.',
                      textAlign: TextAlign.center,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('visualStagePitchDown'),
                    onPressed: ready && m.canPitch && m.pitch > -12
                        ? () => m.changePitch(m.pitch - 1)
                        : null,
                    icon: const Icon(Icons.remove_circle_outline),
                    label: const Text('−1 semitom'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('visualStagePitchUp'),
                    onPressed: ready && m.canPitch && m.pitch < 12
                        ? () => m.changePitch(m.pitch + 1)
                        : null,
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('+1 semitom'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('visualStageExecute'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(72),
              ),
              onPressed:
                  ready || (!_locked && m.loaded && m.playing && !m.muted)
                  ? m.playPause
                  : null,
              icon: Icon(
                m.muted
                    ? Icons.volume_up
                    : m.playing
                    ? Icons.pause
                    : Icons.play_arrow,
              ),
              label: Text(
                m.muted
                    ? 'ATIVAR SOM'
                    : m.playing
                    ? 'PAUSAR'
                    : 'EXECUTAR',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (m.message != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  m.message!,
                  style: const TextStyle(color: studioMuted),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const Key('visualStagePrevious'),
                    onPressed:
                        !_locked &&
                            !m.busy &&
                            !_loading &&
                            !_applying &&
                            index > 0
                        ? () => _apply(index - 1)
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        '← ANTERIOR\n${index > 0 ? _entries[index - 1].name : 'Início da setlist'}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    key: const Key('visualStageNext'),
                    onPressed:
                        !_locked &&
                            !m.busy &&
                            !_loading &&
                            !_applying &&
                            index + 1 < _entries.length
                        ? () => _apply(index + 1)
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'PRÓXIMA →\n${index + 1 < _entries.length ? _entries[index + 1].name : 'Fim da setlist'}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Trocar de música prepara os ajustes guardados e deixa a reprodução pausada.',
              style: TextStyle(fontSize: 12, color: studioMuted),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const Key('stageSetlist'),
                  onPressed: _locked || _applying ? null : widget.onCollections,
                  icon: const Icon(Icons.queue_music),
                  label: const Text('Editar setlist'),
                ),
                OutlinedButton.icon(
                  key: const Key('stageAdd'),
                  onPressed: ready ? widget.onAdd : null,
                  icon: const Icon(Icons.add),
                  label: const Text('Adicionar atual'),
                ),
                OutlinedButton.icon(
                  key: const Key('visualStageTuner'),
                  onPressed: _locked ? null : () => widget.onTool('tuner'),
                  icon: const Icon(Icons.tune),
                  label: const Text('Afinador'),
                ),
                OutlinedButton.icon(
                  key: const Key('stageMetronome'),
                  onPressed: _locked ? null : () => widget.onTool('metronome'),
                  icon: const Icon(Icons.timer_outlined),
                  label: const Text('Metrônomo'),
                ),
                if (_error != null)
                  TextButton(
                    onPressed: _locked ? null : _read,
                    child: const Text('Tentar novamente'),
                  ),
              ],
            ),
          ],
        ),
      );
    },
  );
}
