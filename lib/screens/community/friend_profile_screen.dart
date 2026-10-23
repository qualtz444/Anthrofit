import 'package:flutter/material.dart';

import '../../community/community_models.dart';
import '../../community/community_service.dart';
import '../widgets/empty_state.dart';
import 'post_card.dart';
import 'report_dialog.dart';

/// A friend's page: their shared posts that you can see, and the ways to
/// end the connection (remove, block) or report them.
class FriendProfileScreen extends StatelessWidget {
  const FriendProfileScreen({
    super.key,
    required this.uid,
    required this.handle,
    required this.name,
    required this.me,
  });

  final String uid;
  final String handle;
  final String name;
  final CommunityProfile me;

  Future<void> _confirm(
    BuildContext context, {
    required String title,
    required String body,
    required String action,
    required Future<void> Function() run,
  }) async {
    final navigator = Navigator.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await run();
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(name.isEmpty ? '@$handle' : name),
        actions: [
          PopupMenuButton<String>(
            key: const ValueKey('profile-menu'),
            onSelected: (v) {
              switch (v) {
                case 'remove':
                  _confirm(
                    context,
                    title: 'Remove @$handle?',
                    body:
                        'They stop seeing your workouts, including ones '
                        'already shared, and theirs leave your feed.',
                    action: 'Remove',
                    run: () => communityService.removeFriend(me.uid, uid),
                  );
                case 'block':
                  _confirm(
                    context,
                    title: 'Block @$handle?',
                    body:
                        'Removes them as a friend and stops any new friend '
                        'requests from them. They are not told. You can '
                        'unblock them in the Friends tab.',
                    action: 'Block',
                    run: () => communityService.block(me.uid, uid, handle: handle),
                  );
                case 'report':
                  reportDialog(context, me: me, targetUid: uid);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'remove', child: Text('Remove friend')),
              PopupMenuItem(value: 'block', child: Text('Block')),
              PopupMenuItem(value: 'report', child: Text('Report')),
            ],
          ),
        ],
      ),
      body: StreamBuilder<List<WorkoutPost>>(
        stream: communityService.postsBy(uid, me.uid),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final posts = snap.data!;
          final workouts = [
            for (final p in posts)
              if (p.kind == PostKind.workout) p,
          ];
          final since = DateTime.now().subtract(const Duration(days: 30));
          final recent = [
            for (final p in workouts)
              if (!p.createdAt.isBefore(since)) p,
          ];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('@$handle', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                '${recent.length} shared workout${recent.length == 1 ? '' : 's'} '
                'in the last 30 days · '
                '${recent.fold<int>(0, (s, p) => s + p.totalSets)} sets',
              ),
              const SizedBox(height: 16),
              if (posts.isEmpty)
                const EmptyState(title: 'Nothing shared with you yet')
              else
                for (final p in posts) PostCard(post: p, me: me),
            ],
          );
        },
      ),
    );
  }
}
