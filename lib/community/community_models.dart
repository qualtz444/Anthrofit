import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

/// Community data. Friends only. Workout, program and progress posts carry
/// training data only. Body composition goes into a post only when the user
/// picks it in the share composer, and only the numbers they pick: never a
/// scan outline, a proportion scan, a measurement or a photo.

/// A username: 3–20 lowercase letters, digits or underscores. The same
/// pattern is enforced in firestore.rules.
final RegExp kHandlePattern = RegExp(r'^[a-z0-9_]{3,20}$');

/// Null when [handle] is usable, otherwise what to fix.
String? validateHandle(String handle) {
  if (handle.length < 3) return 'At least 3 characters.';
  if (handle.length > 20) return 'At most 20 characters.';
  if (!kHandlePattern.hasMatch(handle)) {
    return 'Use lowercase letters, numbers and _ only.';
  }
  return null;
}

DateTime _date(Object? v) => v is Timestamp
    ? v.toDate()
    : (v is String ? DateTime.tryParse(v) : null) ?? DateTime.now();

/// What friends can see about a person: a username and a display name.
class CommunityProfile {
  const CommunityProfile({
    required this.uid,
    required this.handle,
    required this.displayName,
    this.avatarBytes,
  });

  final String uid;
  final String handle;
  final String displayName;
  final Uint8List? avatarBytes;

  factory CommunityProfile.fromJson(String uid, Map<String, dynamic> j) {
    final avatar = j['avatar'];
    return CommunityProfile(
      uid: uid,
      handle: j['handle'] as String? ?? '',
      displayName: j['displayName'] as String? ?? '',
      avatarBytes: avatar is Blob ? avatar.bytes : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'handle': handle,
    'displayName': displayName,
    if (avatarBytes != null) 'avatar': Blob(avatarBytes!),
  };
}

class FriendRequest {
  const FriendRequest({
    required this.fromUid,
    required this.toUid,
    required this.fromHandle,
    required this.fromName,
    required this.toHandle,
    required this.createdAt,
  });

  final String fromUid;
  final String toUid;
  final String fromHandle;
  final String fromName;
  final String toHandle;
  final DateTime createdAt;

  /// One request per direction, so sending twice cannot duplicate it.
  String get id => '${fromUid}_$toUid';

  factory FriendRequest.fromJson(Map<String, dynamic> j) => FriendRequest(
    fromUid: j['fromUid'] as String,
    toUid: j['toUid'] as String,
    fromHandle: j['fromHandle'] as String? ?? '',
    fromName: j['fromName'] as String? ?? '',
    toHandle: j['toHandle'] as String? ?? '',
    createdAt: _date(j['createdAt']),
  );

  Map<String, dynamic> toJson() => {
    'fromUid': fromUid,
    'toUid': toUid,
    'fromHandle': fromHandle,
    'fromName': fromName,
    'toHandle': toHandle,
    'createdAt': FieldValue.serverTimestamp(),
  };
}

class Friend {
  const Friend({
    required this.uid,
    required this.handle,
    required this.displayName,
  });

  final String uid;
  final String handle;
  final String displayName;

  factory Friend.fromJson(String uid, Map<String, dynamic> j) => Friend(
    uid: uid,
    handle: j['handle'] as String? ?? '',
    displayName: j['displayName'] as String? ?? '',
  );
}

/// One exercise in a shared workout: name, sets done, and the top set.
class PostExercise {
  const PostExercise({
    required this.name,
    required this.sets,
    this.topWeightKg,
    this.topReps,
  });

  final String name;
  final int sets;
  final double? topWeightKg;
  final int? topReps;

  factory PostExercise.fromJson(Map<String, dynamic> j) => PostExercise(
    name: j['name'] as String? ?? '',
    sets: (j['sets'] as num?)?.toInt() ?? 0,
    topWeightKg: (j['topWeightKg'] as num?)?.toDouble(),
    topReps: (j['topReps'] as num?)?.toInt(),
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'sets': sets,
    'topWeightKg': topWeightKg,
    'topReps': topReps,
  };
}

/// A personal best in this workout: the heaviest top set ever logged for
/// that exercise, beating every earlier completed session.
class PostRecord {
  const PostRecord({required this.exercise, required this.weightKg});

