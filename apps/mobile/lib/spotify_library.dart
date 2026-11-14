import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What a saved Spotify item is. Spotify's mobile web player shows no
/// library of its own («Baixar app»), so Transpono keeps one on the phone.
enum SpotifyLibraryKind { artist, track, album, playlist, show, episode }

SpotifyLibraryKind? _kindFromName(Object? name) {
  for (final SpotifyLibraryKind kind in SpotifyLibraryKind.values) {
    if (kind.name == name) return kind;
  }
  return null;
}

/// `https://open.spotify.com/<kind>/<id>` for a link to one of Spotify's
/// pages (with or without `/intl-xx/`, a query or a trailing slash); null
/// for anything else.
({SpotifyLibraryKind kind, String url})? canonicalSpotifyItemUrl(
  String? text,
) {
  final Uri? uri = Uri.tryParse((text ?? '').trim());
  if (uri == null) return null;
  if (uri.hasScheme && uri.scheme != 'https' && uri.scheme != 'http') {
    return null;
  }
  if (uri.host.isNotEmpty && uri.host != 'open.spotify.com') return null;
  final List<String> parts = uri.pathSegments
      .where((String part) => part.isNotEmpty)
      .toList();
  if (parts.isNotEmpty && parts.first.startsWith('intl-')) {
    parts.removeAt(0);
  }
  if (parts.length < 2) return null;
  final SpotifyLibraryKind? kind = _kindFromName(parts[0]);
  final String id = parts[1];
  if (kind == null || !RegExp(r'^[A-Za-z0-9]{8,40}$').hasMatch(id)) {
    return null;
  }
  return (kind: kind, url: 'https://open.spotify.com/${kind.name}/$id');
}

/// A song with no link of its own (the open player's heart): its search
/// page on Spotify stands for it.
String spotifySearchUrl(String query) =>
    'https://open.spotify.com/search/${Uri.encodeComponent(query.trim())}';

/// One artist, song, album, playlist or podcast in Transpono's library.
@immutable
class SpotifyLibraryItem {
  const SpotifyLibraryItem({
    required this.kind,
    required this.name,
    required this.url,
    this.subtitle = '',
    this.image = '',
    this.addedAt = 0,
  });

  final SpotifyLibraryKind kind;
  final String name, subtitle, url, image;

  /// Milliseconds since the epoch.
  final int addedAt;

  /// Search text for the song (title and artist).
  String get query => subtitle.isEmpty ? name : '$name $subtitle';

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'name': name,
    'subtitle': subtitle,
    'url': url,
    'image': image,
    'addedAt': addedAt,
  };

  /// A stored or page-sent item; null when it is unusable. The URL becomes
  /// the canonical one; a song without one gets its search page.
  static SpotifyLibraryItem? parse(Object? raw) {
    if (raw is! Map) return null;
    final String name = _clean(raw['name'], 200);
    if (name.isEmpty) return null;
    final String subtitle = _clean(raw['subtitle'], 200);
    final canonical = canonicalSpotifyItemUrl('${raw['url'] ?? ''}');
    final SpotifyLibraryKind kind;
    final String url;
    if (canonical != null) {
      kind = canonical.kind;
      url = canonical.url;
    } else if (_kindFromName(raw['kind']) == SpotifyLibraryKind.track) {
      kind = SpotifyLibraryKind.track;
      final String given = '${raw['url'] ?? ''}'.trim();
      url = given.startsWith('https://open.spotify.com/search/')
          ? given
          : spotifySearchUrl(subtitle.isEmpty ? name : '$name $subtitle');
    } else {
      return null;
    }
    final String image = _clean(raw['image'], 1000);
    final Object? added = raw['addedAt'];
    return SpotifyLibraryItem(
      kind: kind,
      name: name,
      subtitle: subtitle,
      url: url,
      image: image.startsWith('https://') ? image : '',
      addedAt: added is num && added.isFinite ? added.toInt() : 0,
    );
  }

  SpotifyLibraryItem copyWith({int? addedAt}) => SpotifyLibraryItem(
    kind: kind,
    name: name,
    subtitle: subtitle,
    url: url,
    image: image,
    addedAt: addedAt ?? this.addedAt,
  );

  @override
  bool operator ==(Object other) =>
      other is SpotifyLibraryItem &&
      other.kind == kind &&
      other.name == name &&
      other.subtitle == subtitle &&
      other.url == url &&
      other.image == image &&
      other.addedAt == addedAt;

  @override
  int get hashCode => Object.hash(kind, name, subtitle, url, image, addedAt);
}

String _clean(Object? value, int max) {
  final String text = '${value ?? ''}'.replaceAll(RegExp(r'\s+'), ' ').trim();
  return text.length > max ? text.substring(0, max) : text;
}

