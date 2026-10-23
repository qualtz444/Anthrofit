import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'community_models.dart';

/// Community storage. Firestore layout (see firestore.rules):
///
/// ```text
/// handles/{handle}                       {uid}           unique usernames
/// publicProfiles/{uid}                   {handle, displayName, avatar?}
/// friendRequests/{fromUid_toUid}         deleted once answered
/// friendships/{uid}/friends/{friendUid}  both sides written on accept
/// blocks/{uid}/blocked/{otherUid}        stops requests from them
/// reports/{id}                           write-only, reviewed in the console
/// inbox/{uid}/items/{id}                 kudos, comments, requests...
/// posts/{postId}                         readable by its audience
/// posts/{id}/kudos/{uid}
/// posts/{id}/comments/{commentId}
/// challenges/{id}                        friends-only challenges
/// ```
///
/// Separate from users/{uid}/data, so sharing never touches private data.
abstract class CommunityService {
  Future<CommunityProfile?> profileOf(String uid);
  Future<String?> setAvatar(String uid, Uint8List bytes);

  /// Claims [handle] for [uid]. Returns an error to show, or null.
  Future<String?> claimHandle({
    required String uid,
    required String handle,
    required String displayName,
  });

  /// Moves [me] to a new username; the old one is freed. Error, or null.
  Future<String?> changeHandle(CommunityProfile me, String handle);

  Future<String?> sendRequest(CommunityProfile me, String handle);
  Stream<List<FriendRequest>> incoming(String uid);
  Stream<List<FriendRequest>> outgoing(String uid);
  Future<void> accept(FriendRequest request, CommunityProfile me);
  Future<void> cancelOrDecline(FriendRequest request);

  Stream<List<Friend>> friends(String uid);
  Future<List<String>> friendUids(String uid);
  Future<void> removeFriend(String uid, String friendUid);

  /// Removes them as a friend and stops any further requests from them.
  Future<void> block(String uid, String otherUid, {String handle = ''});
  Future<void> unblock(String uid, String otherUid);

  /// Blocked accounts: uid → username at the time of blocking.
  Stream<Map<String, String>> blocked(String uid);

  /// Sends a report for review. [postId] when it is about one post.
  Future<void> report({
    required String reporterUid,
    required String targetUid,
    required String reason,
    String? postId,
  });

  /// Shares [post]. [photos] are JPEG bytes stored with it, in order, in
  /// the same write, so a post never appears without its photos.
  Future<String?> share(WorkoutPost post, {List<Uint8List> photos = const []});

  /// The photos stored with a post, in order. Empty when there are none or
  /// they cannot be read.
  Future<List<Uint8List>> postPhotos(String postId);

  /// Deletes a post and any photos stored with it.
  Future<void> deletePost(String postId);
  Stream<List<WorkoutPost>> feed(String uid, {int limit = 50});

  /// Posts by [authorUid] that [viewerUid] may see, newest first.
  Stream<List<WorkoutPost>> postsBy(String authorUid, String viewerUid);

  /// Posts [uid] may see since [since], for leaderboards.
  Future<List<WorkoutPost>> postsSince(String uid, DateTime since);

  Stream<Set<String>> kudos(String postId);

  /// Who gave kudos: uid → the name to show. Kudos given before names were
  /// stored show as an empty name.
  Stream<Map<String, String>> kudosGivers(String postId);
  Future<void> setKudos(
    WorkoutPost post,
    CommunityProfile me, {
    required bool on,
  });

  Stream<List<PostComment>> comments(String postId);
  Future<void> addComment(WorkoutPost post, CommunityProfile me, String text);
  Future<void> deleteComment(String postId, String commentId);

  Stream<List<InboxItem>> inbox(String uid);
  Stream<int> unreadCount(String uid);
  Future<void> markRead(String uid, String itemId);
  Future<void> markAllRead(String uid);

  Stream<List<Challenge>> challenges(String uid);
  Future<String?> createChallenge(Challenge challenge, CommunityProfile me);
  Future<void> leaveChallenge(Challenge challenge, String uid);

  /// Adds a shared workout to every active challenge [uid] is in.
  Future<void> recordWorkout(String uid, DateTime when, int sets);

