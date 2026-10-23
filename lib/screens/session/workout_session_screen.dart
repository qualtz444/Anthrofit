import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../auth/auth_scope.dart';
import '../../coaching/autofill_store.dart';
import '../../community/community_models.dart';
import '../../community/community_service.dart';
import '../../community/post_builder.dart';
import '../../coaching/exercise_tutorial.dart';
import '../../coaching/limitation_check.dart';
import '../../coaching/set_coach.dart';
import '../../intelligence/ai_explainer.dart';
import '../../core/format.dart';
import '../../core/set_input.dart';
import '../../core/set_labels.dart';
import '../../core/units.dart';
import '../../data/exercise_library.dart';
import '../../data/session_report.dart';
import '../../data/training_stats.dart';
import '../../models/models.dart';
import '../../notifications/app_notifications.dart';
import '../../state/session_controller.dart';
import '../../state/profile_scope.dart';
import '../../state/program_scope.dart';
import '../../state/session_scope.dart';
import '../exercises/exercise_detail_screen.dart';
import '../exercises/exercise_library_screen.dart';
import '../widgets/empty_state.dart';
import 'guided_set_screen.dart';
import 'rest_timer.dart';
import '../composition/body_composition_screen.dart';
import '../scan/body_size_check.dart';
import 'warm_cool_card.dart';
import '../../coaching/warm_cool.dart';
import '../widgets/muscle_image.dart';
import '../../core/snack_bar_timing.dart';

/// Performing a workout. Reads the session in progress from SessionController.
///
/// Flow per exercise: log each set -> (optional rest) -> Next exercise.
/// After the last exercise: Complete workout -> summary -> Save workout.
///
/// Targets shown here come from the session's frozen copy of the plan.
/// What the user logs only ever goes into the session.
class WorkoutSessionScreen extends StatefulWidget {
  const WorkoutSessionScreen({super.key});

  @override
  State<WorkoutSessionScreen> createState() => _WorkoutSessionScreenState();
}

