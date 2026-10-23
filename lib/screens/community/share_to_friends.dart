import 'package:flutter/material.dart';

import '../../auth/auth_scope.dart';
import '../../community/community_models.dart';
import '../../community/community_service.dart';
import '../../core/snack_bar_timing.dart';

/// The signed-in user's community profile, ready to share as. Guests, and
/// accounts without a username or without a connection, get a snackbar saying
/// what to do and null back, so nothing is shared.
Future<CommunityProfile?> communityAuthorFor(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final auth = context.getInheritedWidgetOfExactType<AuthScope>()?.notifier;
  final uid = auth?.user?.uid;
  if (auth == null || auth.isGuest || uid == null) {
    messenger.showSnackBar(
      const SnackBar(duration: kSnackBarDuration, persist: false, content: Text('Sign in to share with friends.')),
    );
    return null;
  }

  final CommunityProfile? me;
  try {
    me = await withProgress(
      context,
      'Getting ready to share…',
      () => communityService.profileOf(uid),
    );
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(duration: kSnackBarDuration, persist: false, content: Text("Couldn't reach Community. Try again.")),
    );
    return null;
  }
  if (me == null) {
    messenger.showSnackBar(
      const SnackBar(duration: kSnackBarDuration, persist: false,
        content: Text('Set a username first: Home → Community.'),
      ),
    );
    return null;
  }
  if (!context.mounted) return null;

  return me;
}

/// Shares something with friends after the user confirms what will be seen.
///
/// [build] makes the post once the user's community profile and friends are
/// known. Guests, and accounts without a username, are told what to do
/// instead. Nothing is shared without the confirm step.
Future<void> shareToFriends(
  BuildContext context, {
  required String what,
  required String preview,
  required WorkoutPost Function(CommunityProfile me, List<String> friends)
  build,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final me = await communityAuthorFor(context);
  if (me == null || !context.mounted) return;

  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('Share $what with friends?'),
      content: Text(
        '$preview\n\nOnly your friends will see it. Body scans, body weight '
        'and photos are not included.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(c).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('confirm-share'),
          onPressed: () => Navigator.of(c).pop(true),
          child: const Text('Share'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final CommunityProfile author = me;

  try {
    final error = await withProgress(context, 'Sharing with friends…', () async {
      final friends = await communityService.friendUids(author.uid);
      return communityService.share(build(author, friends));
    });
    messenger.showSnackBar(
      SnackBar(duration: kSnackBarDuration, persist: false, content: Text(error ?? 'Shared with your friends.')),
    );
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(duration: kSnackBarDuration, persist: false, content: Text("Couldn't share. Try again.")),
    );
  }
}

/// Runs [task] behind a small "please wait" dialog, so a slow network never
/// looks like a frozen button. The dialog cannot be dismissed by tapping
/// outside or Back, and always closes when the task ends, even on error.
Future<T> withProgress<T>(
  BuildContext context,
  String message,
  Future<T> Function() task,
) async {
  BuildContext? dialogContext;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (c) {
      dialogContext = c;
      return PopScope(
        canPop: false,
        child: AlertDialog(
          key: const ValueKey('progress-dialog'),
          content: Row(
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(width: 16),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      );
    },
  );

  // Allow the dialog route to be mounted before running the task.
  await Future<void>.value();

  try {
    return await task();
  } finally {
    if (dialogContext != null && dialogContext!.mounted) {
      Navigator.of(dialogContext!).pop();
    } else if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }
}
