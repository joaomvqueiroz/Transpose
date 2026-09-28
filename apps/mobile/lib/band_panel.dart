import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'band_session.dart';

class BandPanel extends StatefulWidget {
  const BandPanel({
    super.key,
    required this.session,
    required this.beforeConnect,
  });
  final BandSession session;
  final Future<void> Function() beforeConnect;
  @override
  State<BandPanel> createState() => _BandPanelState();
}

class _BandPanelState extends State<BandPanel> {
  final _invitation = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _invitation.dispose();
    super.dispose();
  }

  Future<void> _connect(bool host) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.beforeConnect();
      if (!mounted) return;
      if (host) {
        await widget.session.host();
      } else {
        await widget.session.join(_invitation.text);
      }
    } on Object {
      if (mounted) {
        setState(
          () =>
              _error = 'Não foi possível preparar a ligação. Tente novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.session,
    builder: (context, _) {
      final session = widget.session;
      return ExpansionTile(
        title: const Text('Tocar com a banda'),
        subtitle: Text(
          session.connected
              ? session.connectionStatus
              : 'Telemóveis na mesma rede Wi-Fi',
        ),
        childrenPadding: const EdgeInsets.only(bottom: 12),
        children: [
          if (!session.connected) ...[
            const Text(
              'Um músico cria a sessão e partilha o código com os restantes. Mantenha a app aberta.',
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _connect(true),
              icon: const Icon(Icons.group_add_outlined),
              label: const Text('Criar sessão'),
            ),
            TextField(
              controller: _invitation,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Código da sessão',
                hintText: 'transpono://…',
                border: OutlineInputBorder(),
              ),
            ),
            TextButton(
              onPressed: _busy ? null : () => _connect(false),
              child: Text(_busy ? 'A ligar…' : 'Entrar na sessão'),
            ),
          ] else ...[
            if (session.code != null) ...[
              SelectableText(
                session.code!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              TextButton.icon(
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: session.code!)),
                icon: const Icon(Icons.copy),
                label: const Text('Copiar código'),
              ),
            ],
            Text(
              session.isHost
                  ? 'Os controlos acima comandam o metrónomo da banda.'
                  : 'O anfitrião controla o tempo e o início.',
            ),
            Text(
              session.audioStatus['locked'] == true
                  ? 'Saída de áudio temporizada'
                  : 'Saída de áudio em espera',
            ),
            const Text(
              'Modo experimental: precisão entre telemóveis ainda por medir. Bluetooth pode acrescentar atraso.',
            ),
            const SizedBox(height: 8),
            Text('Antecipação desta saída: ${session.correctionMs} ms'),
            Slider(
              min: -250,
              max: 500,
              divisions: 150,
              value: session.correctionMs.toDouble(),
              label: '${session.correctionMs} ms',
              onChanged: (value) =>
                  setState(() => session.correctionMs = value.round()),
            ),
            const Text(
              'Aumente se ouvir este telemóvel atrasado em relação aos outros.',
            ),
            TextButton(
              onPressed: session.leave,
              child: const Text('Sair da sessão'),
            ),
          ],
          if (session.error != null)
            Text(
              session.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      );
    },
  );
}
