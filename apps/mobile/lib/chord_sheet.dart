import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'player_panel_model.dart';
import 'study_tools.dart';
import 'studio_native_pages.dart';

class ChordCue {
  const ChordCue(this.milliseconds, this.chord);
  final int milliseconds;
  final String chord;
}

/// Manual timestamps, not inferred beats or an automatic harmony detector.
List<ChordCue> parseChordCues(String text) {
  final cues = <ChordCue>[];
  for (final line in const LineSplitter().convert(text)) {
    if (line.trim().isEmpty) continue;
    final match = RegExp(r'^\s*(\d{1,3}):([0-5]\d)(?:\.(\d{1,3}))?\s+(.+?)\s*$')
        .firstMatch(line);
    if (match == null) {
      throw const FormatException('Use mm:ss acorde, por exemplo 00:12 Am7.');
    }
    final milliseconds =
        (int.parse(match[1]!) * 60 + int.parse(match[2]!)) * 1000 +
        int.parse((match[3] ?? '0').padRight(3, '0'));
    final chord = match[4]!;
    if (chord.length > 80) {
      throw const FormatException(
        'Cada acorde ou cifra pode ter até 80 caracteres.',
      );
    }
    if (cues.isNotEmpty && milliseconds <= cues.last.milliseconds) {
      throw const FormatException(
        'Os tempos devem estar em ordem crescente, sem repetições.',
      );
    }
    cues.add(ChordCue(milliseconds, chord));
    if (cues.length > 500) {
      throw const FormatException('Use no máximo 500 marcações por música.');
    }
  }
  return cues;
}

int currentChordIndex(List<ChordCue> cues, Duration position) {
  for (int i = cues.length - 1; i >= 0; i--) {
    if (position.inMilliseconds >= cues[i].milliseconds) return i;
  }
  return -1;
}

class ChordSheet {
  const ChordSheet({
    this.timeline = '',
    this.notes = '',
    this.sourceTitle = '',
    this.sourceUrl = '',
    this.transpose = 0,
    this.followAudio = false,
  });
  final String timeline, notes, sourceTitle, sourceUrl;
  final int transpose;
  final bool followAudio;

  ChordSheet copyWith({
    String? timeline,
    String? notes,
    String? sourceTitle,
    String? sourceUrl,
    int? transpose,
    bool? followAudio,
  }) => ChordSheet(
    timeline: timeline ?? this.timeline,
    notes: notes ?? this.notes,
    sourceTitle: sourceTitle ?? this.sourceTitle,
    sourceUrl: sourceUrl ?? this.sourceUrl,
    transpose: transpose ?? this.transpose,
    followAudio: followAudio ?? this.followAudio,
  );
}

class ChordSheetStore {
  ChordSheetStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();
  final SharedPreferencesAsync _preferences;

  /// Session-only draft retained when the player is rebuilt during navigation.
  /// It is never written to preferences or associated with an empty source key.
  ChordSheet temporarySheet = const ChordSheet();

  String _key(String source) =>
      'transpono.chords.v1.${base64Url.encode(utf8.encode(source))}';
  Future<ChordSheet> read(String source) async {
    final raw = await _preferences.getString(_key(source));
    if (raw == null) return const ChordSheet();
    final data = jsonDecode(raw);
    if (data is! Map ||
        data['version'] != 1 ||
        data['timeline'] is! String ||
        data['notes'] is! String) {
      throw const FormatException('Cifras guardadas inválidas.');
    }
    parseChordCues(data['timeline']);
    if ((data['sourceTitle'] != null && data['sourceTitle'] is! String) ||
        (data['sourceUrl'] != null && data['sourceUrl'] is! String)) {
      throw const FormatException('Origem da cifra inválida.');
    }
    if ((data['transpose'] != null &&
            (data['transpose'] is! int ||
                (data['transpose'] as int).abs() > 48)) ||
        (data['followAudio'] != null && data['followAudio'] is! bool)) {
      throw const FormatException('Tonalidade da cifra inválida.');
    }
    return ChordSheet(
      timeline: data['timeline'],
      notes: data['notes'],
      sourceTitle: data['sourceTitle'] ?? '',
      sourceUrl: data['sourceUrl'] ?? '',
      transpose: data['transpose'] ?? 0,
      followAudio: data['followAudio'] ?? false,
    );
  }

