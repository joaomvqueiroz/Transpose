import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transpose_mobile/chord_browser.dart';
import 'package:transpose_mobile/chord_sheet.dart';
import 'package:transpose_mobile/studio_visual_app.dart';
import 'package:transpose_mobile/youtube_browser.dart';

import 'floating_close_helper.dart';

import 'fake_youtube_session.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  Future<void> tap(WidgetTester tester, String key) async {
    if (key.startsWith('visualTab') &&
        find.byKey(Key(key)).evaluate().isEmpty) {
      await tester.tap(find.byKey(const Key('visualMainAdjustments')));
      await tester.pumpAndSettle();
    }
    final target = find.byKey(Key(key));
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await liftAboveFloatingClose(tester, target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  test('the site search encodes the title and blocks other hosts', () {
    final search = chordSearchUri('Canção & acorde');
    expect(search.host, 'www.cifras.com.br');
    expect(search.path, '/busca');
    expect(search.queryParameters['q'], 'Canção & acorde');
    expect(isChordPageUri(search), isFalse);
    expect(chordNavigationUri(search.toString()), search);
    for (final url in ['https://www.cifras.com.br/cifra/artista/musica']) {
      expect(isChordSourceUri(Uri.parse(url)), isTrue);
      expect(isChordPageUri(Uri.parse(url)), isTrue);
    }
    for (final url in [
      'https://www.cifraclub.com.br/artista/musica/',
      'https://www.google.com/search?q=cifra',
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
    expect(() => chordSearchUri(' '), throwsFormatException);
  });

  test('video titles yield song queries, never generic YouTube', () {
    expect(
      chordQueryFromVideoTitle('Santo Pra Sempre - YouTube'),
      'Santo Pra Sempre',
    );
    expect(chordQueryFromVideoTitle('YouTube'), isEmpty);
    expect(chordQueryFromVideoTitle('Vídeo do YouTube'), isEmpty);
    expect(chordQueryFromVideoTitle('Outra canção'), 'Outra canção');
    expect(
      chordQueryFromVideoTitle(
        'Eli Soares - Me Ajude A Melhorar (Ao Vivo Na Penha) [Clipe Oficial] | Live',
      ),
      'Eli Soares - Me Ajude A Melhorar',
    );
  });

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

  test('native result parser keeps only unique public cifra links', () {
    final results = decodeChordSearchResults(
      jsonEncode([
        {
          'title': 'Santo Pra Sempre',
          'url':
              'https://www.cifras.com.br/cifra/gabriel-guedes/santo-pra-sempre',
        },
        {
          'title': 'Repetido',
          'url':
              'https://www.cifras.com.br/cifra/gabriel-guedes/santo-pra-sempre',
        },
        {'title': 'Outro site', 'url': 'https://example.com/cifra/x/y'},
        {'title': 'Pesquisa', 'url': 'https://www.cifras.com.br/busca?q=x'},
      ]),
    );
    expect(results, hasLength(1));
    expect(results.single.title, 'Santo Pra Sempre');
  });

  testWidgets('pesquisa nativa importa a cifra escolhida', (tester) async {
    final browser = _Browser();
    await tester.pumpWidget(
      StudioVisualApp(chordBrowserFactory: () => browser),
    );
    await tap(tester, 'visualMainAdjustments');
    await tap(tester, 'unifiedChooseChord');
    expect(find.byKey(const Key('unifiedChordSearch')), findsOneWidget);
    expect(find.byKey(const Key('chordBrowserPage')), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('chordNativeQuery')))
          .decoration
          ?.hintText,
      'Pesquisar música ou artista',
    );
    await tester.enterText(find.byKey(const Key('chordNativeQuery')), 'Estudo');
    await tap(tester, 'chordNativeSearch');
    await tester.pump();
    expect(browser.currentUri, chordSearchUri('Estudo'));
    expect(find.byKey(const Key('chordNativeResult0')), findsOneWidget);
    await tap(tester, 'chordNativeResult0');
    await tester.pump();
    expect(find.byKey(const Key('unifiedChordSearch')), findsNothing);
    expect(
      find.byKey(const Key('playerChordSheet'), skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('pesquisar cifra não pausa o vídeo em reprodução', (
    tester,
  ) async {
    final session = FakeYouTubeSession();
    await tester.pumpWidget(
      StudioVisualApp(
        youtubeSessionFactory: () => session,
        chordBrowserFactory: _Browser.new,
        openSearchWhenEmpty: true,
      ),
    );
    await tester.pumpAndSettle();
    session.state = const YouTubeMediaState(
      videoId: 'video-em-reproducao',
      title: 'Santo Pra Sempre',
      hasVideo: true,
      playing: true,
      duration: 180,
    );
    session.notifyListeners();
    await tester.pumpAndSettle();
    await tap(tester, 'visualMainAdjustments');
    await tap(tester, 'unifiedChooseChord');
    expect(find.byKey(const Key('unifiedChordSearch')), findsOneWidget);
    expect(session.commands.where((command) => command.$1 == 'pause'), isEmpty);
  });

  testWidgets('cancelar pesquisa não abre cifra', (tester) async {
    final browser = _Browser();
    await tester.pumpWidget(
      StudioVisualApp(chordBrowserFactory: () => browser),
    );
    await tap(tester, 'visualMainAdjustments');
    await tap(tester, 'unifiedChooseChord');
    await tap(tester, 'chordNativeClose');
    expect(find.byKey(const Key('unifiedChordSearch')), findsNothing);
    expect(find.byKey(const Key('playerChordSheet')), findsNothing);
    expect(browser.disposed, isTrue);
  });

  testWidgets('lista de cifras usa cartões compactos de até duas linhas', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final browser = _Browser();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChordSearchPanel(
            initialQuery: 'Estudo',
            onCancel: () {},
            onSelected: (_) async {},
            sessionFactory: () => browser,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final first = find.byKey(const Key('chordNativeResult0'));
    final second = find.byKey(const Key('chordNativeResult1'));
    expect(first, findsOneWidget);
    expect(second, findsOneWidget);
    expect(find.text('Cifras.com.br'), findsNothing);
    final title = tester.widget<Text>(
      find.textContaining('Canção muito longa'),
    );
    expect(title.maxLines, 2);
    expect(title.overflow, TextOverflow.ellipsis);
    expect(title.style?.fontSize, 14);
    expect(tester.getSize(second).height, lessThan(70));
    expect(
      tester.getTopLeft(second).dy - tester.getBottomLeft(first).dy,
      greaterThanOrEqualTo(8),
    );
  });
  testWidgets(
    'unsupported page errors remain visible and import can be retried',
    (tester) async {
      final browser = _Browser()..failure = true;
      await tester.pumpWidget(
        MaterialApp(home: ChordBrowserPage(sessionFactory: () => browser)),
      );
      await tester.pumpAndSettle();
      browser.chooseSong();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(find.byKey(const Key('chordBrowserError')), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('chordBrowserImport')))
            .onPressed,
        isNull,
      );
      browser.failure = false;
      await tap(tester, 'chordBrowserRetry');
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('chordBrowserImport')))
            .onPressed,
        isNotNull,
      );
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
  Future<List<ChordSearchResult>> searchResults() async => [
    ChordSearchResult(
      title: 'Estudo original',
      url: Uri.parse('https://www.cifras.com.br/cifra/estudo/original'),
    ),
    ChordSearchResult(
      title: 'Canção muito longa com artista e versão alternativa para testar o limite visual de duas linhas',
      url: Uri.parse('https://www.cifras.com.br/cifra/estudo/versao'),
    ),
  ];
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
