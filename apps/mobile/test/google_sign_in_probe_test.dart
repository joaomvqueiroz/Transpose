import 'package:flutter_test/flutter_test.dart';
import 'package:transpose_mobile/google_sign_in_probe.dart';

void main() {
  test('the sign-in probe stays on Google and YouTube pages', () {
    bool ok(String url) => isGoogleSignInProbeUri(Uri.parse(url));
    expect(ok(GoogleSignInProbePage.start.toString()), isTrue);
    expect(ok('https://accounts.google.com/v3/signin/challenge/pwd'), isTrue);
    expect(ok('https://accounts.youtube.com/accounts/SetSID'), isTrue);
    expect(ok('https://www.google.pt/accounts/SetSID'), isTrue);
    expect(ok('https://m.youtube.com/'), isTrue);
    expect(ok('https://music.youtube.com/'), isTrue);
    expect(ok('http://accounts.google.com/'), isFalse);
    expect(ok('https://evil.example/accounts.google.com'), isFalse);
    expect(ok('https://google.com.evil.example/'), isFalse);
  });
}
