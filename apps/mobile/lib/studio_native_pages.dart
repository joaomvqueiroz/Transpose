import 'package:flutter/material.dart';

const Color studioBg = Color(0xFF0B1826);
const Color studioCard = Color(0xFF142435);
const Color studioCardAlt = Color(0xFF102132);
const Color studioCyan = Color(0xFF19D9F1);
const Color studioMuted = Color(0xFFADB9C7);

/// Resolution-independent recreation of the supplied 390 dp panel designs.
/// Text, icons, cards and lines are rendered by Flutter, never scaled bitmaps.
class StudioNativePage extends StatelessWidget {
  const StudioNativePage(this.name, {super.key});

  final String name;

  @override
  Widget build(BuildContext context) => switch (name) {
    'player' => const _PlayerPanel(),
    'practice' => const _PracticePanel(),
    'chords' => const _ChordsPanel(),
    'stage' => const _StagePanel(),
    _ => const SizedBox.shrink(),
  };
}

class StudioNativeHeader extends StatelessWidget {
  const StudioNativeHeader(this.name, {super.key});

  final String name;

  @override
  Widget build(BuildContext context) {
    final String title = switch (name) {
      'practice' => 'Prática',
      'chords' => 'Acordes',
      'stage' => 'PALCO',
      _ => 'Player',
    };
    return Container(
      height: 57,
      decoration: const BoxDecoration(
        color: Color(0xFF0C1927),
        border: Border(bottom: BorderSide(color: Color(0xFF1A2A3A))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: <Widget>[
          const Icon(Icons.menu, size: 24, color: studioMuted),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
          ),
          if (name == 'stage')
            const _Pill(Icons.lock_outline, 'BLOQUEAR TELA')
          else ...<Widget>[
            if (name == 'player') ...<Widget>[
              const Icon(Icons.search, color: studioMuted),
              const SizedBox(width: 17),
            ],
            const Icon(Icons.more_horiz, color: studioMuted),
            if (name != 'player') ...<Widget>[
              const SizedBox(width: 17),
              const CircleAvatar(
                radius: 15,
                backgroundColor: Color(0xFFD5FAFF),
                child: Icon(Icons.person_outline, color: studioBg, size: 19),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _PanelCard extends StatelessWidget {
  const _PanelCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color = studioCard,
  });
  final Widget child;
  final EdgeInsets padding;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: color,
      border: Border.all(color: const Color(0xFF203246)),
      borderRadius: BorderRadius.circular(15),
    ),
    child: child,
  );
}

class _Label extends StatelessWidget {
  const _Label(this.text, {this.color = studioMuted, this.size = 11});
  final String text;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      color: color,
      fontSize: size,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.9,
    ),
  );
}

class _Pill extends StatelessWidget {
  const _Pill(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: studioCardAlt,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFF254256)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 15, color: studioCyan),
        const SizedBox(width: 5),
        Text(
          text,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: studioCyan,
          ),
        ),
      ],
    ),
  );
}

