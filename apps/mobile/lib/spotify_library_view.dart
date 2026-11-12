import 'dart:async';

import 'package:flutter/material.dart';

import 'spotify_library.dart';
import 'studio_appearance.dart';

/// The segments of the library: «Tudo» and one per kind.
enum SpotifyLibrarySegment { all, artists, tracks, playlists, albums }

extension on SpotifyLibrarySegment {
  String get label => switch (this) {
    SpotifyLibrarySegment.all => 'Tudo',
    SpotifyLibrarySegment.artists => 'Artistas',
    SpotifyLibrarySegment.tracks => 'Músicas',
    SpotifyLibrarySegment.playlists => 'Playlists',
    SpotifyLibrarySegment.albums => 'Álbuns',
  };

  bool includes(SpotifyLibraryKind kind) => switch (this) {
    SpotifyLibrarySegment.all => true,
    SpotifyLibrarySegment.artists => kind == SpotifyLibraryKind.artist,
    SpotifyLibrarySegment.tracks =>
      kind == SpotifyLibraryKind.track || kind == SpotifyLibraryKind.episode,
    SpotifyLibrarySegment.playlists => kind == SpotifyLibraryKind.playlist,
    SpotifyLibrarySegment.albums => kind == SpotifyLibraryKind.album,
  };
}

String _kindLabel(SpotifyLibraryKind kind) => switch (kind) {
  SpotifyLibraryKind.artist => 'Artista',
  SpotifyLibraryKind.track => 'Música',
  SpotifyLibraryKind.album => 'Álbum',
  SpotifyLibraryKind.playlist => 'Playlist',
  SpotifyLibraryKind.show => 'Podcast',
  SpotifyLibraryKind.episode => 'Episódio',
};

/// Transpono's library for the Spotify source, in Spotify's own look: what
/// the user followed, hearted or saved in the Spotify page.
class SpotifyLibraryView extends StatefulWidget {
  const SpotifyLibraryView({
    super.key,
    required this.store,
    required this.onOpen,
  });

  final SpotifyLibraryStore store;
  final ValueChanged<SpotifyLibraryItem> onOpen;

  static const String emptyText =
      'Ainda não há nada na tua biblioteca. Toca em Seguir, ♡ ou Guardar no '
      'Spotify e aparece aqui.';
  static const String localNote =
      'Guardada só neste telemóvel; não sincroniza com a conta Spotify.';

  @override
  State<SpotifyLibraryView> createState() => _SpotifyLibraryViewState();
}

class _SpotifyLibraryViewState extends State<SpotifyLibraryView> {
  SpotifyLibrarySegment _segment = SpotifyLibrarySegment.all;

  // Swiped away: out of the list at once, before the store says so.
  final Set<String> _dismissed = <String>{};

  void _remove(String url) => widget.store.remove(url).ignore();

  @override
  Widget build(BuildContext context) {
    final double top = MediaQuery.paddingOf(context).top;
    return Material(
      key: const Key('spotifyLibrary'),
      color: spotifyBase,
      child: DefaultTextStyle(
        style: const TextStyle(color: Colors.white),
        child: AnimatedBuilder(
          animation: widget.store,
          builder: (BuildContext context, Widget? _) {
            // Gone from the store: a later save of it shows again.
            _dismissed.removeWhere((String url) => !widget.store.contains(url));
            final List<SpotifyLibraryItem> items = <SpotifyLibraryItem>[
              for (final SpotifyLibraryItem item in widget.store.items)
                if (_segment.includes(item.kind) &&
                    !_dismissed.contains(item.url))
                  item,
            ];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: top + 12),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'A tua biblioteca',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Text(
                    SpotifyLibraryView.localNote,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: spotifySubdued, fontSize: 12),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      for (final SpotifyLibrarySegment segment
                          in SpotifyLibrarySegment.values)
                        _chip(segment),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: items.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 32),
                            child: Text(
                              SpotifyLibraryView.emptyText,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: spotifySubdued,
                                fontSize: 15,
                                height: 1.4,
                              ),
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 16),
                          itemCount: items.length,
                          itemBuilder: (BuildContext context, int index) =>
                              _row(items[index]),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _chip(SpotifyLibrarySegment segment) {
    final bool on = segment == _segment;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: on ? spotifyGreen : const Color(0x1AFFFFFF),
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => setState(() => _segment = segment),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Center(
              child: Text(
                segment.label,
                style: TextStyle(
                  color: on ? Colors.black : Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cover(SpotifyLibraryItem item) {
    final bool round = item.kind == SpotifyLibraryKind.artist;
    final IconData fallback = switch (item.kind) {
      SpotifyLibraryKind.artist => Icons.person,
      SpotifyLibraryKind.track => Icons.music_note,
      SpotifyLibraryKind.album => Icons.album,
      SpotifyLibraryKind.playlist => Icons.queue_music,
      SpotifyLibraryKind.show => Icons.podcasts,
      SpotifyLibraryKind.episode => Icons.podcasts,
    };
    final Widget placeholder = Container(
      color: const Color(0xFF282828),
      alignment: Alignment.center,
      child: Icon(fallback, color: spotifySubdued, size: 28),
    );
    final Widget image = item.image.isEmpty
        ? placeholder
        : Image.network(
            item.image,
            fit: BoxFit.cover,
            errorBuilder: (BuildContext context, Object error, StackTrace? _) =>
                placeholder,
          );
    return SizedBox(
      width: 56,
      height: 56,
      child: round
          ? ClipOval(child: image)
          : ClipRRect(borderRadius: BorderRadius.circular(4), child: image),
    );
  }

  Widget _row(SpotifyLibraryItem item) {
    final String kind = _kindLabel(item.kind);
    final String subtitle = item.subtitle.isEmpty
        ? kind
        : '$kind • ${item.subtitle}';
    return Dismissible(
      key: ValueKey<String>('spotifyLibrary:${item.url}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: const Color(0xFFE22134),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Text(
          'Remover',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
      onDismissed: (_) {
        setState(() => _dismissed.add(item.url));
        _remove(item.url);
      },
      child: InkWell(
        onTap: () => widget.onOpen(item),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
          child: Row(
            children: [
              _cover(item),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: spotifySubdued,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Mais opções',
                icon: const Icon(Icons.more_horiz, color: spotifySubdued),
                color: const Color(0xFF282828),
                onSelected: (String choice) {
                  if (choice == 'remove') _remove(item.url);
                },
                itemBuilder: (BuildContext context) =>
                    const <PopupMenuEntry<String>>[
                      PopupMenuItem<String>(
                        value: 'remove',
                        child: Text(
                          'Remover',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