  /// Removes everything [uid] has in Community, for account deletion: their
  /// posts with photos, kudos and comments; their kudos and comments on
  /// friends' posts; friends on both sides; requests; blocks; inbox;
  /// challenge places; username and public profile. Throws when their posts,
  /// friends, username or public profile could not be removed. Reports they
  /// sent are kept for review, and notifications already in other people's
  /// inboxes stay there.
  Future<void> deleteAccountData(String uid);
}

final ValueNotifier<int> communityAvatarChanges = ValueNotifier(0);

class FirestoreCommunityService implements CommunityService {
  static const _profileCacheDuration = Duration(minutes: 1);

  // Field and parameter names differ on purpose, as in FirestoreStore: the
  // analyzer asks for an initializing formal when they match.
  FirestoreCommunityService({FirebaseFirestore? instance})
    : _firestore = instance;

  final FirebaseFirestore? _firestore;
  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;
  final Map<String, Future<CommunityProfile?>> _profileCache = {};
  final Map<String, DateTime> _profileCacheAt = {};

  CollectionReference<Map<String, dynamic>> get _posts =>
      _db.collection('posts');
  CollectionReference<Map<String, dynamic>> get _requests =>
      _db.collection('friendRequests');
  CollectionReference<Map<String, dynamic>> get _challenges =>
      _db.collection('challenges');
  CollectionReference<Map<String, dynamic>> _friendsOf(String uid) =>
      _db.collection('friendships').doc(uid).collection('friends');
  CollectionReference<Map<String, dynamic>> _inboxOf(String uid) =>
      _db.collection('inbox').doc(uid).collection('items');
  CollectionReference<Map<String, dynamic>> _blocksOf(String uid) =>
      _db.collection('blocks').doc(uid).collection('blocked');

