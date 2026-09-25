import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transpose_mobile/main_player_controller.dart';
import 'package:transpose_mobile/practice_controller.dart';
import 'package:transpose_mobile/practice_progression_card.dart';
import 'package:transpose_mobile/practice_session.dart';

void main() {
  Future<void> tap(WidgetTester tester, String key) async {
    // Commit field validation before reading the next button's callback.
    await tester.pump();
    final finder = find.byKey(Key(key));
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pump();
  }

  Widget app(_Practice controller, {double scale = 1}) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: Scaffold(
        body: SingleChildScrollView(
          child: PracticeProgressionCard(controller: controller),
        ),
      ),
    ),
  );

  _Practice controller() {
    final model = _Practice();
    addTearDown(() {
      model.dispose();
      model.player.dispose();
    });
    return model;
  }

  bool enabled(WidgetTester tester, String key) =>
      tester.widget<ButtonStyleButton>(find.byKey(Key(key))).onPressed != null;

  testWidgets(
    'default plan starts actual controller and exposes confirmed progress',
    (tester) async {
      final model = controller();
      await tester.pumpWidget(app(model));
      expect(
        find.text('60% → 100% · +5 pontos · 3 voltas por etapa'),
        findsOneWidget,
      );
      expect(enabled(tester, 'practicePlanNext'), isFalse);
      expect(enabled(tester, 'practicePlanStop'), isFalse);
      await tap(tester, 'practicePlanStart');
      expect(model.actions, <String>['start']);
      expect(model.plan.startPercent, 60);
      expect(model.plan.targetPercent, 100);
      expect(model.plan.incrementPercent, 5);
      expect(model.plan.repetitionsPerStep, 3);
      expect(find.text('60% · Etapa 1/9'), findsOneWidget);
      expect(enabled(tester, 'practicePlanStart'), isFalse);
      model.step = 2;
      model.total = 5;
      model.notifyListeners();
      await tester.pump();
      expect(find.text('Voltas nesta etapa: 2/3'), findsOneWidget);
      expect(find.text('Total reproduzido: 5 voltas'), findsOneWidget);
      await tester.pump(const Duration(minutes: 10));
      expect(find.text('Total reproduzido: 5 voltas'), findsOneWidget);
      expect(model.actions, <String>['start']);
    },
  );

  testWidgets('pause resume next stop and restart send distinct real actions', (
    tester,
  ) async {
    final model = controller();
    await tester.pumpWidget(app(model));
    await tap(tester, 'practicePlanStart');
    await tap(tester, 'practicePlanPause');
    expect(find.text('Treino pausado'), findsOneWidget);
    expect(enabled(tester, 'practicePlanResume'), isTrue);
    await tap(tester, 'practicePlanResume');
    await tap(tester, 'practicePlanNext');
    expect(model.currentPercent, 65);
    expect(model.totalRepetitions, 0);
    await tap(tester, 'practicePlanStop');
    expect(find.text('Treino encerrado'), findsOneWidget);
    expect(enabled(tester, 'practicePlanStop'), isFalse);
    await tap(tester, 'practicePlanStart');
    expect(model.actions, <String>[
      'start',
      'pause',
      'resume',
      'next',
      'stop',
      'start',
    ]);
  });

  testWidgets('configuration validates ranges and sends chosen integer plan', (
    tester,
  ) async {
    final model = controller();
    await tester.pumpWidget(app(model));
    await tap(tester, 'practicePlanConfiguration');
    await tester.pumpAndSettle();
    Future<void> edit(String field, String value) async {
      final finder = find.byKey(Key('practicePlan$field'));
      await tester.ensureVisible(finder);
      await tester.enterText(finder, value);
      await tester.pump();
    }

    await edit('StartPercent', '75');
    await edit('TargetPercent', '70');
    expect(enabled(tester, 'practicePlanStart'), isFalse);
    expect(
      find.text('O alvo deve ser igual ou superior ao início.'),
      findsOneWidget,
    );
    await edit('TargetPercent', '90');
    await edit('Increment', '0');
    expect(enabled(tester, 'practicePlanStart'), isFalse);
    await edit('Increment', '3');
    await edit('RepetitionsPerStep', '21');
    expect(enabled(tester, 'practicePlanStart'), isFalse);
    await edit('RepetitionsPerStep', '2');
    await tap(tester, 'practicePlanStartPercentPlus');
    await tap(tester, 'practicePlanStartPercentMinus');
    await tap(tester, 'practicePlanStart');
    expect(model.plan.startPercent, 75);
    expect(model.plan.targetPercent, 90);
    expect(model.plan.incrementPercent, 3);
    expect(model.plan.repetitionsPerStep, 2);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('practicePlanIncrement')))
          .enabled,
      isFalse,
    );
  });

  testWidgets('unsupported reason and external readiness refresh actions', (
    tester,
  ) async {
    final model = controller()
      ..reason = 'A fonte não confirma voltas completas.';
    await tester.pumpWidget(app(model));
    expect(find.text('A fonte não confirma voltas completas.'), findsOneWidget);
    expect(enabled(tester, 'practicePlanStart'), isFalse);
    model.reason = null;
    model.player.notifyListeners();
    await tester.pump();
    expect(enabled(tester, 'practicePlanStart'), isTrue);
    await tap(tester, 'practicePlanStart');
    model.percent = 100;
    model.notifyListeners();
    await tester.pump();
    expect(enabled(tester, 'practicePlanNext'), isFalse);
  });

  testWidgets('pause and stop remain available while preparing', (
    tester,
  ) async {
    final model = controller()
      ..session = true
      ..state = PracticeStatus.preparing
      ..preparing = true;
    await tester.pumpWidget(app(model));
    expect(enabled(tester, 'practicePlanStart'), isFalse);
    expect(enabled(tester, 'practicePlanNext'), isFalse);
    expect(enabled(tester, 'practicePlanPause'), isTrue);
    expect(enabled(tester, 'practicePlanStop'), isTrue);
    await tap(tester, 'practicePlanStop');
    expect(model.actions, <String>['stop']);
  });

  testWidgets(
    'completion and restored plan use honest labels and real totals',
    (tester) async {
      final model = controller();
      await tester.pumpWidget(app(model));
      model
        ..savedPlan = const PracticePlan(
          startPercent: 80,
          targetPercent: 85,
          repetitionsPerStep: 2,
        )
        ..session = true
        ..state = PracticeStatus.completed
        ..percent = 85
        ..step = 2
        ..total = 4
        ..notice = 'Plano concluído recuperado, sem reprodução.';
      model.notifyListeners();
      await tester.pump();
      expect(find.text('Plano concluído'), findsOneWidget);
      expect(find.text('85% · Etapa 2/2'), findsOneWidget);
      expect(find.text('Total reproduzido: 4 voltas'), findsOneWidget);
      expect(
        find.textContaining('não avalia a sua execução musical'),
        findsOneWidget,
      );
      expect(enabled(tester, 'practicePlanStart'), isTrue);
      expect(enabled(tester, 'practicePlanNext'), isFalse);
      expect(find.byKey(const Key('practicePlanResume')), findsNothing);
      expect(model.actions, isEmpty);
    },
  );

  testWidgets('narrow layout with text scale two does not overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final model = controller();
    await tester.pumpWidget(app(model, scale: 2));
    await tap(tester, 'practicePlanConfiguration');
    await tester.pumpAndSettle();
    final field = find.byKey(const Key('practicePlanTargetPercent'));
    await tester.ensureVisible(field);
    await tester.enterText(field, '40');
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.enterText(field, '100');
    await tester.pump();
    expect(enabled(tester, 'practicePlanStart'), isTrue);
    await tap(tester, 'practicePlanStart');
    expect(model.running, isTrue);
    await tap(tester, 'practicePlanPause');
    await tap(tester, 'practicePlanResume');
    await tap(tester, 'practicePlanStop');
    expect(tester.takeException(), isNull);
  });
}

