import 'package:flutter/material.dart';

/// Plays once when a tab's content appears: it fades in while gliding a
/// short way from the side the new tab is on ([direction] > 0: from the
/// right; < 0: from the left; 0: fade only).
class TabEntrance extends StatefulWidget {
  const TabEntrance({super.key, required this.direction, required this.child});

  final int direction;
  final Widget child;

  @override
  State<TabEntrance> createState() => _TabEntranceState();
}

class _TabEntranceState extends State<TabEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  )..forward();
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: Offset(widget.direction.sign * .07, 0),
    end: Offset.zero,
  ).animate(_curve);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _curve,
    child: SlideTransition(position: _slide, child: widget.child),
  );
}

/// Clips to everything below [inset], with the tone tab's rounded top: the
/// one blurred backdrop of that tab, which starts under the page's strip.
class TopInsetClipper extends CustomClipper<Path> {
  const TopInsetClipper(this.inset);

  final double inset;

  @override
  Path getClip(Size size) => Path()
    ..addRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTRB(
          0,
          inset.clamp(0.0, size.height),
          size.width,
          size.height,
        ),
        topLeft: const Radius.circular(34),
        topRight: const Radius.circular(34),
      ),
    );

  @override
  bool shouldReclip(TopInsetClipper oldClipper) => oldClipper.inset != inset;
}
