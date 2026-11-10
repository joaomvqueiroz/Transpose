import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'google_sign_in_probe.dart';
import 'home_button_visibility.dart';
import 'premium_branding.dart';
import 'spotify_browser.dart';
import 'youtube_browser.dart';

/// Where the user listens from, chosen on the first screen.
enum ListeningSource { youtube, youtubeMusic, soundCloud, spotify }

/// Builds the studio for a source. [sessionFactory] replaces the YouTube
/// browser (Spotify); [query] is a YouTube search to open first; [home] is
/// the first browser page (music.youtube.com for YouTube Music).
typedef StudioBuilder = Widget Function(
  Key key,
  String? query,
  YouTubeBrowserSession Function()? sessionFactory,
  Uri? home,
);

/// First screen: black, the Transpono symbol and two large choices.
///
/// Both open the same studio. With YouTube everything works (pitch, EQ,
/// effects, chords). With Spotify the studio looks the same, but Spotify's
/// protected audio cannot be processed, so only playback and chords work;
/// a button hands the song to YouTube, where pitch works.
/// Everything is drawn as vectors, so it stays sharp on any screen.
class TransponoSourcePicker extends StatefulWidget {
  const TransponoSourcePicker({super.key, required this.studioBuilder});

  final StudioBuilder studioBuilder;

  @override
  State<TransponoSourcePicker> createState() => _TransponoSourcePickerState();
}

class _TransponoSourcePickerState extends State<TransponoSourcePicker> {
  ListeningSource? _source;
  String? _query;
  int _generation = 0;
  SpotifyStudioSession? _spotify;
  final GoogleSignInGate _google = GoogleSignInGate();

  /// YouTube and YouTube Music: on iPhone, offer the Google sign-in first
  /// (it happens in Safari's engine and passes to Gecko by itself).
  Future<void> _chooseGoogle(ListeningSource source) async {
    await _google.beforeOpening(context);
    if (mounted) _choose(source);
  }

  void _choose(ListeningSource? source, [String? query]) {
    setState(() {
      _source = source;
      _query = query;
      // A new studio (and player) for every choice; the old one is disposed.
      _generation++;
      // The studio's player owns and disposes this session; keep a handle
      // only to read the song for "YouTube com tom".
      _spotify = source == ListeningSource.spotify
          ? SpotifyStudioSession()
          : null;
    });
  }

  YouTubeBrowserSession _spotifySession() => _spotify!;

  void _playOnYouTube() {
    final track = _spotify?.track;
    if (track == null || track.isEmpty) return;
    _choose(ListeningSource.youtube, track.query);
  }

  @override
  Widget build(BuildContext context) {
    final source = _source;
    if (source == null) {
      return _PickerScreen(
        onYouTube: () => _chooseGoogle(ListeningSource.youtube),
        onYouTubeMusic: () => _chooseGoogle(ListeningSource.youtubeMusic),
        onSoundCloud: () => _choose(ListeningSource.soundCloud),
        onSpotify: () => _choose(ListeningSource.spotify),
      );
    }
    // YouTube Music is the same YouTube player and page bridge (pitch, EQ,
    // effects work); only the first page differs.
    final studio = widget.studioBuilder(
      ValueKey<String>('studio-${source.name}-$_generation'),
      _query,
      source == ListeningSource.spotify ? _spotifySession : null,
      switch (source) {
        ListeningSource.youtubeMusic => Uri.https('music.youtube.com', '/'),
        // Same studio and page bridge; covers and user uploads stream
        // without DRM (official label tracks are protected).
        ListeningSource.soundCloud => Uri.https('m.soundcloud.com', '/'),
        _ => null,
      },
    );
    return Stack(
      children: [
        Positioned.fill(child: studio),
        // Top left, just under the page's top bar (YouTube's is 48 px): any
        // higher and it covers the search bar's back arrow, and then the
        // page cannot leave the search.
        Positioned(
          left: 12,
          top: MediaQuery.viewPaddingOf(context).top + 56,
          // Hidden while the search bar has the focus or the adjustments
          // cover the whole screen.
          child: ListenableBuilder(
            listenable: Listenable.merge([
              pageInputFocused,
              adjustmentsCoverScreen,
              pictureInPictureShown,
              pageUnmutePrompt,
            ]),
            builder: (context, child) => IgnorePointer(
              ignoring: hideHomeButton,
              child: AnimatedOpacity(
                opacity: hideHomeButton ? 0 : 1,
                duration: const Duration(milliseconds: 200),
                child: child,
              ),
            ),
            child: _SourceSwitch(
              spotify: source == ListeningSource.spotify,
              session: _spotify,
              onHome: () => _choose(null),
              onPlayOnYouTube: _playOnYouTube,
            ),
          ),
        ),
      ],
    );
  }
}