  final String exercise;
  final double weightKg;

  factory PostRecord.fromJson(Map<String, dynamic> j) => PostRecord(
    exercise: j['exercise'] as String? ?? '',
    weightKg: (j['weightKg'] as num?)?.toDouble() ?? 0,
  );

  Map<String, dynamic> toJson() => {'exercise': exercise, 'weightKg': weightKg};
}

/// What a post is about. [share] is one built in the feed's composer.
enum PostKind { workout, program, progress, share }

/// One exercise's top-set change over a period, for a progress post.
/// Kilograms; each viewer sees their own units.
class PostChange {
  const PostChange({
    required this.exercise,
    required this.fromKg,
    required this.toKg,
  });

  final String exercise;
  final double fromKg;
  final double toKg;

  factory PostChange.fromJson(Map<String, dynamic> j) => PostChange(
    exercise: j['exercise'] as String? ?? '',
    fromKg: (j['fromKg'] as num?)?.toDouble() ?? 0,
    toKg: (j['toKg'] as num?)?.toDouble() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'exercise': exercise,
    'fromKg': fromKg,
    'toKg': toKg,
  };
}

/// Something shared with friends: a finished workout (like a Strava
/// activity), a program friends can copy, or a progress summary.
class WorkoutPost {
  const WorkoutPost({
    required this.id,
    required this.authorUid,
    required this.authorHandle,
    required this.authorName,
    required this.audience,
    required this.createdAt,
    required this.workoutName,
    required this.durationMinutes,
    required this.totalSets,
    required this.volumeKg,
    required this.exercises,
    required this.records,
    this.kind = PostKind.workout,
    this.workoutCount = 0,
    this.periodDays = 0,
    this.changes = const [],
    this.program,
    this.caption = '',
    this.share,
  });

  final PostKind kind;

  /// What the author wrote above the post. Empty when they wrote nothing.
  final String caption;

  /// [PostKind.share] posts: what the author chose to show.
  final ProgressShare? share;

  /// Longest caption accepted. App design value, matching comments.
  static const int maxCaption = 500;

  /// Progress posts: workouts done in the last [periodDays] days, and the
  /// top-set changes in that period.
  final int workoutCount;
  final int periodDays;
  final List<PostChange> changes;

  /// Program posts: the program as TrainingProgram JSON, without its setup
  /// or notes (those can come from body scans), so friends can copy it.
  final Map<String, dynamic>? program;

  final String id;
  final String authorUid;
  final String authorHandle;
  final String authorName;

  /// The author and their friends when it was shared. Only these accounts
  /// can read it (firestore.rules); removing a friend removes them here.
  final List<String> audience;

  final DateTime createdAt;
  final String workoutName;
  final int durationMinutes;
  final int totalSets;

  /// Weight × reps over weighted sets. Not strength, and labelled so.
  final double volumeKg;
  final List<PostExercise> exercises;
  final List<PostRecord> records;

