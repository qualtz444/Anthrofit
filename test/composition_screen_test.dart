import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anthrofit/composition/body_composition.dart';
import 'package:anthrofit/composition/composition_models.dart';
import 'package:anthrofit/composition/composition_source.dart';
import 'package:anthrofit/data/profile_repository.dart';
import 'package:anthrofit/models/models.dart';
import 'package:anthrofit/scan/camera_permission.dart';
import 'package:anthrofit/screens/composition/body_composition_screen.dart';
import 'package:anthrofit/screens/composition/composition_result_screen.dart';
import 'package:anthrofit/state/profile_controller.dart';
import 'package:anthrofit/state/profile_scope.dart';

import 'test_helpers.dart';

class _GrantedCamera implements CameraPermission {
  @override
  Future<CameraAccess> check() async => CameraAccess.granted;

  @override
  Future<CameraAccess> request() async => CameraAccess.granted;

  @override
  Future<bool> openSettings() async => true;
}

/// Never builds a platform view; the test pushes states by hand.
class FakeCompositionSource implements CompositionSource {
  final controller = StreamController<CompositionCaptureState>.broadcast();
  int starts = 0;
  int retries = 0;

  @override
  Stream<CompositionCaptureState> get states => controller.stream;

  @override
  Widget preview() => const ColoredBox(color: Colors.black);

  @override
  void start() => starts++;

  @override
  void retry() => retries++;

  @override
  void dispose() => controller.close();
}

Future<ProfileController> _profileWith(Sex sex) async {
  seedNoProfile();
  final controller = ProfileController(ProfileRepository());
  await controller.save(sampleProfile.copyWith(sex: sex));
  return controller;
}

