import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../community/community_models.dart';
import '../../community/community_service.dart';
import '../../community/share_builder.dart';
import '../../core/format.dart';
import '../../data/training_stats.dart';
import '../../models/models.dart';
import '../../composition/composition_visuals.dart';
import '../../photos/progress_photo.dart';
import '../../photos/progress_photo_store.dart';
import '../../scan/camera_permission.dart';
import '../photos/progress_photos_screen.dart';
import '../../state/profile_scope.dart';
import '../../state/session_scope.dart';
import 'community_avatar.dart';
import 'share_content.dart';
import '../../core/snack_bar_timing.dart';

/// The top of the feed: "Share your fitness progress", a text bar and a
/// Share button. Tapping the bar opens the card to choose what to share,
/// with a preview of exactly what friends will see.
///
/// Defaults (which items start ticked) are an app design choice.
class ShareComposer extends StatefulWidget {
  const ShareComposer({super.key, required this.me, this.picker});

  final CommunityProfile me;

  /// For tests. The composer uses the real camera and gallery by default.
  final ImagePicker? picker;

  @override
  State<ShareComposer> createState() => _ShareComposerState();
}

class _ScanPhoto {
  const _ScanPhoto({
    required this.id,
    required this.takenAt,
    required this.pose,
    required this.bytes,
    this.record,
  });

  final String id;
  final DateTime takenAt;
  final PhotoPose pose;
  final Uint8List bytes;

  /// The scan the photo came from; null for a photo taken or chosen now.
  final CompositionRecord? record;
}

class _PickedPhoto {
  const _PickedPhoto({
    required this.id,
    required this.takenAt,
    required this.pose,
    required this.bytes,
    this.record,
  });

  final String id;
  final DateTime takenAt;
  final PhotoPose pose;
  final Uint8List? bytes;
  final CompositionRecord? record;
}

class _ShareComposerState extends State<ShareComposer> {
  final TextEditingController _caption = TextEditingController();
  final FocusNode _focus = FocusNode();

  bool _open = false;
  bool _sharing = false;
  ShareTopic _topic = ShareTopic.overall;
  ProgressRange _range = ProgressRange.month1;
  String? _exerciseId;
  Set<ShareItem> _items = _defaults(ShareTopic.overall);

  static Set<ShareItem> _defaults(ShareTopic t) => switch (t) {
    ShareTopic.overall => {
      ShareItem.workouts,
      ShareItem.volume,
      ShareItem.volumeChart,
    },
    ShareTopic.exercise => {
      ShareItem.bestWeight,
      ShareItem.bestSet,
      ShareItem.weightChart,
    },
    ShareTopic.body => {ShareItem.bodyFat},
    ShareTopic.bodyWeight => {ShareItem.weight, ShareItem.bodyWeightChart},
    ShareTopic.muscles => {ShareItem.muscleCoverage},
    ShareTopic.photos => <ShareItem>{},
  };

  // ---- progress photos (the Photos topic) ----
  ProgressPhotoStore? _photoStore;
  List<ProgressPhoto>? _myPhotos;
  List<_ScanPhoto>? _scanPhotos;
  final Map<String, Future<Uint8List?>> _thumbs = {};

  /// Photos taken or chosen from the gallery for this post. They are used
  /// for the post only and are not saved on the phone.
  final List<_ScanPhoto> _added = [];

  /// Photos are shrunk as soon as they are ticked and the friends list is
  /// read when the card opens, so Share has little left to wait for.
  final SharePhotoPrep _prep = SharePhotoPrep();
  Future<List<String>>? _friendsAhead;
  late final ImagePicker _picker = widget.picker ?? ImagePicker();

  /// Picked photo ids, and their pictures once read.
  final List<String> _pickedIds = [];
  final Map<String, Uint8List> _pickedBytes = {};

  Future<void> _loadPhotos() async {
    if (_myPhotos != null && _scanPhotos != null) return;
    try {
      final store = _photoStore ??= progressPhotoStoreOf(context);
      final profile = ProfileScope.of(context).profile;
      final photos = await store.load();
      final scanPhotos = <_ScanPhoto>[];
      if (profile != null) {
        final visualsStore = CompositionVisualStore();
        for (final record in profile.compositionLog) {
          try {
            final visuals = await visualsStore.load(record.id);
            if (visuals.frontPhoto case final bytes?) {
              scanPhotos.add(
                _ScanPhoto(
                  id: 'scan-${record.id}-front',
                  takenAt: record.takenAt,
                  pose: PhotoPose.front,
                  bytes: bytes,
                  record: record,
                ),
              );
            }
            if (visuals.sidePhoto case final bytes?) {
              scanPhotos.add(
                _ScanPhoto(
                  id: 'scan-${record.id}-side',
                  takenAt: record.takenAt,
                  pose: PhotoPose.side,
                  bytes: bytes,
                  record: record,
                ),
              );
            }
          } catch (_) {
            // A missing scan photo does not prevent other photos being shared.
          }
        }
      }
      if (mounted) {
        setState(() {
          _myPhotos = photos;
          _scanPhotos = scanPhotos;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _myPhotos = const [];
          _scanPhotos = const [];
        });
      }
    }
  }

