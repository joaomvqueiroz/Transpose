import 'package:flutter_test/flutter_test.dart';
import 'package:transpose_mobile/spotify_browser.dart';

void main() {
  test('Spotify player stays on Spotify and its sign-in pages', () {
    expect(isSpotifyBrowserUri(Uri.parse('https://open.spotify.com/')), isTrue);
    expect(
      isSpotifyBrowserUri(Uri.parse('https://accounts.spotify.com/login')),
      isTrue,
    );
    expect(
      isSpotifyBrowserUri(Uri.parse('https://accounts.google.com/o/oauth2')),
      isTrue,
    );
    expect(isSpotifyBrowserUri(Uri.parse('http://open.spotify.com/')), isFalse);
    expect(isSpotifyBrowserUri(Uri.parse('spotify:track:abc')), isFalse);
    expect(
      isSpotifyBrowserUri(Uri.parse('https://apps.apple.com/app/spotify')),
      isFalse,
    );
    expect(isSpotifyBrowserUri(Uri.parse('https://evilspotify.com/')), isFalse);
  });

  test('track comes from Media Session first', () {
    final track = SpotifyTrack.decode(
      '{"title":"What A Beautiful Name","artist":"Hillsong Worship",'
      '"documentTitle":"Spotify – Web Player"}',
    );
    expect(track, const SpotifyTrack(
      title: 'What A Beautiful Name',
      artist: 'Hillsong Worship',
    ));
    expect(track!.query, 'What A Beautiful Name Hillsong Worship');
  });

  test('track falls back to the "Song • Artist" tab title', () {
    final track = SpotifyTrack.decode(
      '"{\\"title\\":\\"\\",\\"artist\\":\\"\\",'
      '\\"documentTitle\\":\\"Oceans • Hillsong UNITED\\"}"',
    );
    expect(track?.title, 'Oceans');
    expect(track?.artist, 'Hillsong UNITED');
  });

  test('no track while nothing plays', () {
    expect(
      SpotifyTrack.decode(
        '{"title":"","artist":"","documentTitle":"Spotify – Web Player"}',
      ),
      isNull,
    );
    expect(SpotifyTrack.fromDocumentTitle('Spotify • Web Player'), isNull);
    expect(SpotifyTrack.decode('not json'), isNull);
  });
}