/// Small floating controls over the studio: back to the choice screen and,
/// on Spotify, "Tocar no YouTube com tom" for the song that is playing.
class _SourceSwitch extends StatelessWidget {
  const _SourceSwitch({
    required this.spotify,
    required this.session,
    required this.onHome,
    required this.onPlayOnYouTube,
  });

  final bool spotify;
  final SpotifyStudioSession? session;
  final VoidCallback onHome;
  final VoidCallback onPlayOnYouTube;

  @override
  Widget build(BuildContext context) {
    final home = _HomeButton(key: const Key('sourceHome'), onPressed: onHome);
    final current = session;
    if (!spotify || current == null) return home;
    return ListenableBuilder(
      listenable: current,
      builder: (context, _) {
        final track = current.track;
        final ready = track != null && !track.isEmpty;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            home,
            const SizedBox(width: 6),
            _Pill(
              key: const Key('spotifyPlayOnYouTube'),
              tooltip: ready
                  ? 'Tocar «${track.title}» no YouTube com tom'
                  : 'Toque uma música no Spotify primeiro',
              color: ready ? const Color(0xFFFF0033) : const Color(0xCC2A2A2E),
              onPressed: ready ? onPlayOnYouTube : null,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.play_arrow_rounded, size: 18, color: Colors.white),
                  SizedBox(width: 4),
                  Text(
                    'YouTube com tom',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Back to the choice screen: one and a half times the size of the other
/// pills, and every 10 seconds it changes between see-through and
/// see-through black, so it stands out without covering the video for long.
class _HomeButton extends StatefulWidget {
  const _HomeButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_HomeButton> createState() => _HomeButtonState();
}

class _HomeButtonState extends State<_HomeButton> {
  static const _period = Duration(seconds: 10);
  late final Timer _timer;
  bool _dark = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_period, (_) {
      if (mounted) setState(() => _dark = !_dark);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Voltar ao ecrã inicial',
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeInOut,
      decoration: ShapeDecoration(
        color: _dark ? const Color(0x99000000) : Colors.transparent,
        shape: const StadiumBorder(side: BorderSide(color: Color(0x44FFFFFF))),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: widget.onPressed,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 15, vertical: 10.5),
            child: Icon(Icons.apps_rounded, size: 27, color: Colors.white),
          ),
        ),
      ),
    ),
  );
}

class _Pill extends StatelessWidget {
  const _Pill({
    super.key,
    required this.tooltip,
    required this.onPressed,
    required this.child,
    this.color = const Color(0xCC18181B),
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: color,
      shape: const StadiumBorder(side: BorderSide(color: Color(0x44FFFFFF))),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: child,
        ),
      ),
    ),
  );
}

class _PickerScreen extends StatelessWidget {
  const _PickerScreen({
    required this.onYouTube,
    required this.onYouTubeMusic,
    required this.onSoundCloud,
    required this.onSpotify,
  });

