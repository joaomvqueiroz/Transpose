import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'rhythm_map.dart';

class RhythmPanel extends StatefulWidget {
  const RhythmPanel({
    super.key,
    required this.onPreview,
    required this.onStop,
    required this.playing,
    required this.enabled,
  });
  final Future<void> Function(Uint8List) onPreview;
  final Future<void> Function() onStop;
  final bool playing, enabled;
  @override
  State<RhythmPanel> createState() => _RhythmPanelState();
}

class _RhythmPanelState extends State<RhythmPanel> {
  bool _authorized = false, _busy = false, _approved = false;
  Uint8List? _source;
  RhythmMap? _map;
  String? _error, _name;
  int _revision = 0;

  @override
  void didUpdateWidget(covariant RhythmPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled && !widget.enabled) {
      ++_revision;
      _busy = false;
    }
  }

  Future<void> _choose() async {
    final revision = ++_revision;
    setState(() {
      _busy = true;
      _error = null;
      _approved = false;
    });
    try {
      await widget.onStop();
      final selected = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['wav'],
      );
      if (selected == null || !mounted) return;
      if ((selected.lengthSync() ?? 0) > 64 * 1024 * 1024) {
        throw const FormatException('Escolha um WAV local com até 64 MB.');
      }
      final buffer = BytesBuilder(copy: false);
      await for (final chunk in selected.readAsByteStream()) {
        if (buffer.length + chunk.length > 64 * 1024 * 1024) {
          throw const FormatException('O limite é 64 MB.');
        }
        buffer.add(chunk);
      }
      final bytes = buffer.takeBytes();
      final map = await compute(analyzeRhythm, bytes);
      if (!mounted || revision != _revision || !widget.enabled) return;
      setState(() {
        _source = bytes;
        _map = map;
        _name = selected.name;
      });
    } on Object catch (e) {
      if (mounted && revision == _revision) {
        setState(
          () => _error = e is FormatException
              ? e.message
              : 'Não foi possível analisar este ficheiro.',
        );
      }
    } finally {
      if (mounted && revision == _revision) setState(() => _busy = false);
    }
  }

  Future<void> _preview() async {
    final revision = ++_revision;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await compute(mixRhythmPreview, (_source!, _map!.sections));
      if (!mounted ||
          revision != _revision ||
          !widget.enabled ||
          !_authorized ||
          !_approved) {
        return;
      }
      await widget.onPreview(bytes);
    } on Object catch (e) {
      if (mounted && revision == _revision) {
        setState(
          () => _error = e is FormatException
              ? e.message
              : 'Não foi possível preparar a audição.',
        );
      }
    } finally {
      if (mounted && revision == _revision) setState(() => _busy = false);
    }
  }

  Future<void> _edit(int index) async {
    final section = _map!.sections[index];
    final result = await showDialog<RhythmSection>(
      context: context,
      builder: (_) => _RhythmEdit(section),
    );
    if (result == null || !mounted) return;
    await widget.onStop();
    if (!mounted) return;
    setState(() {
      _map = RhythmMap(_map!.duration, [..._map!.sections]..[index] = result);
      _approved = false;
    });
  }

  @override
  Widget build(BuildContext context) => ExpansionTile(
    title: const Text('Analisar ritmo de uma gravação'),
    subtitle: const Text('WAV local · mapa revisto antes de tocar'),
    children: [
      const Text(
        'Analisa o ficheiro completo. A estimativa pode confundir subdivisões, compassos e rubato; reveja cada trecho antes de ouvir com o clique.',
      ),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        value: _authorized,
        title: const Text(
          'Esta gravação é minha ou tenho autorização para a processar.',
        ),
        onChanged: _busy
            ? null
            : (value) => setState(() => _authorized = value ?? false),
      ),
      OutlinedButton(
        onPressed: widget.enabled && _authorized && !_busy ? _choose : null,
        child: Text(_busy ? 'A processar…' : 'Escolher gravação WAV'),
      ),
      if (_name != null) Text(_name!),
      if (_map != null && _map!.sections.isEmpty)
        const Text(
          'Não foi identificado um pulso estável. Nenhum clique será gerado.',
        ),
      if (_map != null) ...[
        for (var i = 0; i < _map!.sections.length; i++)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
              '${_map!.sections[i].start.toStringAsFixed(1)}–${_map!.sections[i].end.toStringAsFixed(1)} s · ${_map!.sections[i].bpm.toStringAsFixed(1)} BPM',
            ),
            subtitle: Text(
              '${_map!.sections[i].beatsPerBar == null ? 'Compasso por confirmar' : '${_map!.sections[i].beatsPerBar} batidas/compasso (estimativa)'} · regularidade ${(_map!.sections[i].confidence * 100).round()}%',
            ),
            trailing: const Icon(Icons.edit_outlined),
            onTap: _busy ? null : () => _edit(i),
          ),
        if (_map!.sections.isNotEmpty) ...[
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _approved,
            title: const Text(
              'Revi o BPM, o compasso e a primeira batida de todos os trechos.',
            ),
            onChanged: _busy
                ? null
                : (value) => setState(() => _approved = value ?? false),
          ),
          FilledButton.icon(
            onPressed: widget.playing
                ? widget.onStop
                : widget.enabled &&
                      !_busy &&
                      _approved &&
                      _authorized &&
                      _map!.sections.every((s) => s.beatsPerBar != null)
                ? _preview
                : null,
            icon: Icon(widget.playing ? Icons.stop : Icons.headphones),
            label: Text(
              widget.playing ? 'Parar audição' : 'Ouvir gravação com metrónomo',
            ),
          ),
        ],
      ],
      if (_error != null)
        Text(
          _error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      const SizedBox(height: 8),
    ],
  );
}

class _RhythmEdit extends StatefulWidget {
  const _RhythmEdit(this.section);
  final RhythmSection section;
  @override
  State<_RhythmEdit> createState() => _RhythmEditState();
}

class _RhythmEditState extends State<_RhythmEdit> {
  late final _bpm = TextEditingController(
    text: widget.section.bpm.toStringAsFixed(1),
  );
  late final _start = TextEditingController(
    text: widget.section.firstBeat.toStringAsFixed(3),
  );
  late int? _beats = widget.section.beatsPerBar;
  String? _error;
  @override
  void dispose() {
    _bpm.dispose();
    _start.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rever trecho'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _bpm,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'BPM (40–240)'),
          ),
          TextField(
            controller: _start,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Primeira batida acentuada (segundos)',
            ),
          ),
          DropdownButtonFormField<int>(
            initialValue: _beats,
            decoration: const InputDecoration(
              labelText: 'Batidas por compasso',
            ),
            items: [
              for (var n = 1; n <= 12; n++)
                DropdownMenuItem(value: n, child: Text('$n')),
            ],
            onChanged: (n) => setState(() => _beats = n),
          ),
          if (_error != null) Text(_error!),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          final bpm = double.tryParse(_bpm.text.replaceAll(',', '.'));
          final start = double.tryParse(_start.text.replaceAll(',', '.'));
          if (bpm == null ||
              !bpm.isFinite ||
              bpm < 40 ||
              bpm > 240 ||
              _beats == null ||
              start == null ||
              !start.isFinite ||
              start < widget.section.start ||
              start >= widget.section.end) {
            setState(
              () => _error =
                  'Verifique o BPM, compasso e início dentro do trecho.',
            );
            return;
          }
          Navigator.pop(
            context,
            widget.section.corrected(bpm: bpm, beats: _beats, firstBeat: start),
          );
        },
        child: const Text('Aplicar'),
      ),
    ],
  );
}
