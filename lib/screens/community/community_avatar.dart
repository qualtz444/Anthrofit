import 'package:flutter/material.dart';

import '../../community/community_models.dart';
import '../../community/community_service.dart';

class CommunityAvatar extends StatefulWidget {
  const CommunityAvatar({
    super.key,
    required this.uid,
    required this.fallbackName,
    required this.radius,
  });

  final String uid;
  final String fallbackName;
  final double radius;

  @override
  State<CommunityAvatar> createState() => _CommunityAvatarState();
}

class _CommunityAvatarState extends State<CommunityAvatar> {
  late Future<CommunityProfile?> _profile = communityService.profileOf(
    widget.uid,
  );

  @override
  void initState() {
    super.initState();
    communityAvatarChanges.addListener(_avatarChanged);
  }

  @override
  void dispose() {
    communityAvatarChanges.removeListener(_avatarChanged);
    super.dispose();
  }

  void _avatarChanged() {
    setState(() {
      _profile = communityService.profileOf(widget.uid);
    });
  }

  @override
  void didUpdateWidget(covariant CommunityAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid) {
      _profile = communityService.profileOf(widget.uid);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _profile,
    builder: (context, snapshot) {
      final avatarBytes = snapshot.data?.avatarBytes;
      final initial = widget.fallbackName.trim().isEmpty
          ? '?'
          : widget.fallbackName.trim().characters.first.toUpperCase();
      return CircleAvatar(
        radius: widget.radius,
        backgroundImage: avatarBytes == null ? null : MemoryImage(avatarBytes),
        child: avatarBytes == null ? Text(initial) : null,
      );
    },
  );
}
