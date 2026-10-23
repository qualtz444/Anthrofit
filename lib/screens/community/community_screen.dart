import 'package:flutter/material.dart';

import '../../auth/auth_scope.dart';
import '../../community/community_models.dart';
import '../../community/community_service.dart';
import '../widgets/empty_state.dart';
import 'friend_profile_screen.dart';
import 'post_card.dart';
import 'share_composer.dart';

/// The community: a friends-only feed, with a composer on top for sharing
/// progress, and friends.
///
/// Needs an account: a guest has no identity to befriend. Body composition
/// is shared only when the user picks it in the composer; scan outlines,
/// proportion scans and measurements never are; progress photos only when
/// picked for a post.
class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  Future<CommunityProfile?>? _profile;
  String? _uid;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final uid = AuthScope.of(context).user?.uid;
    if (uid != _uid) {
      _uid = uid;
      _profile = uid == null ? null : communityService.profileOf(uid);
    }
  }

  void _reload() =>
      setState(() => _profile = communityService.profileOf(_uid!));

  @override
  Widget build(BuildContext context) {
    final auth = AuthScope.of(context);
    if (auth.isGuest || auth.user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Community')),
        body: const EmptyState(
          title: 'Sign in to use Community',
          message:
              'Share workouts with friends, give kudos and comment. Guest '
              'mode keeps everything on this phone.',
        ),
      );
    }
    return FutureBuilder<CommunityProfile?>(
      future: _profile,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Community')),
            body: EmptyState(
              title: "Couldn't load Community",
              message: 'Check your connection.',
              actionLabel: 'Try again',
              onAction: _reload,
            ),
          );
        }
        final me = snap.data;
        if (me == null) return _HandleSetup(onDone: _reload);
        return DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Community'),
              bottom: const TabBar(
                tabs: [
                  Tab(text: 'Feed'),
                  Tab(text: 'Friends'),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                _FeedTab(me: me),
                _FriendsTab(me: me, onProfileChanged: _reload),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// First visit: pick a username friends can find you by.
class _HandleSetup extends StatefulWidget {
  const _HandleSetup({required this.onDone});

  final VoidCallback onDone;

  @override
  State<_HandleSetup> createState() => _HandleSetupState();
}

class _HandleSetupState extends State<_HandleSetup> {
  final TextEditingController _handle = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _handle.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final auth = AuthScope.of(context, listen: false);
    final user = auth.user!;
    final account = auth.account;
    final handle = _handle.text.trim().toLowerCase();
    final name = [
      account?.firstName ?? '',
      account?.lastName ?? '',
    ].where((s) => s.isNotEmpty).join(' ');
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await communityService.claimHandle(
      uid: user.uid,
      handle: handle,
      displayName: name.isNotEmpty ? name : (user.displayName ?? handle),
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = error;
    });
    if (error == null) widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Community')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Pick a username',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'Friends find you by it. Only friends you accept see what you '
            'share. Nothing is shared unless you choose to share it.',
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('handle-field'),
            controller: _handle,
            autocorrect: false,
            decoration: InputDecoration(
              prefixText: '@',
              labelText: 'Username',
              helperText: '3–20 lowercase letters, numbers or _',
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const ValueKey('handle-save'),
            onPressed: _saving ? null : _save,
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }
}

class _FeedTab extends StatelessWidget {
  const _FeedTab({required this.me});

  final CommunityProfile me;

  // The composer is always on top, even while the feed is loading or when
  // it fails to load, so sharing never depends on reading the feed.
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ShareComposer(me: me),
        StreamBuilder<List<WorkoutPost>>(
          stream: communityService.feed(me.uid),
          builder: (context, snap) {
            if (snap.hasError) {
              return const EmptyState(
                title: "Couldn't load the feed",
                message: 'Check your connection and try again later.',
              );
            }
            if (!snap.hasData) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return StreamBuilder<List<Friend>>(
              stream: communityService.friends(me.uid),
              builder: (context, friendSnap) {
                // Only current friends' posts: someone removed drops out of
                // the feed even if their older posts still list you.
                final friendIds = {
                  for (final f in friendSnap.data ?? const <Friend>[]) f.uid,
                };
                final posts = [
                  for (final p in snap.data!)
                    if (p.authorUid == me.uid ||
                        friendIds.contains(p.authorUid))
                      p,
                ];
                return _posts(posts);
              },
            );
          },
        ),
      ],
    );
  }

  /// The posts, newest first.
  Widget _posts(List<WorkoutPost> posts) {
    if (posts.isEmpty) {
      return const EmptyState(
        title: 'Nothing shared yet',
        message:
            'Share your progress above, finish a workout with "Share '
            'with friends" on, or add friends in the Friends tab.',
      );
    }
    return Column(
      children: [for (final p in posts) PostCard(post: p, me: me)],
    );
  }
}

class _FriendsTab extends StatefulWidget {
  const _FriendsTab({required this.me, required this.onProfileChanged});

  final CommunityProfile me;