  Future<void> save(String source, ChordSheet sheet) async {
    if (source.isEmpty ||
        sheet.timeline.length > 60000 ||
        sheet.notes.length > 10000 ||
        sheet.sourceTitle.length > 240 ||
        sheet.sourceUrl.length > 2048 ||
        sheet.transpose.abs() > 48) {
      throw const FormatException('Dados fora do limite permitido.');
    }
    parseChordCues(sheet.timeline);
    // Refuse to overwrite an unreadable record; keep it available for recovery.
    await read(source);
    await _preferences.setString(
      _key(source),
      jsonEncode({
        'version': 1,
        'timeline': sheet.timeline,
        'notes': sheet.notes,
        'sourceTitle': sheet.sourceTitle,
        'sourceUrl': sheet.sourceUrl,
        'transpose': sheet.transpose,
        'followAudio': sheet.followAudio,
      }),
    );
  }
}

class ChordsPanel extends StatefulWidget {
  const ChordsPanel({
    super.key,
    required this.model,
    required this.sourceKey,
    required this.store,
    required this.onOpenPlayer,
    this.unifiedMode = false,
  });
  final PlayerPanelModel model;
  final String sourceKey;
  final ChordSheetStore store;
  final VoidCallback onOpenPlayer;
  final bool unifiedMode;
  @override
  State<ChordsPanel> createState() => _ChordsPanelState();
}

class _ChordsPanelState extends State<ChordsPanel> {
  ChordSheet _sheet = const ChordSheet();
  List<ChordCue> _cues = [];
  String? _error;
  int _revision = 0;
  bool _loading = false;
  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void didUpdateWidget(ChordsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sourceKey != widget.sourceKey ||
        oldWidget.store != widget.store) {
      _read();
    }
  }

  Future<void> _read() async {
    final revision = ++_revision;
    _loading = true;
    _sheet = const ChordSheet();
    _cues = [];
    _error = null;
    try {
      final sheet = widget.sourceKey.isEmpty
          ? const ChordSheet()
          : await widget.store.read(widget.sourceKey);
      if (mounted && revision == _revision) {
        setState(() {
          _sheet = sheet;
          _cues = parseChordCues(sheet.timeline);
        });
      }
    } on Object {
      if (mounted && revision == _revision) {
        setState(
          () => _error = 'Não foi possível ler as cifras guardadas. Nenhum dado foi apagado.',
        );
      }
    } finally {
      if (mounted && revision == _revision) setState(() => _loading = false);
    }
  }

  Future<void> _edit() async {
    final source = widget.sourceKey;
    final initial = _sheet;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _ChordEditor(store: widget.store, source: source, initial: initial),
    );
    if (mounted) await _read();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.model,
    builder: (context, _) {
      final m = widget.model;
      final index = m.canSeek ? currentChordIndex(_cues, m.position) : -1;
      String chordAt(int i) => i < 0 || i >= _cues.length
          ? '—'
          : transposeChordProgression(_cues[i].chord, m.pitch.round());
      final ready = m.loaded && !m.busy;
      return SingleChildScrollView(
        key: const Key('visualScrollchords'),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'ACORDES SINCRONIZADOS',
              style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1),
            ),
            const SizedBox(height: 8),
            const Text(
              'Cifras e tempos inseridos por você · sem deteção automática',
              style: TextStyle(color: studioMuted),
            ),
            if (_loading) const LinearProgressIndicator(),
            if (m.message != null)
              Text(m.message!, style: const TextStyle(color: studioMuted)),
            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: Colors.orangeAccent)),
              TextButton(
                onPressed: _read,
                child: const Text('Tentar novamente'),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              m.loaded ? m.title : 'Escolha uma música no player',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _cueCard('AGORA', m.canSeek ? chordAt(index) : '—'),
                _cueCard('PRÓXIMO', m.canSeek ? chordAt(index + 1) : '—'),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Transposição ligada ao player: ${m.pitch > 0 ? '+' : ''}${m.pitch.toStringAsFixed(0)} semitons',
              style: const TextStyle(color: studioCyan),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const Key('chordsEdit'),
                  onPressed: ready && m.canSeek && !_loading && _error == null
                      ? _edit
                      : null,
                  icon: const Icon(Icons.edit),
                  label: const Text('Editar cifras e notas'),
                ),
                if (!widget.unifiedMode)
                  OutlinedButton.icon(
                    key: const Key('chordsPlay'),
                    onPressed: ready || (m.loaded && m.playing && !m.muted)
                        ? m.playPause
                        : null,
                    icon: Icon(m.playing ? Icons.pause : Icons.play_arrow),
                    label: Text(
                      m.muted
                          ? 'Ativar som'
                          : m.playing
                          ? 'Pausar'
                          : 'Reproduzir',
                    ),
                  ),
                if (!widget.unifiedMode)
                  OutlinedButton.icon(
                    key: const Key('visualChordsTranspose'),
                    onPressed: widget.onOpenPlayer,
                    icon: const Icon(Icons.tune),
                    label: const Text('Tom e velocidade'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (_cues.isEmpty)
              const Text(
                'Adicione marcações como “00:00 C” e “00:08 Am”. Durante a reprodução, o acorde atual acompanha a posição. Toque numa marcação para ir até ela.',
                style: TextStyle(color: studioMuted),
              ),
            for (int i = 0; i < _cues.length; i++)
              ListTile(
                key: Key('chordCue$i'),
                selected: i == index,
                selectedTileColor: studioCyan.withValues(alpha: .1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: Text(
                  _stamp(_cues[i].milliseconds),
                  style: const TextStyle(color: studioMuted),
                ),
                title: Text(
                  chordAt(i),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                trailing: const Icon(Icons.play_arrow),
                enabled:
                    ready &&
                    m.canSeek &&
                    _cues[i].milliseconds <= m.duration.inMilliseconds,
                onTap: () =>
                    m.seek(Duration(milliseconds: _cues[i].milliseconds)),
              ),
            const Divider(height: 32),
            const Text(
              'NOTAS DA MÚSICA',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            SelectableText(
              _sheet.notes.isEmpty
                  ? 'Sem notas guardadas para esta música.'
                  : _sheet.notes,
            ),
            const SizedBox(height: 12),
            const Text(
              'Gravação e reconhecimento automático ficam para uma etapa posterior. As cifras originais guardadas não são alteradas ao mudar o tom.',
              style: TextStyle(color: studioMuted, fontSize: 12),
            ),
          ],
        ),
      );
    },
  );
  Widget _cueCard(String label, String chord) => Container(
    constraints: const BoxConstraints(minWidth: 140),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: studioCard,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: studioCyan.withValues(alpha: .25)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: studioMuted)),
        Text(
          chord,
          style: const TextStyle(
            fontSize: 36,
            color: studioCyan,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    ),
  );
}

