import 'dart:async';

import 'package:flutter/material.dart';

/// The small iOS-style bar above the adjustments: drag it and the adjustments
/// follow the finger — up to raise them, down to lower or close them.
///
/// It is drawn over the adjustments and never moves anything. It shows every
/// [period] for [shown], then fades out; the drag works whether or not the
/// bar is visible, and taps go through to whatever is under it. While a
/// finger is on it, the bar grows a little.
class AdjustmentsHandle extends StatefulWidget {
  const AdjustmentsHandle({
    super.key,
    required this.light,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    this.alwaysVisible = false,
    this.bar = true,
    this.gestureKey = const Key('adjustmentsHandle'),
  });

  static const Duration period = Duration(seconds: 10);
  static const Duration shown = Duration(milliseconds: 3500);
  static const Duration fade = Duration(milliseconds: 700);

  final bool light;

  /// The floating sheet keeps its bar in sight all the time.
  final bool alwaysVisible;

  /// Without a bar the band still takes the drag, unseen.
  final bool bar;
  final Key gestureKey;
  final VoidCallback onDragStart;

  /// Vertical movement since the last update, in logical pixels.
  final ValueChanged<double> onDragUpdate;

  /// The finger's vertical speed when it let go (0 when cancelled).
  final ValueChanged<double> onDragEnd;

  @override
  State<AdjustmentsHandle> createState() => _AdjustmentsHandleState();
}

class _AdjustmentsHandleState extends State<AdjustmentsHandle> {
  late final Timer _cycle;
  Timer? _hide;
  bool _visible = true;
  bool _pressed = false;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _scheduleHide();
    _cycle = Timer.periodic(AdjustmentsHandle.period, (_) => _show());
  }

  void _scheduleHide() {
    _hide?.cancel();
    _hide = Timer(AdjustmentsHandle.shown, () {
      // Never fades under the finger.
      if (mounted && !_pressed) setState(() => _visible = false);
    });
  }

  void _show() {
    if (!mounted) return;
    setState(() => _visible = true);
    _scheduleHide();
  }

  void _press(bool pressed) {
    if (!mounted || _pressed == pressed) return;
    setState(() {
      _pressed = pressed;
      _visible = true;
    });
    _scheduleHide();
  }

  void _end(double velocity) {
    if (!_dragging) return;
    _dragging = false;
    widget.onDragEnd(velocity);
  }

  @override
  void dispose() {
    _cycle.cancel();
    _hide?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    // Observes only: grows the bar while a finger is on its band.
    behavior: HitTestBehavior.translucent,
    onPointerDown: (_) => _press(true),
    onPointerUp: (_) => _press(false),
    onPointerCancel: (_) => _press(false),
    child: GestureDetector(
      key: widget.gestureKey,
      // Translucent and drag-only: a tap reaches the tabs under the band.
      behavior: HitTestBehavior.translucent,
      onVerticalDragStart: (_) {
        _dragging = true;
        widget.onDragStart();
      },
      onVerticalDragUpdate: (details) {
        if (_dragging) widget.onDragUpdate(details.delta.dy);
      },
      onVerticalDragEnd: (details) => _end(details.primaryVelocity ?? 0),
      onVerticalDragCancel: () => _end(0),
      child: SizedBox(
        width: 150,
        height: 28,
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: EdgeInsets.only(top: _pressed ? 2 : 3),
            child: IgnorePointer(
              child: !widget.bar
                  ? const SizedBox(width: 56, height: 7)
                  : AnimatedOpacity(
                      key: const Key('adjustmentsHandleBar'),
                      opacity: widget.alwaysVisible || _visible ? 1 : 0,
                      duration: _visible
                          ? const Duration(milliseconds: 200)
                          : AdjustmentsHandle.fade,
                      curve: Curves.easeOut,
                      child: AnimatedContainer(
                        key: const Key('adjustmentsHandlePill'),
                        duration: const Duration(milliseconds: 140),
                        curve: Curves.easeOut,
                        width: _pressed ? 56 : 40,
                        height: _pressed ? 7 : 5,
                        decoration: BoxDecoration(
                          color: widget.light
                              ? Color(_pressed ? 0xCC000000 : 0x99000000)
                              : Color(_pressed ? 0xFFFFFFFF : 0xCCFFFFFF),
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: const [
                            BoxShadow(color: Color(0x55000000), blurRadius: 4),
                          ],
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    ),
  );
}
