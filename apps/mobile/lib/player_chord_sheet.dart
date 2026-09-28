import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'chord_sheet.dart';
import 'player_panel_model.dart';
import 'studio_native_pages.dart';
import 'study_tools.dart';
import 'studio_appearance.dart';

const int playerChordTextLimit = 10000;
const int _fileByteLimit = 40000;
const String _example =
    '[Progressão de exemplo]\n\n'
    'C       G       Am      F\n'
    '1       2       3       4\n\n'
    'C       G       Am      F\n'
    'Toque quatro tempos em cada acorde.';

/// Text only: keep spaces and line breaks that align chords above lyrics.
String validatePlayerChordText(String text) {
  final normalized = text
      .replaceFirst(RegExp(r'^\uFEFF'), '')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n');
  if (normalized.trim().isEmpty) {
    throw const FormatException('Escreva ou importe uma cifra primeiro.');
  }
  if (normalized.length > playerChordTextLimit ||
      '\n'.allMatches(normalized).length >= 500) {
    throw const FormatException(
      'A cifra pode ter até 10.000 caracteres e 500 linhas.',
    );
  }
  if (RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]').hasMatch(normalized)) {
    throw const FormatException('Escolha um ficheiro de texto simples (.txt).');
  }
  return normalized;
}

String decodePlayerChordFile(List<int> bytes) {
  if (bytes.length > _fileByteLimit) {
    throw const FormatException(
      'O ficheiro é demasiado grande (máximo 40 KB).',
    );
  }
  final String text;
  try {
    text = utf8.decode(bytes);
  } on FormatException {
    throw const FormatException('Guarde a cifra como texto UTF-8 (.txt).');
  }
  return validatePlayerChordText(text);
}

final _chordSymbol = RegExp(
  r'^([A-G])([#b♯♭]?)((?:(?:maj|min|dim|aug|sus|add|m|M|Δ|ø|°|\+|-)\d*|\d+|[#b♯♭]\d+|\([^\s()]*\))*)(?:/([A-G])([#b♯♭]?))?$',
);

const playerChordNoteColors = <Color>[
  Color(0xFF5CA9FF), // C: azul
  Color(0xFF7AC7FF), // C#/Db: azul claro
  Color(0xFF5DD47A), // D: verde
  Color(0xFF80D9A3), // D#/Eb: verde menta
  Color(0xFFFF6B6B), // E: vermelho
  Color(0xFFC89362), // F: marrom
  Color(0xFFD9AC7A), // F#/Gb: marrom claro
  Color(0xFFFFD34F), // G: amarelo
  Color(0xFFF2B84B), // G#/Ab: amarelo âmbar
  Color(0xFFB695F5), // A: roxo
  Color(0xFFD0A8F5), // A#/Bb: roxo claro
  Color(0xFFF48FC7), // B: rosa
];

const playerChordNoteColorsLight = <Color>[
  Color(0xFF1D5FA8),
  Color(0xFF176985),
  Color(0xFF16743A),
  Color(0xFF177450),
  Color(0xFFB42332),
  Color(0xFF7A4A24),
  Color(0xFF805026),
  Color(0xFF806000),
  Color(0xFF8A6000),
  Color(0xFF6740A0),
  Color(0xFF7950A2),
  Color(0xFFA33470),
];

Color playerChordDisplayColor(int pitchClass, StudioAppearance appearance) {
  final customized = appearance.noteColors[pitchClass];
  if (appearance.mode != StudioAppearanceMode.light) {
    return customized ?? playerChordNoteColors[pitchClass];
  }
  if (customized == null) return playerChordNoteColorsLight[pitchClass];
  for (var step = 0; step <= 8; step++) {
    final candidate = Color.lerp(customized, Colors.black, step / 10)!;
    if (candidate.computeLuminance() <= .18) return candidate;
  }
  return Color.lerp(customized, Colors.black, .8)!;
}

