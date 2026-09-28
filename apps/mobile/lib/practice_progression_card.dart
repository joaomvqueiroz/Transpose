import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'practice_controller.dart';
import 'practice_session.dart';
import 'studio_native_pages.dart';

/// Presentation of a real practice session. It never schedules repetitions.
class PracticeProgressionCard extends StatefulWidget {
  const PracticeProgressionCard({
    required this.controller,
    this.embedded = false,
    super.key,
  });

  final PracticeController controller;
  final bool embedded;

  @override
  State<PracticeProgressionCard> createState() =>
      _PracticeProgressionCardState();
}

class _PracticeProgressionCardState extends State<PracticeProgressionCard> {
  late final TextEditingController _start;
  late final TextEditingController _target;
  late final TextEditingController _increment;
  late final TextEditingController _repetitions;
  late PracticePlan _shownPlan;
  String? _actionError;

  @override
  void initState() {
    super.initState();
    _shownPlan = widget.controller.plan;
    _start = TextEditingController(text: '${_shownPlan.startPercent}');
    _target = TextEditingController(text: '${_shownPlan.targetPercent}');
    _increment = TextEditingController(text: '${_shownPlan.incrementPercent}');
    _repetitions = TextEditingController(
      text: '${_shownPlan.repetitionsPerStep}',
    );
    widget.controller.addListener(_syncPlan);
  }

