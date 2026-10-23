import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anthrofit/models/models.dart';
import 'package:anthrofit/reps/pose_frame.dart';
import 'package:anthrofit/reps/pose_source.dart';
import 'package:anthrofit/reps/rep_counter.dart';
import 'package:anthrofit/reps/rep_signal.dart';
import 'package:anthrofit/scan/camera_permission.dart';
import 'package:anthrofit/screens/session/guided_set_screen.dart';

// The camera rep counter, checked on made-up poses. These show the counting
// logic does what it says; they say nothing about accuracy on real people,
// which needs real sets counted by hand.

Exercise _ex(
  String name,
  MovementPattern pattern,
  List<MuscleGroup> muscles, {
  ExerciseType type = ExerciseType.freeWeight,
  List<String> instructions = const [],
}) => Exercise(
  id: name,
  name: name,
  exerciseType: type,
  movementPattern: pattern,
  primaryMuscles: muscles,
  equipment: const [EquipmentItem.dumbbell],
  experienceLevel: ExperienceLevel.beginner,
  complexity: Complexity.low,
  instructions: instructions,
);

/// A pose with the given knee angles (degrees), or a hidden side for null.
PoseFrame _knees(double? left, double? right, {int ms = 0}) {
  final points = List.filled(
    PoseIndex.count,
    const PoseLandmark(0, 0, 0, 0),
  );
  void side(int hip, int knee, int ankle, double? angle) {
    if (angle == null) return;
    final rad = (180 - angle) * math.pi / 180;
    points[hip] = const PoseLandmark(0, 0, 0, 0.99);
    points[knee] = const PoseLandmark(0, 0.45, 0, 0.99);
    points[ankle] = PoseLandmark(
      0.45 * math.sin(rad),
      0.45 + 0.45 * math.cos(rad),
      0,
      0.99,
    );
  }

  side(PoseIndex.leftHip, PoseIndex.leftKnee, PoseIndex.leftAnkle, left);
  side(PoseIndex.rightHip, PoseIndex.rightKnee, PoseIndex.rightAnkle, right);
  return PoseFrame(landmarks: points, timestampMs: ms);
}

/// [frame] at time [ms], with the body at [body] in the image.
PoseFrame _at(PoseFrame frame, int ms, PoseBody body) =>
    PoseFrame(landmarks: frame.landmarks, timestampMs: ms, body: body);

/// [reps] smooth cycles from [from] to [to] and back, 40 frames each.
List<double> _cycles(int reps, double from, double to) => [
  for (var i = 0; i < reps * 40; i++)
    from + (to - from) * (1 - math.cos(i / 40 * 2 * math.pi)) / 2,
  from,
];

Iterable<PoseFrame> _timedCycles(
  int reps,
  double from,
  double to, {
  required int periodMs,
  required int frameMs,
}) sync* {
  for (var rep = 0; rep < reps; rep++) {
    for (var elapsed = 0; elapsed < periodMs; elapsed += frameMs) {
      final phase = elapsed / periodMs * 2 * math.pi;
      final angle = (from + to) / 2 + (from - to) / 2 * math.cos(phase);
      yield _knees(angle, angle, ms: rep * periodMs + elapsed);
    }
  }
}

class _Granted implements CameraPermission {
  @override
  Future<CameraAccess> check() async => CameraAccess.granted;
  @override
  Future<CameraAccess> request() async => CameraAccess.granted;
  @override
  Future<bool> openSettings() async => true;
}