  factory WorkoutPost.fromJson(String id, Map<String, dynamic> j) =>
      WorkoutPost(
        id: id,
        authorUid: j['authorUid'] as String? ?? '',
        authorHandle: j['authorHandle'] as String? ?? '',
        authorName: j['authorName'] as String? ?? '',
        audience: [
          for (final a in (j['audience'] as List? ?? const [])) '$a',
        ],
        createdAt: _date(j['createdAt']),
        workoutName: j['workoutName'] as String? ?? 'Workout',
        durationMinutes: (j['durationMinutes'] as num?)?.toInt() ?? 0,
        totalSets: (j['totalSets'] as num?)?.toInt() ?? 0,
        volumeKg: (j['volumeKg'] as num?)?.toDouble() ?? 0,
        exercises: [
          for (final e in (j['exercises'] as List? ?? const []))
            PostExercise.fromJson(Map<String, dynamic>.from(e as Map)),
        ],
        records: [
          for (final r in (j['records'] as List? ?? const []))
            PostRecord.fromJson(Map<String, dynamic>.from(r as Map)),
        ],
        kind: PostKind.values.firstWhere(
          (k) => k.name == j['kind'],
          orElse: () => PostKind.workout,
        ),
        workoutCount: (j['workoutCount'] as num?)?.toInt() ?? 0,
        periodDays: (j['periodDays'] as num?)?.toInt() ?? 0,
        changes: [
          for (final c in (j['changes'] as List? ?? const []))
            PostChange.fromJson(Map<String, dynamic>.from(c as Map)),
        ],
        program: j['program'] is Map
            ? Map<String, dynamic>.from(j['program'] as Map)
            : null,
        caption: j['caption'] as String? ?? '',
        share: j['share'] is Map
            ? ProgressShare.fromJson(Map<String, dynamic>.from(j['share'] as Map))
            : null,
      );

  Map<String, dynamic> toJson() => {
    'authorUid': authorUid,
    'authorHandle': authorHandle,
    'authorName': authorName,
    'audience': audience,
    'createdAt': Timestamp.fromDate(createdAt),
    'workoutName': workoutName,
    'durationMinutes': durationMinutes,
    'totalSets': totalSets,
    'volumeKg': volumeKg,
    'exercises': [for (final e in exercises) e.toJson()],
    'records': [for (final r in records) r.toJson()],
    'kind': kind.name,
    'workoutCount': workoutCount,
    'periodDays': periodDays,
    'changes': [for (final c in changes) c.toJson()],
    'program': program,
    'caption': caption,
    'share': share?.toJson(),
  };
}

/// What a composer post is about.
enum ShareTopic {
  overall('Overall strength'),
  exercise('One exercise'),
  body('Body composition'),
  bodyWeight('Body weight'),
  muscles('Muscle distribution'),
  photos('Progress photos');

  const ShareTopic(this.label);
  final String label;
}

/// One thing the author can tick in the composer. [topics] says where it
/// makes sense.
enum ShareItem {
  workouts('Workouts & sets', {ShareTopic.overall}),
  sessions('Sessions', {ShareTopic.exercise}),
  volume('Total volume', {ShareTopic.overall, ShareTopic.exercise}),
  bestWeight('Best weight', {ShareTopic.exercise}),
  bestSet('Best set', {ShareTopic.exercise}),
  changes('Top-weight changes', {ShareTopic.overall}),
  weightChart('Weight chart', {ShareTopic.exercise}),
  volumeChart('Volume chart', {ShareTopic.overall, ShareTopic.exercise}),
  bodyFat('Body fat', {ShareTopic.body}),
  fatFree('Fat-free mass', {ShareTopic.body}),
  bodyChange('Change since last scan', {ShareTopic.body}),
  bodyFatChart('Body fat chart', {ShareTopic.body}),
  weight('Body weight', {ShareTopic.bodyWeight}),
  bodyWeightChart('Body weight chart', {ShareTopic.bodyWeight}),
  muscleCoverage('Muscle coverage', {ShareTopic.muscles});

  const ShareItem(this.label, this.topics);
  final String label;
  final Set<ShareTopic> topics;
}

/// What a chart in a shared post plots, which decides its units.
enum ShareChartKind {
  /// Heaviest weight per session, kilograms.
  weight('Heaviest weight per session'),

  /// Weight × reps per session, kilograms·reps.
  volume('Volume per session'),

  /// Body fat per scan, percent.
  bodyFat('Body fat per scan'),
  bodyWeight('Body weight');

  const ShareChartKind(this.label);
  final String label;
}

class SharePoint {
  const SharePoint(this.date, this.value);

  final DateTime date;
  final double value;

  factory SharePoint.fromJson(Map<String, dynamic> j) =>
      SharePoint(_date(j['date']), (j['value'] as num?)?.toDouble() ?? 0);

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'value': value,
  };
}

class ShareChart {
  const ShareChart({required this.kind, required this.points});

