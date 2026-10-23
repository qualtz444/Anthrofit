import 'package:flutter/material.dart';

import '../../community/community_models.dart';
import '../../community/community_service.dart';
import '../../core/format.dart';
import '../../data/training_stats.dart';

/// Friends-only competition: a leaderboard of shared workouts this week or
/// month, and challenges with a target. Strangers never appear here.
class CompeteTab extends StatefulWidget {
  const CompeteTab({super.key, required this.me});

  final CommunityProfile me;

  @override
  State<CompeteTab> createState() => _CompeteTabState();
}

class _CompeteTabState extends State<CompeteTab> {
  bool _month = false;
  late Future<List<WorkoutPost>> _posts;

  DateTime get _since {
    final now = DateTime.now();
    return _month ? DateTime(now.year, now.month) : startOfWeek(now);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => _posts = communityService.postsSince(widget.me.uid, _since);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final me = widget.me;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Leaderboard', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<bool>(
          key: const ValueKey('leaderboard-period'),
          segments: const [
            ButtonSegment(value: false, label: Text('This week')),
            ButtonSegment(value: true, label: Text('This month')),
          ],
          selected: {_month},
          onSelectionChanged: (s) => setState(() {
            _month = s.first;
            _load();
          }),
        ),
        const SizedBox(height: 8),
        FutureBuilder<List<WorkoutPost>>(
          future: _posts,
          builder: (context, snap) {
            if (snap.hasError) {
              return const Text("Couldn't load the leaderboard.");
            }
            if (!snap.hasData) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return StreamBuilder<List<Friend>>(
              stream: communityService.friends(me.uid),
              builder: (context, friendSnap) {
                final friends = friendSnap.data ?? const <Friend>[];
                final ids = {me.uid, for (final f in friends) f.uid};
                final rows = leaderboard(
                  [
                    for (final p in snap.data!)
                      if (ids.contains(p.authorUid)) p,
                  ],
                  _since,
                  include: ids,
                  handles: {
                    me.uid: me.handle,
                    for (final f in friends) f.uid: f.handle,
                  },
                );
                return Column(
                  children: [
                    for (var i = 0; i < rows.length; i++)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(radius: 14, child: Text('${i + 1}')),
                        title: Text(
                          rows[i].uid == me.uid ? 'You' : '@${rows[i].handle}',
                          style: rows[i].uid == me.uid
                              ? const TextStyle(fontWeight: FontWeight.w600)
                              : null,
                        ),
                        trailing: Text(
                          '${rows[i].workouts} workouts · ${rows[i].sets} sets',
                        ),
                      ),
                    Text(
                      'Counts workouts shared with friends, not every '
                      'workout logged.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                );
              },
            );
          },
        ),
        const Divider(height: 32),
        Row(
          children: [
            Expanded(
              child: Text('Challenges', style: theme.textTheme.titleMedium),
            ),
            TextButton.icon(
              key: const ValueKey('new-challenge'),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => _NewChallengeDialog(me: me),
              ),
              icon: const Icon(Icons.add),
              label: const Text('New'),
            ),
          ],
        ),
        StreamBuilder<List<Challenge>>(
          stream: communityService.challenges(me.uid),
          builder: (context, snap) {
            final list = snap.data ?? const <Challenge>[];
            if (list.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No challenges yet. Start one and pick friends to join.',
                ),
              );
            }
            return Column(
              children: [for (final c in list) _ChallengeCard(c: c, me: me)],
            );
          },
        ),
      ],
    );
  }
}

class _ChallengeCard extends StatelessWidget {
  const _ChallengeCard({required this.c, required this.me});

