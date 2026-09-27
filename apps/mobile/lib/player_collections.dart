import 'package:flutter/material.dart';

import 'player_presets.dart';

/// User-owned, persistent collections. Choosing an entry asks the existing
/// player to restore it; this screen never creates a second media session.
class PlayerCollectionsPage extends StatefulWidget {
  const PlayerCollectionsPage({
    super.key,
    required this.store,
    required this.onApply,
    this.setlist = false,
    this.embedded = false,
    this.onAdd,
    this.onPrevious,
    this.onNext,
  });

  final PlayerPresetStore store;
  final bool setlist;
  final bool embedded;
  final Future<void> Function()? onAdd;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final Future<void> Function(PlayerPreset preset) onApply;

  @override
  State<PlayerCollectionsPage> createState() => _PlayerCollectionsPageState();
}

class _PlayerCollectionsPageState extends State<PlayerCollectionsPage> {
  List<PlayerPreset> _items = const [];
  bool _loading = true, _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await widget.store.list(setlist: widget.setlist);
      if (mounted) {
        setState(() {
          _items = items;
          _loading = false;
          _error = null;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Não foi possível ler a coleção. $error';
        });
      }
    }
  }

  Future<void> _change(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      await _load();
    } on Object catch (error) {
      if (mounted) setState(() => _error = 'Não foi possível guardar. $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply(PlayerPreset item) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onApply(item);
      if (mounted && !widget.embedded) Navigator.of(context).pop();
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = 'Não foi possível abrir este item. $error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rename(PlayerPreset item) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _RenameDialog(name: item.name),
    );
    if (!mounted || name == null || name == item.name) return;
    await _change(
      () => widget.store.rename(item.id, name, setlist: widget.setlist),
    );
  }

  Future<void> _delete(PlayerPreset item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remover da coleção?'),
        content: Text(
          'Remover “${item.name}”? Apenas os ajustes guardados serão removidos. '
          'O ficheiro original ou vídeo do YouTube não será apagado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('collectionConfirmDelete'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    await _change(() => widget.store.delete(item.id, setlist: widget.setlist));
  }

  Future<void> _move(int from, int to) async {
    if (_busy || from == to || to < 0 || to >= _items.length) return;
    final ids = _items.map((item) => item.id).toList();
    ids.insert(to, ids.removeAt(from));
    await _change(() => widget.store.reorder(ids, setlist: widget.setlist));
  }

  Future<void> _setlistOptions(PlayerPreset item, int index) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (index > 0)
              ListTile(
                key: const Key('setlistMoveUp'),
                leading: const Icon(Icons.arrow_upward),
                title: const Text('Mover para cima'),
                onTap: () => Navigator.pop(sheet, 'up'),
              ),
            if (index < _items.length - 1)
              ListTile(
                key: const Key('setlistMoveDown'),
                leading: const Icon(Icons.arrow_downward),
                title: const Text('Mover para baixo'),
                onTap: () => Navigator.pop(sheet, 'down'),
              ),
            ListTile(
              key: const Key('setlistRemove'),
              leading: const Icon(Icons.delete_outline),
              title: const Text('Remover da setlist'),
              onTap: () => Navigator.pop(sheet, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'up') await _move(index, index - 1);
    if (action == 'down') await _move(index, index + 1);
    if (action == 'delete') await _delete(item);
  }

  Widget _thumbnail(PlayerPreset item) {
    final videoId = item.locator;
    if (!item.youtube || !RegExp(r'^[\w-]{11}$').hasMatch(videoId)) {
      return const SizedBox(
        width: 72,
        height: 48,
        child: Icon(Icons.music_note),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.network(
        'https://i.ytimg.com/vi/$videoId/mqdefault.jpg',
        key: ValueKey('setlistThumbnail-${item.id}'),
        width: 72,
        height: 48,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const SizedBox(
          width: 72,
          height: 48,
          child: Icon(Icons.ondemand_video),
        ),
      ),
    );
  }

  Widget _row(int index) {
    final item = _items[index];
    if (widget.setlist) {
      return Card(
        key: ValueKey('collection-${item.id}'),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: ListTile(
          key: ValueKey('collectionOpen-${item.id}'),
          onTap: _busy ? null : () => _apply(item),
          onLongPress: _busy ? null : () => _setlistOptions(item, index),
          leading: _thumbnail(item),
          title: Text(
            item.title.trim().characters.take(55).toString(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }
    return Card(
      key: ValueKey('collection-${item.id}'),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            ListTile(
              key: ValueKey('collectionOpen-${item.id}'),
              onTap: _busy ? null : () => _apply(item),
              leading: Icon(
                item.youtube ? Icons.ondemand_video : Icons.audio_file,
              ),
              title: Text(item.name),
              subtitle: Text(
                '${item.title}\n'
                '${item.youtube ? 'YouTube' : 'Ficheiro local'} · '
                '${item.pitch > 0 ? '+' : ''}${item.pitch.toStringAsFixed(item.pitch % 1 == 0 ? 0 : 1)} st · '
                '${item.speed.toStringAsFixed(2)}×\n'
                'Posição ${_time(item.positionMs)}'
                '${item.aMs != null && item.bMs != null ? ' · A/B ${_time(item.aMs!)}–${_time(item.bMs!)} (${item.loop ? 'ligado' : 'desligado'})' : ''}',
              ),
              isThreeLine: true,
              trailing: PopupMenuButton<String>(
                key: ValueKey('collectionMenu-${item.id}'),
                tooltip: 'Opções de ${item.name}',
                enabled: !_busy,
                onSelected: (action) {
                  if (action == 'rename') _rename(item);
                  if (action == 'delete') _delete(item);
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'rename', child: Text('Renomear')),
                  PopupMenuItem(value: 'delete', child: Text('Remover')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: [
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(_error!, key: const Key('collectionError')),
          ),
        if (!_loading && _items.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              'Toque num item para abrir com os ajustes guardados, sem reprodução automática.'
              '${widget.setlist ? ' Mantenha pressionado para ordenar ou remover.' : ''}',
            ),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _items.isEmpty
              ? Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          widget.setlist
                              ? Icons.queue_music
                              : Icons.bookmarks_outlined,
                          size: 52,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _error != null
                              ? 'Os dados não foram alterados. Tente atualizar a coleção.'
                              : widget.setlist
                              ? 'A sua setlist está vazia. Abra uma música e use “Adicionar à setlist” no menu do player.'
                              : 'Ainda não há predefinições. Abra uma música, ajuste tom e velocidade e toque em “Guardar”.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : widget.setlist
              ? ListView.builder(
                  itemCount: _items.length,
                  itemBuilder: (context, index) => _row(index),
                )
              : ListView.builder(
                  itemCount: _items.length,
                  itemBuilder: (context, index) => _row(index),
                ),
        ),
      ],
    );
    if (widget.embedded) {
      return LayoutBuilder(
        builder: (context, constraints) => constraints.maxHeight < 130
            ? content
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.setlist
                                ? 'Minha setlist'
                                : 'Predefinições guardadas',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        if (widget.onAdd != null)
                          IconButton(
                            key: const Key('collectionAddCurrent'),
                            tooltip: 'Adicionar música atual',
                            onPressed: _busy
                                ? null
                                : () async {
                                    await widget.onAdd!();
                                    if (mounted) await _load();
                                  },
                            icon: const Icon(Icons.playlist_add),
                          ),
                        if (widget.onPrevious != null)
                          IconButton(
                            key: const Key('setlistPrevious'),
                            tooltip: 'Anterior da setlist',
                            onPressed: _busy ? null : widget.onPrevious,
                            icon: const Icon(Icons.skip_previous),
                          ),
                        if (widget.onNext != null)
                          IconButton(
                            key: const Key('setlistNext'),
                            tooltip: 'Próxima da setlist',
                            onPressed: _busy ? null : widget.onNext,
                            icon: const Icon(Icons.skip_next),
                          ),
                        IconButton(
                          tooltip: 'Atualizar coleção',
                          onPressed: _busy ? null : _load,
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                  ),
                  Expanded(child: content),
                ],
              ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.setlist ? 'Minha setlist' : 'Predefinições guardadas',
        ),
        actions: [
          IconButton(
            tooltip: 'Atualizar coleção',
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(child: content),
    );
  }
}

String _time(int milliseconds) {
  final seconds = milliseconds ~/ 1000;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.name});
  final String name;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.name,
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    if (_name.text.trim().isNotEmpty) Navigator.pop(context, _name.text.trim());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Renomear item'),
    content: TextField(
      key: const Key('collectionRenameInput'),
      controller: _name,
      autofocus: true,
      maxLength: 120,
      decoration: const InputDecoration(labelText: 'Nome'),
      textInputAction: TextInputAction.done,
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        key: const Key('collectionConfirmRename'),
        onPressed: _name.text.trim().isEmpty ? null : _submit,
        child: const Text('Guardar nome'),
      ),
    ],
  );
}
