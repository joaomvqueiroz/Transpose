import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Scalable wordmark: the lettering remains sharp at every screen density.
class TransponoWordmark extends StatelessWidget {
  const TransponoWordmark({super.key, this.fontSize = 24});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: -1, end: 1),
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 1100),
      curve: Curves.easeInOutCubic,
      builder: (context, glint, _) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment(glint - 1.4, -0.7),
          end: Alignment(glint + 1.4, 0.7),
          colors: const [
            Color(0xFF77777E),
            Color(0xFFF7F7F8),
            Color(0xFF9E9EA4),
            Color(0xFFFFFFFF),
            Color(0xFF78787E),
          ],
          stops: const [0, .3, .52, .69, 1],
        ).createShader(bounds),
        child: Text(
          'Transpono',
          key: const Key('transponoWordmark'),
          maxLines: 1,
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
            letterSpacing: -.8,
            height: 1,
          ),
        ),
      ),
    );
  }
}

/// The Transpono chrome-bars symbol, drawn as vectors (sharp at any size).
class TransponoMark extends StatelessWidget {
  const TransponoMark({super.key, this.height = 120});

  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    width: height * 210 / 228,
    child: FittedBox(
      child: CustomPaint(
        painter: _ChromeBarsPainter(
          animation: const AlwaysStoppedAnimation<double>(0),
          reducedMotion: true,
        ),
        size: const Size(210, 228),
      ),
    ),
  );
}

/// A brief in-app launch screen, distinct from the launcher icon.
class TransponoLaunchGate extends StatefulWidget {
  const TransponoLaunchGate({
    super.key,
    required this.child,
    this.deferChild = false,
    this.revealWhen,
  });

  final Widget child;
  final bool deferChild;

  /// Keep the artwork visible while the first browser page prepares behind it.
  final ValueListenable<bool>? revealWhen;

  @override
  State<TransponoLaunchGate> createState() => _TransponoLaunchGateState();
}

class _TransponoLaunchGateState extends State<TransponoLaunchGate> {
  bool _visible = true;
  bool _mountedSplash = true;
  late bool _showChild;
  Timer? _homeTimer;
  Timer? _revealTimer;
  Timer? _maximumWaitTimer;
  bool _minimumElapsed = false;

  @override
  void initState() {
    super.initState();
    _showChild = !widget.deferChild;
    widget.revealWhen?.addListener(_tryReveal);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.deferChild) {
        _homeTimer = Timer(const Duration(milliseconds: 3300), () {
          if (!mounted) return;
          setState(() => _showChild = true);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _revealTimer = Timer(const Duration(milliseconds: 700), () {
              if (mounted) setState(() => _visible = false);
            });
          });
        });
        return;
      }
      _revealTimer = Timer(const Duration(milliseconds: 3000), () {
        _minimumElapsed = true;
        _tryReveal();
      });
      // A slow or blocked YouTube page must not trap the user on the splash.
      if (widget.revealWhen != null) {
        _maximumWaitTimer = Timer(const Duration(seconds: 10), () {
          if (mounted && _visible) setState(() => _visible = false);
        });
      }
    });
  }

  void _tryReveal() {
    if (!mounted ||
        !_minimumElapsed ||
        !_visible ||
        widget.revealWhen?.value == false) {
      return;
    }
    setState(() => _visible = false);
  }

  @override
  void dispose() {
    _homeTimer?.cancel();
    _revealTimer?.cancel();
    _maximumWaitTimer?.cancel();
    widget.revealWhen?.removeListener(_tryReveal);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Stack(
      children: [
        if (_showChild)
          widget.child
        else
          const ColoredBox(color: Color(0xFF080809), child: SizedBox.expand()),
        if (_mountedSplash)
          IgnorePointer(
            // Keep the player responsive while the brief visual reveal fades.
            ignoring:
                !_visible || (!widget.deferChild && widget.revealWhen == null),
            child: AnimatedOpacity(
              opacity: _visible ? 1 : 0,
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 280),
              onEnd: () {
                if (!_visible && mounted) {
                  setState(() => _mountedSplash = false);
                }
              },
              child: ColoredBox(
                color: const Color(0xFF080809),
                child: const TransponoLaunchArtwork(),
              ),
            ),
          ),
      ],
    );
  }
}

