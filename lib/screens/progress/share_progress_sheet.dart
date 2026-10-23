import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../auth/auth_scope.dart';
import '../../community/community_models.dart';
import '../../community/community_service.dart';
import '../../community/share_builder.dart';
import '../../composition/composition_visuals.dart';
import '../../core/format.dart';
import '../../core/snack_bar_timing.dart';
import '../../data/training_stats.dart';
import '../../models/models.dart';
import '../../photos/progress_photo.dart';
import '../../photos/progress_photo_store.dart';
import '../../scan/camera_permission.dart';
import '../community/share_to_friends.dart';
import '../community/share_content.dart';
import '../photos/progress_photos_screen.dart'
    show PhotoTile, kPhotoMaxSide, kPhotoQuality, progressPhotoStoreOf;

/// Shares progress from the active Progress section, with optional scan or
/// selfie photos. The section's topic is preselected, and the person can
/// switch to another progress type, choose what to include, and preview the
/// post before sharing. It uses the Community pipeline and friends-only
/// audience. A selfie is only used for the post; it is not saved to the phone.
Future<void> showShareProgressSheet(
  BuildContext context, {
  required List<CompositionRecord> scans,
  List<WorkoutSession> sessions = const [],
  List<BodyWeightEntry> weightLog = const [],
  double? currentBodyWeightKg,
  ProgressRange range = ProgressRange.allTime,
  DateTime? muscleWeekStart,
  ShareTopic initialTopic = ShareTopic.photos,
  CompositionVisualStore? visualStore,
  ProgressPhotoStore? photoStore,
  ImagePicker? picker,
}) async {
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width),
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.9,
      child: ShareProgressSheet(
        scans: scans,
        sessions: sessions,
        weightLog: weightLog,
        currentBodyWeightKg: currentBodyWeightKg,
        range: range,
        muscleWeekStart: muscleWeekStart,
        initialTopic: initialTopic,
        visualStore: visualStore ?? CompositionVisualStore(),
        photoStore: photoStore ?? progressPhotoStoreOf(context),
        picker: picker ?? ImagePicker(),
      ),
    ),
  );
}

class _Candidate {
  const _Candidate({
    required this.id,
    required this.takenAt,
    required this.pose,
    required this.bytes,
    this.record,
    this.includeLatestScanInfo = false,
  });

  final String id;
  final DateTime takenAt;
  final PhotoPose pose;
  final Uint8List bytes;

  /// The scan this photo came from. Null for a selfie.
  final CompositionRecord? record;
  final bool includeLatestScanInfo;
}

class ShareProgressSheet extends StatefulWidget {
  const ShareProgressSheet({
    super.key,
    this.me,
    required this.scans,
    this.sessions = const [],
    this.weightLog = const [],
    this.currentBodyWeightKg,
    this.range = ProgressRange.allTime,
    this.muscleWeekStart,
    this.initialTopic = ShareTopic.photos,
    required this.visualStore,
    required this.photoStore,
    required this.picker,
  });

  /// Optional for tests or an already-resolved profile. Production resolves
  /// the profile only after the user has chosen photos and tapped Share.
  final CommunityProfile? me;
  final List<CompositionRecord> scans;
  final List<WorkoutSession> sessions;
  final List<BodyWeightEntry> weightLog;
  final double? currentBodyWeightKg;
  final ProgressRange range;
  final DateTime? muscleWeekStart;
  final ShareTopic initialTopic;
  final CompositionVisualStore visualStore;
  final ProgressPhotoStore photoStore;
  final ImagePicker picker;

  /// How many recent scans are offered. Older ones stay in scan history.
  static const int recentScans = 4;

  @override
  State<ShareProgressSheet> createState() => _ShareProgressSheetState();
}

class _ShareProgressSheetState extends State<ShareProgressSheet> {
  static const String _selfieId = 'selfie';

  final TextEditingController _caption = TextEditingController();

  late ShareTopic _topic = widget.initialTopic;
  late ProgressRange _range = widget.range;
  late Set<ShareItem> _items = _defaults(_topic);
  List<_Candidate>? _scanPhotos;
  List<_Candidate>? _progressPhotos;
  _Candidate? _selfie;
  final List<String> _picked = [];
  bool _initialPhotosSelected = false;
  bool _includeInfo = true;
  bool _sharing = false;