  final Challenge c;
  final CommunityProfile me;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final standings = [...c.members]
      ..sort((a, b) => (c.progress[b] ?? 0).compareTo(c.progress[a] ?? 0));
    final status = now.isBefore(c.start)
        ? 'Starts ${formatDate(c.start, today: now)}'
        : now.isAfter(c.end)
        ? 'Ended ${formatDate(c.end, today: now)}'
        : 'Ends ${formatDate(c.end, today: now)}';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(c.title, style: theme.textTheme.titleSmall),
                ),
                PopupMenuButton<String>(
                  onSelected: (_) => communityService.leaveChallenge(c, me.uid),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'leave', child: Text('Leave')),
                  ],
                ),
              ],
            ),
            Text(
              'Reach ${c.target} ${c.metric.label} · $status',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            for (final m in standings)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${m == me.uid ? 'You' : '@${c.handles[m] ?? '?'}'}: '
                      '${c.progress[m] ?? 0} / ${c.target}',
                    ),
                    LinearProgressIndicator(
                      value: c.target <= 0
                          ? 0
                          : ((c.progress[m] ?? 0) / c.target).clamp(0.0, 1.0),
                    ),
                  ],
                ),
              ),
            Text(
              'Counts workouts each member shares while it runs.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Pick a name, what to count, a target, how long, and which friends.
/// The target is the user's own choice: the app suggests none.
class _NewChallengeDialog extends StatefulWidget {
  const _NewChallengeDialog({required this.me});

  final CommunityProfile me;

  @override
  State<_NewChallengeDialog> createState() => _NewChallengeDialogState();
}

class _NewChallengeDialogState extends State<_NewChallengeDialog> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _target = TextEditingController();
  ChallengeMetric _metric = ChallengeMetric.workouts;
  int _days = 30;
  final Set<String> _picked = {};
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _target.dispose();
    super.dispose();
  }

  Future<void> _create(List<Friend> friends) async {
    final title = _title.text.trim();
    final target = int.tryParse(_target.text.trim());
    if (title.isEmpty || target == null || target < 1 || _picked.isEmpty) {
      setState(
        () => _error = 'Add a name, a target of at least 1, and a friend.',
      );
      return;
    }
    final me = widget.me;
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final members = [me.uid, ..._picked];
    final navigator = Navigator.of(context);
    final error = await communityService.createChallenge(
      Challenge(
        id: '',
        creatorUid: me.uid,
        title: title,
        metric: _metric,
        target: target,
        start: start,
        end: start.add(Duration(days: _days, seconds: -1)),
        members: members,
        handles: {
          me.uid: me.handle,
          for (final f in friends)
            if (_picked.contains(f.uid)) f.uid: f.handle,
        },
        progress: const {},
      ),
      me,
    );
    if (!mounted) return;
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Friend>>(
      stream: communityService.friends(widget.me.uid),
      builder: (context, snap) {
        final friends = snap.data ?? const <Friend>[];
        return AlertDialog(
          title: const Text('New challenge'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                TextField(
                  key: const ValueKey('challenge-title'),
                  controller: _title,
                  maxLength: 40,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const Text('Count'),
                DropdownButton<ChallengeMetric>(
                  value: _metric,
                  isExpanded: true,
                  items: [
                    for (final m in ChallengeMetric.values)
                      DropdownMenuItem(value: m, child: Text(m.label)),
                  ],
                  onChanged: (m) => setState(() => _metric = m ?? _metric),
                ),
                TextField(
                  key: const ValueKey('challenge-target'),
                  controller: _target,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Target'),
                ),
                const SizedBox(height: 8),
                const Text('Length'),
                DropdownButton<int>(
                  value: _days,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 7, child: Text('1 week')),
                    DropdownMenuItem(value: 14, child: Text('2 weeks')),
                    DropdownMenuItem(value: 30, child: Text('30 days')),
                  ],
                  onChanged: (d) => setState(() => _days = d ?? _days),
                ),
                const SizedBox(height: 12),
                const Text('Friends'),
                if (friends.isEmpty)
                  const Text('Add friends first in the Friends tab.')
                else
                  for (final f in friends)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('@${f.handle}'),
                      value: _picked.contains(f.uid),
                      onChanged: (v) => setState(
                        () => v == true
                            ? _picked.add(f.uid)
                            : _picked.remove(f.uid),
                      ),
                    ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
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
            FilledButton(
              key: const ValueKey('challenge-create'),
              onPressed: () => _create(friends),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
  }
}