/// A follow, a heart or a save tapped in the Spotify page (`add`), or its
/// undoing (`remove`).
@immutable
class SpotifyLibraryEvent {
  const SpotifyLibraryEvent({required this.add, required this.item});

  final bool add;
  final SpotifyLibraryItem item;

  /// `{"action": "add"|"remove", "kind", "name", "subtitle", "url",
  /// "image"}` from the page.
  static SpotifyLibraryEvent? decode(String text) {
    Object? raw;
    try {
      raw = jsonDecode(text);
    } on FormatException {
      return null;
    }
    if (raw is! Map) return null;
    final Object? action = raw['action'];
    if (action != 'add' && action != 'remove') return null;
    final SpotifyLibraryItem? item = SpotifyLibraryItem.parse(raw);
    if (item == null) return null;
    return SpotifyLibraryEvent(add: action == 'add', item: item);
  }
}

/// [items] with [item] first (an older copy of the same URL goes), at most
/// [cap] long.
List<SpotifyLibraryItem> spotifyLibraryWith(
  List<SpotifyLibraryItem> items,
  SpotifyLibraryItem item, {
  int cap = SpotifyLibraryStore.cap,
}) {
  final List<SpotifyLibraryItem> next = <SpotifyLibraryItem>[
    item,
    for (final SpotifyLibraryItem other in items)
      if (other.url != item.url) other,
  ];
  return next.length > cap ? next.sublist(0, cap) : next;
}

/// [items] without the one at [url].
List<SpotifyLibraryItem> spotifyLibraryWithout(
  List<SpotifyLibraryItem> items,
  String url,
) => <SpotifyLibraryItem>[
  for (final SpotifyLibraryItem item in items)
    if (item.url != url) item,
];

/// The library, kept only on this phone (SharedPreferences), newest first.
class SpotifyLibraryStore extends ChangeNotifier {
  SpotifyLibraryStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  /// The one the app uses.
  static final SpotifyLibraryStore instance = SpotifyLibraryStore();

  static const String storageKey = 'transpono.spotify.library.v1';
  static const int cap = 500;

  final SharedPreferencesAsync _preferences;
  List<SpotifyLibraryItem> _items = const <SpotifyLibraryItem>[];
  Future<void>? _loading;
  Future<void> _tail = Future<void>.value();

  List<SpotifyLibraryItem> get items => _items;

  bool contains(String url) => _items.any((item) => item.url == url);

  /// Reads the saved library once; later calls wait for the same read.
  Future<void> load() => _loading ??= _read();

  Future<void> _read() async {
    try {
      final String? raw = await _preferences.getString(storageKey);
      if (raw == null) return;
      final Object? value = jsonDecode(raw);
      if (value is! List) return;
      final List<SpotifyLibraryItem> read = <SpotifyLibraryItem>[];
      final Set<String> seen = <String>{};
      for (final Object? entry in value) {
        final SpotifyLibraryItem? item = SpotifyLibraryItem.parse(entry);
        if (item != null && seen.add(item.url)) read.add(item);
        if (read.length >= cap) break;
      }
      // Anything added while reading stays on top.
      List<SpotifyLibraryItem> merged = read;
      for (final SpotifyLibraryItem item in _items.reversed) {
        merged = spotifyLibraryWith(merged, item);
      }
      _items = List<SpotifyLibraryItem>.unmodifiable(merged);
      notifyListeners();
    } on Object {
      // An unreadable library starts empty; it is not overwritten until
      // something new is saved.
    }
  }

  Future<void> add(SpotifyLibraryItem item, {DateTime? now}) async {
    await load();
    _set(
      spotifyLibraryWith(
        _items,
        item.copyWith(
          addedAt: (now ?? DateTime.now()).millisecondsSinceEpoch,
        ),
      ),
    );
    await _save();
  }

  Future<void> remove(String url) async {
    await load();
    if (!contains(url)) return;
    _set(spotifyLibraryWithout(_items, url));
    await _save();
  }

  /// What the Spotify page reported.
  Future<void> apply(SpotifyLibraryEvent event) =>
      event.add ? add(event.item) : remove(event.item.url);

  void _set(List<SpotifyLibraryItem> next) {
    _items = List<SpotifyLibraryItem>.unmodifiable(next);
    notifyListeners();
  }

  Future<void> _save() {
    final String data = jsonEncode(<Object?>[
      for (final SpotifyLibraryItem item in _items) item.toJson(),
    ]);
    final Future<void> result = _tail.then(
      (_) => _preferences.setString(storageKey, data),
    );
    _tail = result.catchError((Object _) {});
    return result;
  }
}
