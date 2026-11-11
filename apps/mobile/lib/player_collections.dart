import 'package:flutter/material.dart';

import 'player_presets.dart';
import 'studio_native_pages.dart';
import 'studio_appearance.dart';

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
    this.appearance = const StudioAppearance(),
  });

  final PlayerPresetStore store;
  final bool setlist;
  final bool embedded;
  final Future<void> Function()? onAdd;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final StudioAppearance appearance;
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
      borderRadius: BorderRadius.circular(14),
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

  static const List<Color> _spotifyTiles = [
    Color(0xFF3B3F5C),
    Color(0xFF2F5552),
    Color(0xFF5C4430),
    Color(0xFF4F3550),
    Color(0xFF34495E),
  ];

  /// The song's picture: the video's thumbnail (square on Spotify, 16:9 on
  /// YouTube), or a coloured tile while offline or without one.
  Widget _spotifyThumbnail(PlayerPreset item, int index) {
    final double width = studioYouTubeSkin ? 80 : 48;
    final double height = studioYouTubeSkin ? 45 : 48;
    final double radius = studioYouTubeSkin ? 8 : 4;
    final Widget tile = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: _spotifyTiles[index % _spotifyTiles.length],
        borderRadius: BorderRadius.circular(radius),
      ),
      child: const Icon(
        Icons.music_note_outlined,
        color: Color(0xBFFFFFFF),
        size: 22,
      ),
    );
    final videoId = item.locator;
    if (!RegExp(r'^[\w-]{11}$').hasMatch(videoId)) return tile;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(
        'https://i.ytimg.com/vi/$videoId/mqdefault.jpg',
        key: ValueKey('setlistThumbnail-${item.id}'),
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => tile,
      ),
    );
  }

  /// A Spotify list row: square tile, title, a line under it, the menu.
  Widget _spotifyRow(int index) {
    final item = _items[index];
    final pitch =
        '${item.pitch > 0 ? '+' : ''}${item.pitch.toStringAsFixed(item.pitch % 1 == 0 ? 0 : 1)} st';
    return Material(
      key: ValueKey('collection-${item.id}'),
      type: MaterialType.transparency,
      child: InkWell(
        key: ValueKey('collectionOpen-${item.id}'),
        onTap: _busy ? null : () => _apply(item),
        onLongPress: _busy ? null : () => _setlistOptions(item, index),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              _spotifyThumbnail(item, index),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      '${item.youtube ? 'YouTube' : 'Ficheiro'} · $pitch · '
                      '${item.speed.toStringAsFixed(2)}×',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xBFFFFFFF),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: ValueKey('collectionMenu-${item.id}'),
                tooltip: 'Ordenar ou remover da setlist',
                onPressed: _busy ? null : () => _setlistOptions(item, index),
                icon: const Icon(Icons.more_vert, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The setlist inside the Spotify adjustments, laid out like its pages.
  Widget _spotifySetlist() {
    Widget icon(Key? key, String tip, IconData data, VoidCallback? onTap) =>
        IconButton(
          key: key,
          tooltip: tip,
          onPressed: _busy ? null : onTap,
          icon: Icon(data, color: Colors.white, size: 26),
        );
    final count = _items.length;
    return ListView(
      key: const Key('setlistHeader'),
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Minha setlist',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$count ${count == 1 ? 'música' : 'músicas'} · abre com os ajustes guardados',
                style: const TextStyle(fontSize: 13, color: Color(0xBFFFFFFF)),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              if (widget.onAdd != null)
                icon(
                  const Key('collectionAddCurrent'),
                  'Adicionar música atual',
                  Icons.add_circle_outline,
                  _addCurrent,
                ),
              icon(null, 'Atualizar coleção', Icons.refresh, _load),
              const Spacer(),
              if (widget.onPrevious != null)
                icon(
                  const Key('setlistPrevious'),
                  'Anterior da setlist',
                  Icons.skip_previous,
                  widget.onPrevious,
                ),
              if (widget.onNext != null)
                icon(
                  const Key('setlistNext'),
                  'Próxima da setlist',
                  Icons.skip_next,
                  widget.onNext,
                ),
            ],
          ),
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_error!, key: const Key('collectionError')),
          ),
        if (widget.onAdd != null)
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: _busy ? null : _addCurrent,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0x1AFFFFFF),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(Icons.add, color: Colors.white),
                    ),
                    const SizedBox(width: 14),
                    const Text(
                      'Adicionar à setlist',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          for (var index = 0; index < count; index++) _spotifyRow(index),
        if (count > 0)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              'Mantenha pressionado para ordenar ou remover.',
              style: TextStyle(fontSize: 12, color: Color(0xBFFFFFFF)),
            ),
          ),
      ],
    );
  }

  Future<void> _addCurrent() async {
    await widget.onAdd!();
    if (mounted) await _load();
  }

  Widget _row(int index) {
    final item = _items[index];
    if (widget.setlist) {
      return Container(
        key: ValueKey('collection-${item.id}'),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        decoration: studioPanelDecoration(
          radius: 23,
          mode: widget.appearance.mode,
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: ListTile(
            key: ValueKey('collectionOpen-${item.id}'),
            onTap: _busy ? null : () => _apply(item),
            onLongPress: _busy ? null : () => _setlistOptions(item, index),
            leading: _thumbnail(item),
            title: Text(
              item.title.trim().characters.take(55).toString(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            trailing: IconButton(
              key: ValueKey('collectionMenu-${item.id}'),
              tooltip: 'Ordenar ou remover da setlist',
              onPressed: _busy ? null : () => _setlistOptions(item, index),
              icon: const Icon(Icons.more_vert, size: 19),
            ),
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
    if (studioSpotifySkin && widget.embedded && widget.setlist) {
      return _spotifySetlist();
    }
    final content = Column(
      children: [
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(_error!, key: const Key('collectionError')),
          ),
        if (!_loading &&
            _items.isNotEmpty &&
            !(widget.embedded && widget.setlist))
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
                  Container(
                    key: const Key('setlistHeader'),
                    margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    padding: const EdgeInsets.fromLTRB(12, 5, 8, 5),
                    decoration: studioPanelDecoration(
                      radius: 26,
                      mode: widget.appearance.mode,
                    ),
                    child: Row(
                      children: [
                        if (widget.setlist) ...[
                          const Icon(Icons.queue_music, size: 19),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            widget.setlist
                                ? 'Minha setlist'
                                : 'Predefinições guardadas',
                            maxLines: 1,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (widget.onAdd != null)
                          IconButton(
                            key: const Key('collectionAddCurrent'),
                            tooltip: 'Adicionar música atual',
                            constraints: const BoxConstraints.tightFor(
                              width: 34,
                              height: 34,
                            ),
                            style: IconButton.styleFrom(
                              fixedSize: const Size(34, 34),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              padding: EdgeInsets.zero,
                            ),
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
                            constraints: const BoxConstraints.tightFor(
                              width: 34,
                              height: 34,
                            ),
                            style: IconButton.styleFrom(
                              fixedSize: const Size(34, 34),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              padding: EdgeInsets.zero,
                            ),
                            onPressed: _busy ? null : widget.onPrevious,
                            icon: const Icon(Icons.skip_previous),
                          ),
                        if (widget.onNext != null)
                          IconButton(
                            key: const Key('setlistNext'),
                            tooltip: 'Próxima da setlist',
                            constraints: const BoxConstraints.tightFor(
                              width: 34,
                              height: 34,
                            ),
                            style: IconButton.styleFrom(
                              fixedSize: const Size(34, 34),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              padding: EdgeInsets.zero,
                            ),
                            onPressed: _busy ? null : widget.onNext,
                            icon: const Icon(Icons.skip_next),
                          ),
                        IconButton(
                          tooltip: 'Atualizar coleção',
                          constraints: const BoxConstraints.tightFor(
                            width: 34,
                            height: 34,
                          ),
                          style: IconButton.styleFrom(
                            fixedSize: const Size(34, 34),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            padding: EdgeInsets.zero,
                          ),
                          onPressed: _busy ? null : _load,
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                  ),
                  if (widget.setlist && !_loading && _items.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(24, 2, 24, 4),
                      child: Text(
                        'Toque num item para abrir com os ajustes guardados, sem reprodução automática. Mantenha pressionado para ordenar ou remover.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFFB7B7BD),
                        ),
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
