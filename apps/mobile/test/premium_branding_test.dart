import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transpose_mobile/premium_branding.dart';

void main() {
  testWidgets('abertura espera o navegador e não mostra ecrã vazio', (
    tester,
  ) async {
    final ready = ValueNotifier(false);
    addTearDown(ready.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: TransponoLaunchGate(
          revealWhen: ready,
          child: const Scaffold(body: Text('YouTube')),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 3200));
    expect(find.byType(TransponoLaunchArtwork), findsOneWidget);
    ready.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(TransponoLaunchArtwork), findsNothing);
    expect(find.text('YouTube'), findsOneWidget);
  });

  testWidgets('abertura não fica presa se o navegador não responder', (
    tester,
  ) async {
    final ready = ValueNotifier(false);
    addTearDown(ready.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: TransponoLaunchGate(
          revealWhen: ready,
          child: const Scaffold(body: Text('Player disponível')),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 10));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(TransponoLaunchArtwork), findsNothing);
    expect(find.text('Player disponível'), findsOneWidget);
  });

  testWidgets('opening artwork gives way to the player', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: TransponoLaunchGate(child: Scaffold(body: Text('Player'))),
      ),
    );

    expect(find.byKey(const Key('launchChromeBars')), findsOneWidget);
    expect(find.byKey(const Key('launchTransponoTitle')), findsOneWidget);
    expect(find.byKey(const Key('launchProgress')), findsOneWidget);
    expect(find.byKey(const Key('launchStatus')), findsOneWidget);
    expect(find.text('Player'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 3100));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byKey(const Key('launchTransponoTitle')), findsNothing);
    expect(find.text('Player'), findsOneWidget);
  });

  testWidgets('abertura desenha antes de iniciar o navegador', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: TransponoLaunchGate(
          deferChild: true,
          child: Scaffold(body: Text('Navegador')),
        ),
      ),
    );
    expect(find.byType(TransponoLaunchArtwork), findsOneWidget);
    expect(find.text('Navegador'), findsNothing);

    await tester.pump(const Duration(milliseconds: 3400));
    await tester.pump();
    expect(find.text('Navegador'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(TransponoLaunchArtwork), findsNothing);
  });

  testWidgets('nova abertura cabe em ecrã compacto sem cortar a marca', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: TransponoLaunchArtwork()));
    expect(find.byKey(const Key('launchChromeBars')), findsOneWidget);
    expect(find.byKey(const Key('launchTransponoTitle')), findsOneWidget);
    expect(find.byKey(const Key('launchProgress')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
