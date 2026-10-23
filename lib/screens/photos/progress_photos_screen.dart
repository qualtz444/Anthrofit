import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../auth/auth_scope.dart';
import '../../core/format.dart';
import '../../core/snack_bar_timing.dart';
import '../../data/storage_scope.dart';
import '../../photos/progress_photo.dart';
import '../../photos/progress_photo_store.dart';
import '../../scan/camera_permission.dart';

/// The store for whoever is using the app: each owner has their own photos.
ProgressPhotoStore progressPhotoStoreOf(BuildContext context) =>
    ProgressPhotoStore(
      scope:
          AuthScope.of(context, listen: false).dataScope ?? StorageScope.guest,
    );

/// Size the camera or gallery photo is saved at on the phone. APP DESIGN
/// VALUES: enough detail to compare, without filling the phone.
const double kPhotoMaxSide = 1440;
const int kPhotoQuality = 85;

/// Progress photos: normal colour photos, by date, to compare over time.
/// Not the scan's black and white outlines.
class ProgressPhotosScreen extends StatefulWidget {
  const ProgressPhotosScreen({super.key, this.store, this.picker});

  /// For tests. The screen uses the signed-in owner's store by default.
  final ProgressPhotoStore? store;
  final ImagePicker? picker;

  @override
  State<ProgressPhotosScreen> createState() => _ProgressPhotosScreenState();
}

class _ProgressPhotosScreenState extends State<ProgressPhotosScreen> {
  late final ProgressPhotoStore _store =
      widget.store ?? progressPhotoStoreOf(context);
  late final ImagePicker _picker = widget.picker ?? ImagePicker();
  final Map<String, Future<Uint8List?>> _cache = {};

  List<ProgressPhoto>? _photos;
  String? _error;

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Here rather than initState: the store depends on who is signed in.
    if (_started) return;
    _started = true;
    _reload();
  }

  Future<void> _reload() async {
    try {
      final photos = await _store.load();
      if (mounted) setState(() => _photos = photos);
    } catch (_) {
      if (mounted) {
        setState(() => _error = "Your photos couldn't be loaded.");
      }
    }
  }

  Future<Uint8List?> _bytes(String id) =>
      _cache.putIfAbsent(id, () => _store.bytes(id));

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: kSnackBarDuration,
        persist: false,
        content: Text(text),
      ),
    );
  }

  /// The camera needs the app's camera permission, because the app already
  /// declares it for the scan; without it Android refuses to open the camera.
  Future<bool> _cameraAllowed() async {
    const permission = SystemCameraPermission();
    var access = await permission.check();
    if (access == CameraAccess.notRequested || access == CameraAccess.denied) {
      access = await permission.request();
    }
    if (access == CameraAccess.granted) return true;
    if (!mounted) return false;
    if (access == CameraAccess.permanentlyDenied) {
      _message('Camera access is off. Turn it on in Settings.');
    }
    return false;
  }

  Future<void> _add() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const ValueKey('photo-from-camera'),
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.of(c).pop(ImageSource.camera),
            ),
            ListTile(
              key: const ValueKey('photo-from-gallery'),
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.of(c).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    if (source == ImageSource.camera && !await _cameraAllowed()) return;

    XFile? file;
    try {
      file = await _picker.pickImage(
        source: source,
        maxWidth: kPhotoMaxSide,
        maxHeight: kPhotoMaxSide,
        imageQuality: kPhotoQuality,
        preferredCameraDevice: CameraDevice.rear,
      );
    } catch (_) {
      if (mounted) _message("Couldn't open the camera or gallery.");
      return;
    }
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;

    final details = await showModalBottomSheet<_Details>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _DetailsSheet(
        preview: bytes,
        initial: _Details(
          pose: PhotoPose.front,
          takenAt: DateTime.now(),
          note: '',
        ),
        askDate: source == ImageSource.gallery,
      ),
    );
    if (details == null || !mounted) return;
    try {
      final photo = await _store.add(
        bytes,
        pose: details.pose,
        takenAt: details.takenAt,
        note: details.note,
      );
      _cache[photo.id] = Future.value(bytes);
      await _reload();
      if (mounted) _message('Photo saved on this phone.');
    } catch (_) {
      if (mounted) _message("Couldn't save the photo. Please try again.");
    }
  }

  Future<void> _open(ProgressPhoto photo) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PhotoViewerScreen(
          photo: photo,
          store: _store,
          all: _photos ?? const [],
          bytesOf: _bytes,
        ),
      ),
    );
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final photos = _photos;
    return Scaffold(
      appBar: AppBar(title: const Text('Progress photos')),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('add-progress-photo'),
        onPressed: _add,
        icon: const Icon(Icons.add_a_photo_outlined),
        label: const Text('Add photo'),
      ),
      body: _error != null
          ? Center(child: Text(_error!))
          : photos == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                Text(
                  'Photos stay on this phone unless you share them. For a fair '
                  'comparison, use the same place, light and pose.',
                  key: const ValueKey('photos-privacy-note'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                if (photos.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Text(
                      'No progress photos yet. Add one to start your record.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge,
                    ),
                  )
                else
                  for (final day in _byDay(photos)) ...[
                    Text(
                      formatDate(day.first.takenAt, today: DateTime.now()),
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 3 / 4,
                      children: [
                        for (final p in day)
                          PhotoTile(
                            key: ValueKey('photo-${p.id}'),
                            bytes: _bytes(p.id),
                            label: p.pose.label,
                            onTap: () => _open(p),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
              ],
            ),
    );
  }

  static List<List<ProgressPhoto>> _byDay(List<ProgressPhoto> photos) {
    final days = <List<ProgressPhoto>>[];
    for (final p in photos) {
      final last = days.isEmpty ? null : days.last.first.takenAt;
      if (last != null &&
          last.year == p.takenAt.year &&
          last.month == p.takenAt.month &&
          last.day == p.takenAt.day) {
        days.last.add(p);
      } else {
        days.add([p]);
      }
    }
    return days;
  }
}

/// A photo thumbnail with a small label.
class PhotoTile extends StatelessWidget {
  const PhotoTile({
    super.key,
    required this.bytes,
    required this.label,
    this.onTap,
    this.selected = false,
  });

  final Future<Uint8List?> bytes;
  final String label;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 3 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            FutureBuilder<Uint8List?>(
              future: bytes,
              builder: (context, snap) {
                final data = snap.data;
                if (data == null) {
                  return ColoredBox(
                    color: scheme.surfaceContainerHighest,
                    child: snap.connectionState == ConnectionState.done
                        ? const Icon(Icons.broken_image_outlined)
                        : null,
                  );
                }
                return Image.memory(data, fit: BoxFit.cover, cacheWidth: 360);
              },
            ),
            Positioned(
              left: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  label,
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ),
            if (selected)
              Positioned(
                right: 6,
                top: 6,
                child: Icon(Icons.check_circle, color: scheme.primary),
              ),
          ],
        ),
      ),
    );
  }
}

