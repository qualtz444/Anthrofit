import 'package:flutter_test/flutter_test.dart';

import 'package:anthrofit/community/community_models.dart';
import 'package:anthrofit/community/post_builder.dart';
import 'package:anthrofit/community/share_builder.dart';
import 'package:anthrofit/data/training_stats.dart';
import 'package:anthrofit/screens/community/post_card.dart';
import 'package:anthrofit/models/models.dart';

import 'test_helpers.dart';

const _me = CommunityProfile(uid: 'u1', handle: 'ben', displayName: 'Ben');

WorkoutSession _session(
  String id,
  DateTime end,
  List<(double?, int)> sets, {
  String exerciseId = 'bench',
}) => WorkoutSession(
  id: id,
  workoutId: 'w',
  workoutName: 'Push',
  startedAt: end.subtract(const Duration(minutes: 50)),
  completedAt: end,
  exerciseLogs: [
    ExerciseLog(
      id: 'l$id',
      exerciseId: exerciseId,
      plannedExerciseId: 'pe',
      exerciseName: 'Bench Press',
      sets: [
        for (var i = 0; i < sets.length; i++)
          SetLog(
            setNumber: i + 1,
            weightKg: sets[i].$1,
            reps: sets[i].$2,
            isCompleted: true,
            completedAt: end,
          ),
      ],
    ),
  ],
);

