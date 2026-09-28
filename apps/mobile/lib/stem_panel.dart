import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Six-stem inference runs inside the Android app. Source files stay private.
class StemPanel extends StatefulWidget {
  const StemPanel({super.key, required this.onBeforePreview});

  final Future<void> Function() onBeforePreview;

  @override
  State<StemPanel> createState() => _StemPanelState();
}

class _StemPanelState extends State<StemPanel> with WidgetsBindingObserver {
  static const _channel = MethodChannel('transpose/stems');
  static const _maxBytes = 64 * 1024 * 1024;
  static const _names = <String, String>{
    'drums': 'Bateria',
    'bass': 'Baixo',
    'other': 'Outros',
    'vocals': 'Voz',
    'guitar': 'Guitarra',
    'piano': 'Piano',
  };

  Timer? _poller;
  AudioPlayer? _preview;
  StreamSubscription<void>? _complete;
  int _previewGeneration = 0;
  Future<void> _previewQueue = Future<void>.value();
  bool _starting = false;
  String? _input, _sourceName, _error, _playing;
  Map<String, String> _outputs = const {};
  String _phase = 'idle';
  int _progress = 0, _downloaded = 0;
  bool _available = false, _modelReady = false, _authorized = false;
  bool _copying = false;
  bool _busyNative = false;
  double _volume = .8;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      _available = await _channel.invokeMethod<bool>('available') ?? false;
      if (_available) await _refresh();
    } on MissingPluginException {
      _available = false;
    } on PlatformException catch (e) {
      _error = e.message;
    }
    if (mounted) setState(() {});
    if (!mounted) return;
    _poller = Timer.periodic(const Duration(milliseconds: 650), (_) {
      if (_available) unawaited(_refresh());
    });
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    try {
      final status = await _channel.invokeMapMethod<String, Object?>('status');
      if (status == null || !mounted) return;
      setState(() {
        _phase = status['phase'] as String? ?? 'idle';
        _busyNative = status['busy'] == true;
        _progress = status['progress'] as int? ?? 0;
        _downloaded = status['downloaded'] as int? ?? 0;
        _modelReady = status['modelReady'] == true;
        final paths = status['paths'];
        if (paths is Map) {
          _outputs = paths.map((key, value) => MapEntry('$key', '$value'));
        }
        if (_phase == 'error') _error = status['error'] as String?;
      });
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _prepare() async {
    setState(() => _error = null);
    try {
      await _channel.invokeMethod<void>('prepare');
      await _refresh();
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _choose() async {
    setState(() {
      _copying = true;
      _error = null;
    });
    File? destination;
    try {
      await _stopPreview();
      if (!mounted) return;
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['wav'],
      );
      if (picked == null || !mounted) return;
      final length = picked.lengthSync();
      if (length == null || length < 44 || length > _maxBytes) {
        throw const FormatException('Escolha um WAV local até 64 MB.');
      }
      final cache = Directory(
        '${(await getTemporaryDirectory()).path}/stem_inputs',
      );
      await cache.create(recursive: true);
      destination = File(
        '${cache.path}/${DateTime.now().microsecondsSinceEpoch}.wav',
      );
      final sink = destination.openWrite();
      var count = 0;
      try {
        await for (final chunk in picked.readAsByteStream()) {
          if (!mounted) throw StateError('Painel fechado.');
          count += chunk.length;
          if (count > _maxBytes) {
            throw const FormatException('O WAV ultrapassa 64 MB.');
          }
          sink.add(chunk);
        }
      } finally {
        await sink.close();
      }
      if (count != length) {
        throw const FormatException('O WAV não foi copiado por completo.');
      }
      if (!mounted) throw StateError('Painel fechado.');
      setState(() {
        _input = destination!.path;
        _sourceName = picked.name;
      });
    } on Object catch (e) {
      if (destination != null && await destination.exists()) {
        await destination.delete();
      }
      if (mounted) {
        setState(
          () => _error = e is FormatException
              ? e.message
              : 'Não foi possível copiar o WAV selecionado.',
        );
      }
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  Future<void> _start() async {
    setState(() {
      _error = null;
    });
    try {
      await _stopPreview();
      if (!mounted) return;
      _starting = true;
      await _channel.invokeMethod<void>('start', {'input': _input});
      await _refresh();
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      _starting = false;
    }
  }

  Future<void> _cancel() async {
    try {
      await _channel.invokeMethod<void>('cancel');
      await _refresh();
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _queuePreview(Future<void> Function() action) {
    final operation = _previewQueue.then((_) => action());
    _previewQueue = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _stopPreview() async {
    ++_previewGeneration;
    await _queuePreview(() async => _preview?.stop());
    if (mounted) setState(() => _playing = null);
  }

  Future<void> _togglePreview(String name, String path) async {
    final generation = ++_previewGeneration;
    try {
      if (_playing == name) {
        await _stopPreview();
        return;
      }
      await widget.onBeforePreview();
      if (!mounted || generation != _previewGeneration) return;
      await _queuePreview(() async {
        if (!mounted || generation != _previewGeneration) return;
        final player = _preview ??= AudioPlayer();
        _complete ??= player.onPlayerComplete.listen((_) {
          if (mounted) setState(() => _playing = null);
        });
        await player.stop();
        if (!mounted || generation != _previewGeneration) return;
        await player.play(DeviceFileSource(path), volume: _volume);
        if (mounted && generation == _previewGeneration) {
          setState(() => _playing = name);
        }
      });
    } on Object {
      if (mounted) {
        setState(() => _error = 'Não foi possível ouvir este instrumento.');
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_stopPreview());
  }

  @override
  void dispose() {
    ++_previewGeneration;
    _poller?.cancel();
    if (_starting || _phase == 'downloading' || _phase == 'separating') {
      unawaited(
        _channel.invokeMethod<void>('cancel').catchError((Object _) {}),
      );
    }
    unawaited(_complete?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_queuePreview(() async => _preview?.dispose()));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final processing = _phase == 'downloading' || _phase == 'separating';
    final running = _busyNative || processing;
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'SEPARAÇÃO EXPERIMENTAL DE INSTRUMENTOS',
              style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: .7),
            ),
            const SizedBox(height: 8),
            const Text(
              'Seis pistas: bateria, baixo, outros, voz, guitarra e piano. A separação é aproximada e pode demorar vários minutos. O áudio é processado só neste telemóvel.',
            ),
            const Text(
              'Mantenha a app aberta; ao sair, a operação é cancelada.',
            ),
            const Text(
              'Motor demucs.cpp e modelo Retrobear: MIT. Eigen: MPL 2.0 e avisos BSD. Textos em assets/stems_licenses.',
            ),
            const SizedBox(height: 8),
            if (!_available)
              const Text(
                'Motor de separação indisponível nesta versão ou arquitetura Android.',
              ),
            if (_available) ...[
              Text(
                _modelReady ? 'Modelo verificado e pronto.' : 'Modelo necessário: 55 MB, descarregado uma vez por HTTPS e verificado por SHA-256.',
              ),
              if (!_modelReady)
                OutlinedButton.icon(
                  onPressed: running ? null : _prepare,
                  icon: const Icon(Icons.download),
                  label: const Text('Preparar modelo (55 MB)'),
                ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Tenho autorização para processar esta gravação.',
                ),
                value: _authorized,
                onChanged: running
                    ? null
                    : (value) => setState(() => _authorized = value ?? false),
              ),
              OutlinedButton.icon(
                onPressed: !_authorized || running || _copying ? null : _choose,
                icon: const Icon(Icons.audio_file_outlined),
                label: Text(_sourceName ?? 'Escolher WAV local'),
              ),
              const Text(
                'WAV PCM 16 bits · 44,1 kHz · mono/estéreo · 1 s–10 min · máximo 64 MB',
              ),
              if (_copying) const LinearProgressIndicator(),
              if (_phase == 'downloading')
                Text(
                  'Modelo: ${(_downloaded / 54855129 * 100).clamp(0, 100).toStringAsFixed(0)}%',
                ),
              if (_phase == 'separating') Text('Separação: $_progress%'),
              if (running) const LinearProgressIndicator(),
              Row(
                children: [
                  FilledButton(
                    onPressed:
                        _authorized &&
                            _modelReady &&
                            _input != null &&
                            !running &&
                            !_copying
                        ? _start
                        : null,
                    child: const Text('Separar neste telemóvel'),
                  ),
                  if (processing)
                    TextButton(
                      onPressed: _cancel,
                      child: const Text('Cancelar'),
                    ),
                ],
              ),
              if (_phase == 'cancelled') const Text('Operação cancelada.'),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (_outputs.isNotEmpty) ...[
                const Divider(),
                const Text(
                  'Última separação · ouvir uma pista de cada vez:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                Slider(
                  value: _volume,
                  onChanged: (value) {
                    setState(() => _volume = value);
                    unawaited(
                      _queuePreview(() async => _preview?.setVolume(value)),
                    );
                  },
                ),
                for (final item in _names.entries)
                  if (_outputs[item.key] case final String path)
                    ListTile(
                      dense: true,
                      title: Text(item.value),
                      subtitle: Text(
                        path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        tooltip: _playing == item.key
                            ? 'Parar ${item.value}'
                            : 'Ouvir ${item.value}',
                        onPressed: () => _togglePreview(item.key, path),
                        icon: Icon(
                          _playing == item.key ? Icons.stop : Icons.play_arrow,
                        ),
                      ),
                    ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