int? playerChordPitchClass(String chord) {
  final match = _chordSymbol.firstMatch(chord);
  if (match == null) return null;
  final root = switch (match[1]) {
    'C' => 0,
    'D' => 2,
    'E' => 4,
    'F' => 5,
    'G' => 7,
    'A' => 9,
    'B' => 11,
    _ => 0,
  };
  final accidental = switch (match[2]) {
    '#' || '♯' => 1,
    'b' || '♭' => -1,
    _ => 0,
  };
  return (root + accidental + 12) % 12;
}

List<InlineSpan> playerChordColorSpans(
  String text, {
  Map<int, Color> noteColors = const {},
  StudioAppearanceMode mode = StudioAppearanceMode.dark,
}) {
  final spans = <InlineSpan>[];
  for (final (index, line) in text.split('\n').indexed) {
    if (index > 0) spans.add(const TextSpan(text: '\n'));
    final chordLine = _isChordLine(line);
    var cursor = 0;
    for (final match in RegExp(r'\[[^\[\]]+\]|[^\s|,;]+').allMatches(line)) {
      final token = match[0]!;
      final embedded = token.startsWith('[') && token.endsWith(']');
      final chord = embedded ? token.substring(1, token.length - 1) : token;
      final pitchClass = (chordLine || embedded)
          ? playerChordPitchClass(chord)
          : null;
      if (pitchClass == null) continue;
      if (match.start > cursor) {
        spans.add(TextSpan(text: line.substring(cursor, match.start)));
      }
      spans.add(
        TextSpan(
          text: token,
          style: TextStyle(
            color: playerChordDisplayColor(
              pitchClass,
              StudioAppearance(mode: mode, noteColors: noteColors),
            ),
            fontWeight: FontWeight.w700,
          ),
        ),
      );
      cursor = match.end;
    }
    if (cursor < line.length) spans.add(TextSpan(text: line.substring(cursor)));
  }
  return spans;
}

bool _isChordLine(String line) {
  final withoutSection = line.replaceFirst(
    RegExp(
      r'^\s*\[(?:intro|solo|refrão|refrao|verso|ponte|final|verse|chorus|bridge|outro|instrumental)\s*\d*\]\s*',
      caseSensitive: false,
    ),
    '',
  );
  final tokens = withoutSection
      .split(RegExp(r'[\s|,;]+'))
      .where((t) => t.isNotEmpty)
      .toList();
  return tokens.any(_chordSymbol.hasMatch) &&
      tokens.every(
        (token) =>
            _chordSymbol.hasMatch(token) ||
            RegExp(r'^\(?\d+x\)?$').hasMatch(token) ||
            token == '-',
      );
}

/// Preserve chord start columns when a sharp/bass changes token width.
/// Explicit ChordPro [C] tokens may occur within lyrics; ordinary words may not.
String transposePlayerChordText(String text, int semitones) => text
    .split('\n')
    .map((line) {
      if (semitones % 12 == 0) return line;
      if (!_isChordLine(line)) {
        return line.replaceAllMapped(
          RegExp(r'\[([^\[\]]+)\]'),
          (match) => _chordSymbol.hasMatch(match[1]!)
              ? '[${transposeChordProgression(match[1]!, semitones)}]'
              : match[0]!,
        );
      }
      final result = StringBuffer();
      var previousEnd = 0;
      for (final match in RegExp(r'[^\s|,;]+|[|,;]').allMatches(line)) {
        final gap = line.substring(previousEnd, match.start);
        if (gap.trim().isNotEmpty) {
          result.write(gap);
        } else {
          final wanted = match.start - result.length;
          result.write(
            ' ' *
                (wanted > 0
                    ? wanted
                    : gap.isNotEmpty
                    ? 1
                    : 0),
          );
        }
        final token = match[0]!;
        result.write(
          _chordSymbol.hasMatch(token)
              ? transposeChordProgression(token, semitones)
              : token,
        );
        previousEnd = match.end;
      }
      result.write(line.substring(previousEnd));
      return result.toString();
    })
    .join('\n');

