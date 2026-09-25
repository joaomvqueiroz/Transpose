import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transpose_mobile/chord_browser.dart';
import 'package:transpose_mobile/chord_sheet.dart';
import 'package:transpose_mobile/studio_visual_app.dart';
import 'package:transpose_mobile/youtube_browser.dart';

import 'fake_youtube_session.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  Future<void> tap(WidgetTester tester, String key) async {
    if (key.startsWith('visualTab') &&
        find.byKey(Key(key)).evaluate().isEmpty) {
      await tester.tap(find.byKey(const Key('visualPlayerMenu')));
      await tester.pumpAndSettle();
    }
    final target = find.byKey(Key(key));
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  test(
    'search encodes query and only known HTTPS destinations are allowed',
    () {
      final search = chordSearchUri(ChordSite.cifras, 'Canção & acorde');
      expect(
        search.queryParameters['q'],
        'site:www.cifras.com.br Canção & acorde',
      );
      expect(chordNavigationUri(search.toString()), search);
      for (final url in [
        'https://www.cifraclub.com.br/artista/musica/',
        'https://www.cifras.com.br/cifra/artista/musica',
      ]) {
        expect(isChordSourceUri(Uri.parse(url)), isTrue);
        final redirect = Uri.https('www.google.com', '/url', {'q': url});
        expect(chordNavigationUri(redirect.toString()).toString(), url);
      }
      for (final url in [
        'http://www.cifras.com.br/',
        'https://www.cifras.com.br.attacker.test/',
        'https://attacker.test/?next=https://www.cifras.com.br',
        'file:///sdcard/test',
        'javascript:alert(1)',
        'https://user:pass@www.cifras.com.br/',
        'https://www.cifras.com.br:8443/',
        'https://accounts.google.com/',
      ]) {
        expect(chordNavigationUri(url), isNull, reason: url);
      }
      expect(
        () => chordSearchUri(ChordSite.cifraClub, ' '),
        throwsFormatException,
      );
    },
  );

  test(
    'import validates URL text size and double-encoded platform results',
    () {
      final url = Uri.parse('https://www.cifras.com.br/cifra/estudo/original');
      final payload = {
        'title': 'Estudo original',
        'url': url.toString(),
        'text': 'C   G/B\nLetra original\nAm  F',
        'error': null,
      };
      final chord = ImportedChord.decode(
        jsonEncode(jsonEncode(payload)),
        expectedUrl: url,
      );
      expect(chord.text, payload['text']);
      expect(chord.title, 'Estudo original');
      expect(
        () => ImportedChord.decode({
          ...payload,
          'url': 'https://attacker.test',
        }, expectedUrl: url),
        throwsFormatException,
      );
      expect(
        () => ImportedChord.decode({
          ...payload,
          'text': 'C' * 10001,
        }, expectedUrl: url),
        throwsFormatException,
      );
      expect(
        () => ImportedChord.decode({
          ...payload,
          'error': 'challenge',
        }, expectedUrl: url),
        throwsFormatException,
      );
      expect(
        () => ImportedChord.decode({
          ...payload,
          'text': 'Página sem acordes',
        }, expectedUrl: url),
        throwsFormatException,
      );
      expect(
        () => ImportedChord.decode([], expectedUrl: url),
        throwsFormatException,
      );
    },
  );

  test('source metadata persists and old records stay compatible', () async {
    final store = ChordSheetStore();
    await store.save(
      'song',
      const ChordSheet(
        notes: 'C G',
        timeline: '00:00 C',
        sourceTitle: 'Estudo',
        sourceUrl: 'https://www.cifras.com.br/cifra/estudo/original',
      ),
    );
    final sheet = await ChordSheetStore().read('song');
    expect(sheet.sourceTitle, 'Estudo');
    expect(sheet.sourceUrl, contains('cifras.com.br'));
    await store.save('song', sheet.copyWith(timeline: '00:01 D'));
    expect((await store.read('song')).sourceTitle, 'Estudo');
    expect((await store.read('song')).notes, 'C G');
  });

  testWidgets('search cancel does not enable Cifra or replace default cards', (
    tester,
  ) async {
    final browser = _Browser();
    await tester.pumpWidget(
      StudioVisualApp(chordBrowserFactory: () => browser),
    );
    expect(find.byKey(const Key('playerChordSheet')), findsNothing);
    await tap(tester, 'visualMainAdjustments');
    await tap(tester, 'visualPlayerChordPicker');
    expect(find.byKey(const Key('chordBrowserPage')), findsOneWidget);
    expect(browser.currentUri, ChordSite.cifraClub.home);
    await tester.enterText(
      find.byKey(const Key('chordSearchInput')),
      'Meu estudo',
    );
    await tap(tester, 'chordSearchSubmit');
    expect(browser.currentUri!.queryParameters['q'], contains('Meu estudo'));
    await tap(tester, 'chordBrowserClose');
    expect(find.byKey(const Key('playerChordSheet')), findsNothing);
    expect(find.byKey(const Key('visualPlayerPitchUp')), findsNothing);
    expect(find.byKey(const Key('visualMainAdjustments')), findsOneWidget);
    expect(browser.disposed, isTrue);
  });

  testWidgets(
    'confirm imports real selected text; toggle keeps it across navigation',
    (tester) async {
      final browser = _Browser();
      final youtube = FakeYouTubeSession()
        ..state = const YouTubeMediaState(
          videoId: 'aqz-KE-bpKQ',
          title: 'Vídeo original',
          hasVideo: true,
          duration: 180,
        );
      await tester.pumpWidget(
        StudioVisualApp(
          chordBrowserFactory: () => browser,
          youtubeSessionFactory: () => youtube,
        ),
      );
      await tap(tester, 'visualMainAdjustments');
      await tap(tester, 'visualPlayerEmptySearch');
      await tap(tester, 'youtubeUseInPlayer');
      await tap(tester, 'visualMainAdjustments');
      await tap(tester, 'visualPlayerChordPicker');
      browser.chooseSong();
      await tester.pump();
      await tap(tester, 'chordBrowserImport');
      expect(find.text('Confirmar cifra'), findsOneWidget);
      await tap(tester, 'chordImportCancel');
      expect(find.byKey(const Key('chordBrowserPage')), findsOneWidget);
      await tap(tester, 'chordBrowserImport');
      await tap(tester, 'chordImportConfirm');
      expect(find.byKey(const Key('chordBrowserPage')), findsNothing);
      expect(find.byKey(const Key('playerChordSheet')), findsOneWidget);
      expect(find.byKey(const Key('visualMainControlsOverlay')), findsNothing);
      await tap(tester, 'visualMainAdjustments');
      expect(
        tester
            .widget<IgnorePointer>(
              find.byKey(const Key('visualMainControlsOverlay')),
            )
            .ignoring,
        isFalse,
      );
      await tester.dragFrom(const Offset(10, 550), const Offset(0, -240));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('visualMainControlsOverlay')), findsNothing);
      await tap(tester, 'visualMainAdjustments');
      expect(find.byKey(const Key('visualMainControlsOverlay')), findsOneWidget);
      await tap(tester, 'visualPlayerPinVideo');
      await tester.dragFrom(const Offset(10, 550), const Offset(0, -240));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pinnedPlayerMedia')), findsOneWidget);
      expect(find.byKey(const Key('visualMainControlsOverlay')), findsNothing);
      await tap(tester, 'visualMainAdjustments');
      await tap(tester, 'visualPlayerPinVideo');
      await tap(tester, 'visualMainAdjustments');
      expect(find.byKey(const Key('visualMainControlsOverlay')), findsNothing);
      expect(find.text('Estudo original'), findsOneWidget);
      expect(find.byKey(const Key('playerChordSource')), findsOneWidget);
      await tap(tester, 'visualMainAdjustments');
      await tap(tester, 'visualPlayerChordPicker');
      expect(find.byKey(const Key('playerChordSheet')), findsNothing);
      expect(find.byKey(const Key('visualPlayerPitchUp')), findsNothing);
      expect(find.byKey(const Key('visualMainAdjustments')), findsOneWidget);
      await tap(tester, 'visualMainAdjustments');
      await tap(tester, 'visualPlayerChordPicker');
      expect(find.byKey(const Key('playerChordSheet')), findsOneWidget);
      expect(find.byKey(const Key('chordBrowserPage')), findsNothing);
      await tap(tester, 'visualTabpractice');
      await tap(tester, 'visualTabplayer');
      expect(find.text('Estudo original'), findsOneWidget);
      expect(youtube.disposed, isFalse);
      expect(youtube.commands.where((c) => c.$1 == 'play'), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'source change during browser selection refuses wrong association',
    (tester) async {
      final browser = _Browser();
      final youtube = FakeYouTubeSession()
        ..state = const YouTubeMediaState(
          videoId: 'aqz-KE-bpKQ',
          title: 'Primeira',
          hasVideo: true,
          duration: 180,
        );
      await tester.pumpWidget(
        StudioVisualApp(
          chordBrowserFactory: () => browser,
          youtubeSessionFactory: () => youtube,
        ),
      );
      await tap(tester, 'visualMainAdjustments');
      await tap(tester, 'visualPlayerEmptySearch');
      await tap(tester, 'youtubeUseInPlayer');
      await tap(tester, 'visualMainAdjustments');
      await tap(tester, 'visualPlayerChordPicker');
      browser.chooseSong();
      await tester.pump();
      await tap(tester, 'chordBrowserImport');
      youtube.state = const YouTubeMediaState(
        videoId: 'AAAAAAAAAAA',
        title: 'Outra',
        hasVideo: true,
        duration: 180,
      );
      youtube.notifyListeners();
      await tester.pump();
      await tap(tester, 'chordImportConfirm');
      expect(find.byKey(const Key('playerChordSheet')), findsNothing);
      expect(find.textContaining('A música mudou'), findsOneWidget);
    },
  );

  testWidgets(
    'unsupported page errors remain visible and import can be retried',
    (tester) async {
      final browser = _Browser()..failure = true;
      await tester.pumpWidget(
        MaterialApp(home: ChordBrowserPage(sessionFactory: () => browser)),
      );
      await tester.pumpAndSettle();
      browser.chooseSong();
      await tester.pump();
      await tap(tester, 'chordBrowserImport');
      expect(find.byKey(const Key('chordBrowserError')), findsOneWidget);
      expect(find.text('Confirmar cifra'), findsNothing);
      browser.failure = false;
      await tap(tester, 'chordBrowserImport');
      expect(find.text('Confirmar cifra'), findsOneWidget);
      await tap(tester, 'chordImportCancel');
    },
  );
}

class _Browser extends ChordBrowserSession {
  Uri? uri;
  bool disposed = false, failure = false;
  @override
  Uri? get currentUri => uri;
  @override
  bool get canGoBack => false;
  @override
  int get progress => 100;
  @override
  String? get error => null;
  @override
  Future<void> open(Uri value) async {
    uri = value;
    notifyListeners();
  }

  void chooseSong() {
    uri = Uri.parse('https://www.cifras.com.br/cifra/estudo/original');
    notifyListeners();
  }

  @override
  Future<void> goBack() async {}
  @override
  Future<void> reload() async {}
  @override
  Future<ImportedChord> extract() async {
    if (failure) throw const FormatException('Sem cifra visível.');
    return ImportedChord(
      title: 'Estudo original',
      url: uri!,
      text: 'C   G/B\nLetra original\nAm  F',
    );
  }

  @override
  Widget buildView() =>
      const Center(child: Text('Site de cifras com resultados'));
  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}
