import '../core/id.dart';
import '../data/training_stats.dart';
import '../models/models.dart';
import '../photos/progress_photo.dart';
import '../progress/body_progress.dart';
import '../progress/muscle_exposure.dart';
import '../progress/strength_trends.dart';
import 'community_models.dart';
import 'post_builder.dart';

/// Builds what the feed's composer shares. Pure: it reads only the user's
/// completed workouts and saved composition scans, and fills in only the
/// parts in [items]. Every number is one the Progress screens already show,
/// worked out the same way; nothing is estimated here.
///
///   Overall    workouts and sets, total volume and the top-weight changes in
///              the period, and total volume per workout as a chart.
///   Exercise   sessions, total volume, heaviest weight and best set in the
///              period, and heaviest weight or volume per session as charts.
///   Body       the latest scan's body fat with its 80% range, its fat-free
///              mass, the scan before it, and body fat per scan in the
///              period as a chart.
///   Body weight the latest weight, change over the period, and a chart.
///   Muscles    workout coverage by muscle, including the selected week's
///              primary and secondary training days.
///   Photos     the progress photos and scan photos the user picked, oldest
///              first, at most [ProgressShare.maxPhotos]. Scan dates, poses
///              and body-composition estimates stay associated with each image.
///
/// Photos can also be attached to Overall, Exercise and Body posts through
/// [photoInfos], so a workout or scan post can carry the person's photos.
ProgressShare buildShare({
  required ShareTopic topic,
  required Set<ShareItem> items,
  required ProgressRange range,
  required List<WorkoutSession> sessions,
  List<CompositionRecord> scans = const [],
  List<BodyWeightEntry> weightLog = const [],
  double? currentBodyWeightKg,
  DateTime? muscleWeekStart,
  String? exerciseId,
  List<ProgressPhoto> photos = const [],
  List<SharedPhotoInfo>? photoInfos,
  DateTime? today,
}) {
  final now = today ?? DateTime.now();
  // Photos can ride along with any topic: workout progress or scan progress.
  final attached = (photoInfos ?? const <SharedPhotoInfo>[])
      .take(ProgressShare.maxPhotos)
      .toList();
  bool want(ShareItem i) => items.contains(i) && i.topics.contains(topic);
  final done = [
    for (final s in sessions)
      if (s.isCompleted) s,
  ];

  switch (topic) {
    case ShareTopic.photos:
      final picked = [...photos]
        ..sort((a, b) => a.takenAt.compareTo(b.takenAt));
      return ProgressShare(
        topic: topic,
        title: topic.label,
        photos: photoInfos == null
            ? [
                for (final p in picked.take(ProgressShare.maxPhotos))
                  SharedPhotoInfo(takenAt: p.takenAt, pose: p.pose.name),
              ]
            : photoInfos.take(ProgressShare.maxPhotos).toList(),
      );

    case ShareTopic.overall:
      final summary = summarize(sessionsInRange(done, range, now));
      final volumes = workoutVolumes(done, range, now);
      final changes = want(ShareItem.changes)
          ? topWeightChanges(done, range, now).take(5).toList()
          : const <PostChange>[];
      return ProgressShare(
        topic: topic,
        title: topic.label,
        periodDays: range.days,
        workouts: want(ShareItem.workouts) ? summary.workouts : null,
        sets: want(ShareItem.workouts) ? summary.sets : null,
        volumeKg: want(ShareItem.volume) ? summary.volumeKg : null,
        changes: changes,
        photos: attached,
        charts: [
          if (want(ShareItem.volumeChart) && volumes.isNotEmpty)
            ShareChart(
              kind: ShareChartKind.volume,
              points: [for (final v in volumes) SharePoint(v.date, v.volumeKg)],
            ),
        ],
      );

    case ShareTopic.exercise:
      final id = exerciseId;
      final perSession = id == null
          ? const <ExerciseSession>[]
          : exerciseSessions(done, id, range, now);
      final entries = id == null
          ? const <ExerciseEntry>[]
          : exerciseHistory(sessionsInRange(done, range, now), id);
      final name = entries.isEmpty ? 'Exercise' : entries.last.exerciseName;
      final weighted = [
        for (final s in perSession)
          if (s.topWeightKg != null) s,
      ];
      final best = bestSetOf(entries);
      return ProgressShare(
        topic: topic,
        title: name,
        periodDays: range.days,
        sessions: want(ShareItem.sessions) ? perSession.length : null,
        volumeKg: want(ShareItem.volume) && perSession.isNotEmpty
            ? perSession.fold<double>(0, (sum, s) => sum + s.volumeKg)
            : null,
        bestWeightKg: want(ShareItem.bestWeight) && weighted.isNotEmpty
            ? weighted
                  .map((s) => s.topWeightKg!)
                  .reduce((a, b) => a > b ? a : b)
            : null,
        bestSetKg:
            want(ShareItem.bestSet) && best != null && isWeightedSet(best)
            ? best.weightKg
            : null,
        bestSetReps: want(ShareItem.bestSet) ? best?.reps : null,
        photos: attached,
        charts: [
          if (want(ShareItem.weightChart) && weighted.isNotEmpty)
            ShareChart(
              kind: ShareChartKind.weight,
              points: [
                for (final s in weighted) SharePoint(s.date, s.topWeightKg!),
              ],
            ),
          if (want(ShareItem.volumeChart) &&
              perSession.any((s) => s.volumeKg > 0))
            ShareChart(
              kind: ShareChartKind.volume,
              points: [
                for (final s in perSession)
                  if (s.volumeKg > 0) SharePoint(s.date, s.volumeKg),
              ],
            ),
        ],
      );

    case ShareTopic.body:
      final all = [...scans]..sort((a, b) => a.takenAt.compareTo(b.takenAt));
      final latest = all.isEmpty ? null : all.last;
      final previous = all.length < 2 ? null : all[all.length - 2];
      final inRange = [
        for (final r in all)
          if (isInRange(r.takenAt, range, now)) r,
      ];
      final fat = want(ShareItem.bodyFat) && latest != null;
      return ProgressShare(
        topic: topic,
        title: topic.label,
        periodDays: range.days,
        bodyFatPct: fat ? latest.bodyFatPct : null,
        bodyFatLow: fat ? latest.bodyFatLow : null,
        bodyFatHigh: fat ? latest.bodyFatHigh : null,
        scanDate: latest != null && (fat || want(ShareItem.fatFree))
            ? latest.takenAt
            : null,
        fatFreeMassKg: want(ShareItem.fatFree) ? latest?.fatFreeMassKg : null,
        previousBodyFatPct: want(ShareItem.bodyChange) && latest != null
            ? previous?.bodyFatPct
            : null,
        photos: attached,
        charts: [
          if (want(ShareItem.bodyFatChart) && inRange.isNotEmpty)
            ShareChart(
              kind: ShareChartKind.bodyFat,
              points: [
                for (final r in inRange) SharePoint(r.takenAt, r.bodyFatPct),
              ],
            ),
        ],
      );

    case ShareTopic.bodyWeight:
      final progress = bodyWeightProgress(weightLog, range, now);
      return ProgressShare(
        topic: topic,
        title: topic.label,
        periodDays: range.days,
        bodyWeightKg: want(ShareItem.weight)
            ? progress.latestKg ?? currentBodyWeightKg
            : null,
        bodyWeightChangeKg: want(ShareItem.weight) ? progress.changeKg : null,
        photos: attached,
        charts: [
          if (want(ShareItem.bodyWeightChart) && progress.points.isNotEmpty)
            ShareChart(
              kind: ShareChartKind.bodyWeight,
              points: [
                for (final p in progress.points) SharePoint(p.date, p.weightKg),
              ],
            ),
        ],
      );

    case ShareTopic.muscles:
      final distribution = muscleDistribution(done, range, now);
      final weekStart = muscleWeekStart;
      final weekDays = weekStart == null
          ? const <MuscleDays>[]
          : weeklyMuscleDays(done, weekStart, range, now);
      final byMuscle = {for (final days in weekDays) days.muscle: days};
      List<int> orderedDays(Set<int>? days) {
        final result = days?.toList() ?? <int>[];
        result.sort();
        return result;
      }
      return ProgressShare(
        topic: topic,
        title: topic.label,
        periodDays: range.days,
        muscleWorkouts: want(ShareItem.muscleCoverage)
            ? distribution.workouts
            : null,
        muscleWeekStart: weekStart,
        muscles: want(ShareItem.muscleCoverage)
            ? [
                for (final involvement in distribution.involved)
                  SharedMuscleProgress(
                    muscle: involvement.muscle.name,
                    primaryWorkouts: involvement.primaryWorkouts,
                    secondaryWorkouts: involvement.secondaryWorkouts,
                    primaryDays: orderedDays(
                      byMuscle[involvement.muscle]?.primaryDays,
                    ),
                    secondaryDays: orderedDays(
                      byMuscle[involvement.muscle]?.secondaryDays,
                    ),
                  ),
              ]
            : const [],
        photos: attached,
      );
  }
}

