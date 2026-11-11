import 'package:flutter_test/flutter_test.dart';
import 'package:transpose_mobile/spotify_browser.dart';
import 'package:transpose_mobile/spotify_sign_in.dart';

void main() {
  test('Spotify sign-in pages are recognised', () {
    expect(
      isSpotifySignInUri(Uri.parse('https://accounts.spotify.com/pt-PT/login')),
      isTrue,
    );
    expect(isSpotifySignInUri(Uri.parse('https://open.spotify.com/')), isFalse);
  });

  test('the sign-in page stays on Spotify and its sign-in providers', () {
    for (final url in [
      'https://accounts.spotify.com/login?continue=https%3A%2F%2Fopen.spotify.com%2F',
      'https://challenge.spotify.com/c/abc',
      'https://accounts.google.com/o/oauth2/auth',
      'https://appleid.apple.com/auth/authorize',
      'https://www.facebook.com/login.php',
    ]) {
      expect(isSpotifySignInPageUri(Uri.parse(url)), isTrue, reason: url);
    }
    expect(isSpotifySignInPageUri(Uri.parse('https://example.com/')), isFalse);
    expect(isSpotifySignInPageUri(Uri.parse('spotify:track:1')), isFalse);
  });

  test('the player page ends the sign-in', () {
    expect(SpotifySignInPage.start.host, 'accounts.spotify.com');
    expect(isSpotifySignedInLanding(Uri.parse('https://open.spotify.com/')), isTrue);
    expect(isSpotifySignedInLanding(SpotifySignInPage.start), isFalse);
  });
}
