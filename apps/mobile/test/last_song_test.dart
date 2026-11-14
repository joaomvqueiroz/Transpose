import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transpose_mobile/last_song.dart';
import 'package:transpose_mobile/player_presets.dart';

PlayerPreset _song() => const PlayerPreset(
  id: '1',
  name: 'Teu Reino',
  title: 'Teu Reino',
  sourceId: 'aqz-KE-bpKQ',
  locator: 'aqz-KE-bpKQ',
  youtube: true,
  pitch: -2,
  speed: .9,
  positionMs: 61000,
);

void main() {
  setUp(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty(),
  );

  test('the last song comes back for the same site only', () async {
    final memory = LastSong();
    await memory.remember(_song(), 'm.youtube.com');
    final back = await LastSong().read('m.youtube.com');
    expect(back?.locator, 'aqz-KE-bpKQ');
    expect(back?.pitch, -2);
    expect(back?.positionMs, 61000);
    expect(await LastSong().read('music.youtube.com'), isNull);
  });

  test('an old or forgotten song is not offered', () async {
    final memory = LastSong();
    await memory.remember(_song(), 'm.youtube.com');
    expect(await memory.read('m.youtube.com', maxAge: Duration.zero), isNull);
    await memory.forget();
    expect(await memory.read('m.youtube.com'), isNull);
  });
}
