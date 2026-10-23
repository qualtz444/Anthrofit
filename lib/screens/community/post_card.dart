import 'package:flutter/material.dart';

import '../../community/community_models.dart';
import '../../community/community_service.dart';
import '../../core/format.dart';
import '../../core/units.dart';
import '../../models/models.dart';
import '../../state/profile_scope.dart';
import '../../state/program_scope.dart';
import '../../core/set_labels.dart';
import '../../data/exercise_library.dart';
import 'friend_profile_screen.dart';
import 'post_detail_screen.dart';
import 'report_dialog.dart';
import 'share_content.dart';
import '../../core/snack_bar_timing.dart';
import 'community_avatar.dart';

/// One post in the feed: who and when, what they wrote, the shared content
/// in a bordered box, then kudos (and who gave them) and comments.
class PostCard extends StatelessWidget {
  const PostCard({
    super.key,
    required this.post,
    required this.me,
    this.openable = true,
  });

  final WorkoutPost post;
  final CommunityProfile me;

  /// False on the post's own page, so tapping does not open it again.
  final bool openable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final units = unitsOf(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final mine = post.authorUid == me.uid;

    void open() => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PostDetailScreen(post: post, me: me),
      ),
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: openable ? open : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CommunityAvatar(
                    uid: post.authorUid,
                    fallbackName: post.authorName.isEmpty
                        ? post.authorHandle
                        : post.authorName,
                    radius: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          key: const ValueKey('post-author'),
                          onTap: mine
                              ? null
                              : () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => FriendProfileScreen(
                                      uid: post.authorUid,
                                      handle: post.authorHandle,
                                      name: post.authorName,
                                      me: me,
                                    ),
                                  ),
                                ),
                          child: Text(
                            mine ? 'You' : post.authorName,
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        Text(
                          '@${post.authorHandle} · '
                          '${formatDate(post.createdAt, today: DateTime.now())}',
                          style: muted,
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                      key: const ValueKey('post-menu'),
                      onSelected: (_) => mine
                          ? _delete(context)
                          : reportDialog(
                              context,
                              me: me,
                              targetUid: post.authorUid,
                              postId: post.id,
                            ),
                      itemBuilder: (_) => [
                        if (mine)
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete post'),
                          )
                        else
                          const PopupMenuItem(
                            value: 'report',
                            child: Text('Report post'),
                          ),
                      ],
                    ),
                ],
              ),
              if (post.caption.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  post.caption,
                  key: const ValueKey('post-caption'),
                  style: theme.textTheme.bodyLarge,
                ),
              ],
              const SizedBox(height: 10),
              PostContentBox(
                key: const ValueKey('post-content'),
                child: post.kind == PostKind.share && post.share != null
                    ? ShareContentView(share: post.share!, postId: post.id)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            post.workoutName,
                            style: theme.textTheme.titleMedium,
                          ),
                          ...switch (post.kind) {
                            PostKind.workout ||
                            PostKind.share => _workoutBody(units, muted),
                            PostKind.program => _programBody(context, muted),
                            PostKind.progress => _progressBody(
                              context,
                              units,
                              muted,
                            ),
                          },
                        ],
                      ),
              ),
              const SizedBox(height: 4),
              StreamBuilder<Map<String, String>>(
                stream: communityService.kudosGivers(post.id),
                builder: (context, snap) {
                  final givers = snap.data ?? const <String, String>{};
                  final liked = givers.containsKey(me.uid);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          TextButton.icon(
                            key: const ValueKey('kudos'),
                            // Your own post: kudos is for friends to give.
                            onPressed: mine
                                ? null
                                : () => communityService.setKudos(
                                    post,
                                    me,
                                    on: !liked,
                                  ),
                            icon: Icon(
                              liked ? Icons.thumb_up : Icons.thumb_up_outlined,
                              size: 18,
                            ),
                            label: Text('Kudos ${givers.length}'),
                          ),
                          StreamBuilder<List<PostComment>>(
                            stream: communityService.comments(post.id),
                            builder: (context, snap) => TextButton.icon(
                              onPressed: openable ? open : null,
                              icon: const Icon(
                                Icons.mode_comment_outlined,
                                size: 18,
                              ),
                              label: Text(
                                'Comments ${snap.data?.length ?? 0}',
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (givers.isNotEmpty)
                        InkWell(
                          key: const ValueKey('kudos-givers'),
                          onTap: () => _showGivers(context, givers),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                            child: Text(
                              kudosLine(givers, me.uid),
                              style: muted,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Everyone who gave kudos, in a sheet.
  void _showGivers(BuildContext context, Map<String, String> givers) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: ListView(
          key: const ValueKey('kudos-sheet'),
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Kudos from'),
            ),
            for (final e in givers.entries)
              ListTile(
                leading: const Icon(Icons.thumb_up_outlined),
                title: Text(_giverName(e.key, e.value, me.uid)),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _workoutBody(WeightUnit units, TextStyle? muted) {
    final shown = post.exercises.take(4).toList();
    return [
      const SizedBox(height: 8),
      Row(
        children: [
          _Stat('Time', '${post.durationMinutes} min'),
          _Stat('Sets', '${post.totalSets}'),
          _Stat(
            'Volume',
            post.volumeKg > 0 ? formatWeight(post.volumeKg, units) : '—',
          ),
        ],
      ),
      const SizedBox(height: 8),
      for (final e in shown)
        Text(
          '${e.name} · ${e.sets} sets'
          '${e.topWeightKg == null ? '' : ' · top ${formatWeight(e.topWeightKg!, units)}'}'
          '${e.topReps == null ? '' : ' × ${e.topReps}'}',
        ),
      if (post.exercises.length > shown.length)
        Text(
          '+${post.exercises.length - shown.length} more',
          style: muted,
        ),
      if (post.records.isNotEmpty) ...[
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final r in post.records)
              Chip(
                avatar: const Icon(Icons.emoji_events_outlined, size: 18),
                label: Text(
                  'Best: ${r.exercise} ${formatWeight(r.weightKg, units)}',
                ),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ],
    ];
  }

  TrainingProgram? get _program {
    final json = post.program;
    if (json == null) return null;
    try {
      return TrainingProgram.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  List<Widget> _programBody(BuildContext context, TextStyle? muted) {
    final program = _program;
    if (program == null) {
      return [Text('This program could not be read.', style: muted)];
    }
    final days = program.trainingDays.length;
    return [
      Text(
        [
          'Program',
          if (program.goal != null) program.goal!.label,
          if (days > 0) '$days day${days == 1 ? '' : 's'} a week',
        ].join(' · '),
        style: muted,
      ),
      const SizedBox(height: 8),
      for (final w in program.workouts) ...[
        Text(
          '${w.name} · ${w.exercises.length} exercise'
          '${w.exercises.length == 1 ? '' : 's'}',
          style: openable ? null : Theme.of(context).textTheme.titleSmall,
        ),
        // On the post's own page: the full program, to look at before
        // copying it.
        if (!openable)
          for (final e in w.exercises)
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 2),
              child: Text(
                '${ExerciseLibrary.byId(e.exerciseId)?.name ?? e.exerciseId}'
                ' · ${plannedSetsSummary(e.plannedSets)}',
              ),
            ),
        if (!openable) const SizedBox(height: 6),
      ],
      if (openable)
        Text('Open to see every exercise.', style: muted),
      if (post.authorUid != me.uid) ...[
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const ValueKey('copy-program'),
          onPressed: () => _copy(context, program),
          icon: const Icon(Icons.library_add_outlined),
          label: const Text('Copy to my programs'),
        ),
      ],
    ];
  }

  /// Adds a copy to the user's own programs, with fresh ids. Not activated:
  /// the user's current program stays as it is.
  Future<void> _copy(BuildContext context, TrainingProgram program) async {
    final messenger = ScaffoldMessenger.of(context);
    final programs = ProgramScope.of(context, listen: false);
    try {
      await programs.saveProgram(
        program.duplicate(name: '${program.name} (from @${post.authorHandle})'),
      );
      messenger.showSnackBar(
        const SnackBar(duration: kSnackBarDuration, persist: false, content: Text('Added to your programs.')),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(duration: kSnackBarDuration, persist: false, content: Text("Couldn't copy the program.")),
      );
    }
  }

  List<Widget> _progressBody(
    BuildContext context,
    WeightUnit units,
    TextStyle? muted,
  ) => [
    Text(
      'Last ${post.periodDays} days: ${post.workoutCount} workout'
      '${post.workoutCount == 1 ? '' : 's'} · ${post.totalSets} sets',
    ),
    if (post.changes.isEmpty)
      Text('No top-weight changes to show yet.', style: muted)
    else ...[
      const SizedBox(height: 8),
      for (final c in post.changes)
        Row(
          children: [
            Icon(
              c.toKg > c.fromKg ? Icons.trending_up : Icons.trending_down,
              size: 18,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${c.exercise}: ${formatWeight(c.fromKg, units)} → '
                '${formatWeight(c.toKg, units)}',
              ),
            ),
          ],
        ),
      Text('Top set, first vs latest session.', style: muted),
    ],
  ];

  Future<void> _delete(BuildContext context) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this post?'),
        content: const Text(
          'Friends will no longer see it. Your workout history is not '
          'affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (yes == true) await communityService.deletePost(post.id);
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          Text(value, style: theme.textTheme.titleSmall),
        ],
      ),
    );
  }
}

String _giverName(String uid, String name, String myUid) =>
    uid == myUid ? 'You' : (name.isEmpty ? 'A friend' : name);

/// "Kudos from Ana", "Kudos from You and Ana", "Kudos from Ana, Ben and 3
/// others". You come first when you gave kudos.
String kudosLine(Map<String, String> givers, String myUid) {
  final names = [
    if (givers.containsKey(myUid)) 'You',
    for (final e in givers.entries)
      if (e.key != myUid) _giverName(e.key, e.value, myUid),
  ];
  if (names.isEmpty) return '';
  if (names.length == 1) return 'Kudos from ${names.first}';
  if (names.length == 2) return 'Kudos from ${names[0]} and ${names[1]}';
  final others = names.length - 2;
  return 'Kudos from ${names[0]}, ${names[1]} and $others '
      'other${others == 1 ? '' : 's'}';
}