  @override
  void didUpdateWidget(PracticeProgressionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncPlan);
      widget.controller.addListener(_syncPlan);
      _replacePlan(widget.controller.plan);
    }
  }

  void _syncPlan() {
    final plan = widget.controller.plan;
    if (!identical(plan, _shownPlan)) _replacePlan(plan);
  }

  void _replacePlan(PracticePlan plan) {
    _shownPlan = plan;
    _start.text = '${plan.startPercent}';
    _target.text = '${plan.targetPercent}';
    _increment.text = '${plan.incrementPercent}';
    _repetitions.text = '${plan.repetitionsPerStep}';
    _actionError = null;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncPlan);
    _start.dispose();
    _target.dispose();
    _increment.dispose();
    _repetitions.dispose();
    super.dispose();
  }

  PracticePlan get _draft => PracticePlan(
    startPercent: int.tryParse(_start.text) ?? 0,
    targetPercent: int.tryParse(_target.text) ?? 0,
    incrementPercent: int.tryParse(_increment.text) ?? 0,
    repetitionsPerStep: int.tryParse(_repetitions.text) ?? 0,
  );

  Future<void> _invoke(Future<void> Function() action) async {
    setState(() => _actionError = null);
    try {
      await action();
    } on Object {
      if (mounted) {
        setState(() {
          _actionError = 'Não foi possível confirmar a ação. Verifique o player e tente novamente.';
        });
      }
    }
  }

  String? _rangeError(TextEditingController field, int min, int max) {
    final value = int.tryParse(field.text);
    return value == null || value < min || value > max
        ? 'Use um inteiro entre $min e $max.'
        : null;
  }

  Widget _field({
    required String name,
    required String label,
    required TextEditingController field,
    required int min,
    required int max,
    required bool enabled,
    String? extraError,
  }) {
    final value = int.tryParse(field.text);
    void adjust(int delta) {
      final next = ((value ?? min) + delta).clamp(min, max);
      setState(() => field.text = '$next');
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              IconButton(
                key: Key('practicePlan${name}Minus'),
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                tooltip: 'Diminuir $label',
                onPressed: enabled && (value == null || value > min)
                    ? () => adjust(-1)
                    : null,
                icon: const Icon(Icons.remove),
              ),
              Expanded(
                child: Semantics(
                  label: label,
                  child: TextField(
                    key: Key('practicePlan$name'),
                    controller: field,
                    enabled: enabled,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(3),
                    ],
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      errorText: _rangeError(field, min, max) ?? extraError,
                      errorMaxLines: 4,
                    ),
                    textAlign: TextAlign.center,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ),
              IconButton(
                key: Key('practicePlan${name}Plus'),
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                tooltip: 'Aumentar $label',
                onPressed: enabled && (value == null || value < max)
                    ? () => adjust(1)
                    : null,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _statusLabel(PracticeStatus status) => switch (status) {
    PracticeStatus.notStarted => 'Pronto para configurar',
    PracticeStatus.preparing => 'A preparar etapa',
    PracticeStatus.running => 'Treino em curso',
    PracticeStatus.paused => 'Treino pausado',
    PracticeStatus.completed => 'Plano concluído',
    PracticeStatus.aborted => 'Treino encerrado',
  };

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge(<Listenable>[
      widget.controller,
      widget.controller.player,
    ]),
    builder: (context, _) {
      final controller = widget.controller;
      final active =
          controller.busy ||
          controller.running ||
          controller.status == PracticeStatus.paused;
      final canEdit = !active;
      final draft = _draft;
      final plan = active ? controller.plan : draft;
      final reason = controller.unavailableReason;
      final canNext =
          !controller.busy &&
          controller.canStart &&
          (controller.running || controller.canResume) &&
          controller.currentPercent < controller.plan.targetPercent;
      return Material(
        key: const Key('practicePlanCard'),
        color: widget.embedded ? Colors.transparent : studioCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(widget.embedded ? 8 : 16),
          side: widget.embedded
              ? BorderSide.none
              : const BorderSide(color: Color(0xFF353537)),
        ),
        child: Padding(
          padding: EdgeInsets.all(widget.embedded ? 4 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (!widget.embedded) ...[
                const Text(
                  'PROGRESSÃO DE VELOCIDADE',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: studioCyan,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Text(
                _statusLabel(controller.status),
                key: const Key('practicePlanStatus'),
                style: TextStyle(
                  fontSize: widget.embedded ? 12 : 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${plan.startPercent}% → ${plan.targetPercent}% · '
                '+${plan.incrementPercent} pontos · '
                '${plan.repetitionsPerStep} voltas por etapa',
                key: const Key('practicePlanSummary'),
                style: widget.embedded ? const TextStyle(fontSize: 11) : null,
              ),
              if (controller.hasSession) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  '${controller.currentPercent}% · '
                  'Etapa ${controller.stepNumber}/${controller.plan.steps}',
                  key: const Key('practicePlanStep'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  'Voltas nesta etapa: ${controller.stepRepetitions}/'
                  '${controller.plan.repetitionsPerStep}',
                  key: const Key('practicePlanRepetitions'),
                ),
                Text(
                  'Total reproduzido: ${controller.totalRepetitions} voltas',
                  key: const Key('practicePlanTotal'),
                ),
              ],
              const SizedBox(height: 10),
              const Text(
                'Cada nova etapa faz uma breve pausa para ajustar a velocidade '
                'e recomeçar em A. Retomar também volta a A. '
                'A contagem não avalia a sua execução musical.',
                style: TextStyle(color: studioMuted, fontSize: 11),
              ),
              if (controller.busy) ...<Widget>[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
              if (reason != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(reason, key: const Key('practicePlanUnavailable')),
              ],
              if (_actionError ?? controller.message case final String message)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(message, key: const Key('practicePlanMessage')),
                  ),
                ),
              const SizedBox(height: 8),
              ExpansionTile(
                key: const Key('practicePlanConfiguration'),
                tilePadding: EdgeInsets.zero,
                title: const Text('Configurar plano'),
                children: <Widget>[
                  if (!canEdit)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text('Encerre o treino para editar o plano.'),
                    ),
                  _field(
                    name: 'StartPercent',
                    label: 'Velocidade inicial (%)',
                    field: _start,
                    min: 50,
                    max: 150,
                    enabled: canEdit,
                  ),
                  _field(
                    name: 'TargetPercent',
                    label: 'Velocidade-alvo (%)',
                    field: _target,
                    min: 50,
                    max: 150,
                    enabled: canEdit,
                    extraError: draft.targetPercent < draft.startPercent
                        ? 'O alvo deve ser igual ou superior ao início.'
                        : null,
                  ),
                  _field(
                    name: 'Increment',
                    label: 'Aumento por etapa (pontos percentuais)',
                    field: _increment,
                    min: 1,
                    max: 20,
                    enabled: canEdit,
                  ),
                  _field(
                    name: 'RepetitionsPerStep',
                    label: 'Voltas por etapa',
                    field: _repetitions,
                    min: 1,
                    max: 20,
                    enabled: canEdit,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FilledButton(
                key: const Key('practicePlanStart'),
                onPressed: canEdit && controller.canStart && draft.valid
                    ? () => unawaited(_invoke(() => controller.start(draft)))
                    : null,
                child: Text(
                  controller.hasSession ? 'Recomeçar plano' : 'Iniciar plano',
                ),
              ),
              if (controller.running || controller.busy)
                OutlinedButton(
                  key: const Key('practicePlanPause'),
                  onPressed: () => unawaited(_invoke(controller.pause)),
                  child: const Text('Pausar treino'),
                ),
              if (controller.status == PracticeStatus.paused)
                FilledButton(
                  key: const Key('practicePlanResume'),
                  onPressed: controller.canResume
                      ? () => unawaited(_invoke(controller.resume))
                      : null,
                  child: const Text('Retomar a partir de A'),
                ),
              OutlinedButton(
                key: const Key('practicePlanNext'),
                onPressed: canNext
                    ? () => unawaited(_invoke(controller.skipStep))
                    : null,
                child: const Text('Próxima etapa (sem contar voltas)'),
              ),
              OutlinedButton(
                key: const Key('practicePlanStop'),
                onPressed: controller.hasSession && active
                    ? () => unawaited(_invoke(controller.stop))
                    : null,
                child: const Text('Encerrar treino'),
              ),
            ],
          ),
        ),
      );
    },
  );
}