  static Set<ShareItem> _defaults(ShareTopic topic) => switch (topic) {
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

  /// Photos are shrunk as soon as they are ticked, and the Community profile
  /// and friends list are read while the person is still choosing, so Share
  /// has little left to wait for.
  final SharePhotoPrep _prep = SharePhotoPrep();
  Future<CommunityProfile?>? _profileAhead;
  Future<List<String>>? _friendsAhead;
  String? _aheadUid;

  void _prepareShrinks() {
    for (final c in _pickedPhotos) {
      _prep.prepare(c.id, c.bytes);
    }
  }

  void _readAhead() {
    final signedIn = context
        .getInheritedWidgetOfExactType<AuthScope>()
        ?.notifier;
    final uid =
        widget.me?.uid ??
        (signedIn == null || signedIn.isGuest ? null : signedIn.user?.uid);
    if (uid == null) return;
    _aheadUid = uid;
    _profileAhead = widget.me != null
        ? Future.value(widget.me)
        : communityService.profileOf(uid).then<CommunityProfile?>((p) => p);
    _friendsAhead = communityService.friendUids(uid);
    // A failure here is dealt with when Share is tapped, not now.
    _profileAhead!.ignore();
    _friendsAhead!.ignore();
  }

  CompositionRecord? get _latestScan {
    if (widget.scans.isEmpty) return null;
    return ([
      ...widget.scans,
    ]..sort((a, b) => a.takenAt.compareTo(b.takenAt))).last;
  }

  @override
  void initState() {
    super.initState();
    _loadScanPhotos();
    _loadProgressPhotos();
    // After the first frame, so the sheet's context can see the sign-in.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _readAhead();
    });
  }

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _loadScanPhotos() async {
    final records =
        ([...widget.scans]..sort((a, b) => b.takenAt.compareTo(a.takenAt)))
            .take(ShareProgressSheet.recentScans);
    final found = <_Candidate>[];
    for (final record in records) {
      try {
        final visuals = await widget.visualStore.load(record.id);
        if (visuals.frontPhoto case final bytes?) {
          found.add(
            _Candidate(
              id: 'scan-${record.id}-front',
              takenAt: record.takenAt,
              pose: PhotoPose.front,
              bytes: bytes,
              record: record,
            ),
          );
        }
        if (visuals.sidePhoto case final bytes?) {
          found.add(
            _Candidate(
              id: 'scan-${record.id}-side',
              takenAt: record.takenAt,
              pose: PhotoPose.side,
              bytes: bytes,
              record: record,
            ),
          );
        }
      } catch (_) {
        // A scan whose photos cannot be read is simply not offered.
      }
    }
    if (!mounted) return;
    setState(() {
      _scanPhotos = found;
    });
    _selectInitialPhotos();
    _prepareShrinks();
  }

  Future<void> _loadProgressPhotos() async {
    try {
      final photos = await widget.photoStore.load();
      final found = <_Candidate>[];
      for (final photo in photos) {
        final bytes = await widget.photoStore.bytes(photo.id);
        if (bytes == null) continue;
        found.add(
          _Candidate(
            id: 'progress-${photo.id}',
            takenAt: photo.takenAt,
            pose: photo.pose,
            bytes: bytes,
          ),
        );
      }
      if (!mounted) return;
      setState(() => _progressPhotos = found);
    } catch (_) {
      if (!mounted) return;
      setState(() => _progressPhotos = []);
    }
    _selectInitialPhotos();
    _prepareShrinks();
  }

  void _selectInitialPhotos() {
    if (_initialPhotosSelected ||
        _topic != ShareTopic.photos ||
        _scanPhotos == null ||
        _progressPhotos == null) {
      return;
    }
    _initialPhotosSelected = true;
    if (!mounted) return;
    setState(() {
      if (_scanPhotos!.isNotEmpty) {
        _selectNewestScanPhotos(_scanPhotos!);
      } else {
        _selectNewestProgressPhotos(_progressPhotos!);
      }
    });
  }

  void _selectNewestScanPhotos(List<_Candidate> photos) {
    if (photos.isEmpty || _picked.isNotEmpty) return;
    final newest = photos.first.record?.id;
    for (final c in photos) {
      if (c.record?.id == newest && _picked.length < ProgressShare.maxPhotos) {
        _picked.add(c.id);
      }
    }
  }

  void _selectNewestProgressPhotos(List<_Candidate> photos) {
    if (photos.isEmpty || _picked.isNotEmpty) return;
    final newest = photos.first.takenAt;
    for (final c in photos) {
      if (c.takenAt == newest && _picked.length < ProgressShare.maxPhotos) {
        _picked.add(c.id);
      }
    }
  }

  List<_Candidate> get _all => [?_selfie, ...?_scanPhotos, ...?_progressPhotos];

  /// Picked photos, oldest first: the order the post shows them in.
  List<_Candidate> get _pickedPhotos {
    final byId = {for (final c in _all) c.id: c};
    return [for (final id in _picked) ?byId[id]]
      ..sort((a, b) => a.takenAt.compareTo(b.takenAt));
  }

  void _toggle(_Candidate c) {
    setState(() {
      if (_picked.contains(c.id)) {
        _picked.remove(c.id);
      } else {
        if (_picked.length >= ProgressShare.maxPhotos) _picked.removeAt(0);
        _picked.add(c.id);
      }
    });
    _prepareShrinks();
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: kSnackBarDuration,
        persist: false,
        content: Text(text),
      ),
    );
  }

  Future<bool> _cameraAllowed() async {
    final access = await ensureCameraAccess();
    if (access == CameraAccess.granted) return true;
    if (mounted && access == CameraAccess.permanentlyDenied) {
      _message('Camera access is off. Turn it on in Settings.');
    }
    return false;
  }

  Future<void> _takeSelfie() async {
    if (!await _cameraAllowed() || !mounted) return;
    XFile? file;
    try {
      file = await widget.picker.pickImage(
        source: ImageSource.camera,
        maxWidth: kPhotoMaxSide,
        maxHeight: kPhotoMaxSide,
        imageQuality: kPhotoQuality,
        preferredCameraDevice: CameraDevice.front,
      );
    } catch (_) {
      if (mounted) _message("Couldn't open the camera.");
      return;
    }
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    _prep.forget(_selfieId); // a retake replaces the old selfie
    setState(() {
      _picked.remove(_selfieId);
      _selfie = _Candidate(
        id: _selfieId,
        takenAt: DateTime.now(),
        pose: PhotoPose.front,
        bytes: bytes,
        includeLatestScanInfo: true,
      );
      if (_picked.length >= ProgressShare.maxPhotos) _picked.removeAt(0);
      _picked.add(_selfieId);
    });
    _prepareShrinks();
  }

  /// The scan result that goes with [c], or null when the person switched
  /// the scan info off. A scan photo carries its own scan's result; a selfie
  /// carries the latest scan's.
  CompositionRecord? _recordFor(_Candidate c) => _includeInfo
      ? (c.record ?? (c.includeLatestScanInfo ? _latestScan : null))
      : null;

  SharedPhotoInfo _infoFor(_Candidate c) {
    final record = _recordFor(c);
    return SharedPhotoInfo(
      takenAt: c.takenAt,
      pose: c.pose.name,
      bodyFatPct: record?.bodyFatPct,
      bodyFatLow: record?.bodyFatLow,
      bodyFatHigh: record?.bodyFatHigh,
      fatFreeMassKg: record?.fatFreeMassKg,
    );
  }

  Future<void> _share() async {
    final picked = _pickedPhotos;
    if ((_topic == ShareTopic.photos && picked.isEmpty) || _sharing) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _sharing = true);
    String? error;
    try {
      final clock = Stopwatch()..start();
      // The profile was read while the person was choosing; only when that
      // gave nothing (guest, offline, no username) does this ask again, and
      // say why not.
      var author = widget.me;
      if (author == null) {
        try {
          author = await _profileAhead;
        } catch (_) {
          author = null;
        }
        if (author == null && mounted) {
          author = await communityAuthorFor(context);
        }
      }
      if (author == null || !mounted) {
        if (mounted) setState(() => _sharing = false);
        return;
      }
      final uid = author.uid;
      // Shrinking is usually done already; the friends list too.
      final shrinking = picked.isEmpty
          ? Future<List<Uint8List>?>.value(const [])
          : _prep.collect([for (final p in picked) (id: p.id, jpeg: p.bytes)]);
      Future<List<String>> friendsRead() async {
        final ahead = _aheadUid == uid ? _friendsAhead : null;
        if (ahead != null) {
          try {
            return await ahead;
          } catch (_) {
            // Fall through to a fresh read.
          }
        }
        return communityService.friendUids(uid);
      }

      final friendsFuture = friendsRead();
      final photos = await shrinking;
      if (photos == null) {
        friendsFuture.ignore();
        throw StateError('photo');
      }
      final share = buildShare(
        topic: _topic,
        items: _items,
        range: _range,
        sessions: widget.sessions,
        scans: widget.scans,
        weightLog: widget.weightLog,
        currentBodyWeightKg: widget.currentBodyWeightKg,
        muscleWeekStart: widget.muscleWeekStart,
        photoInfos: [for (final p in picked) _infoFor(p)],
      );
      if (share.isEmpty) {
        friendsFuture.ignore();
        if (mounted) {
          setState(() => _sharing = false);
          _message('There is no progress to share in this section yet.');
        }
        return;
      }
      final friends = await friendsFuture;
      final preparedAt = clock.elapsedMilliseconds;
      error = await communityService.share(
        buildSharePost(
          share: share,
          caption: _caption.text,
          author: author,
          friendUids: friends,
        ),
        photos: photos,
      );
      // Where the time goes: getting ready, then the upload.
      debugPrint(
        '[Share] prepare ${preparedAt}ms, upload '
        '${clock.elapsedMilliseconds - preparedAt}ms, '
        '${photos.map((b) => b.length ~/ 1024).join('+')} KB',
      );
    } catch (_) {
      error = "Couldn't share. Try again.";
    }
    messenger.showSnackBar(
      SnackBar(
        duration: kSnackBarDuration,
        persist: false,
        content: Text(error ?? 'Shared with your friends.'),
      ),
    );
    if (error == null) {
      if (navigator.mounted) navigator.maybePop();
    } else if (mounted) {
      setState(() => _sharing = false);
    }
  }

  String _infoLine(_Candidate c) {
    final r = _recordFor(c);
    final date = formatShortDate(c.takenAt);
    if (r == null) return '$date · ${c.pose.label}';
    return '$date · ${c.pose.label} · body fat '
        '${r.bodyFatPct.toStringAsFixed(1)}% '
        '(${r.bodyFatLow.toStringAsFixed(1)}–${r.bodyFatHigh.toStringAsFixed(1)}%)';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final scanPhotos = _scanPhotos;
    final progressPhotos = _progressPhotos;
    final picked = _pickedPhotos;
    final selfie = _selfie;
    final sharePreview = buildShare(
      topic: _topic,
      items: _items,
      range: _range,
      sessions: widget.sessions,
      scans: widget.scans,
      weightLog: widget.weightLog,
      currentBodyWeightKg: widget.currentBodyWeightKg,
      muscleWeekStart: widget.muscleWeekStart,
      photoInfos: [for (final p in picked) _infoFor(p)],
    );
    final topicItems = [
      for (final item in ShareItem.values)
        if (item.topics.contains(_topic)) item,
    ];

    Widget tile(_Candidate c, {required String label}) => SizedBox(
      width: 96,
      child: PhotoTile(
        key: ValueKey('share-progress-${c.id}'),
        bytes: Future.value(c.bytes),
        label: label,
        selected: _picked.contains(c.id),
        onTap: _sharing ? null : () => _toggle(c),
      ),
    );

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Share your progress', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Choose the progress to share from the section you are viewing. '
              'You can also attach up to ${ProgressShare.maxPhotos} photos.',
              style: muted,
            ),
            const SizedBox(height: 12),
            Text('Progress type', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final topic in [
                  ShareTopic.overall,
                  ShareTopic.muscles,
                  ShareTopic.bodyWeight,
                  ShareTopic.body,
                  ShareTopic.photos,
                ])
                  ChoiceChip(
                    key: ValueKey('share-progress-topic-${topic.name}'),
                    label: Text(topic.label),
                    selected: topic == _topic,
                    onSelected: _sharing
                        ? null
                        : (_) {
                            setState(() {
                              _topic = topic;
                              _items = _defaults(topic);
                              if (topic == ShareTopic.photos) {
                                if (_scanPhotos != null &&
                                    _progressPhotos != null) {
                                  _initialPhotosSelected = true;
                                  if (_scanPhotos!.isNotEmpty) {
                                    _selectNewestScanPhotos(_scanPhotos!);
                                  } else {
                                    _selectNewestProgressPhotos(
                                      _progressPhotos!,
                                    );
                                  }
                                } else {
                                  _initialPhotosSelected = false;
                                }
                              }
                            });
                            _prepareShrinks();
                          },
                  ),
              ],
            ),
            if (_topic != ShareTopic.photos) ...[
              const SizedBox(height: 10),
              Text('Period', style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: [
                  for (final range in ProgressRange.values)
                    ChoiceChip(
                      key: ValueKey('share-progress-range-${range.name}'),
                      label: Text(range.label),
                      selected: range == _range,
                      onSelected: _sharing
                          ? null
                          : (_) => setState(() => _range = range),
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
                  for (final item in topicItems)
                    FilterChip(
                      key: ValueKey('share-progress-item-${item.name}'),
                      label: Text(item.label),
                      selected: _items.contains(item),
                      onSelected: _sharing
                          ? null
                          : (selected) => setState(() {
                              _items = {..._items};
                              if (selected) {
                                _items.add(item);
                              } else {
                                _items.remove(item);
                              }
                            }),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: ShareContentView(
                    share: sharePreview,
                    photoBytes: [for (final p in picked) p.bytes],
                  ),
                ),
              ),
            ],
            if (_topic == ShareTopic.photos && picked.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('Preview', style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: ShareContentView(
                    share: sharePreview,
                    photoBytes: [for (final p in picked) p.bytes],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text('Your scan photos', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            if (scanPhotos == null)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (scanPhotos.isEmpty)
              Text(
                'No scan photos yet. Photos are kept when you choose to '
                'before a body scan. You can still take a selfie.',
                key: const ValueKey('share-progress-no-scan-photos'),
                style: muted,
              )
            else
              SizedBox(
                height: 128,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: scanPhotos.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final c = scanPhotos[i];
                    return tile(
                      c,
                      label: '${formatShortDate(c.takenAt)} · ${c.pose.label}',
                    );
                  },
                ),
              ),
            const SizedBox(height: 12),
            Text('Your progress photos', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            if (progressPhotos == null)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (progressPhotos.isEmpty)
              Text(
                'No saved progress photos yet.',
                key: const ValueKey('share-progress-no-progress-photos'),
                style: muted,
              )
            else
              SizedBox(
                height: 128,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: progressPhotos.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final c = progressPhotos[i];
                    return tile(
                      c,
                      label: '${formatShortDate(c.takenAt)} · ${c.pose.label}',
                    );
                  },
                ),
              ),
            const SizedBox(height: 12),
            Text('Or a selfie', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),

            Row(
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('share-progress-selfie'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                  ),
                  onPressed: _sharing ? null : _takeSelfie,
                  icon: const Icon(Icons.photo_camera_front_outlined),
                  label: Text(selfie == null ? 'Take a selfie' : 'Retake'),
                ),
                if (selfie != null) ...[
                  const SizedBox(width: 12),
                  SizedBox(height: 128, child: tile(selfie, label: 'Selfie')),
                ],
              ],
            ),

            if (_latestScan != null)
              SwitchListTile(
                key: const ValueKey('share-progress-selfie-scan'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Include my scan result'),
                subtitle: Text(
                  'From ${formatShortDate(_latestScan!.takenAt)}: body fat '
                  '${_latestScan!.bodyFatPct.toStringAsFixed(1)}%, fat-free '
                  'mass ${_latestScan!.fatFreeMassKg.toStringAsFixed(1)} kg',
                ),
                value: _includeInfo,
                onChanged: _sharing
                    ? null
                    : (v) => setState(() => _includeInfo = v),
              ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('share-progress-caption'),
              controller: _caption,
              minLines: 1,
              maxLines: 3,
              maxLength: WorkoutPost.maxCaption,
              decoration: const InputDecoration(
                hintText: 'Say something about it (optional)',
                counterText: '',
                border: OutlineInputBorder(),
              ),
            ),
            if (picked.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Friends will see', style: theme.textTheme.titleSmall),
              for (final c in picked)
                Text(
                  _infoLine(c),
                  key: ValueKey('share-progress-info-${c.id}'),
                  style: muted,
                ),
            ],
            const SizedBox(height: 8),
            Text(
              'Only friends see what you share. They can still screenshot it, '
              'so share only photos you are comfortable with.',
              style: muted,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(
                  key: const ValueKey('share-progress-cancel'),
                  onPressed: _sharing
                      ? null
                      : () => Navigator.of(context).maybePop(),
                  child: const Text('Cancel'),
                ),
                const Spacer(),
                FilledButton(
                  key: const ValueKey('share-progress-confirm'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(96, 48),
                  ),
                  onPressed:
                      (_topic == ShareTopic.photos && picked.isEmpty) ||
                          sharePreview.isEmpty ||
                          _sharing
                      ? null
                      : _share,
                  child: _sharing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Share'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