/// The single best set across [entries], as the exercise page picks it: the
/// most weight × reps among weighted sets, the heavier one on a tie; with no
/// weighted set, the one with the most reps. Null when no set has reps.
SetLog? bestSetOf(List<ExerciseEntry> entries) {
  SetLog? best;
  double score(SetLog s) => isWeightedSet(s) ? s.weightKg! * (s.reps ?? 0) : 0;
  final anyWeighted = entries.any((e) => e.sets.any(isWeightedSet));
  for (final e in entries) {
    for (final set in e.sets) {
      if ((set.reps ?? 0) <= 0) continue;
      if (anyWeighted && !isWeightedSet(set)) continue;
      final current = best;
      if (current == null) {
        best = set;
      } else if (anyWeighted) {
        final a = score(set), b = score(current);
        if (a > b || (a == b && set.weightKg! > current.weightKg!)) best = set;
      } else if ((set.reps ?? 0) > (current.reps ?? 0)) {
        best = set;
      }
    }
  }
  return best;
}

/// A composer post, seen by the author and their friends.
WorkoutPost buildSharePost({
  required ProgressShare share,
  required String caption,
  required CommunityProfile author,
  required List<String> friendUids,
  DateTime? now,
}) {
  final text = caption.trim();
  return WorkoutPost(
    id: '${author.uid}_share_${generateId()}',
    authorUid: author.uid,
    authorHandle: author.handle,
    authorName: author.displayName,
    audience: {author.uid, ...friendUids}.toList(),
    createdAt: now ?? DateTime.now(),
    workoutName: share.title,
    durationMinutes: 0,
    totalSets: share.sets ?? 0,
    volumeKg: 0,
    exercises: const [],
    records: const [],
    kind: PostKind.share,
    caption: text.length > WorkoutPost.maxCaption
        ? text.substring(0, WorkoutPost.maxCaption)
        : text,
    share: share,
  );
}