  final ShareChartKind kind;

  /// Oldest first, each one a recorded value.
  final List<SharePoint> points;

  factory ShareChart.fromJson(Map<String, dynamic> j) => ShareChart(
    kind: ShareChartKind.values.firstWhere(
      (k) => k.name == j['kind'],
      orElse: () => ShareChartKind.volume,
    ),
    points: [
      for (final p in (j['points'] as List? ?? const []))
        SharePoint.fromJson(Map<String, dynamic>.from(p as Map)),
    ],
  );

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'points': [for (final p in points) p.toJson()],
  };
}

class SharedMuscleProgress {
  const SharedMuscleProgress({
    required this.muscle,
    required this.primaryWorkouts,
    required this.secondaryWorkouts,
    required this.primaryDays,
    required this.secondaryDays,
  });

  final String muscle;
  final int primaryWorkouts;
  final int secondaryWorkouts;
  final List<int> primaryDays;
  final List<int> secondaryDays;

  factory SharedMuscleProgress.fromJson(Map<String, dynamic> j) =>
      SharedMuscleProgress(
        muscle: j['muscle'] as String? ?? '',
        primaryWorkouts: (j['primaryWorkouts'] as num?)?.toInt() ?? 0,
        secondaryWorkouts: (j['secondaryWorkouts'] as num?)?.toInt() ?? 0,
        primaryDays: [
          for (final d in j['primaryDays'] as List? ?? const [])
            if (d is num) d.toInt(),
        ],
        secondaryDays: [
          for (final d in j['secondaryDays'] as List? ?? const [])
            if (d is num) d.toInt(),
        ],
      );

  Map<String, dynamic> toJson() => {
    'muscle': muscle,
    'primaryWorkouts': primaryWorkouts,
    'secondaryWorkouts': secondaryWorkouts,
    'primaryDays': primaryDays,
    'secondaryDays': secondaryDays,
  };
}

/// The content of a composer post: only the parts the author ticked are
/// filled in; everything else stays null, and is never sent.
///
/// Weights are kilograms; each viewer sees their own units.
/// What a viewer is told about one shared photo. The picture itself is
/// stored apart from the post (posts/{id}/photos), so the feed stays small.
class SharedPhotoInfo {
  const SharedPhotoInfo({
    required this.takenAt,
    required this.pose,
    this.bodyFatPct,
    this.bodyFatLow,
    this.bodyFatHigh,
    this.fatFreeMassKg,
  });

  final DateTime takenAt;

  /// The pose's name, e.g. "front" (PhotoPose.name).
  final String pose;

  /// Present for an original photo taken during a saved composition scan.
  final double? bodyFatPct;
  final double? bodyFatLow;
  final double? bodyFatHigh;
  final double? fatFreeMassKg;

  factory SharedPhotoInfo.fromJson(Map<String, dynamic> j) => SharedPhotoInfo(
    takenAt: _date(j['takenAt']),
    pose: j['pose'] as String? ?? '',
    bodyFatPct: (j['bodyFatPct'] as num?)?.toDouble(),
    bodyFatLow: (j['bodyFatLow'] as num?)?.toDouble(),
    bodyFatHigh: (j['bodyFatHigh'] as num?)?.toDouble(),
    fatFreeMassKg: (j['fatFreeMassKg'] as num?)?.toDouble(),
  );

  Map<String, dynamic> toJson() => {
    'takenAt': takenAt.toIso8601String(),
    'pose': pose,
    if (bodyFatPct != null) 'bodyFatPct': bodyFatPct,
    if (bodyFatLow != null) 'bodyFatLow': bodyFatLow,
    if (bodyFatHigh != null) 'bodyFatHigh': bodyFatHigh,
    if (fatFreeMassKg != null) 'fatFreeMassKg': fatFreeMassKg,
  };
}