class _Details {
  const _Details({
    required this.pose,
    required this.takenAt,
    required this.note,
  });

  final PhotoPose pose;
  final DateTime takenAt;
  final String note;
}

class _DetailsSheet extends StatefulWidget {
  const _DetailsSheet({
    required this.initial,
    required this.askDate,
    this.preview,
    this.title = 'About this photo',
    this.saveLabel = 'Save photo',
  });

  final _Details initial;
  final bool askDate;
  final Uint8List? preview;
  final String title;
  final String saveLabel;

  @override
  State<_DetailsSheet> createState() => _DetailsSheetState();
}

class _DetailsSheetState extends State<_DetailsSheet> {
  late PhotoPose _pose = widget.initial.pose;
  late DateTime _takenAt = widget.initial.takenAt;
  late final TextEditingController _note = TextEditingController(
    text: widget.initial.note,
  );

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _takenAt.isAfter(now) ? now : _takenAt,
      firstDate: DateTime(now.year - 10),
      lastDate: now,
    );
    if (picked == null) return;
    setState(
      () => _takenAt = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _takenAt.hour,
        _takenAt.minute,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.title, style: theme.textTheme.titleLarge),
              if (widget.preview != null) ...[
                const SizedBox(height: 12),
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(
                      widget.preview!,
                      height: 180,
                      cacheHeight: 360,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text('Pose', style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  for (final p in PhotoPose.values)
                    ChoiceChip(
                      key: ValueKey('photo-pose-${p.name}'),
                      label: Text(p.label),
                      selected: p == _pose,
                      onSelected: (_) => setState(() => _pose = p),
                    ),
                ],
              ),
              if (widget.askDate) ...[
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_outlined),
                  title: const Text('Date taken'),
                  subtitle: Text(
                    formatDate(_takenAt, today: DateTime.now()),
                  ),
                  trailing: TextButton(
                    onPressed: _pickDate,
                    child: const Text('Change'),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('photo-note'),
                controller: _note,
                maxLength: ProgressPhoto.maxNote,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                key: const ValueKey('photo-save'),
                onPressed: () => Navigator.of(context).pop(
                  _Details(
                    pose: _pose,
                    takenAt: _takenAt,
                    note: _note.text.trim(),
                  ),
                ),
                child: Text(widget.saveLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One photo, full size, with its details, edit, delete and compare.
class PhotoViewerScreen extends StatefulWidget {
  const PhotoViewerScreen({
    super.key,
    required this.photo,
    required this.store,
    required this.all,
    required this.bytesOf,
  });

  final ProgressPhoto photo;
  final ProgressPhotoStore store;
  final List<ProgressPhoto> all;
  final Future<Uint8List?> Function(String id) bytesOf;

  @override
  State<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<PhotoViewerScreen> {
  late ProgressPhoto _photo = widget.photo;

  Future<void> _edit() async {
    final details = await showModalBottomSheet<_Details>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _DetailsSheet(
        title: 'Edit photo details',
        saveLabel: 'Save',
        askDate: true,
        initial: _Details(
          pose: _photo.pose,
          takenAt: _photo.takenAt,
          note: _photo.note,
        ),
      ),
    );
    if (details == null || !mounted) return;
    final next = _photo.copyWith(
      pose: details.pose,
      takenAt: details.takenAt,
      note: details.note,
    );
    try {
      await widget.store.update(next);
      if (mounted) setState(() => _photo = next);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            duration: kSnackBarDuration,
            persist: false,
            content: Text("Couldn't save the change."),
          ),
        );
      }
    }
  }

  Future<void> _delete() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this photo?'),
        content: const Text(
          'It is removed from this phone. Posts you already shared keep '
          'their copy until you delete the post.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('photo-delete-confirm'),
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    final navigator = Navigator.of(context);
    await widget.store.delete(_photo.id);
    navigator.pop();
  }

  Future<void> _compare() async {
    final others = [
      for (final p in widget.all)
        if (p.id != _photo.id) p,
    ];
    final other = await showModalBottomSheet<ProgressPhoto>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(c).height * 0.6,
          child: GridView.count(
            padding: const EdgeInsets.all(16),
            crossAxisCount: 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 3 / 4,
            children: [
              for (final p in others)
                PhotoTile(
                  bytes: widget.bytesOf(p.id),
                  label: '${formatShortDate(p.takenAt)} · ${p.pose.label}',
                  onTap: () => Navigator.of(c).pop(p),
                ),
            ],
          ),
        ),
      ),
    );
    if (other == null || !mounted) return;
    final pair = [_photo, other]
      ..sort((a, b) => a.takenAt.compareTo(b.takenAt));
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PhotoCompareScreen(
          before: pair.first,
          after: pair.last,
          bytesOf: widget.bytesOf,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(formatDate(_photo.takenAt, today: DateTime.now())),
        actions: [
          IconButton(
            tooltip: 'Edit details',
            onPressed: _edit,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            key: const ValueKey('photo-delete'),
            tooltip: 'Delete photo',
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder<Uint8List?>(
              future: widget.bytesOf(_photo.id),
              builder: (context, snap) {
                final data = snap.data;
                if (data == null) {
                  return Center(
                    child: snap.connectionState == ConnectionState.done
                        ? const Text("This photo couldn't be read.")
                        : const CircularProgressIndicator(),
                  );
                }
                return InteractiveViewer(
                  maxScale: 4,
                  child: Center(child: Image.memory(data)),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(_photo.pose.label, style: theme.textTheme.titleMedium),
                  if (_photo.note.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(_photo.note),
                  ],
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const ValueKey('photo-compare'),
                    onPressed: widget.all.length < 2 ? null : _compare,
                    icon: const Icon(Icons.compare_outlined),
                    label: const Text('Compare with another photo'),
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

/// Two photos side by side, earlier on the left.
class PhotoCompareScreen extends StatelessWidget {
  const PhotoCompareScreen({
    super.key,
    required this.before,
    required this.after,
    required this.bytesOf,
  });

  final ProgressPhoto before;
  final ProgressPhoto after;
  final Future<Uint8List?> Function(String id) bytesOf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = DateTime(after.takenAt.year, after.takenAt.month,
            after.takenAt.day)
        .difference(
          DateTime(before.takenAt.year, before.takenAt.month,
              before.takenAt.day),
        )
        .inDays;
    Widget side(ProgressPhoto p) => Expanded(
      child: Column(
        children: [
          Expanded(
            child: FutureBuilder<Uint8List?>(
              future: bytesOf(p.id),
              builder: (context, snap) => snap.data == null
                  ? const Center(child: CircularProgressIndicator())
                  : Image.memory(snap.data!, fit: BoxFit.contain),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            formatDate(p.takenAt, today: DateTime.now()),
            style: theme.textTheme.titleSmall,
          ),
          Text(p.pose.label, style: theme.textTheme.bodySmall),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Compare photos')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Text(
                days == 0
                    ? 'Same day'
                    : '$days ${days == 1 ? 'day' : 'days'} apart',
                key: const ValueKey('compare-days'),
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Row(
                  children: [side(before), const SizedBox(width: 8), side(after)],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