  /// Best effort: a notification that fails must not fail the action.
  Future<void> _notify(
    String toUid,
    CommunityProfile from,
    InboxType type, {
    String? postId,
    String? text,
  }) async {
    if (toUid == from.uid) return;
    try {
      await _inboxOf(toUid).add({
        'type': type.name,
        'fromUid': from.uid,
        'fromHandle': from.handle,
        'postId': postId,
        'text': text == null || text.length <= 80
            ? text
            : '${text.substring(0, 80)}…',
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[Community] notify failed: $e');
    }
  }

  @override
  Future<CommunityProfile?> profileOf(String uid) {
    final cached = _profileCache[uid];
    final cachedAt = _profileCacheAt[uid];
    if (cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _profileCacheDuration) {
      return cached;
    }
    final future = _loadProfile(uid);
    _profileCache[uid] = future;
    _profileCacheAt[uid] = DateTime.now();
    return future;
  }

  Future<CommunityProfile?> _loadProfile(String uid) async {
    final snap = await _db.collection('publicProfiles').doc(uid).get();
    final data = snap.data();
    return data == null ? null : CommunityProfile.fromJson(uid, data);
  }

  void _invalidateProfile(String uid) {
    _profileCache.remove(uid);
    _profileCacheAt.remove(uid);
  }

  @override
  Future<String?> setAvatar(String uid, Uint8List bytes) async {
    try {
      await _db.collection('publicProfiles').doc(uid).update({
        'avatar': Blob(bytes),
      });
      _invalidateProfile(uid);
      communityAvatarChanges.value++;
      return null;
    } catch (e) {
      _invalidateProfile(uid);
      debugPrint('[Community] set avatar failed: $e');
      return "Couldn't share your avatar with friends. Check your connection.";
    }
  }

  @override
  Future<String?> claimHandle({
    required String uid,
    required String handle,
    required String displayName,
  }) async {
    final problem = validateHandle(handle);
    if (problem != null) return problem;
    try {
      await _db.runTransaction((tx) async {
        final ref = _db.collection('handles').doc(handle);
        if ((await tx.get(ref)).exists) throw const _Taken();
        tx.set(ref, {'uid': uid});
        tx.set(
          _db.collection('publicProfiles').doc(uid),
          CommunityProfile(
            uid: uid,
            handle: handle,
            displayName: displayName,
          ).toJson(),
        );
      });
      _profileCache[uid] = Future.value(
        CommunityProfile(uid: uid, handle: handle, displayName: displayName),
      );
      _profileCacheAt[uid] = DateTime.now();
      return null;
    } on _Taken {
      return kHandleTaken;
    } catch (e) {
      debugPrint('[Community] claimHandle failed: $e');
      return "Couldn't save your username. Check your connection.";
    }
  }

  @override
  Future<String?> changeHandle(CommunityProfile me, String handle) async {
    final clean = handle.trim().toLowerCase().replaceFirst('@', '');
    final problem = validateHandle(clean);
    if (problem != null) return problem;
    if (clean == me.handle) return null;
    try {
      await _db.runTransaction((tx) async {
        final next = _db.collection('handles').doc(clean);
        if ((await tx.get(next)).exists) throw const _Taken();
        tx.set(next, {'uid': me.uid});
        tx.delete(_db.collection('handles').doc(me.handle));
        tx.update(_db.collection('publicProfiles').doc(me.uid), {
          'handle': clean,
        });
      });
      _invalidateProfile(me.uid);
      return null;
    } on _Taken {
      return kHandleTaken;
    } catch (e) {
      debugPrint('[Community] changeHandle failed: $e');
      return "Couldn't change your username.";
    }
  }

  @override
  Future<String?> sendRequest(CommunityProfile me, String handle) async {
    final clean = handle.trim().toLowerCase().replaceFirst('@', '');
    if (clean == me.handle) return "That's you.";
    try {
      final owner = await _db.collection('handles').doc(clean).get();
      final toUid = owner.data()?['uid'] as String?;
      if (toUid == null) return 'No one uses that username.';
      if ((await _friendsOf(me.uid).doc(toUid).get()).exists) {
        return 'You are already friends.';
      }
      if ((await _blocksOf(me.uid).doc(toUid).get()).exists) {
        return 'You blocked this person. Unblock them first.';
      }
      await _requests
          .doc('${me.uid}_$toUid')
          .set(
            FriendRequest(
              fromUid: me.uid,
              toUid: toUid,
              fromHandle: me.handle,
              fromName: me.displayName,
              toHandle: clean,
              createdAt: DateTime.now(),
            ).toJson(),
          );
      await _notify(toUid, me, InboxType.request);
      return null;
    } catch (e) {
      // A block by the other person also ends up here (rules refuse it),
      // and is deliberately not told apart.
      debugPrint('[Community] sendRequest failed: $e');
      return "Couldn't send the request.";
    }
  }

  Stream<List<FriendRequest>> _requestsWhere(String field, String uid) =>
      _requests
          .where(field, isEqualTo: uid)
          .snapshots()
          .map((q) => [for (final d in q.docs) FriendRequest.fromJson(d.data())]);

  @override
  Stream<List<FriendRequest>> incoming(String uid) =>
      _requestsWhere('toUid', uid);

  @override
  Stream<List<FriendRequest>> outgoing(String uid) =>
      _requestsWhere('fromUid', uid);

  @override
  Future<void> accept(FriendRequest request, CommunityProfile me) async {
    final batch = _db.batch()
      ..set(_friendsOf(me.uid).doc(request.fromUid), {
        'handle': request.fromHandle,
        'displayName': request.fromName,
        'since': FieldValue.serverTimestamp(),
      })
      ..set(_friendsOf(request.fromUid).doc(me.uid), {
        'handle': me.handle,
        'displayName': me.displayName,
        'since': FieldValue.serverTimestamp(),
      })
      ..delete(_requests.doc(request.id));
    await batch.commit();
    await _notify(request.fromUid, me, InboxType.accepted);
  }

  @override
  Future<void> cancelOrDecline(FriendRequest request) =>
      _requests.doc(request.id).delete();

  @override
  Stream<List<Friend>> friends(String uid) => _friendsOf(uid).snapshots().map(
    (q) => [for (final d in q.docs) Friend.fromJson(d.id, d.data())],
  );

  @override
  Future<List<String>> friendUids(String uid) async {
    final q = await _friendsOf(uid).get();
    return [for (final d in q.docs) d.id];
  }

  @override
  Future<void> removeFriend(String uid, String friendUid) async {
    // They stop seeing posts already shared with them, too.
    final mine = await _posts
        .where('audience', arrayContains: friendUid)
        .where('authorUid', isEqualTo: uid)
        .get();
    final batch = _db.batch()
      ..delete(_friendsOf(uid).doc(friendUid))
      ..delete(_friendsOf(friendUid).doc(uid));
    for (final d in mine.docs) {
      batch.update(d.reference, {
        'audience': FieldValue.arrayRemove([friendUid]),
      });
    }
    await batch.commit();
  }

  @override
  Future<void> block(String uid, String otherUid, {String handle = ''}) async {
    await _blocksOf(uid).doc(otherUid).set({
      'handle': handle,
      'at': FieldValue.serverTimestamp(),
    });
    // Any pending request in either direction goes too.
    for (final id in ['${uid}_$otherUid', '${otherUid}_$uid']) {
      try {
        await _requests.doc(id).delete();
      } catch (_) {}
    }
    await removeFriend(uid, otherUid);
  }

  @override
  Future<void> unblock(String uid, String otherUid) =>
      _blocksOf(uid).doc(otherUid).delete();

  @override
  Stream<Map<String, String>> blocked(String uid) => _blocksOf(uid)
      .snapshots()
      .map(
        (q) => {
          for (final d in q.docs) d.id: (d.data()['handle'] as String?) ?? '',
        },
      );

  @override
  Future<void> report({
    required String reporterUid,
    required String targetUid,
    required String reason,
    String? postId,
  }) => _db.collection('reports').add({
    'reporterUid': reporterUid,
    'targetUid': targetUid,
    'postId': postId,
    'reason': reason,
    'createdAt': FieldValue.serverTimestamp(),
  });

  @override
  Future<String?> share(
    WorkoutPost post, {
    List<Uint8List> photos = const [],
  }) async {
    try {
      final batch = _db.batch();
      final ref = _posts.doc(post.id);
      batch.set(ref, post.toJson());
      for (var i = 0; i < photos.length; i++) {
        batch.set(ref.collection('photos').doc('$i'), {
          'index': i,
          'image': Blob(photos[i]),
        });
      }
      await batch.commit();
      return null;
    } catch (e) {
      debugPrint('[Community] share failed: $e');
      return "Couldn't share it. It may already be shared.";
    }
  }

  @override
  Future<List<Uint8List>> postPhotos(String postId) async {
    try {
      final q = await _posts.doc(postId).collection('photos').get();
      final docs = [...q.docs]
        ..sort(
          (a, b) => ((a.data()['index'] as num?) ?? 0).compareTo(
            (b.data()['index'] as num?) ?? 0,
          ),
        );
      return [
        for (final d in docs)
          if (d.data()['image'] is Blob) (d.data()['image'] as Blob).bytes,
      ];
    } catch (e) {
      debugPrint('[Community] photos failed: $e');
      return const [];
    }
  }

  @override
  Future<void> deletePost(String postId) async {
    final ref = _posts.doc(postId);
    // Firestore does not delete a document's sub-collections with it, so
    // the photos go in the same write.
    final photos = await ref.collection('photos').get();
    final batch = _db.batch();
    for (final d in photos.docs) {
      batch.delete(d.reference);
    }
    batch.delete(ref);
    await batch.commit();
  }

  List<WorkoutPost> _toPosts(QuerySnapshot<Map<String, dynamic>> q) => [
    for (final d in q.docs) WorkoutPost.fromJson(d.id, d.data()),
  ];

  @override
  Stream<List<WorkoutPost>> feed(String uid, {int limit = 50}) => _posts
      .where('audience', arrayContains: uid)
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map(_toPosts)
      .handleError((Object e) => debugPrint('[Community] feed failed: $e'));

  @override
  Stream<List<WorkoutPost>> postsBy(String authorUid, String viewerUid) =>
      _posts
          .where('audience', arrayContains: viewerUid)
          .where('authorUid', isEqualTo: authorUid)
          .snapshots()
          .map((q) => _toPosts(q)..sort((a, b) => b.createdAt.compareTo(a.createdAt)))
          .handleError(
            (Object e) => debugPrint('[Community] postsBy failed: $e'),
          );

  @override
  Future<List<WorkoutPost>> postsSince(String uid, DateTime since) async {
    final q = await _posts
        .where('audience', arrayContains: uid)
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
        .orderBy('createdAt', descending: true)
        .get();
    return _toPosts(q);
  }

  @override
  Stream<Set<String>> kudos(String postId) => _posts
      .doc(postId)
      .collection('kudos')
      .snapshots()
      .map((q) => {for (final d in q.docs) d.id});

  @override
  Stream<Map<String, String>> kudosGivers(String postId) => _posts
      .doc(postId)
      .collection('kudos')
      .snapshots()
      .map(
        (q) => {
          for (final d in q.docs)
            d.id: () {
              final name = d.data()['displayName'] as String? ?? '';
              final handle = d.data()['handle'] as String? ?? '';
              return name.isNotEmpty
                  ? name
                  : (handle.isNotEmpty ? '@$handle' : '');
            }(),
        },
      );

  @override
  Future<void> setKudos(
    WorkoutPost post,
    CommunityProfile me, {
    required bool on,
  }) async {
    final ref = _posts.doc(post.id).collection('kudos').doc(me.uid);
    if (!on) return ref.delete();
    // The name is stored with the kudos so everyone who can see the post can
    // see who gave it, friends of theirs or not.
    await ref.set({
      'at': FieldValue.serverTimestamp(),
      'handle': me.handle,
      'displayName': me.displayName,
    });
    await _notify(post.authorUid, me, InboxType.kudos, postId: post.id);
  }

  @override
  Stream<List<PostComment>> comments(String postId) => _posts
      .doc(postId)
      .collection('comments')
      .orderBy('createdAt')
      .snapshots()
      .map(
        (q) => [for (final d in q.docs) PostComment.fromJson(d.id, d.data())],
      );

  @override
  Future<void> addComment(
    WorkoutPost post,
    CommunityProfile me,
    String text,
  ) async {
    await _posts.doc(post.id).collection('comments').add({
      'authorUid': me.uid,
      'authorHandle': me.handle,
      'text': text.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    await _notify(
      post.authorUid,
      me,
      InboxType.comment,
      postId: post.id,
      text: text.trim(),
    );
  }

  @override
  Future<void> deleteComment(String postId, String commentId) =>
      _posts.doc(postId).collection('comments').doc(commentId).delete();

  @override
  Stream<List<InboxItem>> inbox(String uid) => _inboxOf(uid)
      .orderBy('createdAt', descending: true)
      .limit(100)
      .snapshots()
      .map((q) => [for (final d in q.docs) InboxItem.fromJson(d.id, d.data())]);

  @override
  Stream<int> unreadCount(String uid) {
    // Shown on Home, so it must never throw while building: without
    // Firebase (tests, or a failed start) the badge simply stays empty.
    try {
      return _inboxOf(uid)
          .where('read', isEqualTo: false)
          .snapshots()
          .map((q) => q.size)
          .handleError(
            (Object e) => debugPrint('[Community] inbox failed: $e'),
          );
    } catch (e) {
      debugPrint('[Community] inbox unavailable: $e');
      return Stream.value(0);
    }
  }

  @override
  Future<void> markRead(String uid, String itemId) =>
      _inboxOf(uid).doc(itemId).update({'read': true});

  @override
  Future<void> markAllRead(String uid) async {
    final q = await _inboxOf(uid).where('read', isEqualTo: false).get();
    final batch = _db.batch();
    for (final d in q.docs) {
      batch.update(d.reference, {'read': true});
    }
    await batch.commit();
  }

  @override
  Stream<List<Challenge>> challenges(String uid) => _challenges
      .where('members', arrayContains: uid)
      .snapshots()
      .map(
        (q) => [for (final d in q.docs) Challenge.fromJson(d.id, d.data())]
          ..sort((a, b) => b.end.compareTo(a.end)),
      )
      .handleError(
        (Object e) => debugPrint('[Community] challenges failed: $e'),
      );

  @override
  Future<String?> createChallenge(
    Challenge challenge,
    CommunityProfile me,
  ) async {
    try {
      await _challenges.add(challenge.toJson());
      for (final m in challenge.members) {
        await _notify(m, me, InboxType.challenge, text: challenge.title);
      }
      return null;
    } catch (e) {
      debugPrint('[Community] createChallenge failed: $e');
      return "Couldn't create the challenge.";
    }
  }

  @override
  Future<void> leaveChallenge(Challenge challenge, String uid) =>
      _challenges.doc(challenge.id).update({
        'members': FieldValue.arrayRemove([uid]),
      });

  @override
  Future<void> recordWorkout(String uid, DateTime when, int sets) async {
    try {
      final q = await _challenges.where('members', arrayContains: uid).get();
      for (final d in q.docs) {
        final c = Challenge.fromJson(d.id, d.data());
        if (!c.activeOn(when)) continue;
        final add = c.metric == ChallengeMetric.workouts ? 1 : sets;
        await d.reference.update({
          'progress.$uid': FieldValue.increment(add),
        });
      }
    } catch (e) {
      debugPrint('[Community] recordWorkout failed: $e');
    }
  }

  /// Deletes [refs] in batches, as one batch holds at most 500 writes.
  Future<void> _deleteAll(
    Iterable<DocumentReference<Map<String, dynamic>>> refs,
  ) async {
    final list = refs.toList();
    for (var i = 0; i < list.length; i += 400) {
      final batch = _db.batch();
      for (final ref in list.skip(i).take(400)) {
        batch.delete(ref);
      }
      await batch.commit();
    }
  }

  /// Runs [step], logging instead of throwing: for clean-up that must not
  /// stop an account deletion.
  Future<void> _bestEffort(String what, Future<void> Function() step) async {
    try {
      await step();
    } catch (e) {
      debugPrint('[Community] delete account: $what failed: $e');
    }
  }

  @override
  Future<void> deleteAccountData(String uid) async {
    // Kudos and comments on friends' posts, while the posts can still be
    // read (they are found through this account's friendships).
    await _bestEffort('kudos and comments', () async {
      final visible = await _posts.where('audience', arrayContains: uid).get();
      for (final post in visible.docs) {
        if (post.data()['authorUid'] == uid) continue;
        final mine = await post.reference
            .collection('comments')
            .where('authorUid', isEqualTo: uid)
            .get();
        await _deleteAll([
          post.reference.collection('kudos').doc(uid),
          for (final c in mine.docs) c.reference,
        ]);
      }
    });

    // Own posts, with everything stored under them.
    final posts = await _posts.where('authorUid', isEqualTo: uid).get();
    for (final post in posts.docs) {
      for (final sub in ['photos', 'kudos', 'comments']) {
        final docs = await post.reference.collection(sub).get();
        await _deleteAll([for (final d in docs.docs) d.reference]);
      }
      await post.reference.delete();
    }

    // Friendships, on both sides.
    final friends = await friendUids(uid);
    await _deleteAll([
      for (final f in friends) ...[
        _friendsOf(uid).doc(f),
        _friendsOf(f).doc(uid),
      ],
    ]);

    await _bestEffort('friend requests', () async {
      final sent = await _requests.where('fromUid', isEqualTo: uid).get();
      final received = await _requests.where('toUid', isEqualTo: uid).get();
      await _deleteAll([
        for (final d in [...sent.docs, ...received.docs]) d.reference,
      ]);
    });
    await _bestEffort('blocks', () async {
      final q = await _blocksOf(uid).get();
      await _deleteAll([for (final d in q.docs) d.reference]);
    });
    await _bestEffort('inbox', () async {
      final q = await _inboxOf(uid).get();
      await _deleteAll([for (final d in q.docs) d.reference]);
    });
    await _bestEffort('challenges', () async {
      final q = await _challenges.where('members', arrayContains: uid).get();
      for (final d in q.docs) {
        await d.reference.update({
          'members': FieldValue.arrayRemove([uid]),
          'progress.$uid': FieldValue.delete(),
        });
      }
    });

    // Username and public profile last, so friends see the name until the
    // posts are gone.
    final profile = await _db.collection('publicProfiles').doc(uid).get();
    final handle = profile.data()?['handle'] as String?;
    await _deleteAll([
      if (handle != null && handle.isNotEmpty)
        _db.collection('handles').doc(handle),
      profile.reference,
    ]);
    _invalidateProfile(uid);
  }
}

/// The error [CommunityService.claimHandle] returns for a taken username,
/// so a screen can tell it apart from a connection problem.
const String kHandleTaken = 'That username is taken.';

class _Taken implements Exception {
  const _Taken();
}

/// The service screens use. Tests swap in a fake.
CommunityService communityService = FirestoreCommunityService();
