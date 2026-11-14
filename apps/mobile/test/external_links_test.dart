import 'package:flutter_test/flutter_test.dart';
import 'package:transpose_mobile/external_links.dart';

void main() {
  test('web, email and phone links open outside; app schemes do not', () {
    expect(opensOutside(Uri.parse('https://example.com/x')), isTrue);
    expect(opensOutside(Uri.parse('mailto:a@example.com')), isTrue);
    expect(opensOutside(Uri.parse('tel:+351000000000')), isTrue);
    expect(opensOutside(Uri.parse('spotify:track:abc')), isFalse);
    expect(opensOutside(Uri.parse('intent://x#Intent;end')), isFalse);
  });

  test("YouTube's leave-YouTube page leads straight to its site", () {
    final Uri page = Uri.parse(
      'https://m.youtube.com/redirect?event=video_description&q=https%3A%2F%2Fexample.com%2Fcifra&v=abc',
    );
    expect(youtubeRedirectTarget(page), Uri.parse('https://example.com/cifra'));
    expect(
      youtubeRedirectTarget(Uri.parse('https://m.youtube.com/watch?v=abc')),
      isNull,
    );
    expect(
      youtubeRedirectTarget(
        Uri.parse('https://evil.example/redirect?q=https://x.com'),
      ),
      isNull,
    );
    expect(
      youtubeRedirectTarget(
        Uri.parse('https://m.youtube.com/redirect?q=javascript:alert(1)'),
      ),
      isNull,
    );
  });
}
