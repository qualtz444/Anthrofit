import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anthrofit/composition/body_composition.dart';
import 'package:anthrofit/data/program_repository.dart';
import 'package:anthrofit/models/models.dart';
import 'package:anthrofit/screens/composition/composition_result_screen.dart';
import 'package:anthrofit/state/program_controller.dart';
import 'package:anthrofit/state/program_scope.dart';

import 'test_helpers.dart';

// A new body composition estimate never changes the active program, so the
// result says when that program is built for a different goal.

const _estimate = CompositionEstimate(
  value: 18.4, // a man: the ACE "Average" range -> Improve body composition
  low: 17.5,
  high: 19.5,
  mae: 2.8,
  coverage80: 80.5,
);

const _result = BodyCompositionResult(
  measurements: SilhouetteMeasurements(
    waist: 82.1,
    bicep: 30.2,
    hip: 95.3,
    chest: 98.0,
    thigh: 55.4,
  ),
  bodyFatPct: _estimate,
  appendicularLeanKg: CompositionEstimate(
    value: 24.0,
    low: 22.0,
    high: 26.0,
    mae: 1.1,
    coverage80: 80.0,
  ),
  fatMassKg: 12.1,
  fatFreeMassKg: 53.4,
  frameCount: 3,
  waistSpreadCm: 1.2,
);

const _input = CompositionInput(
  heightCm: 170,
  weightKg: 65.5,
  age: 25,
  isMale: true,
);

TrainingProgram _program(TrainingGoal goal) => TrainingProgram(
  id: 'p',
  name: 'My Plan',
  goal: goal,
  createdAt: DateTime(2026, 10, 1),
  updatedAt: DateTime(2026, 10, 1),
);

Future<void> _show(WidgetTester tester, TrainingGoal activeGoal) async {
  seedProfileAndPrograms([_program(activeGoal)], activeProgramId: 'p');
  final programs = ProgramController(ProgramRepository());
  await programs.load();
  await tester.pumpWidget(
    ProgramScope(
      controller: programs,
      child: const MaterialApp(
        home: CompositionResultScreen(result: _result, input: _input),
      ),
    ),
  );
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('suggested-goal')),
    200,
  );
}

void main() {
  testWidgets('a program built for another goal is pointed out', (
    tester,
  ) async {
    await _show(tester, TrainingGoal.loseFat);
    final note = find.byKey(const ValueKey('program-goal-differs'));
    await tester.scrollUntilVisible(note, 100);
    expect(note, findsOneWidget);
    expect(find.textContaining('My Plan, is still set for'), findsOneWidget);
  });

  testWidgets('no note when the program already matches', (tester) async {
    await _show(tester, TrainingGoal.improveBodyComposition);
    expect(
      find.byKey(const ValueKey('program-goal-differs')),
      findsNothing,
    );
  });
}