  /// Reloads the profile after a username change.
  final VoidCallback onProfileChanged;

  @override
  State<_FriendsTab> createState() => _FriendsTabState();
}

class _FriendsTabState extends State<_FriendsTab> {
  final TextEditingController _add = TextEditingController();
  String? _message;

  @override
  void dispose() {
    _add.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final error = await communityService.sendRequest(widget.me, _add.text);
    if (!mounted) return;
    setState(() => _message = error ?? 'Request sent.');
    if (error == null) _add.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final me = widget.me;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'You are @${me.handle}',
                style: theme.textTheme.titleSmall,
              ),
            ),
            TextButton(
              key: const ValueKey('change-username'),
              onPressed: _changeHandle,
              child: const Text('Change'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('add-friend-field'),
                controller: _add,
                autocorrect: false,
                decoration: const InputDecoration(
                  prefixText: '@',
                  labelText: 'Add a friend by username',
                ),
              ),
            ),
            IconButton(
              key: const ValueKey('add-friend-send'),
              tooltip: 'Send request',
              onPressed: _send,
              icon: const Icon(Icons.person_add_alt_1),
            ),
          ],
        ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(_message!, style: theme.textTheme.bodySmall),
          ),
        const SizedBox(height: 16),
        StreamBuilder<List<FriendRequest>>(
          stream: communityService.incoming(me.uid),
          builder: (context, snap) {
            final list = snap.data ?? const <FriendRequest>[];
            if (list.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Requests', style: theme.textTheme.titleSmall),
                for (final r in list)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(r.fromName.isEmpty ? '@${r.fromHandle}' : r.fromName),
                    subtitle: Text('@${r.fromHandle}'),
                    trailing: Wrap(
                      children: [
                        IconButton(
                          tooltip: 'Decline',
                          icon: const Icon(Icons.close),
                          onPressed: () => communityService.cancelOrDecline(r),
                        ),
                        IconButton(
                          tooltip: 'Accept',
                          icon: const Icon(Icons.check),
                          onPressed: () => communityService.accept(r, me),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
              ],
            );
          },
        ),
        StreamBuilder<List<FriendRequest>>(
          stream: communityService.outgoing(me.uid),
          builder: (context, snap) {
            final list = snap.data ?? const <FriendRequest>[];
            if (list.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sent', style: theme.textTheme.titleSmall),
                for (final r in list)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('@${r.toHandle}'),
                    subtitle: const Text('Waiting for them to accept'),
                    trailing: TextButton(
                      onPressed: () => communityService.cancelOrDecline(r),
                      child: const Text('Cancel'),
                    ),
                  ),
                const SizedBox(height: 16),
              ],
            );
          },
        ),
        Text('Friends', style: theme.textTheme.titleSmall),
        StreamBuilder<List<Friend>>(
          stream: communityService.friends(me.uid),
          builder: (context, snap) {
            final list = snap.data ?? const <Friend>[];
            if (list.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No friends yet. Add one by username above.'),
              );
            }
            return Column(
              children: [
                for (final f in list)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(f.displayName.isEmpty ? '@${f.handle}' : f.displayName),
                    subtitle: Text('@${f.handle}'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => FriendProfileScreen(
                          uid: f.uid,
                          handle: f.handle,
                          name: f.displayName,
                          me: me,
                        ),
                      ),
                    ),
                    trailing: IconButton(
                      tooltip: 'Remove friend',
                      icon: const Icon(Icons.person_remove_outlined),
                      onPressed: () => _remove(f),
                    ),
                  ),
              ],
            );
          },
        ),
        StreamBuilder<Map<String, String>>(
          stream: communityService.blocked(me.uid),
          builder: (context, snap) {
            final blocked = snap.data ?? const <String, String>{};
            if (blocked.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                Text('Blocked', style: theme.textTheme.titleSmall),
                for (final e in blocked.entries)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(e.value.isEmpty ? 'Blocked account' : '@${e.value}'),
                    trailing: TextButton(
                      onPressed: () => communityService.unblock(me.uid, e.key),
                      child: const Text('Unblock'),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _changeHandle() async {
    final controller = TextEditingController(text: widget.me.handle);
    String? error;
    final changed = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialog) => AlertDialog(
          title: const Text('Change username'),
          content: TextField(
            key: const ValueKey('new-username'),
            controller: controller,
            autocorrect: false,
            decoration: InputDecoration(
              prefixText: '@',
              helperText:
                  'Old posts keep the name they were shared with.',
              errorText: error,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final e = await communityService.changeHandle(
                  widget.me,
                  controller.text,
                );
                if (e == null) {
                  if (c.mounted) Navigator.of(c).pop(true);
                } else {
                  setDialog(() => error = e);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (changed == true) widget.onProfileChanged();
  }

  Future<void> _remove(Friend f) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Remove @${f.handle}?'),
        content: const Text(
          'They stop seeing your workouts, including ones already shared, '
          'and theirs leave your feed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (yes == true) {
      await communityService.removeFriend(widget.me.uid, f.uid);
    }
  }
}