class _Practice extends PracticeController {
  _Practice() : super(MainPlayerController());
  final actions = <String>[];
  PracticePlan savedPlan = const PracticePlan();
  PracticeStatus state = PracticeStatus.notStarted;
  bool session = false, preparing = false;
  int percent = 60, step = 0, total = 0;
  String? reason, notice;
  @override
  PracticePlan get plan => savedPlan;
  @override
  PracticeStatus get status => state;
  @override
  bool get running => state == PracticeStatus.running;
  @override
  bool get busy => preparing;
  @override
  bool get hasSession => session;
  @override
  String? get unavailableReason => reason;
  @override
  String? get message => notice;
  @override
  bool get canStart => !busy && reason == null;
  @override
  bool get canResume => canStart && state == PracticeStatus.paused;
  @override
  int get currentPercent => percent;
  @override
  int get stepRepetitions => step;
  @override
  int get totalRepetitions => total;
  @override
  int get stepNumber =>
      ((percent - plan.startPercent) / plan.incrementPercent).ceil() + 1;
  @override
  Future<void> start(PracticePlan plan) async {
    actions.add('start');
    savedPlan = plan;
    percent = plan.startPercent;
    step = 0;
    total = 0;
    session = true;
    state = PracticeStatus.running;
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    actions.add('pause');
    preparing = false;
    state = PracticeStatus.paused;
    notifyListeners();
  }

  @override
  Future<void> resume() async {
    actions.add('resume');
    state = PracticeStatus.running;
    notifyListeners();
  }

  @override
  Future<void> skipStep() async {
    actions.add('next');
    percent += plan.incrementPercent;
    step = 0;
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    actions.add('stop');
    preparing = false;
    state = PracticeStatus.aborted;
    notifyListeners();
  }
}
