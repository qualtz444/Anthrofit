import 'package:flutter/material.dart';

import '../../community/community_models.dart';
import '../../community/community_service.dart';
import '../../core/format.dart';
import '../widgets/empty_state.dart';

/// Kudos, comments, friend requests and challenge invites, newest first.
/// In-app only: there are no phone push notifications.
class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key, required this.uid});

  final String uid;

  static IconData _icon(InboxType t) => switch (t) {
    InboxType.kudos => Icons.thumb_up_outlined,
    InboxType.comment => Icons.mode_comment_outlined,
    InboxType.request => Icons.person_add_alt_1,
    InboxType.accepted => Icons.handshake_outlined,
    InboxType.challenge => Icons.flag_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            key: const ValueKey('mark-all-read'),
            onPressed: () => communityService.markAllRead(uid),
            child: const Text('Mark all read'),
          ),
        ],
      ),
      body: StreamBuilder<List<InboxItem>>(
        stream: communityService.inbox(uid),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data!;
          if (items.isEmpty) {
            return const EmptyState(
              title: 'No notifications yet',
              message: 'Kudos, comments and friend requests show up here.',
            );
          }
          return ListView(
            children: [
              for (final i in items)
                ListTile(
                  leading: Icon(_icon(i.type)),
                  title: Text(
                    i.message,
                    style: i.read
                        ? null
                        : const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    formatDate(i.createdAt, today: DateTime.now()),
                    style: theme.textTheme.bodySmall,
                  ),
                  trailing: i.read
                      ? null
                      : Icon(
                          Icons.circle,
                          size: 10,
                          color: theme.colorScheme.primary,
                        ),
                  onTap: i.read
                      ? null
                      : () => communityService.markRead(uid, i.id),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// The bell on Home: shows the unread count, opens the inbox. Hidden for
/// guests, since they have no Community.
class InboxBell extends StatelessWidget {
  const InboxBell({super.key, required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: communityService.unreadCount(uid),
      builder: (context, snap) {
        final n = snap.data ?? 0;
        return IconButton(
          key: const ValueKey('open-inbox'),
          tooltip: 'Notifications',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => InboxScreen(uid: uid)),
          ),
          icon: Badge(
            isLabelVisible: n > 0,
            label: Text(n > 99 ? '99+' : '$n'),
            child: const Icon(Icons.notifications_outlined),
          ),
        );
      },
    );
  }
}