class PlayerChordSheet extends StatefulWidget {
  const PlayerChordSheet({
    super.key,
    required this.model,
    required this.sourceKey,
    required this.store,
    this.onSearch,
    this.onHide,
    this.onPullDown,
    this.lyricsOnly = false,
    this.revision = 0,
    this.appearance = const StudioAppearance(),
  });

  final PlayerPanelModel model;
  final String sourceKey;
  final ChordSheetStore store;
  final VoidCallback? onSearch;
  final VoidCallback? onHide;
  final VoidCallback? onPullDown;
  final bool lyricsOnly;
  final int revision;
  final StudioAppearance appearance;

  @override
  PlayerChordSheetState createState() => PlayerChordSheetState();
}

class PlayerChordSheetState extends State<PlayerChordSheet> {
  final ScrollController _horizontalScroll = ScrollController();
  ChordSheet _sheet = const ChordSheet();
  bool _visible = true,
      _showExample = false,
      _loading = false,
      _choosing = false;
  String? _error;
  int _revision = 0;
  bool _savingTone = false;
  bool _changingAudioPitch = false;
  String? _measuredText;
  double? _measuredWidth;
  TextScaler? _measuredScaler;
  double _fittedFontSize = 15;
  bool _needsHorizontalScroll = false;

  int get _displayPitch =>
      _sheet.transpose + (_sheet.followAudio ? widget.model.pitch.round() : 0);