/// Code-native rendering of Abertura/stitch_animated_image_loader/code.html.
/// The splash needs no network fonts, scripts, or WebView to appear.
class TransponoLaunchArtwork extends StatefulWidget {
  const TransponoLaunchArtwork({super.key});

  @override
  State<TransponoLaunchArtwork> createState() => _TransponoLaunchArtworkState();
}

class _TransponoLaunchArtworkState extends State<TransponoLaunchArtwork>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  )..repeat();

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    if (reducedMotion && _motion.isAnimating) _motion.stop();
    return ColoredBox(
      color: Colors.black,
      child: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _LaunchAtmospherePainter(
                  animation: _motion,
                  reducedMotion: reducedMotion,
                ),
              ),
            ),
            Column(
              children: [
                Expanded(
                  child: Center(
                    child: Transform.translate(
                      offset: const Offset(0, -8),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CustomPaint(
                              key: const Key('launchChromeBars'),
                              painter: _ChromeBarsPainter(
                                animation: _motion,
                                reducedMotion: reducedMotion,
                              ),
                              size: const Size(210, 228),
                            ),
                            const SizedBox(height: 32),
                            Semantics(
                              label: 'Transpono.',
                              child: CustomPaint(
                                key: const Key('launchTransponoTitle'),
                                size: const Size(300, 54),
                                painter: _LaunchLetteringPainter(
                                  text: 'Transpono.',
                                  fontSize: 44,
                                  weight: FontWeight.w900,
                                  letterSpacing: -2.2,
                                  animation: _motion,
                                  metallic: true,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            CustomPaint(
                              key: Key('launchTagline'),
                              size: Size(300, 18),
                              painter: _LaunchLetteringPainter(
                                text: 'ESTÚDIO HARMÔNICO & CIFRAS',
                                fontSize: 10,
                                weight: FontWeight.w400,
                                letterSpacing: 3.5,
                                color: Color(0xFFB8B8BC),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(40, 0, 40, 78),
                  child: Column(
                    children: [
                      AnimatedBuilder(
                        animation: _motion,
                        builder: (context, _) => SizedBox(
                          key: const Key('launchProgress'),
                          height: 12,
                          child: CustomPaint(
                            painter: _LaunchProgressPainter(
                              progress: reducedMotion ? .7 : _motion.value,
                            ),
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 13),
                      CustomPaint(
                        key: const Key('launchStatus'),
                        size: const Size(300, 16),
                        painter: _LaunchLetteringPainter(
                          text: 'SINCRONIZANDO TIMBRES...',
                          fontSize: 9,
                          weight: FontWeight.w500,
                          letterSpacing: 2.2,
                          color: Color(0xFF55555B),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// CustomPaint avoids Flutter's optional debug baseline guides being drawn
/// through the launch lettering on development devices.
class _LaunchLetteringPainter extends CustomPainter {
  _LaunchLetteringPainter({
    required this.text,
    required this.fontSize,
    required this.weight,
    required this.letterSpacing,
    this.color = Colors.white,
    this.animation,
    this.metallic = false,
  }) : super(repaint: animation);

  final String text;
  final double fontSize;
  final FontWeight weight;
  final double letterSpacing;
  final Color color;
  final Animation<double>? animation;
  final bool metallic;

  @override
  void paint(Canvas canvas, Size size) {
    final foreground = Paint()..color = color;
    if (metallic) {
      final phase = animation?.value ?? 0;
      foreground.shader = LinearGradient(
        begin: Alignment(-1 + phase * 1.4, -1),
        end: Alignment(1 + phase * 1.4, 1),
        colors: const [
          Color(0xFFF9FAFB),
          Color(0xFFCDD2DA),
          Color(0xFF94A3B8),
          Color(0xFFF8FAFC),
        ],
      ).createShader(Offset.zero & size);
    }
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          foreground: foreground,
          fontSize: fontSize,
          fontWeight: weight,
          letterSpacing: letterSpacing,
          height: 1.1,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: size.width);
    painter.paint(
      canvas,
      Offset(
        (size.width - painter.width) / 2,
        (size.height - painter.height) / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _LaunchLetteringPainter oldDelegate) =>
      text != oldDelegate.text || color != oldDelegate.color;
}

class _LaunchAtmospherePainter extends CustomPainter {
  _LaunchAtmospherePainter({
    required this.animation,
    required this.reducedMotion,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final bool reducedMotion;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * .42);
    canvas.drawCircle(
      center,
      math.min(size.width * .65, 320),
      Paint()
        ..shader = RadialGradient(
          colors: const [
            Color(0x144E5666),
            Color(0x080E1117),
            Colors.transparent,
          ],
        ).createShader(Rect.fromCircle(center: center, radius: 320)),
    );
    for (var i = 0; i < 28; i++) {
      final x = ((i * 73 + 17) % 101) / 101 * size.width;
      final baseY = ((i * 47 + 31) % 103) / 103;
      final drift = reducedMotion
          ? 0.0
          : animation.value * (.02 + i % 3 * .008);
      final y = ((baseY - drift + 1) % 1) * size.height;
      canvas.drawCircle(
        Offset(x, y),
        .3 + i % 4 * .19,
        Paint()..color = Color.fromRGBO(235, 240, 250, .05 + i % 5 * .018),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LaunchAtmospherePainter oldDelegate) =>
      oldDelegate.reducedMotion != reducedMotion;
}

class _ChromeBarsPainter extends CustomPainter {
  _ChromeBarsPainter({required this.animation, required this.reducedMotion})
    : super(repaint: animation);

  final Animation<double> animation;
  final bool reducedMotion;

  @override
  void paint(Canvas canvas, Size size) {
    const widths = [25.0, 28.0, 32.0, 28.0, 25.0];
    const heights = [78.0, 154.0, 228.0, 140.0, 68.0];
    var x = 8.0;
    for (var i = 0; i < widths.length; i++) {
      final pulse = reducedMotion
          ? 1.0
          : 1 + .035 * math.sin(animation.value * math.pi * 2 + i * 1.4);
      final height = heights[i] * pulse;
      final rect = Rect.fromCenter(
        center: Offset(x + widths[i] / 2, size.height / 2),
        width: widths[i],
        height: height,
      );
      final rrect = RRect.fromRectAndRadius(
        rect,
        Radius.circular(widths[i] / 2),
      );
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = const Color(0x55CBD5E1)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
      );
      canvas.drawRRect(
        rrect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: [0, .19, .35, .5, .68, .85, 1],
            colors: [
              Color(0xFF7A828E),
              Color(0xFFE2E8F0),
              Colors.white,
              Color(0xFF94A3B8),
              Color(0xFFF8FAFC),
              Color(0xFF64748B),
              Color(0xFFCBD5E1),
            ],
          ).createShader(rect),
      );
      canvas.drawRRect(
        rrect.deflate(1),
        Paint()
          ..color = const Color(0x70FFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      x += widths[i] + 14;
    }
  }

  @override
  bool shouldRepaint(covariant _ChromeBarsPainter oldDelegate) =>
      oldDelegate.reducedMotion != reducedMotion;
}

class _LaunchProgressPainter extends CustomPainter {
  const _LaunchProgressPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final track = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, y - 1, size.width, 2),
      const Radius.circular(2),
    );
    canvas.drawRRect(track, Paint()..color = const Color(0xFF343438));
    final fraction = progress < .5
        ? progress / .5 * .72
        : .72 + (progress - .5) / .5 * .28;
    final end = size.width * fraction;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, y - 1, end, 2),
        const Radius.circular(2),
      ),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF66666B), Color(0xFFD6D6DA), Colors.white],
        ).createShader(Rect.fromLTWH(0, y - 1, math.max(end, 1), 2)),
    );
    canvas.drawCircle(
      Offset(end, y),
      8,
      Paint()
        ..color = const Color(0xCCFFFFFF)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 11),
    );
    canvas.drawCircle(Offset(end, y), 3.5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _LaunchProgressPainter oldDelegate) =>
      progress != oldDelegate.progress;
}