  final VoidCallback onYouTube;
  final VoidCallback onYouTubeMusic;
  final VoidCallback onSoundCloud;
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
                      // Two per row on a phone held upright (the third is
                      // centred below), all three in one row when wide.
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: tile * .14,
                        runSpacing: tile * .14,
                        children: [
                          _SourceTile(
                            key: const Key('pickYouTube'),
                            size: tile,
                            label: 'YouTube',
                            caption: 'Tom, EQ e efeitos',
                            logo: const _YouTubeLogo(),
                            accent: const Color(0xFFFF0033),
                            onPressed: onYouTube,
                          ),
                          _SourceTile(
                            key: const Key('pickYouTubeMusic'),
                            size: tile,
                            label: 'YouTube Music',
                            caption: 'Músicas com tom e EQ',
                            logo: const _YouTubeMusicLogo(),
                            accent: const Color(0xFFFF0033),
                            onPressed: onYouTubeMusic,
                          ),
                          _SourceTile(
                            key: const Key('pickSoundCloud'),
                            size: tile,
                            label: 'SoundCloud',
                            caption: 'Covers com tom e EQ',
                            logo: const _SoundCloudLogo(),
                            accent: const Color(0xFFFF5500),
                            onPressed: onSoundCloud,
                          ),
                          _SourceTile(
                            key: const Key('pickSpotify'),
                            size: tile,
                            label: 'Spotify',
                            caption: 'Ouvir e ver a cifra',
                            logo: const _SpotifyLogo(),
                            accent: const Color(0xFF1ED760),
                            onPressed: onSpotify,
                          ),
                        ],
                      ),
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
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: s * .08),
                  // "YouTube Music" shrinks to fit instead of wrapping.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: s * .12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.3,
                      ),
                    ),
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

class _YouTubeMusicLogo extends StatelessWidget {
  const _YouTubeMusicLogo();

  @override
  Widget build(BuildContext context) =>
      const CustomPaint(painter: _YouTubeMusicLogoPainter());
}

/// Red disc, white ring and white play triangle, drawn as vectors.
class _YouTubeMusicLogoPainter extends CustomPainter {
  const _YouTubeMusicLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final d = math.min(size.width, size.height);
    final c = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(c, d / 2, Paint()..color = const Color(0xFFFF0033));
    canvas.drawCircle(
      c,
      d * .29,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = d * .045,
    );
    final t = d * .26;
    final play = Path()
      ..moveTo(c.dx - t * .36, c.dy - t * .45)
      ..lineTo(c.dx + t * .5, c.dy)
      ..lineTo(c.dx - t * .36, c.dy + t * .45)
      ..close();
    canvas.drawPath(play, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SoundCloudLogo extends StatelessWidget {
  const _SoundCloudLogo();

  @override
  Widget build(BuildContext context) =>
      const CustomPaint(painter: _SoundCloudLogoPainter());
}

/// Orange disc with a white cloud and its row of bars, drawn as vectors.
class _SoundCloudLogoPainter extends CustomPainter {
  const _SoundCloudLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final d = math.min(size.width, size.height);
    final c = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(c, d / 2, Paint()..color = const Color(0xFFFF5500));
    final white = Paint()..color = Colors.white;
    final base = c.dy + d * .12;
    // Cloud: two overlapping circles on a rounded base, on the right.
    canvas.drawCircle(Offset(c.dx + d * .06, c.dy - d * .02), d * .14, white);
    canvas.drawCircle(Offset(c.dx + d * .2, c.dy + d * .03), d * .09, white);
    canvas.drawRRect(
      RRect.fromLTRBR(
        c.dx - d * .06,
        c.dy + d * .02,
        c.dx + d * .29,
        base,
        Radius.circular(d * .05),
      ),
      white,
    );
    // Bars rising towards the cloud, on the left.
    for (var i = 0; i < 4; i++) {
      final x = c.dx - d * .3 + i * d * .062;
      final top = base - d * (.1 + i * .045);
      canvas.drawRRect(
        RRect.fromLTRBR(x, top, x + d * .03, base, Radius.circular(d * .015)),
        white,
      );
    }
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
      stroke.strokeWidth = d * arc.t;
      canvas.drawPath(
        Path()
          ..moveTo(left.dx, left.dy)
          ..quadraticBezierTo(control.dx, control.dy, right.dx, right.dy),
        stroke,
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