void main() {
  group('which joint is followed', () {
    test('by movement pattern and, for isolation, the first muscle', () {
      expect(
        repSignalFor(_ex('Squat', MovementPattern.kneeDominant, [MuscleGroup.quads])),
        RepSignal.knee,
      );
      expect(
        repSignalFor(_ex('RDL', MovementPattern.hipDominant, [MuscleGroup.hamstrings])),
        RepSignal.hip,
      );
      expect(
        repSignalFor(_ex('Row', MovementPattern.horizontalPull, [MuscleGroup.lats])),
        RepSignal.elbow,
      );
      expect(
        repSignalFor(_ex('Curl', MovementPattern.isolation, [MuscleGroup.biceps])),
        RepSignal.elbow,
      );
      expect(
        repSignalFor(_ex('Raise', MovementPattern.isolation, [MuscleGroup.sideDelts])),
        RepSignal.shoulder,
      );
      expect(
        repSignalFor(_ex('Calf', MovementPattern.isolation, [MuscleGroup.calves])),
        RepSignal.ankle,
      );
    });

    test('cardio and shrugs are not counted by camera', () {
      expect(
        repSignalFor(
          _ex('Run', MovementPattern.cardio, [MuscleGroup.quads],
              type: ExerciseType.cardio),
        ),
        isNull,
      );
      expect(
        repSignalFor(_ex('Shrug', MovementPattern.isolation, [MuscleGroup.traps])),
        isNull,
      );
    });
  });

  group('pose input', () {
    test('a right angle reads as 90 degrees', () {
      expect(
        jointAngle(
          const PoseLandmark(1, 0, 0, 1),
          const PoseLandmark(0, 0, 0, 1),
          const PoseLandmark(0, 1, 0, 1),
        ),
        closeTo(90, 1e-9),
      );
    });

    test('a malformed event is read as no pose, not guessed at', () {
      expect(PoseFrame.fromEvent({'landmarks': [[1, 2]]}).hasPose, isFalse);
      expect(PoseFrame.fromEvent({}).hasPose, isFalse);
      final ok = PoseFrame.fromEvent({
        'timestampMs': 5,
        'landmarks': List.filled(33, [0.1, 0.2, 0.3, 0.9]),
      });
      expect(ok.hasPose, isTrue);
      expect(ok.timestampMs, 5);
      expect(
        PoseFrame.fromEvent({
          'landmarks': List.filled(33, [double.nan, 0.2, 0.3, 0.9]),
        }).hasPose,
        isFalse,
      );
    });
  });

  group('counting', () {
    test('five squats from standing count five', () {
      final c = RepCounter(RepSignal.knee);
      for (final a in _cycles(5, 170, 90)) {
        c.add(_knees(a, a));
      }
      expect(c.reps, 5);
    });

    test('a movement that starts at the low end counts too', () {
      final c = RepCounter(RepSignal.knee);
      for (final a in _cycles(3, 90, 160)) {
        c.add(_knees(a, a));
      }
      expect(c.reps, 3);
    });

    test('standing still with jittery landmarks counts nothing', () {
      final c = RepCounter(RepSignal.knee);
      final rng = math.Random(1);
      for (var i = 0; i < 300; i++) {
        final a = 170 + (rng.nextDouble() - 0.5) * 6; // +/- 3 degrees
        c.add(_knees(a, a));
      }
      expect(c.reps, 0);
    });

    test('strong timestamped standing jitter does not arm the counter', () {
      final c = RepCounter(RepSignal.knee);
      final rng = math.Random(8);
      for (var i = 0; i < 300; i++) {
        final a = 165 + (rng.nextDouble() - 0.5) * 24;
        c.add(_knees(a, a, ms: i * 33));
      }
      expect(c.reps, 0);
    });

    test('fast complete repetitions count without median-filter delay', () {
      final c = RepCounter(RepSignal.knee);
      for (final frame in _timedCycles(
        4,
        170,
        90,
        periodMs: 400,
        frameMs: 33,
      )) {
        c.add(frame);
      }
      expect(c.reps, 4);
    });

    test(
      'partial repetitions without full joint endpoints are not counted',
      () {
        final c = RepCounter(RepSignal.knee);
        for (final a in _cycles(5, 145, 100)) {
          c.add(_knees(a, a));
        }
        expect(c.reps, 0);
      },
    );

    test('small incidental knee movements are not counted as squats', () {
      final c = RepCounter(RepSignal.knee);
      for (final a in _cycles(8, 170, 145)) {
        c.add(_knees(a, a));
      }
      expect(c.reps, 0);
    });

    test('a half-way rep after full ones is not counted', () {
      final c = RepCounter(RepSignal.knee);
      for (final a in [..._cycles(2, 170, 90), ..._cycles(1, 170, 150)]) {
        c.add(_knees(a, a));
      }
      expect(c.reps, 2);
    });

    test('one-leg work counts on the side that moves', () {
      final c = RepCounter(RepSignal.knee);
      for (final a in _cycles(4, 170, 100)) {
        c.add(_knees(a, 170));
      }
      expect(c.reps, 4);
    });

    test('hidden joints count nothing and report out of view', () {
      final c = RepCounter(RepSignal.knee);
      for (final _ in _cycles(2, 170, 90)) {
        c.add(_knees(null, null));
      }
      expect(c.reps, 0);
      expect(c.inView, isFalse);
      c.add(const PoseFrame(landmarks: [], timestampMs: 0));
      expect(c.inView, isFalse);
    });

    test('a one-frame landmark glitch does not break counting', () {
      final c = RepCounter(RepSignal.knee);
      final angles = _cycles(5, 170, 90);
      angles[50] = 20; // one wildly wrong frame
      for (var i = 0; i < angles.length; i++) {
        c.add(_knees(angles[i], angles[i], ms: i * 100));
      }
      expect(c.reps, 5);
    });

    test('a half-hidden, jittery far side does not add reps', () {
      final c = RepCounter(RepSignal.knee);
      final rng = math.Random(3);
      final angles = _cycles(5, 170, 90);
      for (var i = 0; i < angles.length; i++) {
        // The far side is seen in one frame of three, at random angles.
        c.add(
          _knees(angles[i], i % 3 == 0 ? 60 + rng.nextDouble() * 120 : null),
        );
      }
      expect(c.reps, 5);
    });

    test('real squats still count with real time and a still body', () {
      final c = RepCounter(RepSignal.knee);
      final angles = _cycles(5, 170, 90);
      for (var i = 0; i < angles.length; i++) {
        c.add(
          _at(
            _knees(angles[i], angles[i]),
            i * 50,
            const PoseBody(0.4, 0.5, 0.2),
          ),
        );
      }
      expect(c.reps, 5);
      expect(c.moving, isFalse);
    });

    test('quick twitches are not reps', () {
      final c = RepCounter(RepSignal.knee);
      var ms = 0;
      for (var twitch = 0; twitch < 5; twitch++) {
        // A second standing still, then a 170 -> 110 -> 170 flick in 150 ms.
        for (final a in [
          ...List.filled(30, 170.0),
          140.0,
          110.0,
          110.0,
          140.0,
          170.0,
        ]) {
          c.add(_knees(a, a, ms: ms));
          ms += 33;
        }
      }
      expect(c.reps, 0);
    });

    test('bending down slowly and standing up again is not a rep', () {
      final c = RepCounter(RepSignal.knee);
      // One 170 -> 90 -> 170 cycle stretched over 16 seconds.
      final angles = _cycles(1, 170, 90);
      for (var i = 0; i < angles.length; i++) {
        c.add(_knees(angles[i], angles[i], ms: i * 400));
      }
      expect(c.reps, 0);
    });

    test('walking across the room is not counted', () {
      final c = RepCounter(RepSignal.knee);
      // Knees swinging like squats while the hips cross the image at about
      // three torso lengths a second.
      final angles = _cycles(6, 170, 110);
      for (var i = 0; i < angles.length; i++) {
        final ms = i * 33;
        c.add(
          _at(
            _knees(angles[i], angles[i]),
            ms,
            PoseBody(ms / 1000 * 0.6, 0.5, 0.2),
          ),
        );
      }
      expect(c.reps, 0);
      expect(c.moving, isTrue);
    });

    test('walking up to the phone is not counted', () {
      final c = RepCounter(RepSignal.knee);
      final angles = _cycles(6, 170, 110);
      for (var i = 0; i < angles.length; i++) {
        final ms = i * 33;
        // The torso looks half as big again every second.
        c.add(
          _at(
            _knees(angles[i], angles[i]),
            ms,
            PoseBody(0.4, 0.5, 0.1 * math.pow(1.5, ms / 1000)),
          ),
        );
      }
      expect(c.reps, 0);
    });

    test('a rep half done before walking off is not finished on return', () {
      final c = RepCounter(RepSignal.knee);
      var ms = 0;
      void frame(double a, double x) {
        c.add(_at(_knees(a, a), ms, PoseBody(x, 0.5, 0.2)));
        ms += 33;
      }

      // Two squats in place.
      for (final a in _cycles(2, 170, 90)) {
        frame(a, 0.4);
      }
      // Down to the bottom, then walk away and back still bent.
      for (final a in _cycles(1, 170, 90).take(20)) {
        frame(a, 0.4);
      }
      for (var i = 0; i < 60; i++) {
        frame(90, 0.4 + 0.02 * (i < 30 ? i : 60 - i));
      }
      // Hold still a moment, then stand up: that is not a third rep.
      for (var i = 0; i < 40; i++) {
        frame(90, 0.4);
      }
      for (var i = 0; i <= 20; i++) {
        frame(90 + 80 * i / 20, 0.4);
      }
      expect(c.reps, 2);
      // A full squat after that counts again.
      for (final a in _cycles(1, 170, 90)) {
        frame(a, 0.4);
      }
      expect(c.reps, 3);
    });

    test('tracking loss abandons a partial rep and counting recovers', () {
      final c = RepCounter(RepSignal.knee);
      var ms = 0;
      void add(double angle) {
        c.add(_knees(angle, angle, ms: ms));
        ms += 33;
      }

      for (final frame in _timedCycles(
        1,
        170,
        90,
        periodMs: 1000,
        frameMs: 33,
      )) {
        c.add(frame);
        ms = frame.timestampMs + 33;
      }
      expect(c.reps, 1);

      add(170);
      add(145);
      add(110);
      add(90);
      c.add(PoseFrame(landmarks: const [], timestampMs: ms + 700));
      ms += 733;
      add(170);
      expect(c.reps, 1);

      for (final angle in _cycles(1, 170, 90)) {
        add(angle);
      }
      expect(c.reps, 2);
    });

    test('a native event carries where the body is', () {
      final f = PoseFrame.fromEvent({
        'timestampMs': 1,
        'landmarks': List.filled(33, [0.1, 0.2, 0.3, 0.9]),
        'body': [0.4, 0.5, 0.2],
      });
      expect(f.body?.torso, 0.2);
      expect(
        PoseFrame.fromEvent({
          'landmarks': List.filled(33, [0.1, 0.2, 0.3, 0.9]),
          'body': [0.4, 0.5, 0],
        }).body,
        isNull,
      );
      expect(
        PoseFrame.fromEvent({
          'landmarks': List.filled(33, [0.1, 0.2, 0.3, 0.9]),
          'body': [double.nan, 0.5, 0.2],
        }).body,
        isNull,
      );
    });

    test('the mock squatter counts one rep per period', () {
      final c = RepCounter(RepSignal.knee);
      for (var ms = 50; ms <= 6000; ms += 50) {
        c.add(MockPoseSource.squatFrame(ms, 2000));
      }
      expect(c.reps, 3);
    });
  });

  group('guided set screen', () {
    /// Opens [screen] from a button and returns a getter for what it popped.
    Future<GuidedSetResult? Function()> host(
      WidgetTester tester,
      GuidedSetScreen screen,
    ) async {
      GuidedSetResult? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () async {
                    result = await Navigator.of(context).push<GuidedSetResult>(
                      MaterialPageRoute(builder: (_) => screen),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      return () => result;
    }

    final squat = _ex(
      'Goblet squat',
      MovementPattern.kneeDominant,
      [MuscleGroup.quads],
      instructions: const [
        'Hold the weight at your chest.',
        'Sit down and stand up.',
      ],
    );

    testWidgets('without the camera: steps, then a tap counter', (
      tester,
    ) async {
      final result = await host(
        tester,
        GuidedSetScreen(
          exercise: squat,
          setNumber: 2,
          target: '10 reps',
          cameraAvailable: false,
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Hold the weight at your chest.'), findsOneWidget);
      expect(find.text('Set 2 · Target: 10 reps'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('guided-camera-unavailable')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('guided-start-camera')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('guided-start-tap')));
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const ValueKey('guided-tap-area')));
        await tester.pump();
      }
      await tester.tap(find.byKey(const ValueKey('guided-minus')));
      await tester.pump();
      expect(find.text('2'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('guided-done')));
      await tester.pumpAndSettle();
      expect(result()?.reps, 2);
      expect(result()?.weight, '');
    });

    testWidgets('with the camera: counts reps, and can be corrected', (
      tester,
    ) async {
      final source = MockPoseSource(period: const Duration(seconds: 2));
      final result = await host(
        tester,
        GuidedSetScreen(
          exercise: squat,
          setNumber: 1,
          workoutName: 'Upper A',
          cameraAvailable: true,
          permission: _Granted(),
          createSource: () => source,
          startDelay: Duration.zero,
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      // Where to put the phone comes first, in plain steps.
      expect(find.byKey(const ValueKey('guided-setup')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('guided-workout-header')),
        findsOneWidget,
      );
      expect(
        find.text('Turn sideways, so the phone sees your side, not your front.'),
        findsOneWidget,
      );
      // The counting note sits below the steps, so scroll down to it.
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('guided-camera-note')),
        200,
      );
      expect(find.byKey(const ValueKey('guided-camera-note')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('guided-start-camera')));
      await tester.pump(); // permission check
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 4100));
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('guided-count'))).data,
        '2',
      );

      expect(find.byKey(const ValueKey('guided-weight')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('guided-weight-control')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('guided-weight')), '40');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('guided-plus')));
      await tester.pump();
      // Done stops the mock's timer by leaving the screen.
      await tester.tap(find.byKey(const ValueKey('guided-done')));
      await tester.pumpAndSettle();
      expect(result()?.reps, 3);
      expect(result()?.weight, '40');
    });

    testWidgets('nothing is counted while getting into position', (
      tester,
    ) async {
      await host(
        tester,
        GuidedSetScreen(
          exercise: squat,
          setNumber: 1,
          cameraAvailable: true,
          permission: _Granted(),
          createSource: () => MockPoseSource(),
          startDelay: const Duration(seconds: 2),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('guided-start-camera')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('guided-countdown')), findsOneWidget);
      expect(find.byKey(const ValueKey('guided-placement')), findsOneWidget);

      // A full squat happens during the countdown: not counted.
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pump(const Duration(milliseconds: 1000));
      expect(find.byKey(const ValueKey('guided-countdown')), findsNothing);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('guided-count'))).data,
        '0',
      );

      // Two more squats once counting has started.
      await tester.pump(const Duration(milliseconds: 4100));
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('guided-count'))).data,
        '2',
      );
      await tester.tap(find.byKey(const ValueKey('guided-done')));
      await tester.pumpAndSettle();
    });

    testWidgets('an exercise the camera cannot count offers tapping only', (
      tester,
    ) async {
      await host(
        tester,
        GuidedSetScreen(
          exercise: _ex('Shrug', MovementPattern.isolation, [MuscleGroup.traps]),
          setNumber: 1,
          cameraAvailable: true,
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('guided-no-camera')), findsOneWidget);
      expect(find.byKey(const ValueKey('guided-start-camera')), findsNothing);
      expect(find.text('No step-by-step guide for this exercise yet.'),
          findsOneWidget);
    });
  });
}
