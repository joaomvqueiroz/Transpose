import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// While the adjustments are open, "Fechar ajustes" floats over the bottom of
/// the screen. `ensureVisible` can leave a target right under it; scroll the
/// target's list a little further so the tap reaches the target, as a person
/// would.
Future<void> liftAboveFloatingClose(WidgetTester tester, Finder target) async {
  final close = find.byKey(const Key('visualCloseAdjustments'));
  final compact = find.byKey(const Key('visualCloseAdjustmentsCompact'));
  final floating = close.evaluate().isNotEmpty
      ? close
      : (compact.evaluate().isNotEmpty ? compact : null);
  if (floating == null || target.evaluate().isEmpty) return;
  final barTop = tester.getTopLeft(floating).dy - 8;
  final centre = tester.getCenter(target);
  if (centre.dy < barTop) return;
  final scrollable = find.ancestor(
    of: target,
    matching: find.byType(Scrollable),
  );
  if (scrollable.evaluate().isEmpty) return;
  await tester.drag(scrollable.first, Offset(0, -(centre.dy - barTop + 40)));
  await tester.pumpAndSettle();
}