class ProgressShare {
  const ProgressShare({
    required this.topic,
    required this.title,
    this.periodDays,
    this.workouts,
    this.sets,
    this.sessions,
    this.volumeKg,
    this.bestWeightKg,
    this.bestSetKg,
    this.bestSetReps,
    this.changes = const [],
    this.bodyFatPct,
    this.bodyFatLow,
    this.bodyFatHigh,
    this.scanDate,
    this.fatFreeMassKg,
    this.previousBodyFatPct,
    this.bodyWeightKg,
    this.bodyWeightChangeKg,
    this.muscleWorkouts,
    this.muscleWeekStart,
    this.muscles = const [],
    this.charts = const [],
    this.photos = const [],
  });

  final ShareTopic topic;

  /// "Overall strength", the exercise name, or "Body composition".
  final String title;

  /// The period it covers; null is all time.
  final int? periodDays;

  final int? workouts;
  final int? sets;
  final int? sessions;
  final double? volumeKg;
  final double? bestWeightKg;

  /// The best set: its weight (null for a bodyweight set) and reps.
  final double? bestSetKg;
  final int? bestSetReps;

  final List<PostChange> changes;

  /// The latest scan's body fat estimate and its 80% range.
  final double? bodyFatPct;
  final double? bodyFatLow;
  final double? bodyFatHigh;
  final DateTime? scanDate;
  final double? fatFreeMassKg;

  /// The scan before the latest, for the change.
  final double? previousBodyFatPct;

  final double? bodyWeightKg;
  final double? bodyWeightChangeKg;
  final int? muscleWorkouts;
  final DateTime? muscleWeekStart;
  final List<SharedMuscleProgress> muscles;

  final List<ShareChart> charts;

  /// [ShareTopic.photos]: the photos, oldest first. Their pictures are in
  /// the post's photos collection, in the same order.
  final List<SharedPhotoInfo> photos;

  /// Most photos in one post. APP DESIGN VALUE: a before and an after.
  static const int maxPhotos = 2;

  String get periodLabel =>
      periodDays == null ? 'All time' : 'Last $periodDays days';

  /// True when nothing was filled in: there is nothing to post.
  bool get isEmpty =>
      workouts == null &&
      sessions == null &&
      volumeKg == null &&
      bestWeightKg == null &&
      bestSetReps == null &&
      changes.isEmpty &&
      bodyFatPct == null &&
      fatFreeMassKg == null &&
      previousBodyFatPct == null &&
      bodyWeightKg == null &&
      bodyWeightChangeKg == null &&
      muscleWorkouts == null &&
      muscles.isEmpty &&
      charts.isEmpty &&
      photos.isEmpty;

  factory ProgressShare.fromJson(Map<String, dynamic> j) {
    double? d(String k) => (j[k] as num?)?.toDouble();
    int? i(String k) => (j[k] as num?)?.toInt();
    return ProgressShare(
      topic: ShareTopic.values.firstWhere(
        (t) => t.name == j['topic'],
        orElse: () => ShareTopic.overall,
      ),
      title: j['title'] as String? ?? '',
      periodDays: i('periodDays'),
      workouts: i('workouts'),
      sets: i('sets'),
      sessions: i('sessions'),
      volumeKg: d('volumeKg'),
      bestWeightKg: d('bestWeightKg'),
      bestSetKg: d('bestSetKg'),
      bestSetReps: i('bestSetReps'),
      changes: [
        for (final c in (j['changes'] as List? ?? const []))
          PostChange.fromJson(Map<String, dynamic>.from(c as Map)),
      ],
      bodyFatPct: d('bodyFatPct'),
      bodyFatLow: d('bodyFatLow'),
      bodyFatHigh: d('bodyFatHigh'),
      scanDate: j['scanDate'] == null ? null : _date(j['scanDate']),
      fatFreeMassKg: d('fatFreeMassKg'),
      previousBodyFatPct: d('previousBodyFatPct'),
      bodyWeightKg: d('bodyWeightKg'),
      bodyWeightChangeKg: d('bodyWeightChangeKg'),
      muscleWorkouts: i('muscleWorkouts'),
      muscleWeekStart: j['muscleWeekStart'] == null
          ? null
          : _date(j['muscleWeekStart']),
      muscles: [
        for (final m in (j['muscles'] as List? ?? const []))
          SharedMuscleProgress.fromJson(Map<String, dynamic>.from(m as Map)),
      ],
      charts: [
        for (final c in (j['charts'] as List? ?? const []))
          ShareChart.fromJson(Map<String, dynamic>.from(c as Map)),
      ],
      photos: [
        for (final p in (j['photos'] as List? ?? const []))
          SharedPhotoInfo.fromJson(Map<String, dynamic>.from(p as Map)),
      ],
    );
  }

