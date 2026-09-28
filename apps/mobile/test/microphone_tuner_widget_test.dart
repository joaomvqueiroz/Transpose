import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transpose_mobile/microphone_tuner.dart';
import 'package:transpose_mobile/piano_reference_player.dart';

class _FakePianoReferencePlayer implements PianoReferencePlayer {
  final played = <String>[];

  @override
  Future<void> play(String note) async => played.add(note);

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  test('afinador usa verde, laranja e vermelho conforme a afinação', () {
    expect(tunerFeedbackColor(0, inTune: true), const Color(0xFF4ADE80));
    expect(tunerFeedbackColor(18, inTune: false), const Color(0xFFFB923C));
    expect(tunerFeedbackColor(-45, inTune: false), const Color(0xFFF87171));
  });

  testWidgets('ponteiro atravessa o mostrador e acende verde ao afinar', (
    tester,
  ) async {
    Widget gauge(double cents, {bool inTune = false}) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            height: 132,
            child: TunerGauge(cents: cents, inTune: inTune),
          ),
        ),
      ),
    );
    double needle() =>
        (tester
                        .widget<CustomPaint>(
                          find.byKey(const Key('tunerGaugePaint')),
                        )
                        .painter!
                    as dynamic)
                .cents
            as double;
    double green() =>
        (tester
                        .widget<CustomPaint>(
                          find.byKey(const Key('tunerGaugePaint')),
                        )
                        .painter!
                    as dynamic)
                .green
            as double;

    await tester.pumpWidget(gauge(-40));
    expect(needle(), -40);
    expect(green(), 0);
    await tester.pumpWidget(gauge(40));
    await tester.pump(const Duration(milliseconds: 80));
    expect(needle(), greaterThan(-40));
    expect(needle(), lessThan(40));
    await tester.pumpAndSettle();
    expect(needle(), 40);

    await tester.pumpWidget(gauge(0, inTune: true));
    await tester.pump(const Duration(milliseconds: 100));
    expect(green(), greaterThan(0));
    expect(green(), lessThan(1));
    await tester.pumpAndSettle();
    expect(green(), 1);
    expect(needle(), 0);
  });

  testWidgets('afinador começa automático e botões tocam notas de piano', (
    tester,
  ) async {
    final piano = _FakePianoReferencePlayer();
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MicrophoneTunerTool(referencePlayer: piano),
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('chromaticTunerCard')), findsOneWidget);
    expect(find.byKey(const Key('tunerMicrophoneToggle')), findsOneWidget);
    expect(find.text('E2'), findsWidgets);
    expect(find.text('—'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tunerStringA2')));
    await tester.pump();
    expect(piano.played, ['A2']);
    expect(find.text('A2'), findsWidgets);
    expect(find.text('Nota de referência · piano'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
