import 'package:flutter/material.dart';

import '../../community/community_models.dart';
import '../../community/community_service.dart';
import '../../core/format.dart';
import 'post_card.dart';
import '../../core/snack_bar_timing.dart';

/// A shared workout with its comments.
class PostDetailScreen extends StatefulWidget {
  const PostDetailScreen({super.key, required this.post, required this.me});

  final WorkoutPost post;
  final CommunityProfile me;

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final TextEditingController _text = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty || text.length > PostComment.maxLength) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sending = true);
    try {
      await communityService.addComment(widget.post, widget.me, text);
      _text.clear();
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(duration: kSnackBarDuration, persist: false, content: Text("Couldn't post your comment.")),
      );
    }
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final post = widget.post;
    return Scaffold(
      appBar: AppBar(title: Text(post.workoutName)),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                PostCard(post: post, me: widget.me, openable: false),
                Text('Comments', style: theme.textTheme.titleSmall),
                StreamBuilder<List<PostComment>>(
                  stream: communityService.comments(post.id),
                  builder: (context, snap) {
                    final list = snap.data ?? const <PostComment>[];
                    if (list.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('No comments yet.'),
                      );
                    }
                    return Column(
                      children: [
                        for (final c in list)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text('@${c.authorHandle}'),
                            subtitle: Text(c.text),
                            trailing:
                                c.authorUid == widget.me.uid ||
                                    post.authorUid == widget.me.uid
                                ? IconButton(
                                    tooltip: 'Delete comment',
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () => communityService
                                        .deleteComment(post.id, c.id),
                                  )
                                : Text(
                                    formatDate(
                                      c.createdAt,
                                      today: DateTime.now(),
                                    ),
                                    style: theme.textTheme.bodySmall,
                                  ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('comment-field'),
                      controller: _text,
                      maxLength: PostComment.maxLength,
                      decoration: const InputDecoration(
                        hintText: 'Add a comment',
                        counterText: '',
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('comment-send'),
                    tooltip: 'Send',
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
