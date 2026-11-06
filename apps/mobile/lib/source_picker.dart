import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'premium_branding.dart';
import 'spotify_browser.dart';

/// Where the user listens from, chosen on the first screen.
enum ListeningSource { youtube, spotify }

/// First screen: black, the Transpono symbol and two large choices.
///
/// YouTube opens the full Transpono studio (pitch, EQ, effects, chords).
/// Spotify opens its web player inside Transpono for listening, with chords
/// and a shortcut that plays the same song on YouTube, where pitch works.
/// Everything is drawn as vectors, so it stays sharp on any screen.
class TransponoSourcePicker extends StatefulWidget {
  const TransponoSourcePicker({super.key, required this.youtubeBuilder});

  /// Builds the YouTube studio; [query] is a search to open, if any.
  final Widget Function(String? query) youtubeBuilder;

  @override
  State<TransponoSourcePicker> createState() => _TransponoSourcePickerState();
}

class _TransponoSourcePickerState extends State<TransponoSourcePicker> {
  ListeningSource? _source;
  String? _query;

  void _openYouTube([String? query]) {
    setState(() {
      // The studio reads its first search once; it stays open afterwards.
      _query = query;
      _source = ListeningSource.youtube;
    });
  }

  @override
  Widget build(BuildContext context) {
    switch (_source) {
      case ListeningSource.youtube:
        return widget.youtubeBuilder(_query);
      case ListeningSource.spotify:
        return SpotifyPage(
          onBack: () => setState(() => _source = null),
          onPlayOnYouTube: _openYouTube,
        );
      case null:
        return _PickerScreen(
          onYouTube: _openYouTube,
          onSpotify: () => setState(() => _source = ListeningSource.spotify),
        );
    }
  }
}

class _PickerScreen extends StatelessWidget {
  const _PickerScreen({required this.onYouTube, required this.onSpotify});

  final VoidCallback onYouTube;
  final VoidCallback onSpotify;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: Stack(
      children: [
        const Positioned.fill(child: CustomPaint(painter: _GlowPainter())),
        SafeArea(
          child: LayoutBuilder(
            builder: (context, box) {
              final wide = box.maxWidth > box.maxHeight;
              final tile = math.min(
                // Two tiles plus their gap (2.14 tiles) fit inside the
                // 24 px side padding on every phone width.
                wide ? box.maxHeight * .46 : (box.maxWidth - 56) / 2.14,
                230.0,
              );
              final tiles = <Widget>[
                _SourceTile(
                  key: const Key('pickYouTube'),
                  size: tile,
                  label: 'YouTube',
                  caption: 'Tom, EQ e efeitos',
                  logo: const _YouTubeLogo(),
                  accent: const Color(0xFFFF0033),
                  onPressed: onYouTube,
                ),
                SizedBox(width: tile * .14, height: tile * .14),
                _SourceTile(
                  key: const Key('pickSpotify'),
                  size: tile,
                  label: 'Spotify',
                  caption: 'Ouvir e ver a cifra',
                  logo: const _SpotifyLogo(),
                  accent: const Color(0xFF1ED760),
                  onPressed: onSpotify,
                ),
              ];
              return Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 24,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TransponoMark(height: wide ? 64 : 104),
                      const SizedBox(height: 22),
                      const TransponoWordmark(fontSize: 40),
                      const SizedBox(height: 10),
                      const Text(
                        'Onde queres ouvir?',
                        style: TextStyle(
                          color: Color(0xFFB8B8BC),
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          letterSpacing: .4,
                        ),
                      ),
                      SizedBox(height: wide ? 24 : 44),
                      Row(mainAxisSize: MainAxisSize.min, children: tiles),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

class _SourceTile extends StatefulWidget {
  const _SourceTile({
    super.key,
    required this.size,
    required this.label,
    required this.caption,
    required this.logo,
    required this.accent,
    required this.onPressed,
  });

  final double size;
  final String label, caption;
  final Widget logo;
  final Color accent;
  final VoidCallback onPressed;

  @override
  State<_SourceTile> createState() => _SourceTileState();
}

class _SourceTileState extends State<_SourceTile> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return Semantics(
      button: true,
      label: '${widget.label}. ${widget.caption}',
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _down ? .96 : 1,
          duration: const Duration(milliseconds: 120),
          child: Container(
            width: s,
            height: s * 1.18,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(s * .16),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1C1C20), Color(0xFF0D0D0F)],
              ),
              border: Border.all(color: const Color(0x33FFFFFF)),
              boxShadow: [
                BoxShadow(
                  color: widget.accent.withValues(alpha: _down ? .35 : .18),
                  blurRadius: s * .22,
                  spreadRadius: -s * .04,
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(width: s * .52, height: s * .52, child: widget.logo),
                SizedBox(height: s * .1),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: s * .12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.3,
                  ),
                ),
                SizedBox(height: s * .03),
                Text(
                  widget.caption,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: const Color(0xFF9E9EA4),
                    fontSize: math.max(11, s * .062),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _YouTubeLogo extends StatelessWidget {
  const _YouTubeLogo();

  @override
  Widget build(BuildContext context) =>
      const CustomPaint(painter: _YouTubeLogoPainter());
}

class _YouTubeLogoPainter extends CustomPainter {
  const _YouTubeLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = w / 1.42;
    final top = (size.height - h) / 2;
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, top, w, h),
      Radius.circular(h * .26),
    );
    canvas.drawRRect(body, Paint()..color = const Color(0xFFFF0033));
    final cx = w / 2, cy = top + h / 2, t = h * .36;
    final play = Path()
      ..moveTo(cx - t * .42, cy - t * .5)
      ..lineTo(cx + t * .58, cy)
      ..lineTo(cx - t * .42, cy + t * .5)
      ..close();
    canvas.drawPath(play, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SpotifyLogo extends StatelessWidget {
  const _SpotifyLogo();

  @override
  Widget build(BuildContext context) =>
      const CustomPaint(painter: _SpotifyLogoPainter());
}

class _SpotifyLogoPainter extends CustomPainter {
  const _SpotifyLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final d = math.min(size.width, size.height);
    final c = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(c, d / 2, Paint()..color = const Color(0xFF1ED760));
    final stroke = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    // Three arcs, widest on top, each a little lower and narrower.
    const arcs = [
      (y: -.17, w: .62, t: .085, bow: .16),
      (y: .03, w: .52, t: .07, bow: .13),
      (y: .2, w: .42, t: .058, bow: .1),
    ];
    for (final arc in arcs) {
      final left = Offset(c.dx - d * arc.w / 2, c.dy + d * arc.y + d * .02);
      final right = Offset(c.dx + d * arc.w / 2, c.dy + d * arc.y + d * .05);
      final control = Offset(c.dx, c.dy + d * arc.y - d * arc.bow);
      canvas.drawPath(
        Path()
          ..moveTo(left.dx, left.dy)
          ..quadraticBezierTo(control.dx, control.dy, right.dx, right.dy),
        stroke..strokeWidth = d * arc.t,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _GlowPainter extends CustomPainter {
  const _GlowPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * .3);
    final radius = math.max(size.width, size.height) * .55;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x1A8E97A8), Color(0x080E1117), Colors.transparent],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