  /// Unticked parts are left out entirely, not sent as null.
  Map<String, dynamic> toJson() => {
    'topic': topic.name,
    'title': title,
    'periodDays': ?periodDays,
    'workouts': ?workouts,
    'sets': ?sets,
    'sessions': ?sessions,
    'volumeKg': ?volumeKg,
    'bestWeightKg': ?bestWeightKg,
    'bestSetKg': ?bestSetKg,
    'bestSetReps': ?bestSetReps,
    if (changes.isNotEmpty) 'changes': [for (final c in changes) c.toJson()],
    'bodyFatPct': ?bodyFatPct,
    'bodyFatLow': ?bodyFatLow,
    'bodyFatHigh': ?bodyFatHigh,
    if (scanDate != null) 'scanDate': scanDate!.toIso8601String(),
    'fatFreeMassKg': ?fatFreeMassKg,
    'previousBodyFatPct': ?previousBodyFatPct,
    'bodyWeightKg': ?bodyWeightKg,
    'bodyWeightChangeKg': ?bodyWeightChangeKg,
    'muscleWorkouts': ?muscleWorkouts,
    if (muscleWeekStart != null)
      'muscleWeekStart': muscleWeekStart!.toIso8601String(),
    if (muscles.isNotEmpty) 'muscles': [for (final m in muscles) m.toJson()],
    if (charts.isNotEmpty) 'charts': [for (final c in charts) c.toJson()],
    if (photos.isNotEmpty) 'photos': [for (final p in photos) p.toJson()],
  };
}

class PostComment {
  const PostComment({
    required this.id,
    required this.authorUid,
    required this.authorHandle,
    required this.text,
    required this.createdAt,
  });

  final String id;
  final String authorUid;
  final String authorHandle;
  final String text;
  final DateTime createdAt;

  /// Longest comment accepted; the same limit is in firestore.rules.
  static const int maxLength = 500;

  factory PostComment.fromJson(String id, Map<String, dynamic> j) =>
      PostComment(
        id: id,
        authorUid: j['authorUid'] as String? ?? '',
        authorHandle: j['authorHandle'] as String? ?? '',
        text: j['text'] as String? ?? '',
        createdAt: _date(j['createdAt']),
      );
}

/// Something that happened to the user in Community, for the in-app inbox.
enum InboxType { kudos, comment, request, accepted, challenge }

class InboxItem {
  const InboxItem({
    required this.id,
    required this.type,
    required this.fromUid,
    required this.fromHandle,
    required this.createdAt,
    this.postId,
    this.text,
    this.read = false,
  });

  final String id;
  final InboxType type;
  final String fromUid;
  final String fromHandle;
  final DateTime createdAt;
  final String? postId;

  /// Comment text or challenge title, shortened.
  final String? text;
  final bool read;

  String get message => switch (type) {
    InboxType.kudos => '@$fromHandle gave you kudos',
    InboxType.comment => '@$fromHandle commented: ${text ?? ''}',
    InboxType.request => '@$fromHandle sent you a friend request',
    InboxType.accepted => '@$fromHandle accepted your friend request',
    InboxType.challenge =>
      '@$fromHandle added you to "${text ?? 'a challenge'}"',
  };

  factory InboxItem.fromJson(String id, Map<String, dynamic> j) => InboxItem(
    id: id,
    type: InboxType.values.firstWhere(
      (t) => t.name == j['type'],
      orElse: () => InboxType.kudos,
    ),
    fromUid: j['fromUid'] as String? ?? '',
    fromHandle: j['fromHandle'] as String? ?? '',
    createdAt: _date(j['createdAt']),
    postId: j['postId'] as String?,
    text: j['text'] as String?,
    read: j['read'] == true,
  );
}

