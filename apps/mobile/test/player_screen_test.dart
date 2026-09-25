import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transpose_mobile/main.dart';

void main() {
  testWidgets('player starts idle and does not allow premature playback', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const TransposeApp());

    expect(find.text('Player'), findsOneWidget);
    expect(find.text('Nenhuma faixa carregada'), findsOneWidget);
    expect(find.byKey(const Key('openFileButton')), findsOneWidget);
    expect(find.byKey(const Key('sampleButton')), findsOneWidget);
    expect(find.byKey(const Key('seekSlider')), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('playPauseButton')))
          .onPressed,
      isNull,
    );
  });
}