class _WorkoutSessionScreenState extends State<WorkoutSessionScreen>
    with WidgetsBindingObserver {
  final TextEditingController _weight = TextEditingController();
  final TextEditingController _reps = TextEditingController();

  int _exerciseIndex = 0;
  String? _weightError;
  String? _repsError;

  /// Minutes and seconds, for a cardio set.
  final TextEditingController _minutes = TextEditingController();
  final TextEditingController _seconds = TextEditingController();
  String? _durationError;

  /// A bodyweight exercise hides the weight box, because almost always there
  /// is none. This shows it anyway, for a weighted pull-up or dip.
  bool _addingWeight = false;

  /// Set when the user taps "Complete workout"; shown on the summary screen.
  WorkoutSession? _summary;

  /// For the workout's real duration: when this screen last came to the
  /// front, or null while it is in the background or the workout is done.
  /// The time in between is added to the session's active time.
  late final SessionController _sessions;
  DateTime? _activeSince;

  /// When the last set was completed, for the time between sets. Cleared
  /// by a break (app in the background, screen left), so a break is never
  /// counted as rest.
  DateTime? _lastSetDoneAt;
  bool _saving = false;
  bool _openingGuidedSet = false;
  String? _lastAutoGuidedSet;

  /// True once the screen is on its way out (discarded), so no message flashes.
  bool _closing = false;

  /// Set when the user hides the warm-up or cool-down card. Neither card
  /// is ever required, and neither is logged.
  bool _warmUpHidden = false;
  bool _coolDownHidden = false;

  /// Autofill suggestions the user approved, per exercise log and set index.
  /// Kept apart from the plan and from what is logged: they only fill the
  /// input boxes, and a set is recorded only when the user completes it.
  final Map<String, Map<int, SetProposal>> _autofill = {};

  /// The coaching line for the last completed set.
  String? _coachText;

  /// Situation check for the set just completed: its index, the user's
  /// answer, what the rules did with it, and the AI coach's message.
  int? _checkSetIndex;
  SetFeel? _feel;
  NextSetAdjustment? _adjustment;
  String? _aiCoach;
  bool _aiLoading = false;

  /// Which units the weight box uses. Loads are always STORED in kilograms;
  /// this only decides what the number in the box means.
  WeightUnit get _units => unitsOf(context, listen: false);

  @override
  void initState() {
    super.initState();
    _sessions = SessionScope.of(context, listen: false);
    WidgetsBinding.instance.addObserver(this);
    _activeSince = DateTime.now();
    final session = _sessions.activeSession;
    if (session != null && session.exerciseLogs.isNotEmpty) {
      // Resuming: continue at the first exercise that still has sets to do.
      _exerciseIndex = _firstUnfinishedIndex(session);
      _prefill(session.exerciseLogs[_exerciseIndex]);
      _restoreAutofill(session);
      if (session.guidedMode) _queueGuidedSet();
    }
    // Asked here, at the start of a workout, because this is where the rest
    // alert is used. Android only asks once; a "no" is respected.
    appNotifications.requestPermission();
  }

  /// Brings back Autofill suggestions approved before the app was closed.
  Future<void> _restoreAutofill(WorkoutSession session) async {
    final saved = await AutofillStore.load(session.id);
    if (!mounted || saved.isEmpty) return;
    final current = SessionScope.of(context, listen: false).activeSession;
    if (current == null || current.id != session.id) return;
    setState(() {
      _autofill
        ..clear()
        ..addAll(saved);
      final i = _exerciseIndex.clamp(0, current.exerciseLogs.length - 1);
      _prefill(current.exerciseLogs[i]);
    });
  }

  void _queueGuidedSet() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openGuidedSetForCurrentSet();
    });
  }

  Future<void> _openGuidedSetForCurrentSet() async {
    if (_openingGuidedSet) return;
    final session = _sessions.activeSession;
    if (session == null ||
        !session.guidedMode ||
        session.exerciseLogs.isEmpty ||
        _exerciseIndex >= session.exerciseLogs.length) {
      return;
    }
    final log = session.exerciseLogs[_exerciseIndex];
    if (log.skipped) return;
    final setIndex = log.sets.indexWhere((set) => !set.isSettled);
    if (setIndex < 0 ||
        _logStyleFor(ExerciseLibrary.byId(log.exerciseId)) == _LogStyle.time) {
      return;
    }
    final set = log.sets[setIndex];
    final key = '${session.id}:${log.id}:${set.setNumber}';
    if (_lastAutoGuidedSet == key) return;

    _lastAutoGuidedSet = key;
    _openingGuidedSet = true;
    try {
      await _guidedSet(log, set, log.plannedSetFor(setIndex));
    } finally {
      _openingGuidedSet = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_summary == null) _activeSince ??= DateTime.now();
    } else {
      // Locked, switched away or closing: stop the clock and keep the time.
      _flushActiveTime();
    }
  }

  /// Time on this screen since it last came to the front.
  Duration _sinceActive() {
    final since = _activeSince;
    return since == null ? Duration.zero : DateTime.now().difference(since);
  }

  /// Saves the time since the screen came to the front and stops the clock.
  void _flushActiveTime() {
    final time = _sinceActive();
    _activeSince = null;
    _lastSetDoneAt = null;
    _sessions.addActiveTime(time).catchError((Object _) {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_summary == null) _flushActiveTime();
    _coachTick.dispose();
    _weight.dispose();
    _reps.dispose();
    _minutes.dispose();
    _seconds.dispose();
    super.dispose();
  }

  /// How a set is recorded, which depends on the exercise rather than on
  /// anything the user chose.
  ///   cardio      time, because reps and load mean nothing on a treadmill
  ///   bodyweight  reps, with weight hidden unless asked for
  ///   otherwise   weight and reps
  static _LogStyle _logStyleFor(Exercise? exercise) {
    switch (exercise?.exerciseType) {
      case ExerciseType.cardio:
        return _LogStyle.time;
      case ExerciseType.bodyweight:
        return _LogStyle.reps;
      default:
        return _LogStyle.weightAndReps;
    }
  }

  static int _firstUnfinishedIndex(WorkoutSession session) {
    final logs = session.exerciseLogs;
    for (var i = 0; i < logs.length; i++) {
      if (logs[i].completedSets.length < logs[i].sets.length) return i;
    }
    return logs.length - 1;
  }

  /// Fills the inputs for the set about to be logged. Always easy to change.
  ///  Weight: the planned target load if there is one, otherwise the previous
  ///          set's weight.
  ///  Reps:   the previous set's reps.
  /// A warm-up set's numbers are never copied into a later working set.
  void _prefill(ExerciseLog log) {
    _weight.clear();
    _reps.clear();
    _minutes.clear();
    _seconds.clear();
    _durationError = null;
    // Each exercise decides again whether a weight box is wanted.
    _addingWeight = false;
    final next = log.sets.indexWhere((s) => !s.isSettled);
    if (next >= 0) {
      final canCopyPrevious =
          next > 0 &&
          (log.sets[next - 1].setType != SetType.warmUp ||
              log.sets[next].setType == SetType.warmUp);
      final previous = canCopyPrevious ? log.sets[next - 1] : null;
      final previousWeight = previous?.weightKg;
      final previousReps = previous?.reps;
      final targetLoad = log.plannedSetFor(next)?.targetLoadKg;

      final targetDuration = log.plannedSetFor(next)?.targetDurationSeconds;
      if (targetDuration != null && targetDuration > 0) {
        _minutes.text = (targetDuration ~/ 60).toString();
        final seconds = targetDuration % 60;
        if (seconds > 0) _seconds.text = seconds.toString();
      }

      if (targetLoad != null && targetLoad > 0) {
        _weight.text = formatNumber(enteredFromKg(targetLoad, _units));
      } else if (previousWeight != null) {
        _weight.text = formatNumber(enteredFromKg(previousWeight, _units));
      }
      if (previousReps != null) _reps.text = '$previousReps';

      // An approved Autofill suggestion wins over the plain prefill.
      final proposal = _autofill[log.id]?[next];
      if (proposal != null) {
        if (proposal.loadKg != null) {
          _weight.text = formatNumber(enteredFromKg(proposal.loadKg!, _units));
          _addingWeight = true;
        }
        if (proposal.reps != null) _reps.text = '${proposal.reps}';
      }
    }
    _weightError = null;
    _repsError = null;
  }

  // ------------------------------------------------------------------
  // Actions
  // ------------------------------------------------------------------

  /// The duration typed in, in seconds, or null if neither box has a number.
  /// Seconds alone is fine, and so is minutes alone.
  int? _enteredSeconds() {
    final minutes = int.tryParse(_minutes.text.trim());
    final seconds = int.tryParse(_seconds.text.trim());
    if (minutes == null && seconds == null) return null;
    return (minutes ?? 0) * 60 + (seconds ?? 0);
  }

  Future<void> _completeSet(
    SessionController controller,
    ExerciseLog log,
    SetLog set,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final style = _logStyleFor(ExerciseLibrary.byId(log.exerciseId));

    double? weightKg;
    var reps = 0;
    int? durationSeconds;

    if (style == _LogStyle.time) {
      final seconds = _enteredSeconds();
      if (seconds == null || seconds <= 0) {
        setState(() => _durationError = 'Enter how long it took');
        return;
      }
      durationSeconds = seconds;
    } else {
      // A bodyweight set with the weight box hidden has no load at all.
      final weightText = style == _LogStyle.reps && !_addingWeight
          ? ''
          : _weight.text;
      final input = parseSetInput(weightText: weightText, repsText: _reps.text);
      if (!input.isValid) {
        setState(() {
          _weightError = input.weightError;
          _repsError = input.repsError;
        });
        return;
      }
      weightKg = input.weightKg == null
          ? null
          : kgFromEntered(input.weightKg!, _units);
      reps = input.reps!;
    }

    final now = DateTime.now();
    final last = _lastSetDoneAt;
    try {
      await controller.logSet(
        exerciseLogId: log.id,
        setNumber: set.setNumber,
        weightKg: weightKg,
        reps: reps,
        durationSeconds: durationSeconds,
        now: now,
        restBeforeSeconds: last == null
            ? null
            : now.difference(last).inSeconds,
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(duration: kSnackBarDuration, persist: false, content: Text("Couldn't save your set. Try again.")),
      );
      return;
    }
    _lastSetDoneAt = now;
    if (!mounted) return;
    final session = controller.activeSession;
    if (session == null) return;
    final updated = session.exerciseLogs.firstWhere((l) => l.id == log.id);
    final setIndex = updated.sets.indexWhere(
      (s) => s.setNumber == set.setNumber,
    );
    setState(() {
      _prefill(updated);
      _coachText = coachAfterSet(updated, setIndex, sessionSoFar: session);
      // A new rest: ask again. Only working sets with a rep target get
      // a check, the same sets that get a coaching line.
      _checkSetIndex = _coachText == null ? null : setIndex;
      _feel = null;
      _adjustment = null;
      _aiCoach = null;
      _aiLoading = false;
    });
    await _openRestCoach(controller, session, updated, setIndex);
    if (session.guidedMode) _queueGuidedSet();
  }

  /// Opens the guided set (how-to steps and a rep counter) and puts the
  /// count in the Reps box. Nothing is logged until the user completes the
  /// set as usual.
  Future<void> _guidedSet(
    ExerciseLog log,
    SetLog set,
    PlannedSet? planned,
  ) async {
    final exercise = ExerciseLibrary.byId(log.exerciseId);
    if (exercise == null) return;
    final result = await Navigator.of(context).push<GuidedSetResult>(
      MaterialPageRoute(
        builder: (_) => GuidedSetScreen(
          exercise: exercise,
          setNumber: set.setNumber,
          workoutName: _sessions.activeSession?.workoutName,
          target: planned == null
              ? null
              : plannedTargetLabel(planned, _units),
          initialWeight: _weight.text,
          weightUnit: _units,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _reps.text = '${result.reps}';
      _weight.text = result.weight;
      _addingWeight =
          _logStyleFor(exercise) == _LogStyle.reps && result.weight.isNotEmpty;
      _repsError = null;
      _weightError = null;
    });
  }

  /// The user answered the situation check. The rules decide the next set;
  /// the AI only writes the coaching message about it.
  Future<void> _answerFeel(
    WorkoutSession session,
    ExerciseLog log,
    SetFeel feel,
  ) async {
    final index = _checkSetIndex;
    final ruleLine = _coachText;
    if (index == null || ruleLine == null) return;
    final adj = adjustNextSet(log, index, feel);
    final experience = ProfileScope.of(
      context,
      listen: false,
    ).profile?.experience.label;
    final goal = _goalOf(session)?.label;
    setState(() {
      _feel = feel;
      _adjustment = adj;
      _aiCoach = null;
      // Pain gets the fixed safety message, never an AI rewording.
      _aiLoading = !adj.stop;
      final target = adj.setIndex;
      if (target != null) {
        (_autofill[log.id] ??= {})[target] = SetProposal(
          setIndex: target,
          loadKg: adj.loadKg,
          reps: adj.reps,
        );
        _prefill(log);
      }
    });
    _coachChanged();
    if (adj.setIndex != null) await AutofillStore.save(session.id, _autofill);
    if (adj.stop) return;

    final reply = await aiExplainer.explain(
      ExplainRequest(
        kind: ExplainKind.coaching,
        goal: goal,
        experience: experience,
        facts: [
          'Exercise: ${log.exerciseName}',
          if (log.plannedSets.isNotEmpty)
            'Planned: ${plannedSetsSummary(log.plannedSets)}',
          ruleLine,
          'The user said the set felt: ${feel.label}.',
          adj.reason,
        ],
      ),
    );
    if (!mounted || _feel != feel || _checkSetIndex != index) return;
    setState(() {
      _aiCoach = reply;
      _aiLoading = false;
    });
    _coachChanged();
  }

  /// Suggests targets for the sets not yet done, shows them for editing,
  /// and applies only what the user approves. Never adds or changes sets,
  /// never touches the program, and running it twice just replaces the
  /// earlier suggestions.
  Future<void> _runAutofill(
    SessionController controller,
    WorkoutSession session, {
    required List<ExerciseLog> logs,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final history = historyWithout(controller.completedSessions, session);
    final proposals = <ExerciseLog, List<SetProposal>>{};
    for (final log in logs) {
      if (log.skipped) continue;
      final style = _logStyleFor(ExerciseLibrary.byId(log.exerciseId));
      if (style == _LogStyle.time) continue;
      final list = proposeTargets(log: log, history: history);
      if (list.isNotEmpty) proposals[log] = list;
    }
    if (proposals.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          duration: kSnackBarDuration,
          persist: false,
          content: Text(
            'Nothing to go on yet: no plan targets, earlier sets or past '
            'sessions. Enter your first set yourself.',
          ),
        ),
      );
      return;
    }
    final approved = await showDialog<Map<String, List<SetProposal>>>(
      context: context,
      builder: (_) => _AutofillDialog(proposals: proposals, units: _units),
    );
    if (approved == null || !mounted) return;
    setState(() {
      for (final e in approved.entries) {
        _autofill[e.key] = {for (final p in e.value) p.setIndex: p};
      }
      final current =
          session.exerciseLogs[_exerciseIndex.clamp(
            0,
            session.exerciseLogs.length - 1,
          )];
      _prefill(current);
    });
    await AutofillStore.save(session.id, _autofill);
    messenger.showSnackBar(
    const SnackBar(duration: kSnackBarDuration, persist: false, content: Text('Suggestions filled in. Edit as needed.')),
    );
  }

  /// The goal this workout was prescribed for: its program's own goal, else
  /// the profile goal. Null for a quick workout with no goal set anywhere.
  TrainingGoal? _goalOf(WorkoutSession session) {
    final programId = session.programId;
    final program = programId == null
        ? null
        : ProgramScope.of(context, listen: false).programById(programId);
    return program?.goal ??
        ProfileScope.of(context, listen: false).profile?.goal;
  }

  Future<void> _editSet(
    SessionController controller,
    ExerciseLog log,
    SetLog set,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final input = await showDialog<SetInput>(
      context: context,
      builder: (_) => _SetEditDialog(set: set, units: _units),
    );
    if (input == null) return;
    try {
      await controller.logSet(
        exerciseLogId: log.id,
        setNumber: set.setNumber,
        weightKg: input.weightKg == null
            ? null
            : kgFromEntered(input.weightKg!, _units),
        reps: input.reps!,
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(duration: kSnackBarDuration, persist: false, content: Text("Couldn't save your change. Try again.")),
      );
    }
  }

  void _nextExercise(WorkoutSession session) {
    setState(() {
      _exerciseIndex += 1;
      _prefill(session.exerciseLogs[_exerciseIndex]);
    });
    if (session.guidedMode) _queueGuidedSet();
  }

  /// Ends the workout. The finish time is fixed now, so the duration on the
  /// summary is exactly what gets saved.
  void _completeWorkout(WorkoutSession session) {
    final active = (session.activeSeconds ?? 0) + _sinceActive().inSeconds;
    _activeSince = null; // the clock stops at Complete workout
    setState(
      () => _summary = session.copyWith(
        completedAt: DateTime.now(),
        activeSeconds: active,
      ),
    );
    _loadCommunity();
  }

  void _returnToWorkout() {
    setState(() {
      _summary = null;
      _activeSince = DateTime.now();
    });
  }

  /// The user's community profile, if they have one: only then is sharing
  /// offered. Guests and accounts without a username never see the switch.
  CommunityProfile? _communityProfile;

  /// Set by the button the user picks on the summary: share or just save.
  bool _share = false;
  bool _thenScan = false;

  /// True once the workout is saved and the scan was opened on top of the
  /// summary. The summary stays underneath, so Back from the scan returns to
  /// it, now showing that the workout is saved.
  bool _saved = false;

  Future<void> _loadCommunity() async {
    final auth = AuthScope.of(context, listen: false);
    final uid = auth.user?.uid;
    if (auth.isGuest || uid == null) return;
    try {
      final profile = await communityService.profileOf(uid);
      if (mounted) setState(() => _communityProfile = profile);
    } catch (_) {
      // Offline: the workout still saves; it just is not shared.
    }
  }

  /// Shares the saved workout with friends. Workout data only: no scan,
  /// body weight or photo is ever part of a post.
  Future<String?> _shareWorkout(
    SessionController controller,
    WorkoutSession saved,
  ) async {
    final me = _communityProfile;
    if (me == null || !_share) return null;
    try {
      final friends = await communityService.friendUids(me.uid);
      final post = buildWorkoutPost(
        session: saved,
        history: controller.completedSessions,
        author: me,
        friendUids: friends,
      );
      return await communityService.share(post);
    } catch (_) {
      return "Saved, but couldn't share it with friends.";
    }
  }

  Future<void> _saveWorkout(
    SessionController controller,
    WorkoutSession summary, {
    bool share = false,
    bool thenScan = false,
  }) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _saving = true;
      _share = share;
      _thenScan = thenScan;
    });
    try {
      await controller.completeSession(
        completedAt: summary.completedAt,
        activeSeconds: summary.activeSeconds,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        const SnackBar(
          duration: kSnackBarDuration,
          persist: false,
          content: Text("Couldn't save the workout. Try again."),
        ),
      );
      return;
    }
    if (!mounted) return;
    final shareError = await _shareWorkout(controller, summary);
    messenger.showSnackBar(
      SnackBar(
        duration: kSnackBarDuration,
        persist: false,
        content: Text(
          shareError ??
              (_communityProfile != null && _share
                  ? 'Workout saved and shared with friends'
                  : 'Workout saved'),
        ),
      ),
    );
    if (!mounted) return;
    await _offerToKeepSetChanges(summary);
    if (!mounted) return;
    // The loop: workout, then a body composition scan, whose result shows
    // what changed since the last scan. The same height and weight check as
    // starting the scan from the Scan screen; closing it skips the scan.
    final scan = thenScan && await confirmHeightAndWeight(context);
    if (!mounted) return;
    if (scan) {
      // The summary stays underneath, so Back from the scan (or its result)
      // returns here instead of dropping the person at the start.
      setState(() {
        _saving = false;
        _saved = true;
      });
      await navigator.push(
        MaterialPageRoute<void>(builder: (_) => const BodyCompositionScreen()),
      );
      return;
    }
    navigator.pop(true);
  }

  /// Opens the body composition scan again from the saved summary.
  Future<void> _scanAgain() async {
    final navigator = Navigator.of(context);
    if (!await confirmHeightAndWeight(context) || !mounted) return;
    await navigator.push(
      MaterialPageRoute<void>(builder: (_) => const BodyCompositionScreen()),
    );
  }

  /// If sets were added or removed during the workout, offers to keep the new
  /// counts in the program.
  ///
  /// The program is only changed if the user says yes: a one-off extra set
  /// should not quietly rewrite the plan. Quick workouts have no program, so
  /// there is nothing to offer.
  Future<void> _offerToKeepSetChanges(WorkoutSession summary) async {
    // A quick workout has no program, so there is nothing to offer.
    final programId = summary.programId;
    if (programId == null || programId.isEmpty || summary.workoutId.isEmpty) {
      return;
    }
    final programs = ProgramScope.of(context, listen: false);
    final program = programs.programById(programId);
    if (program == null) return;

    Workout? workout;
    for (final w in program.workouts) {
      if (w.id == summary.workoutId) workout = w;
    }
    if (workout == null) return;

    // Which exercises now have a different number of sets than the plan.
    final changed = <PlannedExercise, ExerciseLog>{};
    for (final planned in workout.exercises) {
      for (final log in summary.exerciseLogs) {
        if (log.plannedExerciseId == planned.id &&
            log.plannedSets.length != planned.plannedSets.length) {
          changed[planned] = log;
        }
      }
    }
    if (changed.isEmpty) return;

    final names = [
      for (final entry in changed.entries)
        '${ExerciseLibrary.byId(entry.value.exerciseId)?.name ?? 'An exercise'}'
            ': ${entry.key.plannedSets.length} → '
            '${entry.value.plannedSets.length} sets',
    ];

    final keep = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Keep these changes?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('You changed how many sets you did:'),
            const SizedBox(height: 8),
            for (final name in names) Text('· $name'),
            const SizedBox(height: 12),
            const Text('Update the workout in your program to match?'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Just this time'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Keep changes'),
          ),
        ],
      ),
    );
    if (keep != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final updated = workout.copyWith(
      exercises: [
        for (final planned in workout.exercises)
          changed.containsKey(planned)
              ? planned.copyWith(
                  plannedSets: List.of(changed[planned]!.plannedSets),
                )
              : planned,
      ],
    );
    try {
      await programs.saveProgram(
        program.copyWith(
          workouts: [
            for (final w in program.workouts) w.id == updated.id ? updated : w,
          ],
          updatedAt: DateTime.now(),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(duration: kSnackBarDuration, persist: false, content: Text("Couldn't update your program.")),
      );
    }
  }

  Future<void> _confirmLeave() async {
    final navigator = Navigator.of(context);
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave workout?'),
        content: const Text('Your current workout progress will be kept.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep working out'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Leave workout'),
          ),
        ],
      ),
    );
    if (leave == true) navigator.pop();
  }

  /// Skips the exercise, or puts it back.
  ///
  /// A skipped exercise stays in the session and in history, but nothing in
  /// it counts: progression and the progress figures ignore it.
  Future<void> _toggleSkip(
    SessionController controller,
    WorkoutSession session,
    ExerciseLog log,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final wasSkipped = log.skipped;
    try {
      await controller.setSkipped(exerciseLogId: log.id, skipped: !wasSkipped);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(duration: kSnackBarDuration, persist: false, content: Text("Couldn't save that. Try again.")),
      );
      return;
    }
    if (!mounted || wasSkipped) return;

    // Skipping is a decision to move on, so the screen does.
    if (_exerciseIndex < session.exerciseLogs.length - 1) {
      _nextExercise(session);
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text('${log.exerciseName} skipped'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            await controller.setSkipped(exerciseLogId: log.id, skipped: false);
            if (mounted) _goToExercise(session, log.id);
          },
        ),
      ),
    );
  }

  /// Adds a set to the exercise being performed.
  Future<void> _addSet(SessionController controller, ExerciseLog log) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await controller.addSet(exerciseLogId: log.id);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(duration: kSnackBarDuration, persist: false, content: Text("Couldn't add a set. Try again.")),
      );
    }
  }

  /// Removes a set from the exercise being performed.
  Future<void> _removeSet(
    SessionController controller,
    ExerciseLog log,
    SetLog set,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await controller.removeSet(
        exerciseLogId: log.id,
        setNumber: set.setNumber,
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(duration: kSnackBarDuration, persist: false, content: Text("Couldn't remove the set. Try again.")),
      );
    }
  }

  /// Skips one set. The exercise stops waiting for it, and nothing in it
  /// counts.
  Future<void> _skipSet(
    SessionController controller,
    ExerciseLog log,
    SetLog set,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await controller.setSetSkipped(
        exerciseLogId: log.id,
        setNumber: set.setNumber,
        skipped: true,
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(duration: kSnackBarDuration, persist: false, content: Text("Couldn't save that. Try again.")),
      );
      return;
    }
    if (!mounted) return;
    if (controller.activeSession?.guidedMode == true) _queueGuidedSet();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Set ${set.setNumber} skipped'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => controller.clearSet(
            exerciseLogId: log.id,
            setNumber: set.setNumber,
          ),
        ),
      ),
    );
  }

  /// Puts a set back to waiting, for one completed by mistake.
  Future<void> _clearSet(
    SessionController controller,
    ExerciseLog log,
    SetLog set,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await controller.clearSet(
        exerciseLogId: log.id,
        setNumber: set.setNumber,
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(duration: kSnackBarDuration, persist: false, content: Text("Couldn't save that. Try again.")),
      );
    }
  }

  /// Jumps back to one exercise by its log id, for Undo.
  void _goToExercise(WorkoutSession session, String logId) {
    final index = session.exerciseLogs.indexWhere((l) => l.id == logId);
    if (index < 0) return;
    setState(() {
      _exerciseIndex = index;
      _prefill(session.exerciseLogs[index]);
    });
  }

  /// Swaps this exercise for another, for this session only. The program is
  /// not changed, and history records what was actually performed.
  Future<void> _replace(SessionController controller, ExerciseLog log) async {
    final messenger = ScaffoldMessenger.of(context);
    final picked = await Navigator.of(context).push<List<Exercise>>(
      MaterialPageRoute<List<Exercise>>(
        builder: (_) => const ExerciseLibraryScreen(pickMode: true),
      ),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    final replacement = picked.first;
    if (replacement.id == log.exerciseId) return;

    if (log.completedSets.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Replace with ${replacement.name}?'),
          content: Text(
            'The ${pluralize(log.completedSets.length, 'set')} you logged for '
            '${log.exerciseName} will be cleared, because they were not done '
            'on this exercise.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Replace'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    try {
      await controller.substituteExercise(
        exerciseLogId: log.id,
        replacement: replacement,
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(duration: kSnackBarDuration, persist: false, content: Text("Couldn't replace the exercise.")),
      );
    }
  }

  Future<void> _confirmDiscard(SessionController controller) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Discard workout?'),
        content: const Text(
          'Everything you logged in this workout will be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard != true) return;
    setState(() => _closing = true);
    try {
      await controller.discardActiveSession();
    } catch (_) {
      if (mounted) setState(() => _closing = false);
      messenger.showSnackBar(
        const SnackBar(duration: kSnackBarDuration, persist: false,
          content: Text("Couldn't discard the workout. Try again."),
        ),
      );
      return;
    }
    navigator.pop();
  }

  // ------------------------------------------------------------------
  // Rest and coach pop-up
  // ------------------------------------------------------------------

  /// Rebuilds the open rest pop-up when the coaching changes (the user's
  /// answer, the AI reply) or the rest changes.
  final ValueNotifier<int> _coachTick = ValueNotifier<int>(0);
  void _coachChanged() => _coachTick.value++;

  /// The rest shown in the pop-up, in seconds, and whether it has run out.
  int _sheetRest = 0;
  bool _restOver = false;

  /// What comes after the set just done: "set 3", the next exercise's name,
  /// or null when the whole workout is done.
  static String? _whatsNext(WorkoutSession session, ExerciseLog log) {
    final next = log.sets.indexWhere((s) => !s.isSettled);
    if (!log.skipped && next >= 0) return 'set ${log.sets[next].setNumber}';
    final i = session.exerciseLogs.indexWhere((l) => l.id == log.id);
    for (final other in session.exerciseLogs.skip(i + 1)) {
      if (!other.skipped && other.sets.any((s) => !s.isSettled)) {
        return other.exerciseName;
      }
    }
    for (final other in session.exerciseLogs.take(i)) {
      if (!other.skipped && other.sets.any((s) => !s.isSettled)) {
        return other.exerciseName;
      }
    }
    return null;
  }

  /// Pops up right after a set is logged: the coach says it is rest time,
  /// the rest timer runs, and the situation check and coaching follow.
  /// Nothing is shown when there is neither a rest nor anything to say.
  Future<void> _openRestCoach(
    SessionController controller,
    WorkoutSession session,
    ExerciseLog log,
    int setIndex,
  ) async {
    final next = _whatsNext(session, log);
    final planned = log.plannedSetFor(setIndex)?.restSeconds ?? 0;
    // No rest after the very last set of the workout.
    _sheetRest = next == null ? 0 : planned;
    _restOver = false;
    if (_sheetRest <= 0 && _coachText == null) return;
    final setNumber = log.sets[setIndex].setNumber;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => ValueListenableBuilder<int>(
        valueListenable: _coachTick,
        builder: (context, _, _) => _restCoachPanel(
          sheetContext,
          controller: controller,
          session: session,
          log: log,
          setIndex: setIndex,
          setNumber: setNumber,
          next: next,
        ),
      ),
    );
  }

  Widget _restCoachPanel(
    BuildContext sheetContext, {
    required SessionController controller,
    required WorkoutSession session,
    required ExerciseLog log,
    required int setIndex,
    required int setNumber,
    required String? next,
  }) {
    final theme = Theme.of(sheetContext);
    final resting = _sheetRest > 0;
    final String message;
    if (!resting) {
      message = next == null
          ? 'Set $setNumber done. That was the last set of the workout.'
          : 'Set $setNumber done.';
    } else if (_restOver) {
      message = 'Rest is over. Time for $next.';
    } else {
      message =
          "Set $setNumber done. It's rest time: take "
          '${formatClock(_sheetRest)} before $next.';
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          key: const ValueKey('rest-coach-sheet'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // The coach speaks first: what just happened, and that it is
            // time to rest.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Icon(
                    Icons.sports,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(16),
                        bottomLeft: Radius.circular(16),
                        bottomRight: Radius.circular(16),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Coach', style: theme.textTheme.labelMedium),
                        const SizedBox(height: 2),
                        Text(
                          message,
                          key: const ValueKey('coach-rest-message'),
                          style: theme.textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (resting) ...[
              const SizedBox(height: 12),
              RestTimer(
                key: ValueKey('rest-${log.id}-$setIndex'),
                seconds: _sheetRest,
                // Changes the rest for this set, in this session only.
                onSecondsChanged: (seconds) {
                  _sheetRest = seconds;
                  _restOver = false;
                  _coachChanged();
                  controller.setRestSeconds(
                    exerciseLogId: log.id,
                    setIndex: setIndex,
                    seconds: seconds,
                  );
                },
                onFinished: () {
                  _restOver = true;
                  _coachChanged();
                },
                alertText: next == null ? null : 'Time for $next.',
              ),
            ],
            if (_coachText != null) ...[
              const SizedBox(height: 12),
              _coachFeedback(theme, session, log),
            ],
            const SizedBox(height: 8),
            Text(
              kCoachSafetyNote,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const ValueKey('rest-sheet-done'),
              onPressed: () => Navigator.of(sheetContext).pop(),
              child: Text(
                next == null
                    ? 'Done'
                    : (resting && !_restOver
                          ? 'Skip rest, start next set'
                          : 'Start next set'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The situation check and the coaching that follows it.
  Widget _coachFeedback(
    ThemeData theme,
    WorkoutSession session,
    ExerciseLog log,
  ) {
    return Column(
      key: const ValueKey('coach-card'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_feel == null) ...[
          const Text(
            'While you rest: how did that set feel?',
            key: ValueKey('situation-check'),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final f in SetFeel.values)
                OutlinedButton(
                  key: ValueKey('feel-${f.name}'),
                  onPressed: () => _answerFeel(session, log, f),
                  child: Text(f.label),
                ),
            ],
          ),
        ] else if (_adjustment?.stop ?? false) ...[
          Text(
            _adjustment!.reason,
            key: const ValueKey('coach-stop'),
            style: TextStyle(
              color: theme.colorScheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ] else if (_aiLoading) ...[
          _coachBox(
            theme,
            const Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Expanded(child: Text('Coach is thinking…')),
              ],
            ),
          ),
        ] else if (_aiCoach != null) ...[
          _coachBox(
            theme,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_aiCoach!, key: const ValueKey('ai-coach')),
                const SizedBox(height: 6),
                Text(
                  "AI coach. The next-set numbers come from the app's rules.",
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          // Offline or the AI failed: the rule-based coaching.
          _coachBox(
            theme,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_coachText!, key: const ValueKey('rule-coach')),
                if (_adjustment != null) ...[
                  const SizedBox(height: 4),
                  Text(_adjustment!.reason),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// The coach's reply in its own box, so it stands apart from the
  /// questions and buttons around it.
  Widget _coachBox(ThemeData theme, Widget child) => Container(
    key: const ValueKey('coach-reply-box'),
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: theme.colorScheme.primary.withValues(alpha: 0.4),
      ),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.sports, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(child: child),
      ],
    ),
  );

  // ------------------------------------------------------------------
  // Build
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final controller = SessionScope.of(context);

    final summary = _summary;
    if (summary != null) return _buildSummary(controller, summary);

    final session = controller.activeSession;
    if (session == null || session.exerciseLogs.isEmpty) {
      if (_closing) return const Scaffold(body: SizedBox.shrink());
      return Scaffold(
        appBar: AppBar(title: const Text('Workout')),
        body: const EmptyState(title: 'There is no workout in progress.'),
      );
    }

    final theme = Theme.of(context);
    final total = session.exerciseLogs.length;
    final index = _exerciseIndex >= total ? total - 1 : _exerciseIndex;
    final log = session.exerciseLogs[index];
    final isLast = index == total - 1;
    // A skipped set is settled: the exercise stops waiting for it.
    final currentSetIndex = log.sets.indexWhere((s) => !s.isSettled);
    final exerciseComplete = currentSetIndex == -1;
    final totalSets = session.exerciseLogs.fold<int>(
      0,
      (sum, l) => sum + l.sets.length,
    );
    final exercise = ExerciseLibrary.byId(log.exerciseId);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(session.workoutName),
          actions: [
            PopupMenuButton<String>(
              tooltip: 'Workout options',
              onSelected: (value) {
                switch (value) {
                  case 'autofill':
                    _runAutofill(controller, session, logs: [log]);
                  case 'autofill-all':
                    _runAutofill(
                      controller,
                      session,
                      logs: session.exerciseLogs,
                    );
                  case 'skip':
                    _toggleSkip(controller, session, log);
                  case 'replace':
                    _replace(controller, log);
                  case 'discard':
                    _confirmDiscard(controller);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem<String>(
                  value: 'autofill',
                  child: Text('Autofill this exercise'),
                ),
                const PopupMenuItem<String>(
                  value: 'autofill-all',
                  child: Text('Autofill whole workout'),
                ),
                const PopupMenuDivider(),
                // Skip has its own button below; only the undo lives here.
                if (log.skipped)
                  PopupMenuItem<String>(
                    value: 'skip',
                    child: Text('Unskip ${log.exerciseName}'),
                  ),
                const PopupMenuItem<String>(
                  value: 'replace',
                  child: Text('Replace exercise'),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem<String>(
                  value: 'discard',
                  child: Text('Discard workout'),
                ),
              ],
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Warm-up prompt: only before the first set, and only while the
            // setting is on.
            if (warmCoolSettings.value &&
                session.completedSetCount == 0 &&
                !_warmUpHidden) ...[
              WarmCoolCard(
                kind: WarmCoolKind.warmUp,
                onHide: () => setState(() => _warmUpHidden = true),
              ),
              const SizedBox(height: 16),
            ],
            _ProgressHeader(
              exerciseNumber: index + 1,
              exerciseTotal: total,
              setsDone: session.completedSetCount,
              setsTotal: totalSets,
            ),
            const SizedBox(height: 20),

            // ---- current exercise ----
            Text(
              log.exerciseName,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            if (log.wasSubstituted)
              Text(
                'Instead of ${log.substitutedForName}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            if (log.skipped)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.block, size: 18, color: theme.colorScheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Skipped. Nothing logged here counts toward your '
                        'progress.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _toggleSkip(controller, session, log),
                      child: const Text('Undo'),
                    ),
                  ],
                ),
              ),
            if (exercise != null) ...[
              Row(
                children: [
                  for (final m in exercise.primaryMuscles)
                    Padding(
                      padding: const EdgeInsets.only(right: 6, bottom: 4),
                      child: MuscleImage(m, size: 36),
                    ),
                ],
              ),
              Text(
                'Primary: ${exercise.primaryMuscles.map((m) => m.label).join(' · ')}',
              ),
              if (exercise.secondaryMuscles.isNotEmpty)
                Text(
                  'Secondary: ${exercise.secondaryMuscles.map((m) => m.label).join(' · ')}',
                ),
            ],
            const SizedBox(height: 8),
            if (log.plannedSets.isNotEmpty)
              Text(
                plannedSetsSummary(log.plannedSets),
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            if (log.targetNote.isNotEmpty) Text(log.targetNote),
            if (exercise != null)
              if (limitationCaution(
                    exercise,
                    context
                            .dependOnInheritedWidgetOfExactType<ProfileScope>()
                            ?.notifier
                            ?.profile
                            ?.limitations ??
                        const [],
                  )
                  case final caution?)
                Padding(
                  key: const ValueKey('limitation-caution'),
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.healing_outlined,
                        size: 18,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(width: 6),
                      Expanded(child: Text(caution)),
                    ],
                  ),
                ),
            if (exercise != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ExerciseDetailScreen(
                          exercise: exercise,
                          canStart: false,
                          whyPrescription: _goalOf(session) == null
                              ? null
                              : prescriptionRationale(
                                  _goalOf(session)!,
                                  exercise,
                                ),
                        ),
                      ),
                    );
                  },
                  child: const Text('View exercise details'),
                ),
              ),
            // Autofill on the screen itself, not only in the ⋮ menu, so it
            // can be found. Timed (cardio) exercises have nothing to fill.
            if (!log.skipped &&
                !exerciseComplete &&
                _logStyleFor(exercise) != _LogStyle.time)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('autofill-button'),
                  onPressed: () =>
                      _runAutofill(controller, session, logs: [log]),
                  icon: const Icon(Icons.auto_fix_high, size: 18),
                  label: const Text('Autofill sets'),
                ),
              ),
            const SizedBox(height: 12),

            // ---- sets ----
            for (var i = 0; i < log.sets.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _buildSetRow(
                  controller: controller,
                  log: log,
                  index: i,
                  isCurrent: i == currentSetIndex,
                ),
              ),
            // Sets can be added or dropped while training: a plan is a
            // starting point, not a contract.
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _addSet(controller, log),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add set'),
              ),
            ),
            if (exerciseComplete)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '${log.completedSets.length}/${log.sets.length} sets completed',
                  style: theme.textTheme.titleMedium,
                ),
              ),
          ],
        ),
        // Always visible, so moving on is never buried in a menu.
        // Skip sits beside the forward action rather than replacing it:
        // finishing an exercise and abandoning it are different choices.
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                if (!log.skipped)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _toggleSkip(controller, session, log),
                      icon: const Icon(Icons.skip_next),
                      label: const Text('Skip'),
                    ),
                  ),
                if (!log.skipped) const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    // A skipped exercise has nothing left to do, so moving on
                    // is always available for it.
                    onPressed: (exerciseComplete || log.skipped)
                        ? (isLast
                              ? () => _completeWorkout(session)
                              : () => _nextExercise(session))
                        : null,
                    child: Text(isLast ? 'Complete workout' : 'Next exercise'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSetRow({
    required SessionController controller,
    required ExerciseLog log,
    required int index,
    required bool isCurrent,
  }) {
    final theme = Theme.of(context);
    final set = log.sets[index];
    final planned = log.plannedSetFor(index);
    final style = _logStyleFor(ExerciseLibrary.byId(log.exerciseId));

    if (set.isCompleted) {
      return Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          leading: Icon(Icons.check_circle, color: theme.colorScheme.primary),
          // "Working · 40 kg × 10"
          title: Row(
            children: [
              Text('${set.setType.shortLabel} · '),
              Flexible(
                child: Text(
                  formatSetLog(set),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          subtitle: Text('Set ${set.setNumber} · tap to edit'),
          // Undoing one set should never mean discarding the workout.
          trailing: IconButton(
            tooltip: 'Mark set ${set.setNumber} not done',
            icon: const Icon(Icons.undo),
            onPressed: () => _clearSet(controller, log, set),
          ),
          onTap: () => _editSet(controller, log, set),
        ),
      );
    }

    if (set.skipped) {
      return Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          leading: Icon(Icons.block, color: theme.colorScheme.onSurfaceVariant),
          title: Text('${set.setType.shortLabel} · skipped'),
          subtitle: Text('Set ${set.setNumber}'),
          trailing: TextButton(
            onPressed: () => _clearSet(controller, log, set),
            child: const Text('Undo'),
          ),
        ),
      );
    }

    if (!isCurrent) {
      return Padding(
        padding: const EdgeInsets.only(left: 16, right: 4, top: 8, bottom: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Set ${set.setNumber} · ${set.setType.shortLabel}'
                '${planned == null ? '' : ' · ${plannedTargetLabel(planned)}'}',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (log.sets.length > 1)
              IconButton(
                tooltip: 'Remove set ${set.setNumber}',
                icon: const Icon(Icons.close, size: 18),
                visualDensity: VisualDensity.compact,
                onPressed: () => _removeSet(controller, log, set),
              ),
          ],
        ),
      );
    }

    // The set being logged right now.
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Set ${set.setNumber}',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              set.setType.label.toUpperCase(),
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            if (planned != null)
              Text(
                'Target: ${plannedTargetLabel(planned)}',
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            const SizedBox(height: 12),
            if (style == _LogStyle.time)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _minutes,
                      keyboardType: TextInputType.number,
                      inputFormatters: [LengthLimitingTextInputFormatter(3)],
                      decoration: InputDecoration(
                        labelText: 'Minutes',
                        errorText: _durationError,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) {
                        if (_durationError != null) {
                          setState(() => _durationError = null);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _seconds,
                      keyboardType: TextInputType.number,
                      inputFormatters: [LengthLimitingTextInputFormatter(2)],
                      decoration: const InputDecoration(
                        labelText: 'Seconds',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Hidden for bodyweight work until the user asks for it:
                  // a push-up has no weight to enter.
                  if (style == _LogStyle.weightAndReps || _addingWeight) ...[
                    Expanded(
                      child: TextField(
                        controller: _weight,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(
                            kWeightInputMaxLength,
                          ),
                        ],
                        decoration: InputDecoration(
                          labelText: style == _LogStyle.reps
                              ? 'Added weight (${_units.short})'
                              : 'Weight (${_units.short})',
                          helperText: style == _LogStyle.reps
                              ? null
                              : 'Blank for bodyweight',
                          errorText: _weightError,
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (_) {
                          if (_weightError != null) {
                            setState(() => _weightError = null);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: TextField(
                      controller: _reps,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(kRepsInputMaxLength),
                      ],
                      decoration: InputDecoration(
                        labelText: 'Reps',
                        errorText: _repsError,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) {
                        if (_repsError != null) {
                          setState(() => _repsError = null);
                        }
                      },
                    ),
                  ),
                ],
              ),
            // For a weighted pull-up or dip.
            if (style == _LogStyle.reps && !_addingWeight)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _addingWeight = true),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add weight'),
                ),
              ),
            // Steps for the exercise and a rep counter; the count lands in
            // the Reps box, to check before completing the set.
            if (style != _LogStyle.time)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('guided-set'),
                  onPressed: () => _guidedSet(log, set, planned),
                  icon: const Icon(Icons.play_circle_outline, size: 18),
                  label: const Text('Guided set'),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _skipSet(controller, log, set),
                    child: const Text('Skip'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: () => _completeSet(controller, log, set),
                    child: const Text('Complete set'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary(SessionController controller, WorkoutSession summary) {
    final theme = Theme.of(context);
    final duration = summary.duration ?? Duration.zero;
    final totals = summarize([summary]);
    final muscles = _musclesWorked(summary);
    final bodyWeight = context
        .dependOnInheritedWidgetOfExactType<ProfileScope>()
        ?.notifier
        ?.profile
        ?.weightKg;
    final kcal = estimatedKcal(duration, bodyWeight);
    final between = averageTimeBetweenSets(summary);
    final canShare = _communityProfile != null;

    Widget savingLabel() => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 10),
        // Saving and sharing can take a moment on a slow connection; say
        // so instead of looking frozen.
        Text(
          _share
              ? 'Saving and sharing…'
              : (_thenScan ? 'Saving and scanning…' : 'Saving…'),
        ),
      ],
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // Saved: nothing is lost by leaving. Not saved: ask first.
        if (_saved) {
          Navigator.of(context).pop(true);
        } else {
          _returnToWorkout();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Workout summary'),
          actions: [
            if (!_saved)
              TextButton(
                key: const ValueKey('summary-discard'),
                onPressed: _saving ? null : () => _confirmDiscard(controller),
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
                child: const Text('Discard'),
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Header: which workout, and how long it took.
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.emoji_events_outlined,
                    size: 40,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          summary.workoutName,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                        Text(
                          'Workout complete · ${formatDuration(duration)}',
                          key: const ValueKey('summary-time'),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (warmCoolSettings.value && !_coolDownHidden) ...[
              WarmCoolCard(
                kind: WarmCoolKind.coolDown,
                muscles: muscles,
                onHide: () => setState(() => _coolDownHidden = true),
              ),
              const SizedBox(height: 12),
            ],
            // The four totals, side by side.
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: IntrinsicHeight(
                  child: Row(
                    children: [
                      _StatTile(
                        key: const ValueKey('summary-sets'),
                        value: '${summary.completedSetCount}',
                        label: 'Total sets',
                      ),
                      const VerticalDivider(width: 1),
                      _StatTile(
                        key: const ValueKey('summary-volume'),
                        value: totals.weightedSets == 0
                            ? '—'
                            : formatVolume(totals.volumeKg, _units),
                        label: 'Total volume',
                      ),
                      const VerticalDivider(width: 1),
                      _StatTile(
                        key: const ValueKey('summary-kcal'),
                        value: kcal == null ? '—' : '~${kcal.round()}',
                        label: 'Calories (est.)',
                      ),
                      const VerticalDivider(width: 1),
                      _StatTile(
                        key: const ValueKey('summary-rest'),
                        value: between == null
                            ? '—'
                            : formatClock(between.inSeconds),
                        label: 'Avg between sets',
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            const SizedBox(height: 20),
            Text('Exercise breakdown', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 48, 6),
                    child: DefaultTextStyle.merge(
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      child: const Row(
                        children: [
                          Expanded(flex: 4, child: Text('Exercise')),
                          Expanded(flex: 3, child: Text('Sets × reps')),
                          Expanded(flex: 3, child: Text('Weight')),
                          Expanded(
                            flex: 3,
                            child: Text('Volume', textAlign: TextAlign.end),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  for (final log in summary.exerciseLogs)
                    _ExerciseBreakdown(log: log, units: _units),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text('Muscles worked', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            MuscleGallery(
              key: const ValueKey('summary-muscles'),
              muscles: muscles,
              emptyText: 'No sets were done, so no muscles were worked.',
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_saved) ...[
                  FilledButton(
                    key: const ValueKey('summary-done'),
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Done'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const ValueKey('scan-again'),
                    onPressed: _scanAgain,
                    icon: const Icon(Icons.accessibility_new),
                    label: const Text('Scan body composition'),
                  ),
                ] else ...[
                  FilledButton.icon(
                    key: const ValueKey('save-and-scan'),
                    onPressed: _saving
                        ? null
                        : () =>
                              _saveWorkout(controller, summary, thenScan: true),
                    icon: const Icon(Icons.accessibility_new),
                    label: _saving && _thenScan
                        ? savingLabel()
                        : const Text('Save and scan body composition'),
                  ),
                  const SizedBox(height: 8),
                  if (canShare) ...[
                    TextButton.icon(
                      key: const ValueKey('save-and-share'),
                      onPressed: _saving
                          ? null
                          : () =>
                                _saveWorkout(controller, summary, share: true),
                      icon: const Icon(Icons.share_outlined),
                      label: _saving && _share
                          ? savingLabel()
                          : const Text('Save and share with friends'),
                    ),
                    const SizedBox(height: 4),
                    const SizedBox(height: 4),
                    TextButton(
                      key: const ValueKey('save-only'),
                      onPressed: _saving
                          ? null
                          : () => _saveWorkout(controller, summary),
                      child: _saving && !_share && !_thenScan
                          ? savingLabel()
                          : const Text('Save workout'),
                    ),
                  ] else
                    OutlinedButton(
                      key: const ValueKey('save-only'),
                      onPressed: _saving
                          ? null
                          : () => _saveWorkout(controller, summary),
                      child: _saving && !_thenScan
                          ? savingLabel()
                          : const Text('Save workout'),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The primary muscles of every exercise with at least one completed
  /// working set, most-trained first.
  static List<MuscleGroup> _musclesWorked(WorkoutSession session) {
    final sets = <MuscleGroup, int>{};
    for (final log in session.exerciseLogs) {
      final done = workSetsOf(log).length;
      if (done == 0) continue;
      final exercise = ExerciseLibrary.byId(log.exerciseId);
      if (exercise == null) continue;
      for (final m in exercise.primaryMuscles) {
        sets[m] = (sets[m] ?? 0) + done;
      }
    }
    return sets.keys.toList()..sort((a, b) => sets[b]!.compareTo(sets[a]!));
  }
}

/// One total in the summary's top row.
class _StatTile extends StatelessWidget {
  const _StatTile({super.key, required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One exercise in the breakdown: a row of totals that opens to show every
/// set, skipped ones included.
class _ExerciseBreakdown extends StatelessWidget {
  const _ExerciseBreakdown({required this.log, required this.units});

  final ExerciseLog log;
  final WeightUnit units;

  String _weight(ExerciseReport r) {
    final lo = r.minWeightKg, hi = r.maxWeightKg;
    if (lo == null || hi == null) return r.isTimed ? '—' : 'Bodyweight';
    if (lo == hi) return formatWeight(lo, units);
    return '${formatWeight(lo, units)}–${formatWeight(hi, units)}';
  }

  String _setLine(SetLog set) {
    if (set.skipped) return 'Skipped';
    if (!set.isCompleted) return 'Not done';
    final d = set.durationSeconds;
    if (d != null && d > 0) return formatClock(d);
    final reps = '${set.reps ?? 0} reps';
    final w = set.weightKg;
    return w == null || w == 0
        ? '$reps · bodyweight'
        : '$reps · ${formatWeight(w, units)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = exerciseReport(log);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final cell = theme.textTheme.bodyMedium;

    return ExpansionTile(
      key: ValueKey('breakdown-${log.id}'),
      tilePadding: const EdgeInsets.only(left: 16, right: 8),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      shape: const Border(),
      title: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              log.exerciseName,
              style: cell?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          if (r.nothingDone)
            Expanded(flex: 9, child: Text('Skipped', style: muted))
          else ...[
            Expanded(
              flex: 3,
              child: Text(
                r.isTimed ? formatClock(r.durationSeconds) : r.setsByReps,
                style: cell,
              ),
            ),
            Expanded(flex: 3, child: Text(_weight(r), style: cell)),
            Expanded(
              flex: 3,
              child: Text(
                r.volumeKg > 0 ? formatVolume(r.volumeKg, units) : '—',
                textAlign: TextAlign.end,
                style: cell,
              ),
            ),
          ],
        ],
      ),
      children: [
        if (log.skipped)
          Align(
            alignment: Alignment.centerLeft,
            child: Text('This exercise was skipped.', style: muted),
          )
        else
          for (final set in log.sets)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 96,
                    child: Text(
                      set.setType == SetType.warmUp
                          ? 'Set ${set.setNumber} (warm-up)'
                          : 'Set ${set.setNumber}',
                      style: muted,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      _setLine(set),
                      style: set.skipped ? muted : cell,
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({
    required this.exerciseNumber,
    required this.exerciseTotal,
    required this.setsDone,
    required this.setsTotal,
  });

  final int exerciseNumber;
  final int exerciseTotal;
  final int setsDone;
  final int setsTotal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Exercise $exerciseNumber of $exerciseTotal',
                style: theme.textTheme.titleMedium,
              ),
            ),
            Text('$setsDone / $setsTotal sets completed'),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: setsTotal == 0 ? 0 : setsDone / setsTotal,
        ),
      ],
    );
  }
}

class _SetEditDialog extends StatefulWidget {
  const _SetEditDialog({required this.set, required this.units});

  final SetLog set;

  /// Passed in rather than read from context: the units decide what the
  /// number in the box means, and the dialog must use the same ones as the
  /// screen behind it.
  final WeightUnit units;

  @override
  State<_SetEditDialog> createState() => _SetEditDialogState();
}

class _SetEditDialogState extends State<_SetEditDialog> {
  late final TextEditingController _weight;
  late final TextEditingController _reps;
  String? _weightError;
  String? _repsError;

  WeightUnit get _units => widget.units;

  @override
  void initState() {
    super.initState();
    final weight = widget.set.weightKg;
    _weight = TextEditingController(
      text: weight == null
          ? ''
          : formatNumber(enteredFromKg(weight, widget.units)),
    );
    _reps = TextEditingController(text: '${widget.set.reps ?? ''}');
  }

  @override
  void dispose() {
    _weight.dispose();
    _reps.dispose();
    super.dispose();
  }

  void _save() {
    final input = parseSetInput(weightText: _weight.text, repsText: _reps.text);
    if (!input.isValid) {
      setState(() {
        _weightError = input.weightError;
        _repsError = input.repsError;
      });
      return;
    }
    Navigator.of(context).pop(input);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit set ${widget.set.setNumber}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _weight,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                LengthLimitingTextInputFormatter(kWeightInputMaxLength),
              ],
              decoration: InputDecoration(
                labelText: 'Weight (${_units.short})',
                helperText: 'Blank for bodyweight',
                errorText: _weightError,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reps,
              keyboardType: TextInputType.number,
              inputFormatters: [
                LengthLimitingTextInputFormatter(kRepsInputMaxLength),
              ],
              decoration: InputDecoration(
                labelText: 'Reps',
                errorText: _repsError,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

/// What a set records, decided by the exercise.
enum _LogStyle {
  /// Weight and reps, the usual case.
  weightAndReps,

  /// Reps only, for bodyweight work. Weight can still be added by hand.
  reps,

  /// Time only, for cardio.
  time,
}

/// The Autofill preview: every suggested number, editable, with where it
/// came from. Returns the approved proposals by exercise log id, or null
/// when cancelled (nothing changes then).
class _AutofillDialog extends StatefulWidget {
  const _AutofillDialog({required this.proposals, required this.units});

  final Map<ExerciseLog, List<SetProposal>> proposals;
  final WeightUnit units;

  @override
  State<_AutofillDialog> createState() => _AutofillDialogState();
}

class _AutofillDialogState extends State<_AutofillDialog> {
  final Map<SetProposal, TextEditingController> _load = {};
  final Map<SetProposal, TextEditingController> _reps = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final list in widget.proposals.values) {
      for (final p in list) {
        _load[p] = TextEditingController(
          text: p.loadKg == null
              ? ''
              : formatNumber(enteredFromKg(p.loadKg!, widget.units)),
        );
        _reps[p] = TextEditingController(text: p.reps?.toString() ?? '');
      }
    }
  }

  @override
  void dispose() {
    for (final c in [..._load.values, ..._reps.values]) {
      c.dispose();
    }
    super.dispose();
  }

  void _apply() {
    final out = <String, List<SetProposal>>{};
    for (final e in widget.proposals.entries) {
      final list = <SetProposal>[];
      for (final p in e.value) {
        final loadText = _load[p]!.text.trim();
        final repsText = _reps[p]!.text.trim();
        final load = loadText.isEmpty ? null : double.tryParse(loadText);
        final reps = repsText.isEmpty ? null : int.tryParse(repsText);
        if ((loadText.isNotEmpty && load == null) ||
            (repsText.isNotEmpty && reps == null)) {
          setState(() => _error = '${e.key.exerciseName}: check the numbers.');
          return;
        }
        final edited = SetProposal(
          setIndex: p.setIndex,
          loadKg: load == null ? null : kgFromEntered(load, widget.units),
          reps: reps,
          loadSource: p.loadSource,
          repsSource: p.repsSource,
        );
        final problem = validateProposal(edited);
        if (problem != null) {
          setState(() => _error = '${e.key.exerciseName} $problem');
          return;
        }
        if (edited.loadKg != null || edited.reps != null) list.add(edited);
      }
      out[e.key.id] = list;
    }
    Navigator.of(context).pop(out);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return AlertDialog(
      title: const Text('Autofill suggestions'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            Text(
              'Suggestions only. Nothing is logged until you complete a set, '
              'and your program is not changed.',
              style: muted,
            ),
            for (final e in widget.proposals.entries) ...[
              const SizedBox(height: 12),
              Text(e.key.exerciseName, style: theme.textTheme.titleSmall),
              for (final p in e.value)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: 48,
                            child: Text('Set ${p.setIndex + 1}'),
                          ),
                          Expanded(
                            child: TextField(
                              key: ValueKey(
                                'autofill-load-${e.key.id}-${p.setIndex}',
                              ),
                              controller: _load[p],
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                isDense: true,
                                labelText: widget.units.short,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              key: ValueKey(
                                'autofill-reps-${e.key.id}-${p.setIndex}',
                              ),
                              controller: _reps[p],
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                isDense: true,
                                labelText: 'Reps',
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(_sourceText(p), style: muted),
                    ],
                  ),
                ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('autofill-apply'),
          onPressed: _apply,
          child: const Text('Apply'),
        ),
      ],
    );
  }

  static String _sourceText(SetProposal p) {
    final parts = <String>[
      if (p.loadSource != null) 'weight from ${p.loadSource!.label}',
      if (p.repsSource != null) 'reps from ${p.repsSource!.label}',
    ];
    return parts.join(', ');
  }
}