String _stamp(int milliseconds) =>
    '${milliseconds ~/ 60000}:${((milliseconds ~/ 1000) % 60).toString().padLeft(2, '0')}';

class _ChordEditor extends StatefulWidget {
  const _ChordEditor({
    required this.store,
    required this.source,
    required this.initial,
  });
  final ChordSheetStore store;
  final String source;
  final ChordSheet initial;
  @override
  State<_ChordEditor> createState() => _ChordEditorState();
}

class _ChordEditorState extends State<_ChordEditor> {
  late final _timeline = TextEditingController(text: widget.initial.timeline);
  late final _notes = TextEditingController(text: widget.initial.notes);
  String? _error;
  bool _saving = false, _confirming = false;
  @override
  void dispose() {
    _timeline.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _cancel() async {
    if (_saving || _confirming) return;
    final dirty =
        _timeline.text != widget.initial.timeline ||
        _notes.text != widget.initial.notes;
    if (!dirty) {
      Navigator.pop(context);
      return;
    }
    _confirming = true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Descartar alterações?'),
        content: const Text(
          'As últimas alterações nas cifras e notas ainda não foram guardadas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Continuar a editar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    _confirming = false;
    if (mounted && discard == true) Navigator.pop(context);
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final latest = await widget.store.read(widget.source);
      if (latest.timeline != widget.initial.timeline ||
          latest.notes != widget.initial.notes) {
        throw const FormatException(
          'A cifra mudou noutro painel. Copie as suas alterações e reabra a edição para evitar perder dados.',
        );
      }
      await widget.store.save(
        widget.source,
        latest.copyWith(timeline: _timeline.text, notes: _notes.text),
      );
      if (mounted) Navigator.pop(context);
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Não foi possível guardar. Pode tentar novamente sem perder o texto.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _cancel();
    },
    child: AlertDialog(
      title: const Text('Cifras e notas desta música'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('chordsTimelineInput'),
                controller: _timeline,
                enabled: !_saving,
                minLines: 5,
                maxLines: 10,
                maxLength: 60000,
                decoration: const InputDecoration(
                  labelText: 'Tempo e cifra · uma por linha',
                  hintText: '00:00 C\n00:08 Am7\n00:16 F G',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('chordsNotesInput'),
                controller: _notes,
                enabled: !_saving,
                minLines: 3,
                maxLines: 6,
                maxLength: 10000,
                decoration: const InputDecoration(labelText: 'Notas pessoais'),
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.orangeAccent),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : _cancel,
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('chordsSave'),
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'A guardar…' : 'Guardar'),
        ),
      ],
    ),
  );
}