class _PlayerPanel extends StatelessWidget {
  const _PlayerPanel();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: studioBg,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 65, 16, 24),
      child: Column(
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  Image.asset(
                    'assets/visual_refs/concert_guitarist_hd.png',
                    fit: BoxFit.cover,
                    alignment: const Alignment(-0.1, -0.15),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[Colors.transparent, Color(0xD9000B16)],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 14,
                    right: 14,
                    bottom: 47,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: const LinearProgressIndicator(
                        value: .38,
                        minHeight: 6,
                        color: studioCyan,
                        backgroundColor: Color(0x66FFFFFF),
                      ),
                    ),
                  ),
                  const Positioned(
                    left: 14,
                    bottom: 15,
                    child: Text(
                      '01:24  /  03:42',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: studioCyan,
                      ),
                    ),
                  ),
                  const Positioned(
                    right: 13,
                    bottom: 13,
                    child: Icon(Icons.fullscreen, size: 23),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _PanelCard(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
            child: Row(
              children: <Widget>[
                const Icon(
                  Icons.touch_app_outlined,
                  color: studioCyan,
                  size: 19,
                ),
                const SizedBox(width: 9),
                const Expanded(
                  child: Text(
                    'Dica: Dê duplo toque para avançar ou voltar…',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: studioMuted, fontSize: 13),
                  ),
                ),
                const Icon(Icons.close, color: studioMuted, size: 17),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _PanelCard(
            child: Column(
              children: <Widget>[
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[_Label('TOM'), _Label('Original: C')],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    const CircleAvatar(
                      radius: 24,
                      backgroundColor: Color(0xFF203146),
                      child: Icon(Icons.remove, color: Colors.white),
                    ),
                    Column(
                      children: <Widget>[
                        const Text(
                          'B♭',
                          style: TextStyle(
                            fontSize: 38,
                            fontWeight: FontWeight.w800,
                            height: 1,
                          ),
                        ),
                        const Text(
                          '-2 semitons',
                          style: TextStyle(
                            color: studioCyan,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const CircleAvatar(
                      radius: 24,
                      backgroundColor: Color(0xFF203146),
                      child: Icon(Icons.add, color: Colors.white),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _PanelCard(
            child: Column(
              children: <Widget>[
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    _Label('VELOCIDADE'),
                    Text(
                      '0.85x',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 23),
                const LinearProgressIndicator(
                  value: .35,
                  minHeight: 6,
                  color: studioCyan,
                  backgroundColor: Color(0xFF25384D),
                ),
                const SizedBox(height: 23),
                Row(
                  children: <Widget>[
                    for (final String value in <String>[
                      '0.75x',
                      '0.85x',
                      '1.00x',
                    ]) ...<Widget>[
                      Expanded(
                        child: Container(
                          height: 43,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1B2C40),
                            border: Border.all(
                              color: value == '0.85x'
                                  ? studioCyan
                                  : const Color(0xFF2C4055),
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            value,
                            style: TextStyle(
                              color: value == '0.85x'
                                  ? studioCyan
                                  : studioMuted,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      if (value != '1.00x') const SizedBox(width: 8),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _PanelCard(
            child: Column(
              children: <Widget>[
                const Row(
                  children: <Widget>[
                    Icon(Icons.repeat, color: studioMuted, size: 18),
                    SizedBox(width: 8),
                    Expanded(child: _Label('REPETIÇÃO A–B')),
                    Switch(
                      value: true,
                      onChanged: null,
                      activeThumbColor: studioCyan,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(child: _loopPoint('PONTO A', '01:14')),
                    const SizedBox(width: 9),
                    Expanded(child: _loopPoint('PONTO B', '01:38')),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const CircleAvatar(
                radius: 27,
                backgroundColor: studioCard,
                child: Icon(Icons.replay_10, color: Colors.white),
              ),
              const SizedBox(width: 24),
              const CircleAvatar(
                radius: 29,
                backgroundColor: studioCyan,
                child: Icon(Icons.pause, size: 30, color: studioBg),
              ),
              const SizedBox(width: 24),
              const CircleAvatar(
                radius: 27,
                backgroundColor: studioCard,
                child: Icon(Icons.forward_10, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const _PanelCard(
            padding: EdgeInsets.all(14),
            child: Row(
              children: <Widget>[
                Icon(Icons.school_outlined, size: 20, color: studioMuted),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Ferramentas de Estudo',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Icon(Icons.expand_more, color: studioMuted),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            '▥  Ferramentas Áudio Avançado ⌄',
            style: TextStyle(color: studioMuted, fontSize: 13),
          ),
        ],
      ),
    ),
  );

  static Widget _loopPoint(String label, String time) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: const Color(0xFF1B2D40),
      borderRadius: BorderRadius.circular(10),
    ),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(
              color: studioMuted,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            time,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    ),
  );
}

class _PracticePanel extends StatelessWidget {
  const _PracticePanel();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: studioBg,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 65, 16, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _PanelCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: _Label('⟳  DOMINAR TRECHO', color: studioCyan),
                      ),
                    ),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: _Label('● Em Reprodução'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Solo Principal',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                ),
                const Text(
                  '02:13 – 02:37  ·  Duração: 24s',
                  style: TextStyle(
                    color: studioMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                const Center(
                  child: Text.rich(
                    TextSpan(
                      children: <InlineSpan>[
                        TextSpan(
                          text: '70',
                          style: TextStyle(
                            fontSize: 62,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        TextSpan(
                          text: '%',
                          style: TextStyle(
                            fontSize: 18,
                            color: studioCyan,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Center(
                  child: Text(
                    '━━   ━━   ▬    Repetição 2 de 3',
                    style: TextStyle(color: studioMuted, fontSize: 12),
                  ),
                ),
                const SizedBox(height: 12),
                const LinearProgressIndicator(
                  value: .65,
                  minHeight: 7,
                  color: studioCyan,
                  backgroundColor: Color(0xFF3A4859),
                ),
                const SizedBox(height: 9),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '↗ Próximo incremento: 75%',
                          style: TextStyle(
                            color: studioCyan,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          'Ciclo 2/5',
                          style: TextStyle(color: studioMuted, fontSize: 11),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 17),
                Row(
                  children: <Widget>[
                    Expanded(child: _practiceButton('-5%')),
                    const SizedBox(width: 5),
                    Expanded(
                      flex: 2,
                      child: Container(
                        height: 54,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: studioCyan,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Ⅱ  PAUSAR',
                          style: TextStyle(
                            color: studioBg,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Expanded(child: _practiceButton('+5%')),
                  ],
                ),
                const SizedBox(height: 23),
                const Row(
                  children: <Widget>[
                    Icon(Icons.tune, color: studioMuted, size: 17),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Configuração do Treino',
                        style: TextStyle(
                          color: studioMuted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Icon(Icons.expand_more, color: studioMuted),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 17),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Partes da Música',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    'Pressione para alternar',
                    style: TextStyle(color: studioMuted, fontSize: 11),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: Column(
              children: <Widget>[
                for (final (String time, String title) in <(String, String)>[
                  ('00:00', 'Intro'),
                  ('00:18', 'Verso 1'),
                  ('01:14', 'Refrão'),
                  ('02:13', 'Solo'),
                  ('02:45', 'Bridge'),
                  ('03:20', 'Final'),
                ])
                  Container(
                    height: 66,
                    padding: const EdgeInsets.symmetric(horizontal: 15),
                    decoration: BoxDecoration(
                      color: title == 'Solo'
                          ? const Color(0xFF153148)
                          : studioCard,
                      border: title == 'Solo'
                          ? const Border(
                              left: BorderSide(color: studioCyan, width: 4),
                            )
                          : null,
                    ),
                    child: Row(
                      children: <Widget>[
                        Text(
                          time,
                          style: TextStyle(
                            color: title == 'Solo' ? studioCyan : studioMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 17),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                title,
                                style: TextStyle(
                                  color: title == 'Solo'
                                      ? studioCyan
                                      : Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                              if (title == 'Solo')
                                const Text(
                                  '● Tocando agora · Loop Ativo',
                                  style: TextStyle(
                                    color: studioMuted,
                                    fontSize: 10,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Icon(
                          title == 'Solo' ? Icons.equalizer : Icons.replay,
                          color: title == 'Solo' ? studioCyan : studioMuted,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Loops Salvos',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    '⚑ Salvar atual',
                    style: TextStyle(color: studioCyan, fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          _savedLoop('Solo Rápido', '02:24 – 02:37 · 85% meta'),
          const SizedBox(height: 5),
          _savedLoop('Riff de Abertura', '00:04 – 00:18 · 100% pronto'),
        ],
      ),
    ),
  );

  static Widget _practiceButton(String text) => Container(
    height: 54,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: const Color(0xFF1D2E40),
      borderRadius: BorderRadius.circular(11),
    ),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.w800)),
  );

  static Widget _savedLoop(String title, String detail) => _PanelCard(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    child: Row(
      children: <Widget>[
        const Icon(Icons.repeat, color: studioCyan),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(
                detail,
                style: const TextStyle(color: studioMuted, fontSize: 10),
              ),
            ],
          ),
        ),
        const Icon(Icons.play_arrow, color: studioMuted),
      ],
    ),
  );
}

class _ChordsPanel extends StatelessWidget {
  const _ChordsPanel();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: studioBg,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 65, 16, 26),
      child: Column(
        children: <Widget>[
          _PanelCard(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: <Widget>[
                const Icon(Icons.queue_music, color: studioCyan),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Sultans of Swing',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        'Dire Straits · Tom atual: B♭ (-2)',
                        style: TextStyle(fontSize: 11, color: studioMuted),
                      ),
                    ],
                  ),
                ),
                const _Label('4/4 · 148 BPM', color: studioCyan, size: 10),
              ],
            ),
          ),
          const SizedBox(height: 15),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                flex: 3,
                child: _chordCard(
                  '● AGORA',
                  'B♭',
                  'Maior c/ Pestana',
                  'Casa 1',
                  true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: _chordCard('A SEGUIR', 'Gm', 'Menor', 'Casa 3', false),
              ),
            ],
          ),
          const SizedBox(height: 15),
          _PanelCard(
            child: Column(
              children: <Widget>[
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: _Label('SEQUÊNCIA NO COMPASSO'),
                      ),
                    ),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: _Label(
                          'Compassos 14–17',
                          color: studioCyan,
                          size: 10,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 13),
                Row(
                  children: <Widget>[
                    for (final (String caption, String chord, String bar)
                        in <(String, String, String)>[
                          ('AGORA', 'B♭', 'c.14'),
                          ('PRÓX', 'Gm', 'c.15'),
                          ('DEPOIS', 'E♭', 'c.16'),
                          ('FIM', 'F', 'c.17'),
                        ]) ...<Widget>[
                      Expanded(
                        child: Container(
                          height: 86,
                          decoration: BoxDecoration(
                            color: caption == 'AGORA'
                                ? const Color(0xFF263C4E)
                                : studioCardAlt,
                            borderRadius: BorderRadius.circular(8),
                            border: caption == 'AGORA'
                                ? const Border(
                                    bottom: BorderSide(
                                      color: studioCyan,
                                      width: 2,
                                    ),
                                  )
                                : null,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              _Label(
                                caption,
                                color: caption == 'AGORA'
                                    ? studioCyan
                                    : studioMuted,
                                size: 9,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                chord,
                                style: TextStyle(
                                  color: caption == 'AGORA'
                                      ? studioCyan
                                      : Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              _Label(bar, size: 9),
                            ],
                          ),
                        ),
                      ),
                      if (caption != 'FIM') const SizedBox(width: 4),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 15),
          _PanelCard(
            padding: const EdgeInsets.all(12),
            color: studioCardAlt,
            child: const Row(
              children: <Widget>[
                Icon(Icons.push_pin, color: studioCyan),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Capo na 2ª casa para posições abertas no violão acústico (formato Lá Maior).',
                    style: TextStyle(fontSize: 12, color: studioMuted),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 15),
          for (final (IconData icon, String text) in <(IconData, String)>[
            (Icons.grid_on, 'Ver diagrama no braço da guitarra'),
            (Icons.receipt_long, 'Ver progressão harmônica completa'),
            (Icons.sync_alt, 'Detalhes da transposição (+2 semitons)'),
            (Icons.edit_note, 'Notas da música'),
          ]) ...<Widget>[
            _PanelCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
              child: Row(
                children: <Widget>[
                  Icon(icon, color: studioCyan, size: 19),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      text,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const Icon(Icons.expand_more, color: studioMuted),
                ],
              ),
            ),
            const SizedBox(height: 5),
          ],
          const SizedBox(height: 11),
          const _PanelCard(
            padding: EdgeInsets.all(16),
            child: Center(
              child: Text(
                '🎙  ABRIR GRAVADOR DE ESTUDO   →',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .7,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  static Widget _chordCard(
    String heading,
    String chord,
    String type,
    String fret,
    bool current,
  ) => _PanelCard(
    color: current ? const Color(0xFF162B3C) : studioCardAlt,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _Label(heading, color: current ? studioCyan : studioMuted, size: 10),
        const SizedBox(height: 10),
        Text(
          chord,
          style: TextStyle(
            color: current ? studioCyan : Colors.white,
            fontSize: current ? 47 : 37,
            fontWeight: FontWeight.w900,
            height: 1.1,
          ),
        ),
        Text(type, style: const TextStyle(color: studioMuted, fontSize: 12)),
        const SizedBox(height: 22),
        Text(fret, style: const TextStyle(fontSize: 12, color: studioMuted)),
      ],
    ),
  );
}

class _StagePanel extends StatelessWidget {
  const _StagePanel();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: studioBg,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 69, 16, 26),
      child: Column(
        children: <Widget>[
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: _Pill(Icons.circle, 'ENSAIO DOMINGO  ·  3 DE 12'),
                ),
              ),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: _Label('AO VIVO', color: studioCyan),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const _Label('MÚSICA EM ANDAMENTO', color: studioCyan),
          const SizedBox(height: 7),
          const Text(
            'GRAVITY (LIVE)',
            style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 20),
          _PanelCard(
            padding: const EdgeInsets.symmetric(vertical: 22),
            child: Column(
              children: <Widget>[
                const _Label('TOM ATUAL DA BANDA'),
                const SizedBox(height: 14),
                const Text(
                  'B♭',
                  style: TextStyle(
                    fontSize: 69,
                    height: 1,
                    color: studioCyan,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 17),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: studioCardAlt,
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: const Text(
                    '-2 semitons  ·  Original em C',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(child: _stageSmall('⊖  −1 Tom')),
              const SizedBox(width: 12),
              Expanded(child: _stageSmall('⊕  +1 Tom')),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            height: 76,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: studioCyan,
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Text(
              '▶  EXECUTAR',
              style: TextStyle(
                color: studioBg,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(child: _stageSong('← ANTERIOR', 'Waiting on the World')),
              const SizedBox(width: 12),
              Expanded(child: _stageSong('PRÓXIMA →', 'Slow Dancing')),
            ],
          ),
          const SizedBox(height: 18),
          const _PanelCard(
            child: Row(
              children: <Widget>[
                Icon(Icons.tune, color: studioCyan),
                SizedBox(width: 10),
                Expanded(
                  child: _Label(
                    'AFINADOR & METRÔNOMO RÁPIDO',
                    color: Colors.white,
                  ),
                ),
                Icon(Icons.expand_more, color: studioMuted),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  static Widget _stageSmall(String text) => _PanelCard(
    padding: const EdgeInsets.symmetric(vertical: 15),
    child: Center(
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
      ),
    ),
  );

  static Widget _stageSong(String label, String song) => _PanelCard(
    padding: const EdgeInsets.all(13),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _Label(
          label,
          color: label.startsWith('PRÓXIMA') ? studioCyan : studioMuted,
          size: 10,
        ),
        const SizedBox(height: 7),
        Text(
          song,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}

class StudioNativeSidebar extends StatelessWidget {
  const StudioNativeSidebar({super.key});

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFF0A1724),
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Row(
              children: <Widget>[
                CircleAvatar(
                  radius: 18,
                  backgroundColor: studioCard,
                  child: Icon(Icons.graphic_eq, color: studioCyan),
                ),
                SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Transpono',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                        ),
                      ),
                      _Label('AUDIO LAB', color: studioCyan, size: 9),
                    ],
                  ),
                ),
                Icon(Icons.chevron_left, color: studioMuted),
              ],
            ),
            const SizedBox(height: 18),
            _PanelCard(
              padding: const EdgeInsets.all(11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      _Label('AGORA A TOCAR', size: 9),
                      _Label('● 0.85x', color: studioCyan, size: 9),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: Image.asset(
                          'assets/visual_refs/concert_guitarist_hd.png',
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 9),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'Sultans of Swing',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              'Dire Straits',
                              style: TextStyle(
                                color: studioMuted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tom: B♭      Loop A–B       03:42 / 05:48',
                    style: TextStyle(color: studioMuted, fontSize: 10),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const _Label('NAVEGAÇÃO & ESTUDO', size: 10),
            const SizedBox(height: 7),
            for (final (IconData icon, String title, String trailing)
                in <(IconData, String, String)>[
                  (Icons.play_circle_outline, 'Agora a Tocar', '●'),
                  (Icons.folder_open, 'Biblioteca', '48'),
                  (Icons.queue_music, 'Setlists', '4'),
                  (Icons.repeat, 'Loops Salvos', '12 trechos'),
                  (Icons.tune, 'Predefinições de Afinação', 'E♭, D'),
                  (Icons.mic_none, 'Gravações de Ensaio', '●'),
                  (Icons.speed, 'Afinador & Metrônomo', 'Tap'),
                  (Icons.show_chart, 'Progresso e Prática', '14.2h'),
                ])
              _sidebarRow(icon, title, trailing),
            const Divider(color: Color(0xFF263849), height: 28),
            const _Label('SISTEMA & AJUSTES', size: 10),
            const SizedBox(height: 8),
            _sidebarRow(
              Icons.settings_outlined,
              'Configurações de Áudio',
              'DSP',
            ),
            _sidebarRow(Icons.help_outline, 'Ajuda & Atalhos de Teclado', '↗'),
            const SizedBox(height: 20),
            _PanelCard(
              padding: const EdgeInsets.all(11),
              child: Row(
                children: <Widget>[
                  const CircleAvatar(
                    radius: 17,
                    backgroundColor: studioCyan,
                    child: Icon(Icons.person, color: studioBg),
                  ),
                  const SizedBox(width: 9),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Músico Pro',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Motor DSP Ativo',
                          style: TextStyle(fontSize: 10, color: studioCyan),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.logout, size: 17, color: studioMuted),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  static Widget _sidebarRow(IconData icon, String title, String trailing) =>
      SizedBox(
        height: 45,
        child: Row(
          children: <Widget>[
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: studioCard,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 17, color: studioMuted),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              trailing,
              style: const TextStyle(color: studioMuted, fontSize: 10),
            ),
          ],
        ),
      );
}
