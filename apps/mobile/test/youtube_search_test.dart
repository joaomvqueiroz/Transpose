import 'package:flutter_test/flutter_test.dart';
import 'package:transpose_mobile/youtube_search.dart';

void main() {
  test('YouTube search URI encodes the query without processing media', () {
    final Uri uri = youtubeSearchUri('  Sultans of Swing & guitar  ');
    expect(uri.scheme, 'https');
    expect(uri.host, 'm.youtube.com');
    expect(uri.path, '/results');
    expect(uri.queryParameters['search_query'], 'Sultans of Swing & guitar');
  });

  test('empty query is rejected', () {
    expect(() => youtubeSearchUri('   '), throwsArgumentError);
  });

  test('navigation accepts exact hosts and keeps YouTube intents internal', () {
    expect(
      embeddedYouTubeUri('https://m.youtube.com/watch?v=aqz-KE-bpKQ')?.host,
      'm.youtube.com',
    );
    expect(
      embeddedYouTubeUri(
        'intent://www.youtube.com/watch?v=aqz-KE-bpKQ#Intent;scheme=https;package=com.google.android.youtube;end',
      )?.scheme,
      'https',
    );
    expect(
      embeddedYouTubeUri('vnd.youtube:aqz-KE-bpKQ')?.queryParameters['v'],
      'aqz-KE-bpKQ',
    );
    for (final String blocked in <String>[
      'https://youtube.com.evil.test/watch',
      'http://m.youtube.com/watch',
      'javascript:alert(1)',
      'file:///etc/passwd',
      'intent://evil.test/#Intent;scheme=https;end',
    ]) {
      expect(embeddedYouTubeUri(blocked), isNull, reason: blocked);
    }
  });
}