  Future<Uint8List?> _thumb(String id) =>
      _thumbs.putIfAbsent(id, () => _photoStore!.bytes(id));

  Future<void> _togglePhoto(ProgressPhoto photo) async {
    await _togglePick(photo.id);
  }

  Future<void> _toggleScanPhoto(_ScanPhoto photo) async {
    await _togglePick(photo.id, bytes: photo.bytes);
  }

  Future<void> _togglePick(String id, {Uint8List? bytes}) async {
    if (_pickedIds.contains(id)) {
      setState(() {
        _pickedIds.remove(id);
        _pickedBytes.remove(id);
      });
      return;
    }
    if (_pickedIds.length >= ProgressShare.maxPhotos) return;
    final image = bytes ?? await _thumb(id);
    if (image == null || !mounted) return;
    setState(() {
      _pickedIds.add(id);
      _pickedBytes[id] = image;
    });
    _prep.prepare(id, image);
  }

  /// The picked photos, oldest first: the order the post shows them in.
  List<_PickedPhoto> get _pickedPhotos {
    final progressById = {
      for (final p in _myPhotos ?? const <ProgressPhoto>[]) p.id: p,
    };
    final scansById = {
      for (final p in [..._added, ...?_scanPhotos]) p.id: p,
    };
    return [
      for (final id in _pickedIds)
        if (progressById[id] case final photo?)
          _PickedPhoto(
            id: id,
            takenAt: photo.takenAt,
            pose: photo.pose,
            bytes: _pickedBytes[id],
          )
        else if (scansById[id] case final photo?)
          _PickedPhoto(
            id: id,
            takenAt: photo.takenAt,
            pose: photo.pose,
            bytes: _pickedBytes[id],
            record: photo.record,
          ),
    ]..sort((a, b) => a.takenAt.compareTo(b.takenAt));
  }

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (_focus.hasFocus && !_open) _openCard();
    });
  }

  /// Opens the card and starts reading the photos that can be attached.
  void _openCard() {
    setState(() => _open = true);
    _loadPhotos();
    _friendsAhead ??= communityService.friendUids(widget.me.uid)..ignore();
  }

  @override
  void dispose() {
    _caption.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _close() {
    _focus.unfocus();
    setState(() {
      _open = false;
      _caption.clear();
      _topic = ShareTopic.overall;
      _items = _defaults(_topic);
      _pickedIds.clear();
      _pickedBytes.clear();
      _added.clear();
      _friendsAhead = null; // read again next time it opens
    });
  }

  Future<void> _share(ProgressShare share) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sharing = true);
    String? error;
    try {
      // Photos are shrunk for Community; the full-size ones stay here.
      // Usually both the shrinking and the friends list are done already.
      final clock = Stopwatch()..start();
      final picked = _pickedPhotos;
      if (picked.any((p) => p.bytes == null)) throw StateError('photo');
      final shrinking = _prep.collect([
        for (final p in picked) (id: p.id, jpeg: p.bytes!),
      ]);
      Future<List<String>> friendsRead() async {
        final ahead = _friendsAhead;
        if (ahead != null) {
          try {
            return await ahead;
          } catch (_) {
            // Fall through to a fresh read.
          }
        }
        return communityService.friendUids(widget.me.uid);
      }

      final friendsFuture = friendsRead();
      final photos = await shrinking;
      if (photos == null) {
        friendsFuture.ignore();
        throw StateError('photo');
      }
      final friends = await friendsFuture;
      final readAt = clock.elapsedMilliseconds;
      error = await communityService.share(
        buildSharePost(
          share: share,
          caption: _caption.text,
          author: widget.me,
          friendUids: friends,
        ),
        photos: photos,
      );
      debugPrint(
        '[Share] prepare ${readAt}ms, upload '
        '${clock.elapsedMilliseconds - readAt}ms, '
        '${photos.map((b) => b.length ~/ 1024).join('+')} KB',
      );
    } catch (_) {
      error = "Couldn't share. Try again.";
    }
    if (!mounted) return;
    setState(() => _sharing = false);
    messenger.showSnackBar(
      SnackBar(
        duration: kSnackBarDuration,
        persist: false,
        content: Text(error ?? 'Shared with your friends.'),
      ),
    );
    if (error == null) _close();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sessions = SessionScope.of(context).completedSessions;
    final scans =
        ProfileScope.of(context).profile?.compositionLog ??
        const <CompositionRecord>[];
    final profile = ProfileScope.of(context).profile;
    final exercises = exercisesPerformed(sessions);
    final exerciseId = exercises.any((e) => e.exerciseId == _exerciseId)
        ? _exerciseId
        : (exercises.isEmpty ? null : exercises.first.exerciseId);

    final share = buildShare(
      topic: _topic,
      items: _items,
      range: _range,
      sessions: sessions,
      scans: scans,
      weightLog: profile?.weightLog ?? const [],
      currentBodyWeightKg: profile?.weightKg,
      muscleWeekStart: startOfWeek(DateTime.now()),
      exerciseId: exerciseId,
      photoInfos: [
        for (final p in _pickedPhotos)
          SharedPhotoInfo(
            takenAt: p.takenAt,
            pose: p.pose.name,
            bodyFatPct: p.record?.bodyFatPct,
            bodyFatLow: p.record?.bodyFatLow,
            bodyFatHigh: p.record?.bodyFatHigh,
            fatFreeMassKg: p.record?.fatFreeMassKg,
          ),
      ],
    );
    final name = widget.me.displayName.isEmpty
        ? widget.me.handle
        : widget.me.displayName;

    return Card(
      key: const ValueKey('share-composer'),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Share your fitness progress',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  CommunityAvatar(
                    uid: widget.me.uid,
                    fallbackName: name,
                    radius: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('share-text'),
                      controller: _caption,
                      focusNode: _focus,
                      minLines: 1,
                      maxLines: _open ? 4 : 1,
                      maxLength: WorkoutPost.maxCaption,
                      onTap: () {
                        if (!_open) _openCard();
                      },
                      decoration: InputDecoration(
                        hintText: _open
                            ? 'Say something about it (optional)'
                            : "What's your progress today?",
                        counterText: '',
                        isDense: true,
                        border: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(24)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const ValueKey('share-button'),
                    // The app theme makes filled buttons full width
                    // (Size.fromHeight). Inside this Row that is an
                    // infinite width, which blanked the whole feed, so this
                    // one button sizes to its text.
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(64, 48),
                    ),
                    onPressed: _sharing
                        ? null
                        : !_open
                        ? _openCard
                        : share.isEmpty
                        ? null
                        : () => _share(share),
                    child: const Text('Share'),
                  ),
                ],
              ),
              if (_open) ...[
                const SizedBox(height: 12),
                _options(theme, exercises, exerciseId),
                const SizedBox(height: 12),
                Text('Preview', style: theme.textTheme.titleSmall),
                const SizedBox(height: 6),
                if (share.isEmpty)
                  Text(
                    'Nothing to show for this choice yet. Pick something '
                    'else, or a longer period.',
                    key: const ValueKey('share-empty'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                else
                  PostContentBox(
                    key: const ValueKey('share-preview'),
                    child: ShareContentView(
                      share: share,
                      photoBytes: [
                        for (final p in _pickedPhotos)
                          if (p.bytes != null) p.bytes!,
                      ],
                    ),
                  ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    key: const ValueKey('share-cancel'),
                    onPressed: _sharing ? null : _close,
                    child: const Text('Cancel'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _options(
    ThemeData theme,
    List<ExerciseSummary> exercises,
    String? exerciseId,
  ) {
    final items = [
      for (final i in ShareItem.values)
        if (i.topics.contains(_topic)) i,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('What to share', style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final t in ShareTopic.values)
              ChoiceChip(
                key: ValueKey('share-topic-${t.name}'),
                label: Text(t.label),
                selected: t == _topic,
                onSelected: (_) {
                  setState(() {
                    _topic = t;
                    _items = _defaults(t);
                  });
                  _loadPhotos();
                },
              ),
          ],
        ),
        if (_topic == ShareTopic.exercise) ...[
          const SizedBox(height: 10),
          if (exercises.isEmpty)
            const Text('No exercises logged yet.')
          else
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Exercise',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  key: const ValueKey('share-exercise'),
                  value: exerciseId,
                  isExpanded: true,
                  isDense: true,
                  items: [
                    for (final e in exercises)
                      DropdownMenuItem(
                        value: e.exerciseId,
                        child: Text(e.name),
                      ),
                  ],
                  onChanged: (id) => setState(() => _exerciseId = id),
                ),
              ),
            ),
        ],
        if (_topic != ShareTopic.photos) ...[
          const SizedBox(height: 10),
          Text('Period', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              for (final r in ProgressRange.values)
                ChoiceChip(
                  key: ValueKey('share-range-${r.name}'),
                  label: Text(r.label),
                  selected: r == _range,
                  onSelected: (_) => setState(() => _range = r),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text('Include', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final i in items)
                FilterChip(
                  key: ValueKey('share-item-${i.name}'),
                  label: Text(i.label),
                  selected: _items.contains(i),
                  onSelected: (on) => setState(() {
                    _items = {..._items};
                    if (on) {
                      _items.add(i);
                    } else {
                      _items.remove(i);
                    }
                  }),
                ),
            ],
          ),
        ],
        if (_topic == ShareTopic.body) ...[
          const SizedBox(height: 8),
          Text(
            'Only what you tick is shared, and only with friends. Body fat plus '
            'fat-free mass reveals your weight. Scan outlines are never shared.',
            key: const ValueKey('share-body-note'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 14),
        _photoPicker(theme),
      ],
    );
  }

  Future<void> _addFrom(ImageSource source) async {
    final messenger = ScaffoldMessenger.of(context);
    void say(String text) => messenger.showSnackBar(
      SnackBar(
        duration: kSnackBarDuration,
        persist: false,
        content: Text(text),
      ),
    );
    if (source == ImageSource.camera) {
      final access = await ensureCameraAccess();
      if (access != CameraAccess.granted) {
        if (access == CameraAccess.permanentlyDenied) {
          say('Camera access is off. Turn it on in Settings.');
        }
        return;
      }
    }
    XFile? file;
    try {
      file = await _picker.pickImage(
        source: source,
        maxWidth: kPhotoMaxSide,
        maxHeight: kPhotoMaxSide,
        imageQuality: kPhotoQuality,
      );
    } catch (_) {
      say(
        source == ImageSource.camera
            ? "Couldn't open the camera."
            : "Couldn't open your gallery.",
      );
      return;
    }
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    final photo = _ScanPhoto(
      id: 'added-${_added.length}-${DateTime.now().microsecondsSinceEpoch}',
      takenAt: DateTime.now(),
      pose: PhotoPose.other,
      bytes: bytes,
    );
    setState(() {
      _added.add(photo);
      // A full post swaps out the oldest pick, so the new photo is used.
      if (_pickedIds.length >= ProgressShare.maxPhotos) {
        final dropped = _pickedIds.removeAt(0);
        _pickedBytes.remove(dropped);
      }
      _pickedIds.add(photo.id);
      _pickedBytes[photo.id] = bytes;
    });
    _prep.prepare(photo.id, bytes);
  }

  /// Photos to attach to the post, up to two: take one, choose one, or pick
  /// from the user's scan photos (which keep their date, view and scan
  /// result) and progress photos. Works with every topic, so a workout or
  /// scan post can carry photos.
  Widget _photoPicker(ThemeData theme) {
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final photos = _myPhotos;
    final scanPhotos = _scanPhotos;
    final loading = photos == null || scanPhotos == null;
    // Newest first: photos just taken, then the scan photos.
    final scanLike = [..._added.reversed, ...?scanPhotos];
    final count = (photos?.length ?? 0) + scanLike.length;

    return Column(
      key: const ValueKey('share-attach'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Attach photos (optional)', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          'Up to ${ProgressShare.maxPhotos}. Take a photo, choose one, or '
          'pick from your scans. Scan photos keep their date, view and '
          'body-composition result.',
          style: muted,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('attach-camera'),
              onPressed: _sharing ? null : () => _addFrom(ImageSource.camera),
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Take photo'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('attach-gallery'),
              onPressed: _sharing ? null : () => _addFrom(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Choose photo'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (loading && _added.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (count == 0 && !loading)
          Text(
            'No scan or progress photos are available yet.',
            key: const ValueKey('share-no-photos'),
            style: muted,
          )
        else
          SizedBox(
            height: 120,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: count,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                if (i < scanLike.length) {
                  final p = scanLike[i];
                  final isAdded = p.record == null;
                  return SizedBox(
                    width: 90,
                    child: PhotoTile(
                      key: ValueKey('share-photo-${p.id}'),
                      bytes: Future.value(p.bytes),
                      label: isAdded
                          ? 'New photo'
                          : '${formatShortDate(p.takenAt)} · ${p.pose.label}',
                      selected: _pickedIds.contains(p.id),
                      onTap: () => _toggleScanPhoto(p),
                    ),
                  );
                }
                final p = photos![i - scanLike.length];
                return SizedBox(
                  width: 90,
                  child: PhotoTile(
                    key: ValueKey('share-photo-${p.id}'),
                    bytes: _thumb(p.id),
                    label: formatShortDate(p.takenAt),
                    selected: _pickedIds.contains(p.id),
                    onTap: () => _togglePhoto(p),
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 8),
        Text(
          'Only friends see shared photos, at a smaller size. They can still '
          'screenshot them, so share only what you are comfortable with. '
          'Deleting the post deletes its photos.',
          key: const ValueKey('share-photos-note'),
          style: muted,
        ),
      ],
    );
  }
}