/// What a challenge counts, from workouts its members share.
enum ChallengeMetric {
  workouts('workouts'),
  sets('sets');

  const ChallengeMetric(this.label);
  final String label;
}

/// A friends-only challenge: reach [target] [metric] between [start] and
/// [end]. Each member's count is written by that member's own app when they
/// share a workout, so members need not be friends with each other.
class Challenge {
  const Challenge({
    required this.id,
    required this.creatorUid,
    required this.title,
    required this.metric,
    required this.target,
    required this.start,
    required this.end,
    required this.members,
    required this.handles,
    required this.progress,
  });

  final String id;
  final String creatorUid;
  final String title;
  final ChallengeMetric metric;
  final int target;
  final DateTime start;
  final DateTime end;
  final List<String> members;

  /// uid → username, for showing the standings.
  final Map<String, String> handles;

  /// uid → count so far.
  final Map<String, int> progress;

  bool activeOn(DateTime t) => !t.isBefore(start) && !t.isAfter(end);

  factory Challenge.fromJson(String id, Map<String, dynamic> j) => Challenge(
    id: id,
    creatorUid: j['creatorUid'] as String? ?? '',
    title: j['title'] as String? ?? '',
    metric: ChallengeMetric.values.firstWhere(
      (m) => m.name == j['metric'],
      orElse: () => ChallengeMetric.workouts,
    ),
    target: (j['target'] as num?)?.toInt() ?? 0,
    start: _date(j['start']),
    end: _date(j['end']),
    members: [for (final m in (j['members'] as List? ?? const [])) '$m'],
    handles: {
      for (final e in ((j['handles'] as Map?) ?? const {}).entries)
        '${e.key}': '${e.value}',
    },
    progress: {
      for (final e in ((j['progress'] as Map?) ?? const {}).entries)
        '${e.key}': (e.value as num?)?.toInt() ?? 0,
    },
  );

  Map<String, dynamic> toJson() => {
    'creatorUid': creatorUid,
    'title': title,
    'metric': metric.name,
    'target': target,
    'start': Timestamp.fromDate(start),
    'end': Timestamp.fromDate(end),
    'members': members,
    'handles': handles,
    'progress': {for (final m in members) m: progress[m] ?? 0},
  };
}

/// One row of a friends leaderboard.
class LeaderRow {
  const LeaderRow({
    required this.uid,
    required this.handle,
    required this.workouts,
    required this.sets,
  });

  final String uid;
  final String handle;
  final int workouts;
  final int sets;
}

/// Ranks the author of each shared WORKOUT post in [posts] since [since]:
/// most workouts first, then most sets. Only shared workouts count, so this
/// is a ranking of what friends chose to share, not of all their training.
List<LeaderRow> leaderboard(
  List<WorkoutPost> posts,
  DateTime since, {
  Iterable<String> include = const [],
  Map<String, String> handles = const {},
}) {
  final rows = <String, (String, int, int)>{
    for (final uid in include) uid: (handles[uid] ?? '', 0, 0),
  };
  for (final p in posts) {
    if (p.kind != PostKind.workout || p.createdAt.isBefore(since)) continue;
    final r = rows[p.authorUid] ?? (p.authorHandle, 0, 0);
    rows[p.authorUid] = (
      r.$1.isEmpty ? p.authorHandle : r.$1,
      r.$2 + 1,
      r.$3 + p.totalSets,
    );
  }
  final list = [
    for (final e in rows.entries)
      LeaderRow(
        uid: e.key,
        handle: e.value.$1,
        workouts: e.value.$2,
        sets: e.value.$3,
      ),
  ];
  list.sort((a, b) {
    final w = b.workouts.compareTo(a.workouts);
    return w != 0 ? w : b.sets.compareTo(a.sets);
  });
  return list;
}
