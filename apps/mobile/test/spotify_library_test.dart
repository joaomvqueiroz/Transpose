import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transpose_mobile/spotify_library.dart';

SpotifyLibraryItem _item(String id, {SpotifyLibraryKind? kind}) =>
    SpotifyLibraryItem(
      kind: kind ?? SpotifyLibraryKind.artist,
      name: 'Item $id',
      url: 'https://open.spotify.com/${(kind ?? SpotifyLibraryKind.artist).name}/$id',
    );

void main() {
  setUp(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty(),
  );

  test('Spotify links become canonical item URLs', () {
    final a = canonicalSpotifyItemUrl(
      'https://open.spotify.com/intl-pt/artist/0OdUWJ0sBjDrqHygGUXeCF?si=abc',
    );
    expect(a?.kind, SpotifyLibraryKind.artist);
    expect(a?.url, 'https://open.spotify.com/artist/0OdUWJ0sBjDrqHygGUXeCF');
    expect(
      canonicalSpotifyItemUrl('/track/4uLU6hMCjMI75M1A2tKUQC/')?.url,
      'https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC',
    );
    expect(
      canonicalSpotifyItemUrl('https://open.spotify.com/album/1ATL5GLyefJaxhQzSPVrLX')
          ?.kind,
      SpotifyLibraryKind.album,
    );
    expect(canonicalSpotifyItemUrl('https://open.spotify.com/'), isNull);
    expect(canonicalSpotifyItemUrl('https://open.spotify.com/user/abcdefgh1'), isNull);
    expect(canonicalSpotifyItemUrl('https://example.com/artist/0OdUWJ0sBjDrqHygGUXeCF'), isNull);
    expect(canonicalSpotifyItemUrl('/collection'), isNull);
    expect(canonicalSpotifyItemUrl(null), isNull);
  });

  test('page events decode with their action; unusable ones are refused', () {
    final event = SpotifyLibraryEvent.decode(
      jsonEncode({
        'action': 'add',
        'kind': 'playlist',
        'name': '  Top   Hits ',
        'subtitle': 'Spotify',
        'url': 'https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M',
        'image': 'https://i.scdn.co/image/abc',
      }),
    );
    expect(event?.add, isTrue);
    expect(event?.item.kind, SpotifyLibraryKind.playlist);
    expect(event?.item.name, 'Top Hits');
    expect(event?.item.image, 'https://i.scdn.co/image/abc');

    final removed = SpotifyLibraryEvent.decode(
      jsonEncode({
        'action': 'remove',
        'kind': 'track',
        'name': 'Song',
        'url': '/intl-pt/track/4uLU6hMCjMI75M1A2tKUQC',
      }),
    );
    expect(removed?.add, isFalse);
    expect(removed?.item.url, 'https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC');

    expect(SpotifyLibraryEvent.decode('{broken'), isNull);
    expect(SpotifyLibraryEvent.decode(jsonEncode({'action': 'add'})), isNull);
    expect(
      SpotifyLibraryEvent.decode(
        jsonEncode({'action': 'toggle', 'name': 'x', 'url': '/artist/0OdUWJ0sBjDrqHygGUXeCF'}),
      ),
      isNull,
    );
    // An artist or album needs its page.
    expect(
      SpotifyLibraryEvent.decode(jsonEncode({'action': 'add', 'kind': 'artist', 'name': 'x'})),
      isNull,
    );
  });

  test('a song without a link is kept by its search page', () {
    final item = SpotifyLibraryItem.parse({
      'kind': 'track',
      'name': 'Garota de Ipanema',
      'subtitle': 'Tom Jobim',
      'url': '',
      'image': 'http://insecure/cover.jpg',
    });
    expect(item?.kind, SpotifyLibraryKind.track);
    expect(item?.url, 'https://open.spotify.com/search/Garota%20de%20Ipanema%20Tom%20Jobim');
    expect(item?.image, '');
  });

  test('items round-trip through JSON', () {
    const item = SpotifyLibraryItem(
      kind: SpotifyLibraryKind.album,
      name: 'Album',
      subtitle: 'Artist',
      url: 'https://open.spotify.com/album/1ATL5GLyefJaxhQzSPVrLX',
      image: 'https://i.scdn.co/image/x',
      addedAt: 42,
    );
    expect(SpotifyLibraryItem.parse(jsonDecode(jsonEncode(item.toJson()))), item);
  });

  test('adding puts the item first, once, and the list is capped', () {
    var list = <SpotifyLibraryItem>[];
    for (var i = 0; i < 5; i++) {
      list = spotifyLibraryWith(list, _item('aaaaaaaa$i'), cap: 3);
    }
    expect(list.map((e) => e.name), ['Item aaaaaaaa4', 'Item aaaaaaaa3', 'Item aaaaaaaa2']);
    list = spotifyLibraryWith(list, _item('aaaaaaaa2'), cap: 3);
    expect(list.map((e) => e.name), ['Item aaaaaaaa2', 'Item aaaaaaaa4', 'Item aaaaaaaa3']);
    list = spotifyLibraryWithout(list, _item('aaaaaaaa4').url);
    expect(list.map((e) => e.name), ['Item aaaaaaaa2', 'Item aaaaaaaa3']);
  });

  test('the store saves on the phone, newest first, and removes', () async {
    final store = SpotifyLibraryStore();
    await store.add(_item('bbbbbbbb1'), now: DateTime.fromMillisecondsSinceEpoch(1));
    await store.add(
      _item('bbbbbbbb2', kind: SpotifyLibraryKind.track),
      now: DateTime.fromMillisecondsSinceEpoch(2),
    );
    await store.apply(
      SpotifyLibraryEvent(add: true, item: _item('bbbbbbbb3', kind: SpotifyLibraryKind.album)),
    );
    expect(store.items.first.kind, SpotifyLibraryKind.album);

    final reopened = SpotifyLibraryStore();
    await reopened.load();
    expect(reopened.items.map((e) => e.name), [
      'Item bbbbbbbb3',
      'Item bbbbbbbb2',
      'Item bbbbbbbb1',
    ]);
    expect(reopened.items[1].addedAt, 2);

    await reopened.apply(
      SpotifyLibraryEvent(add: false, item: _item('bbbbbbbb2', kind: SpotifyLibraryKind.track)),
    );
    final again = SpotifyLibraryStore();
    await again.load();
    expect(again.items.map((e) => e.name), ['Item bbbbbbbb3', 'Item bbbbbbbb1']);
    expect(again.contains(_item('bbbbbbbb2', kind: SpotifyLibraryKind.track).url), isFalse);
  });

  test('the store keeps at most 500 items', () async {
    final store = SpotifyLibraryStore();
    for (var i = 0; i < SpotifyLibraryStore.cap + 5; i++) {
      await store.add(_item('cccccccc${i.toString().padLeft(4, '0')}'));
    }
    expect(store.items.length, SpotifyLibraryStore.cap);
    expect(store.items.first.name, 'Item cccccccc0504');
  });

  test('an unreadable library starts empty and is not overwritten', () async {
    final prefs = SharedPreferencesAsync();
    await prefs.setString(SpotifyLibraryStore.storageKey, '{broken');
    final store = SpotifyLibraryStore(preferences: prefs);
    await store.load();
    expect(store.items, isEmpty);
    expect(await prefs.getString(SpotifyLibraryStore.storageKey), '{broken');
  });

  test('stored entries that cannot be read are skipped', () async {
    final prefs = SharedPreferencesAsync();
    await prefs.setString(
      SpotifyLibraryStore.storageKey,
      jsonEncode([
        _item('dddddddd1').toJson(),
        {'kind': 'artist', 'name': ''},
        'junk',
        _item('dddddddd1').toJson(),
      ]),
    );
    final store = SpotifyLibraryStore(preferences: prefs);
    await store.load();
    expect(store.items.map((e) => e.name), ['Item dddddddd1']);
  });
}