const _estimate = CompositionEstimate(
  value: 18.4,
  low: 14.9,
  high: 22.1,
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

void main() {
  group('capture events', () {
    test('a progress event is read as-is', () {
      final state = CompositionCaptureState.fromEvent({
        'phase': 'holding',
        'step': 'side',
        'stepIndex': 1,
        'stepCount': 2,
        'title': 'Turn 90 degrees to your right',
        'message': 'Hold still',
        'holdProgress': 0.5,
      });
      expect(state.phase, CompositionPhase.holding);
      expect(state.step, 'side');
      expect(state.stepIndex, 1);
      expect(state.title, 'Turn 90 degrees to your right');
      expect(state.holdProgress, 0.5);
    });

    test('done decodes masks and drops damaged ones', () {
      // 4 wide, 2 tall: row 0 has one run (start 1, length 2), row 1 none.
      const good = [4, 2, 1, 1, 2, 0];
      const damaged = [4, 2, 1, 3, 5, 0]; // run past the edge
      final state = CompositionCaptureState.fromEvent({
        'phase': 'done',
        'front': [good, damaged],
        'side': [good],
      });
      expect(state.phase, CompositionPhase.done);
      expect(state.front.length, 1);
      expect(state.side.length, 1);
      expect(state.front.single.mask, [0, 1, 1, 0, 0, 0, 0, 0]);
    });

    test('an unknown phase is treated as positioning', () {
      final state = CompositionCaptureState.fromEvent({'phase': 'what'});
      expect(state.phase, CompositionPhase.positioning);
    });
  });

  group('screen', () {
    testWidgets('no profile: explains why and does not start the camera', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: BodyCompositionScreen()));
      expect(find.byKey(const ValueKey('composition-blocker')), findsOneWidget);
      expect(find.text('Before you start'), findsNothing);
      expect(find.text('Start'), findsNothing);
    });

    testWidgets('prefer not to say gets no estimate', (tester) async {
      final profile = await _profileWith(Sex.preferNotToSay);
      await tester.pumpWidget(
        ProfileScope(
          controller: profile,
          child: const MaterialApp(home: BodyCompositionScreen()),
        ),
      );
      expect(find.textContaining('Male or Female'), findsOneWidget);
    });

    testWidgets('a capture with no usable frames shows a retry', (
      tester,
    ) async {
      final profile = await _profileWith(Sex.male);
      final source = FakeCompositionSource();
      await tester.pumpWidget(
        ProfileScope(
          controller: profile,
          child: MaterialApp(
            home: BodyCompositionScreen(
              permission: _GrantedCamera(),
              createSource: (_) => source,
              // Empty models: the empty capture fails before they are used.
              loadModels: () async => const CompositionModels(
                stage1: {},
                stage2: {},
                stage1Features: [],
                stage2Features: [],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(source.starts, 1);
      expect(find.text('Before you start'), findsNothing);
      expect(find.textContaining('US adults aged 18-59'), findsNothing);

      source.controller.add(
        const CompositionCaptureState(phase: CompositionPhase.done),
      );
      await tester.pumpAndSettle();

      expect(find.text("The capture didn't finish"), findsOneWidget);
      expect(find.textContaining('No usable front and side'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(source.retries, 1);
      expect(find.text("The capture didn't finish"), findsNothing);
    });
  });

  testWidgets('photos are always kept and the camera receives that setting', (
    tester,
  ) async {
    final profile = await _profileWith(Sex.male);
    bool? asked;
    final source = FakeCompositionSource();
    await tester.pumpWidget(
      ProfileScope(
        controller: profile,
        child: MaterialApp(
          home: BodyCompositionScreen(
            permission: _GrantedCamera(),
            createSource: (includePhotos) {
              asked = includePhotos;
              return source;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(asked, isTrue);
  });

  group('result', () {
    testWidgets('shows the estimate, its range and the caveats', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: CompositionResultScreen(
            result: _result,
            input: CompositionInput(
              heightCm: 170,
              weightKg: 65.5,
              age: 25,
              isMale: true,
            ),
          ),
        ),
      );
      // The ring and the breakdown both show the estimate.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('body-fat-ring')),
          matching: find.text('18.4%'),
        ),
        findsOneWidget,
      );
      // The date and how sure it is come first.
      expect(find.byKey(const ValueKey('composition-date')), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('composition-confidence')))
            .data,
        contains('80% range 14.9% to 22.1%'),
      );
      expect(find.textContaining('An estimate, not a measurement'), findsOneWidget);
      // Three masses, then the breakdown, which repeats the range.
      await tester.scrollUntilVisible(
        find.text('Arm & leg lean mass').first,
        200,
      );
      expect(find.text('Arm & leg lean mass'), findsWidgets);
      await tester.scrollUntilVisible(
        find.textContaining('80% range: 14.9% to 22.1%'),
        200,
      );
      expect(
        find.textContaining('80% range: 14.9% to 22.1%'),
        findsOneWidget,
      );
      // Circumferences fold away, in cm or in.
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('circumferences')),
        -200,
      );
      await tester.tap(find.text('Estimated circumferences'));
      await tester.pumpAndSettle();
      expect(find.text('82.1 cm'), findsOneWidget);
      await tester.tap(find.text('in'));
      await tester.pumpAndSettle();
      expect(find.text('32.3 in'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.textContaining('Not a medical device'),
        200,
      );
      expect(find.textContaining('Not a medical device'), findsOneWidget);
      expect(find.textContaining('trained on ages'), findsNothing);
    });

    testWidgets('suggests a goal from the ACE body fat range', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: CompositionResultScreen(
            result: _result,
            input: CompositionInput(
              heightCm: 170,
              weightKg: 65.5,
              age: 25,
              isMale: true,
            ),
          ),
        ),
      );
      final card = find.byKey(const ValueKey('suggested-goal'));
      await tester.scrollUntilVisible(card, 200);
      // 18.4% for a man is the ACE "Average" range (18-24%).
      expect(
        find.descendant(of: card, matching: find.text('Improve body composition')),
        findsOneWidget,
      );
      expect(find.textContaining('"Average"'), findsOneWidget);
      // 14.9-22.1% reaches from Fitness into Average, so it says so.
      expect(find.textContaining('rough guide'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('build-plan-suggested')),
        findsOneWidget,
      );
    });

    testWidgets('the result omits the age-range warning', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: CompositionResultScreen(
            result: _result,
            input: CompositionInput(
              heightCm: 170,
              weightKg: 65.5,
              age: 64,
              isMale: false,
            ),
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey('composition-age-warning')),
        findsNothing,
      );
    });
  });
}
