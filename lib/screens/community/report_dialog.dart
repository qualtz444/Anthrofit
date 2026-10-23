import 'package:flutter/material.dart';

import '../../community/community_models.dart';
import '../../community/community_service.dart';
import '../../core/snack_bar_timing.dart';

/// Asks why, then files a report. Reports are only readable in the Firebase
/// console, where the team reviews them; the person is not told who reported.
Future<void> reportDialog(
  BuildContext context, {
  required CommunityProfile me,
  required String targetUid,
  String? postId,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  const reasons = [
    'Spam or fake',
    'Harassment or hate',
    'Unsafe training advice',
    'Something else',
  ];
  final reason = await showDialog<String>(
    context: context,
    builder: (c) => SimpleDialog(
      title: Text(postId == null ? 'Report this person' : 'Report this post'),
      children: [
        for (final r in reasons)
          SimpleDialogOption(
            onPressed: () => Navigator.of(c).pop(r),
            child: Text(r),
          ),
      ],
    ),
  );
  if (reason == null) return;
  try {
    await communityService.report(
      reporterUid: me.uid,
      targetUid: targetUid,
      reason: reason,
      postId: postId,
    );
    messenger.showSnackBar(
      const SnackBar(duration: kSnackBarDuration, persist: false,
        content: Text(
          'Report sent. You can also remove or block them from their profile.',
        ),
      ),
    );
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(duration: kSnackBarDuration, persist: false, content: Text("Couldn't send the report.")),
    );
  }
}
