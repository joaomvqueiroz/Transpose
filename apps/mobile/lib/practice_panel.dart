import 'package:flutter/material.dart';

import 'player_panel_model.dart';
import 'practice_controller.dart';
import 'practice_progression_card.dart';
import 'studio_native_pages.dart';

/// Manual controls and optional confirmed-loop progression share one player.
class PracticePanel extends StatefulWidget {
  const PracticePanel({
    required this.model,
    required this.onOpenPlayer,
    required this.onSaveLoop,
    required this.onOpenLoops,
    required this.onMetronome,
    this.onEditLoop,
    this.practiceController,
    this.unifiedMode = false,
    super.key,
  });

  final PlayerPanelModel model;
  final PracticeController? practiceController;
  final bool unifiedMode;
  final VoidCallback onOpenPlayer;
  final VoidCallback onSaveLoop;
  final VoidCallback onOpenLoops;
  final VoidCallback onMetronome;
  final VoidCallback? onEditLoop;

  @override
  State<PracticePanel> createState() => _PracticePanelState();
}

class _PracticePanelState extends State<PracticePanel> {
  double? _speedPreview;
  double? _seekPreview;

  static String _time(Duration? value) {
    if (value == null) return '—';
    final int seconds = value.inSeconds;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  Widget _card({required List<Widget> children}) => Material(
    color: studioCard,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: Color(0xFF203246)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.model,
    builder: (_, _) {
      final model = widget.model;
      final ready = model.loaded && !model.busy;
      final hasRange =
          model.markerA != null &&
          model.markerB != null &&
          model.markerB! - model.markerA! >= const Duration(milliseconds: 250);
      final speed = _speedPreview ?? model.speed;
      final maxPosition = model.duration.inMilliseconds.toDouble();
      final position =
          (_seekPreview ?? model.position.inMilliseconds.toDouble()).clamp(
            0.0,
            maxPosition > 0 ? maxPosition : 1.0,
          );
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              'DOMINAR TRECHO',
              style: TextStyle(
                color: studioCyan,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              model.loaded ? model.title : 'Escolha uma música para praticar',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              widget.practiceController == null
                  ? 'Treino manual · marque o trecho, repita e aumente a velocidade quando estiver confortável.'
                  : 'Marque o trecho e escolha um plano progressivo ou ajuste a velocidade manualmente.',
              style: TextStyle(color: studioMuted),
            ),
            if (!model.loaded) ...<Widget>[
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const Key('practiceOpenPlayer'),
                onPressed: widget.onOpenPlayer,
                icon: const Icon(Icons.library_music_outlined),
                label: const Text('Escolher música no player'),
              ),
            ],
            if (model.busy) ...<Widget>[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (model.message case final String message
                when message.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Semantics(liveRegion: true, child: Text(message)),
            ],
            const SizedBox(height: 16),
            if (!widget.unifiedMode)
              _card(
                children: <Widget>[
                  const Text(
                    'TRECHO A–B',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${_time(model.markerA)} — ${_time(model.markerB)}',
                    key: const Key('practiceRange'),
                    style: const TextStyle(
                      fontSize: 25,
                      color: studioCyan,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Posição: ${_time(Duration(milliseconds: position.round()))} / ${_time(model.duration)}',
                    style: TextStyle(color: studioMuted),
                  ),
                  Slider(
                    key: const Key('practiceSeek'),
                    value: position,
                    max: maxPosition > 0 ? maxPosition : 1,
                    label: _time(Duration(milliseconds: position.round())),
                    onChanged: ready && model.canSeek
                        ? (v) => setState(() => _seekPreview = v)
                        : null,
                    onChangeEnd: ready && model.canSeek
                        ? (v) {
                            setState(() => _seekPreview = null);
                            model.seek(Duration(milliseconds: v.round()));
                          }
                        : null,
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      OutlinedButton(
                        key: const Key('visualPracticeMarkA'),
                        onPressed: ready && model.canLoop ? model.markA : null,
                        child: const Text('Marcar A'),
                      ),
                      OutlinedButton(
                        key: const Key('visualPracticeMarkB'),
                        onPressed: ready && model.canLoop ? model.markB : null,
                        child: const Text('Marcar B'),
                      ),
                      if (widget.onEditLoop != null)
                        OutlinedButton.icon(
                          key: const Key('practiceEditLoop'),
                          onPressed: ready && model.canLoop
                              ? widget.onEditLoop
                              : null,
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Editar tempos'),
                        ),
                    ],
                  ),
                  SwitchListTile.adaptive(
                    key: const Key('practiceLoopToggle'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Repetir trecho'),
                    subtitle: Text(
                      !model.canLoop && model.loaded
                          ? 'A fonte atual não permite loop.'
                          : 'Marque A e B com pelo menos 0,25 s entre eles.',
                    ),
                    value: model.loopEnabled,
                    onChanged: ready && model.canLoop && hasRange
                        ? (_) => model.toggleLoop()
                        : null,
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      TextButton.icon(
                        key: const Key('practiceReturnA'),
                        onPressed:
                            ready && model.canSeek && model.markerA != null
                            ? () => model.seek(model.markerA!)
                            : null,
                        icon: const Icon(Icons.first_page),
                        label: const Text('Voltar ao A'),
                      ),
                      TextButton.icon(
                        key: const Key('practiceClearLoop'),
                        onPressed:
                            ready &&
                                (model.markerA != null || model.markerB != null)
                            ? model.clearLoop
                            : null,
                        icon: const Icon(Icons.clear),
                        label: const Text('Limpar A/B'),
                      ),
                    ],
                  ),
                ],
              ),
            const SizedBox(height: 16),
            if (widget.practiceController case final controller?) ...[
              PracticeProgressionCard(controller: controller),
              const SizedBox(height: 16),
            ],
            if (!widget.unifiedMode)
              _card(
                children: <Widget>[
                  const Text(
                    'VELOCIDADE DO TREINO',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${(speed * 100).round()}%',
                    key: const Key('practiceSpeedValue'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 46,
                      fontWeight: FontWeight.w900,
                      color: studioCyan,
                    ),
                  ),
                  Slider(
                    key: const Key('practiceSpeed'),
                    value: speed.clamp(.5, 1.5),
                    min: .5,
                    max: 1.5,
                    divisions: 20,
                    label: '${(speed * 100).round()}%',
                    onChanged: ready && model.canSpeed
                        ? (v) => setState(() => _speedPreview = v)
                        : null,
                    onChangeEnd: ready && model.canSpeed
                        ? (v) {
                            setState(() => _speedPreview = null);
                            model.changeSpeed(v);
                          }
                        : null,
                  ),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      OutlinedButton.icon(
                        key: const Key('visualPracticeMinus'),
                        onPressed: ready && model.canSpeed && model.speed > .5
                            ? () => model.changeSpeed(
                                ((model.speed * 100).round() - 5).clamp(
                                      50,
                                      150,
                                    ) /
                                    100,
                              )
                            : null,
                        icon: const Icon(Icons.remove),
                        label: const Text('5%'),
                      ),
                      FilledButton.icon(
                        key: const Key('visualPracticePause'),
                        onPressed:
                            ready ||
                                (model.loaded && model.playing && !model.muted)
                            ? model.playPause
                            : null,
                        icon: Icon(
                          model.playing && !model.muted
                              ? Icons.pause
                              : Icons.play_arrow,
                        ),
                        label: Text(
                          model.muted
                              ? 'Ativar som'
                              : model.playing
                              ? 'Pausar'
                              : 'Reproduzir',
                        ),
                      ),
                      OutlinedButton.icon(
                        key: const Key('visualPracticePlus'),
                        onPressed: ready && model.canSpeed && model.speed < 1.5
                            ? () => model.changeSpeed(
                                ((model.speed * 100).round() + 5).clamp(
                                      50,
                                      150,
                                    ) /
                                    100,
                              )
                            : null,
                        icon: const Icon(Icons.add),
                        label: const Text('5%'),
                      ),
                      TextButton(
                        key: const Key('practiceOriginalSpeed'),
                        onPressed: ready && model.canSpeed
                            ? () => model.changeSpeed(1)
                            : null,
                        child: const Text('100% original'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.practiceController == null
                        ? 'A velocidade só muda quando você a ajusta. Não contamos repetições nem avaliamos a sua execução automaticamente.'
                        : 'Um ajuste manual pausa a progressão. As voltas contam reprodução do trecho, não avaliam a sua execução.',
                    style: TextStyle(color: studioMuted, fontSize: 12),
                  ),
                ],
              ),
            const SizedBox(height: 16),
            _card(
              children: <Widget>[
                const Text(
                  'OS SEUS TRECHOS',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  'Guarde cada trecho com um nome, como Intro, Refrão ou Solo. Os tempos e ajustes ficam no seu dispositivo.',
                  style: TextStyle(color: studioMuted),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    FilledButton.icon(
                      key: const Key('visualPracticeSaveLoop'),
                      onPressed: ready && hasRange ? widget.onSaveLoop : null,
                      icon: const Icon(Icons.bookmark_add_outlined),
                      label: const Text('Guardar trecho'),
                    ),
                    OutlinedButton.icon(
                      key: const Key('practiceSavedLoops'),
                      onPressed: widget.onOpenLoops,
                      icon: const Icon(Icons.bookmarks_outlined),
                      label: const Text('Trechos guardados'),
                    ),
                    OutlinedButton.icon(
                      key: const Key('practiceMetronome'),
                      onPressed: widget.onMetronome,
                      icon: const Icon(Icons.timer_outlined),
                      label: const Text('Metrônomo'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}