void main() {
  useExerciseLibrary();

  group('usernames', () {
    test('valid and invalid handles', () {
      expect(validateHandle('ben_01'), isNull);
      expect(validateHandle('ab'), isNotNull);
      expect(validateHandle('Ben'), isNotNull);
      expect(validateHandle('has space'), isNotNull);
      expect(validateHandle('a' * 21), isNotNull);
    });
  });

  group('post builder', () {
    final today = _session('s2', DateTime(2026, 10, 12, 18), [
      (60, 8),
      (60, 7),
      (55, 10),
    ]);

    test('summarises sets, volume, time and the top set', () {
      final p = buildWorkoutPost(
        session: today,
        history: const [],
        author: _me,
        friendUids: const ['f1'],
      );
      expect(p.id, 'u1_s2');
      expect(p.totalSets, 3);
      expect(p.volumeKg, 60 * 8 + 60 * 7 + 55 * 10);
      expect(p.durationMinutes, 50);
      expect(p.exercises.single.topWeightKg, 60);
      expect(p.exercises.single.topReps, 8);
      expect(p.audience, containsAll(['u1', 'f1']));
    });

    test('a heavier top set than every earlier session is a record', () {
      final p = buildWorkoutPost(
        session: today,
        history: [
          _session('s1', DateTime(2026, 10, 5), [(57.5, 8)]),
        ],
        author: _me,
        friendUids: const [],
      );
      expect(p.records.single.weightKg, 60);
    });

    test('the first time an exercise is done is not a record', () {
      final p = buildWorkoutPost(
        session: today,
        history: const [],
        author: _me,
        friendUids: const [],
      );
      expect(p.records, isEmpty);
    });

    test('matching an earlier best is not a record', () {
      final p = buildWorkoutPost(
        session: today,
        history: [
          _session('s1', DateTime(2026, 10, 5), [(60, 10)]),
        ],
        author: _me,
        friendUids: const [],
      );
      expect(p.records, isEmpty);
    });

    test('a post carries workout data only', () {
      final json = buildWorkoutPost(
        session: today,
        history: const [],
        author: _me,
        friendUids: const [],
      ).toJson();
      for (final banned in ['bodyFat', 'weightKg', 'photo', 'measurement']) {
        expect(
          json.keys.any((k) => k.contains(banned)),
          isFalse,
          reason: banned,
        );
      }
    });
  });

  group('program and progress posts', () {
    test('a shared program drops its notes and setup, keeps the training', () {
      final program = TrainingProgram(
        id: 'p1',
        name: 'PPL',
        goal: TrainingGoal.buildMuscle,
        workouts: [
          Workout(
            id: 'w1',
            name: 'Push',
            exercises: [
              testPlanned(
                'pe1',
                'barbell_bench_press',
                note: 'Setup tip: wider grip for your longer arms',
              ),
            ],
          ),
        ],
        createdAt: DateTime(2026, 9, 1),
        updatedAt: DateTime(2026, 9, 1),
      );
      final post = buildProgramPost(
        program: program,
        author: _me,
        friendUids: const ['f1'],
      );
      expect(post.kind, PostKind.program);
      expect(post.id, startsWith('u1_program_'));
      expect(post.program!['setup'], isNull);
      final copy = TrainingProgram.fromJson(post.program!);
      expect(copy.workouts.single.exercises.single.note, '');
      expect(copy.workouts.single.exercises.single.plannedSets, hasLength(3));
      expect(post.totalSets, 3);
    });

    test('progress: workouts, sets and top-weight change in 30 days', () {
      final post = buildProgressPost(
        sessions: [
          _session('a', DateTime(2026, 10, 1), [(50, 8)]),
          _session('b', DateTime(2026, 10, 10), [(60, 8), (60, 7)]),
        ],
        author: _me,
        friendUids: const [],
        today: DateTime(2026, 10, 12),
      );
      expect(post.kind, PostKind.progress);
      expect(post.workoutCount, 2);
      expect(post.periodDays, 30);
      expect(post.changes.single.fromKg, 50);
      expect(post.changes.single.toKg, 60);
    });

    test('one session is not a change', () {
      final post = buildProgressPost(
        sessions: [
          _session('a', DateTime(2026, 10, 1), [(50, 8)]),
        ],
        author: _me,
        friendUids: const [],
        today: DateTime(2026, 10, 12),
      );
      expect(post.changes, isEmpty);
    });
  });

  group('compete', () {
    WorkoutPost post(
      String author,
      DateTime at,
      int sets, {
      PostKind kind = PostKind.workout,
    }) => WorkoutPost(
      id: '${author}_$at',
      authorUid: author,
      authorHandle: author,
      authorName: author,
      audience: const [],
      createdAt: at,
      workoutName: 'W',
      durationMinutes: 40,
      totalSets: sets,
      volumeKg: 0,
      exercises: const [],
      records: const [],
      kind: kind,
    );

    test('leaderboard: most workouts, then sets; only shared workouts', () {
      final since = DateTime(2026, 10, 6);
      final rows = leaderboard(
        [
          post('a', DateTime(2026, 10, 7), 10),
          post('a', DateTime(2026, 10, 8), 10),
          post('b', DateTime(2026, 10, 7), 30),
          post('b', DateTime(2026, 10, 1), 30), // before the period
          post('b', DateTime(2026, 10, 9), 0, kind: PostKind.progress),
        ],
        since,
        include: const ['a', 'b', 'c'],
      );
      expect(rows.map((r) => r.uid), ['a', 'b', 'c']);
      expect(rows.first.workouts, 2);
      expect(rows[1].workouts, 1);
      expect(rows.last.workouts, 0);
    });

    test('a challenge round-trips and starts everyone at 0', () {
      final c = Challenge(
        id: 'x',
        creatorUid: 'a',
        title: 'October push',
        metric: ChallengeMetric.sets,
        target: 200,
        start: DateTime(2026, 10, 1),
        end: DateTime(2026, 10, 31),
        members: const ['a', 'b'],
        handles: const {'a': 'ann', 'b': 'bob'},
        progress: const {},
      );
      final back = Challenge.fromJson('x', c.toJson());
      expect(back.metric, ChallengeMetric.sets);
      expect(back.progress, {'a': 0, 'b': 0});
      expect(back.activeOn(DateTime(2026, 10, 15)), isTrue);
      expect(back.activeOn(DateTime(2026, 11, 2)), isFalse);
    });

    test('inbox messages read naturally', () {
      final i = InboxItem(
        id: '1',
        type: InboxType.comment,
        fromUid: 'b',
        fromHandle: 'bob',
        createdAt: DateTime(2026, 10, 12),
        text: 'Nice PR!',
      );
      expect(i.message, '@bob commented: Nice PR!');
    });
  });

  group('share composer posts', () {
    final today = DateTime(2026, 10, 12);
    final sessions = [
      _session('a', DateTime(2026, 10, 1), [(50, 8), (50, 8)]),
      _session('b', DateTime(2026, 10, 10), [(60, 6), (55, 10)]),
    ];
    CompositionRecord scan(String id, DateTime at, double fat) =>
        CompositionRecord(
          id: id,
          takenAt: at,
          weightKg: 70,
          bodyFatPct: fat,
          bodyFatLow: fat - 3,
          bodyFatHigh: fat + 3,
          leanLimbKg: 24,
          fatFreeMassKg: 70 * (1 - fat / 100),
          fatMassKg: 70 * fat / 100,
          waistCm: 80,
          chestCm: 95,
          hipCm: 94,
          thighCm: 54,
          upperArmCm: 29,
          frameCount: 3,
        );

    test('overall: only the ticked parts are filled in', () {
      final s = buildShare(
        topic: ShareTopic.overall,
        items: {ShareItem.workouts, ShareItem.volumeChart},
        range: ProgressRange.month1,
        sessions: sessions,
        today: today,
      );
      expect(s.workouts, 2);
      expect(s.sets, 4);
      expect(s.volumeKg, isNull);
      expect(s.changes, isEmpty);
      expect(s.charts.single.kind, ShareChartKind.volume);
      expect([for (final p in s.charts.single.points) p.value], [800, 910]);
      expect(s.toJson().containsKey('volumeKg'), isFalse);
    });

    test('one exercise: best weight, best set, sessions and weight chart', () {
      final s = buildShare(
        topic: ShareTopic.exercise,
        exerciseId: 'bench',
        items: {
          ShareItem.bestWeight,
          ShareItem.bestSet,
          ShareItem.sessions,
          ShareItem.weightChart,
          // Not for this topic: ignored.
          ShareItem.bodyFat,
        },
        range: ProgressRange.month1,
        sessions: sessions,
        today: today,
      );
      expect(s.title, 'Bench Press');
      expect(s.sessions, 2);
      expect(s.bestWeightKg, 60);
      // 55 × 10 = 550 beats 60 × 6 = 360.
      expect(s.bestSetKg, 55);
      expect(s.bestSetReps, 10);
      expect([for (final p in s.charts.single.points) p.value], [50, 60]);
      expect(s.bodyFatPct, isNull);
    });

    test('body composition: latest scan, previous scan, nothing else', () {
      final s = buildShare(
        topic: ShareTopic.body,
        items: {ShareItem.bodyFat, ShareItem.bodyChange},
        range: ProgressRange.month1,
        sessions: const [],
        scans: [
          scan('new', DateTime(2026, 10, 10), 20),
          scan('old', DateTime(2026, 9, 1), 22),
        ],
        today: today,
      );
      expect(s.bodyFatPct, 20);
      expect(s.bodyFatLow, 17);
      expect(s.previousBodyFatPct, 22);
      expect(s.fatFreeMassKg, isNull);
      expect(s.charts, isEmpty);
      final json = s.toJson();
      for (final banned in ['weightKg', 'waist', 'outline', 'photo']) {
        expect(
          json.keys.any((k) => k.contains(banned)),
          isFalse,
          reason: banned,
        );
      }
    });

    test('body weight: latest entry, change and chart round-trip', () {
      final s = buildShare(
        topic: ShareTopic.bodyWeight,
        items: {ShareItem.weight, ShareItem.bodyWeightChart},
        range: ProgressRange.month1,
        sessions: const [],
        weightLog: [
          BodyWeightEntry(date: DateTime(2026, 10, 2), weightKg: 72),
          BodyWeightEntry(date: DateTime(2026, 10, 10), weightKg: 70.5),
        ],
        today: today,
      );
      expect(s.bodyWeightKg, 70.5);
      expect(s.bodyWeightChangeKg, -1.5);
      expect(s.charts.single.kind, ShareChartKind.bodyWeight);
      final back = ProgressShare.fromJson(s.toJson());
      expect(back.bodyWeightKg, 70.5);
      expect(back.charts.single.points.last.value, 70.5);
    });

    test(
      'muscle distribution: workout coverage and weekly days round-trip',
      () {
        final session = _session('bench-session', DateTime(2026, 10, 5), [
          (50, 8),
        ], exerciseId: 'machine_chest_press');
        final s = buildShare(
          topic: ShareTopic.muscles,
          items: {ShareItem.muscleCoverage},
          range: ProgressRange.allTime,
          sessions: [session],
          muscleWeekStart: DateTime(2026, 10, 5),
          today: today,
        );
        expect(s.muscleWorkouts, 1);
        expect(s.muscles, isNotEmpty);
        expect(s.muscles.any((m) => m.primaryWorkouts > 0), isTrue);
        final back = ProgressShare.fromJson(s.toJson());
        expect(back.muscleWeekStart, DateTime(2026, 10, 5));
        expect(back.muscles.length, s.muscles.length);
      },
    );

    test('nothing to show is empty, and cannot be posted', () {
      final s = buildShare(
        topic: ShareTopic.body,
        items: {ShareItem.bodyFat},
        range: ProgressRange.month1,
        sessions: const [],
        today: today,
      );
      expect(s.isEmpty, isTrue);
    });

    test('a share post round-trips with its caption', () {
      final share = buildShare(
        topic: ShareTopic.overall,
        items: {ShareItem.workouts, ShareItem.volumeChart},
        range: ProgressRange.month1,
        sessions: sessions,
        today: today,
      );
      final post = buildSharePost(
        share: share,
        caption: '  Two weeks in!  ',
        author: _me,
        friendUids: const ['f1'],
      );
      expect(post.kind, PostKind.share);
      expect(post.id, startsWith('u1_share_'));
      expect(post.caption, 'Two weeks in!');
      final json = post.toJson()..['createdAt'] = '2026-10-12T00:00:00';
      final back = WorkoutPost.fromJson(post.id, json);
      expect(back.caption, 'Two weeks in!');
      expect(back.share!.workouts, 2);
      expect(back.share!.charts.single.points, hasLength(2));
    });

    test('who gave kudos reads naturally', () {
      expect(kudosLine({'u1': 'Ben'}, 'u1'), 'Kudos from You');
      expect(
        kudosLine({'a': 'Ana', 'u1': 'Ben'}, 'u1'),
        'Kudos from You and Ana',
      );
      expect(
        kudosLine({'a': 'Ana', 'b': '@bob', 'c': '', 'd': 'Dee'}, 'u1'),
        'Kudos from Ana, @bob and 2 others',
      );
    });
  });
}