  double _fontSizeFor(String text, double width, TextScaler scaler) {
    if (_measuredText == text &&
        _measuredWidth == width &&
        _measuredScaler == scaler) {
      return _fittedFontSize;
    }
    final painter = TextPainter(
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    );
    var widest = 0.0;
    for (final line in text.split('\n')) {
      painter.text = TextSpan(
        text: line.isEmpty ? ' ' : line,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 15),
      );
      painter.layout();
      if (painter.width > widest) widest = painter.width;
    }
    painter.dispose();
    final available = width.isFinite ? width.clamp(1.0, double.infinity) : 1.0;
    _fittedFontSize = widest > available
        ? (15 * available / widest).clamp(11.0, 15.0)
        : 15.0;
    _needsHorizontalScroll = widest * _fittedFontSize / 15 > available + 1;
    _measuredText = text;
    _measuredWidth = width;
    _measuredScaler = scaler;
    return _fittedFontSize;
  }

  Future<void> _saveTone(int transpose, bool followAudio) async {
    if (_loading || _savingTone) return;
    final revision = _revision;
    final source = widget.sourceKey;
    final store = widget.store;
    setState(() => _savingTone = true);
    try {
      final latest = source.isEmpty
          ? store.temporarySheet
          : await store.read(source);
      if (!mounted || revision != _revision) return;
      final sheet = latest.copyWith(
        transpose: transpose.clamp(-48, 48),
        followAudio: followAudio,
      );
      if (source.isEmpty) {
        store.temporarySheet = sheet;
      } else {
        await store.save(source, sheet);
      }
      if (!mounted || revision != _revision) return;
      setState(() {
        _sheet = sheet;
        _error = null;
      });
    } on Object {
      if (mounted && revision == _revision) {
        setState(
          () => _error =
              'Não foi possível guardar o tom da cifra. Tente novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => _savingTone = false);
    }
  }

  Future<void> _changeTone(int delta) async {
    if (_sheet.followAudio) {
      if (_changingAudioPitch) return;
      setState(() => _changingAudioPitch = true);
      try {
        // The visible cifra follows only the pitch acknowledged by the engine.
        await widget.model.changePitch(
          (widget.model.pitch + delta).clamp(-12, 12),
        );
      } on Object {
        if (mounted) {
          setState(() => _error = 'O áudio não confirmou a mudança de tom.');
        }
      } finally {
        if (mounted) setState(() => _changingAudioPitch = false);
      }
      return;
    }
    await _saveTone((_sheet.transpose + delta).clamp(-24, 24), false);
  }

  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void dispose() {
    _horizontalScroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(PlayerChordSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sourceKey != widget.sourceKey ||
        oldWidget.store != widget.store ||
        oldWidget.revision != widget.revision) {
      _read();
    }
  }

  Future<void> _read() async {
    if (_horizontalScroll.hasClients) _horizontalScroll.jumpTo(0);
    final revision = ++_revision;
    _sheet = const ChordSheet();
    _visible = true;
    _showExample = false;
    _error = null;
    _loading = true;
    try {
      final sheet = widget.sourceKey.isEmpty
          ? widget.store.temporarySheet
          : await widget.store.read(widget.sourceKey);
      if (!mounted || revision != _revision) return;
      setState(() {
        _sheet = sheet;
        _showExample = false;
      });
    } on Object {
      if (mounted && revision == _revision) {
        setState(
          () => _error =
              'Não foi possível ler a cifra guardada. Tente novamente.',
        );
      }
    } finally {
      if (mounted && revision == _revision) setState(() => _loading = false);
    }
  }

  /// Opens the same chooser from the Cifra button beside Abrir ficheiro.
  Future<void> choose() async {
    if (_choosing || _loading || !mounted) return;
    _choosing = true;
    final source = widget.sourceKey;
    final store = widget.store;
    final revision = _revision;
    try {
      await showDialog<void>(
        context: context,
        builder: (_) => _ChordChooser(
          initial: _sheet.notes,
          visible: _visible,
          sourceSelected: source.isNotEmpty,
          onApply: (text, visible, example) async {
            void checkSource() {
              if (!mounted || revision != _revision) {
                throw const FormatException(
                  'A música mudou. Feche e escolha a cifra da música atual.',
                );
              }
            }

            checkSource();
            var sheet = _sheet;
            if (text != null) {
              final validated = validatePlayerChordText(text);
              if (source.isNotEmpty) {
                // Read again to preserve edits made in the synchronized view.
                final latest = await store.read(source);
                checkSource();
                sheet = latest.copyWith(notes: validated);
                await store.save(source, sheet);
              } else {
                sheet = sheet.copyWith(notes: validated);
                store.temporarySheet = sheet;
              }
            }
            checkSource();
            setState(() {
              _sheet = sheet;
              _visible = visible;
              _showExample = example;
              _error = null;
            });
          },
        ),
      );
    } finally {
      _choosing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: widget.model,
      builder: (context, _) {
        final pitch = _displayPitch;
        final ready = !_loading && !_savingTone;
        final canChange =
            ready &&
            !_changingAudioPitch &&
            (!_sheet.followAudio ||
                (widget.model.loaded &&
                    !widget.model.busy &&
                    widget.model.canPitch));
        final original = _showExample ? _example : _sheet.notes;
        final text = transposePlayerChordText(original, pitch);
        if (widget.lyricsOnly) {
          return Container(
            key: const Key('playerChordSheet'),
            decoration: studioPanelDecoration(
              radius: 26,
              mode: widget.appearance.mode,
            ),
            clipBehavior: Clip.antiAlias,
            child: NotificationListener<OverscrollNotification>(
              onNotification: (notification) {
                if (notification.metrics.axis == Axis.vertical &&
                    notification.overscroll < -4) {
                  widget.onPullDown?.call();
                }
                return false;
              },
              child: SingleChildScrollView(
                key: const Key('pinnedChordTextScroll'),
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(14),
                child: LayoutBuilder(
                  builder: (context, box) {
                    final fontSize = _fontSizeFor(
                      text,
                      box.maxWidth,
                      MediaQuery.textScalerOf(context),
                    );
                    return Scrollbar(
                      controller: _horizontalScroll,
                      thumbVisibility: _needsHorizontalScroll,
                      child: SingleChildScrollView(
                        controller: _horizontalScroll,
                        scrollDirection: Axis.horizontal,
                        child: SelectableText.rich(
                          key: const Key('playerChordText'),
                          TextSpan(
                            children: playerChordColorSpans(
                              text,
                              noteColors: widget.appearance.noteColors,
                              mode: widget.appearance.mode,
                            ),
                          ),
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: fontSize,
                            height: 1.8,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        }
        return Container(
          key: const Key('playerChordSheet'),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: studioPanelDecoration(
            radius: 26,
            mode: widget.appearance.mode,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.library_music_outlined,
                    color: studioCyan,
                    size: 21,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _showExample
                              ? 'Cifra de exemplo'
                              : _sheet.sourceTitle.isNotEmpty
                              ? _sheet.sourceTitle
                              : 'Minha cifra',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (_sheet.sourceUrl.isNotEmpty)
                          SelectableText(
                            'Fonte: ${Uri.tryParse(_sheet.sourceUrl)?.host ?? _sheet.sourceUrl}',
                            key: const Key('playerChordSource'),
                            maxLines: 1,
                            style: const TextStyle(
                              color: studioMuted,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const Key('playerChordPitchReset'),
                    tooltip: 'Repor cifra',
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF303034),
                    ),
                    onPressed: ready ? () => _saveTone(0, false) : null,
                    icon: const Icon(Icons.restore, size: 20),
                  ),
                  IconButton(
                    key: const Key('playerChordEdit'),
                    tooltip: widget.onSearch == null
                        ? 'Editar cifra'
                        : 'Pesquisar outra cifra',
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF303034),
                    ),
                    onPressed: _loading ? null : widget.onSearch ?? choose,
                    icon: Icon(
                      widget.onSearch == null
                          ? Icons.edit_outlined
                          : Icons.search,
                      size: 20,
                    ),
                  ),
                  if (widget.onHide != null)
                    IconButton(
                      key: const Key('playerChordHide'),
                      tooltip: 'Esconder cifra',
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFF303034),
                      ),
                      onPressed: widget.onHide,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.visibility_off_outlined, size: 20),
                    ),
                ],
              ),
              if (_showExample || widget.sourceKey.isEmpty)
                Text(
                  _showExample
                      ? 'Exercício original · não é a cifra da música em reprodução.'
                      : widget.sourceKey.isEmpty
                      ? 'Cifra temporária · escolha uma música para guardar por faixa.'
                      : widget.model.title,
                  style: const TextStyle(color: studioMuted, fontSize: 12),
                ),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                children: [
                  const Text('Tom da cifra'),
                  IconButton(
                    key: const Key('playerChordPitchDown'),
                    tooltip: 'Diminuir tonalidade da cifra',
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF303034),
                    ),
                    onPressed:
                        canChange &&
                            (_sheet.followAudio
                                ? widget.model.pitch > -12
                                : _sheet.transpose > -24)
                        ? () => _changeTone(-1)
                        : null,
                    icon: const Icon(Icons.remove),
                  ),
                  Text(
                    pitch == 0
                        ? 'Original'
                        : '${pitch > 0 ? '+' : ''}$pitch st',
                    key: const Key('playerChordPitchValue'),
                    style: const TextStyle(
                      color: studioCyan,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  IconButton(
                    key: const Key('playerChordPitchUp'),
                    tooltip: 'Aumentar tonalidade da cifra',
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF303034),
                    ),
                    onPressed:
                        canChange &&
                            (_sheet.followAudio
                                ? widget.model.pitch < 12
                                : _sheet.transpose < 24)
                        ? () => _changeTone(1)
                        : null,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              Text(
                _sheet.followAudio
                    ? 'Acordes · acompanham o áudio'
                    : 'Acordes · independente do áudio',
                style: const TextStyle(color: studioMuted, fontSize: 11),
              ),
              const SizedBox(height: 8),
              if (_loading) const LinearProgressIndicator(),
              if (_error != null) ...[
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.orangeAccent),
                ),
                TextButton(
                  onPressed: _read,
                  child: const Text('Tentar novamente'),
                ),
              ],
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: widget.appearance.mode == StudioAppearanceMode.light
                      ? const Color(0xFFFFFFFF)
                      : const Color(0xFF0D0D0F),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: LayoutBuilder(
                  builder: (context, box) {
                    final fontSize = _fontSizeFor(
                      text,
                      box.maxWidth,
                      MediaQuery.textScalerOf(context),
                    );
                    return SelectableText.rich(
                      key: const Key('playerChordText'),
                      TextSpan(
                        children: playerChordColorSpans(
                          text,
                          noteColors: widget.appearance.noteColors,
                          mode: widget.appearance.mode,
                        ),
                      ),
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: fontSize,
                        height: 1.8,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

typedef _ApplyChord = Future<void> Function(
  String? text,
  bool visible,
  bool example,
);

class _ChordChooser extends StatefulWidget {
  const _ChordChooser({
    required this.initial,
    required this.visible,
    required this.sourceSelected,
    required this.onApply,
  });
  final String initial;
  final bool visible, sourceSelected;
  final _ApplyChord onApply;

  @override
  State<_ChordChooser> createState() => _ChordChooserState();
}

class _ChordChooserState extends State<_ChordChooser> {
  late final _text = TextEditingController(text: widget.initial);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final picked = await FilePicker.pickFile(
        dialogTitle: 'Escolher cifra em texto',
        type: FileType.custom,
        allowedExtensions: ['txt'],
      );
      if (picked == null || !mounted) return;
      if (picked.extension?.toLowerCase() != 'txt') {
        throw const FormatException(
          'Escolha um ficheiro de texto simples (.txt).',
        );
      }
      if ((picked.lengthSync() ?? 0) > _fileByteLimit) {
        throw const FormatException(
          'O ficheiro é demasiado grande (máximo 40 KB).',
        );
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in picked.readAsByteStream()) {
        if (bytes.length + chunk.length > _fileByteLimit) {
          throw const FormatException(
            'O ficheiro é demasiado grande (máximo 40 KB).',
          );
        }
        bytes.add(chunk);
      }
      final text = decodePlayerChordFile(bytes.takeBytes());
      if (mounted) _text.text = text;
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Object {
      if (mounted) {
        setState(
          () => _error =
              'Não foi possível importar. O texto anterior foi mantido.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply({
    String? text,
    bool visible = true,
    bool example = false,
  }) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onApply(text, visible, example);
      if (mounted) Navigator.pop(context);
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Não foi possível guardar. O texto continua disponível para tentar novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('Escolher cifra'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Cole a letra com os acordes no tom original, ou importe um ficheiro .txt em UTF-8.',
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('playerChordImport'),
                onPressed: _busy ? null : _import,
                icon: const Icon(Icons.upload_file),
                label: const Text('Importar cifra .txt'),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('playerChordInput'),
                controller: _text,
                enabled: !_busy,
                minLines: 5,
                maxLines: 9,
                maxLength: playerChordTextLimit,
                autocorrect: false,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                decoration: const InputDecoration(
                  labelText: 'Cifra e letra',
                  hintText: 'C       G       Am      F\nEscreva a letra aqui…',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              if (!widget.sourceSelected)
                const Text(
                  'Sem música selecionada, a cifra fica apenas nesta sessão.',
                  style: TextStyle(color: studioMuted, fontSize: 12),
                ),
              if (_error != null)
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.orangeAccent),
                ),
              const SizedBox(height: 8),
              TextButton(
                key: const Key('playerChordExample'),
                onPressed: _busy ? null : () => _apply(example: true),
                child: const Text('Mostrar exemplo C · G · Am · F'),
              ),
              if (widget.visible)
                TextButton(
                  key: const Key('playerChordHide'),
                  onPressed: _busy ? null : () => _apply(visible: false),
                  child: const Text('Ocultar cifra'),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('playerChordCancel'),
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('playerChordSave'),
          onPressed: _busy ? null : () => _apply(text: _text.text),
          child: Text(
            _busy
                ? 'A preparar…'
                : widget.sourceSelected
                ? 'Guardar e mostrar'
                : 'Mostrar cifra',
          ),
        ),
      ],
    ),
  );
}
