import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../core/id.dart';
import '../core/json_utils.dart';
import '../data/storage_scope.dart';
import '../data/stored_json.dart';
import 'progress_photo.dart';

/// Saves progress photos on this phone, separately for each owner:
///
/// ```text
/// (app documents)/progress_photos/(owner)/(photo id).jpg   the picture
/// shared preferences  "progress_photos" in the owner's scope  the list
/// ```
///
/// The list goes through the same storage as the rest of the app, but NOT
/// through SyncService: progress photos never go to the cloud on their own.
class ProgressPhotoStore {
  ProgressPhotoStore({
    this.scope = StorageScope.guest,
    Future<Directory> Function()? baseDirectory,
  }) : _baseDirectory = baseDirectory ?? getApplicationDocumentsDirectory;

  final StorageScope scope;
  final Future<Directory> Function() _baseDirectory;

  static const String folder = 'progress_photos';
  static const String storageKey = 'progress_photos';

  Future<Directory> _dir() async {
    final base = await _baseDirectory();
    final owner = scope.id.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return Directory('${base.path}/$folder/$owner');
  }

  Future<File> _file(String id) async {
    final safe = id.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return File('${(await _dir()).path}/$safe.jpg');
  }

  /// Every photo, newest first.
  Future<List<ProgressPhoto>> load() async {
    final map = await readSavedObject(scope.key(storageKey));
    final photos = [
      for (final entry in parseMapList(map?['photos']))
        ?ProgressPhoto.fromJson(entry),
    ]..sort((a, b) => b.takenAt.compareTo(a.takenAt));
    return photos;
  }

  Future<void> _saveList(List<ProgressPhoto> photos) => writeSavedObject(
    scope.key(storageKey),
    {'photos': photos.map((p) => p.toJson()).toList()},
  );

  /// Saves a new photo. The picture is written first, so the list never
  /// points at a file that is not there.
  Future<ProgressPhoto> add(
    Uint8List jpeg, {
    required PhotoPose pose,
    DateTime? takenAt,
    String note = '',
  }) async {
    final photo = ProgressPhoto(
      id: generateId(),
      takenAt: takenAt ?? DateTime.now(),
      pose: pose,
      note: note.trim(),
    );
    final file = await _file(photo.id);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(jpeg, flush: true);
    try {
      await _saveList([photo, ...await load()]);
    } catch (e) {
      // The list could not be saved: do not leave the picture behind.
      if (await file.exists()) await file.delete();
      rethrow;
    }
    return photo;
  }

  /// Changes the pose, date or note. The picture is not touched.
  Future<void> update(ProgressPhoto photo) async {
    final photos = await load();
    await _saveList([
      for (final p in photos) p.id == photo.id ? photo : p,
    ]);
  }

  /// Removes a photo from the list, then its picture.
  Future<void> delete(String id) async {
    final photos = await load();
    await _saveList([
      for (final p in photos)
        if (p.id != id) p,
    ]);
    final file = await _file(id);
    if (await file.exists()) await file.delete();
  }

  /// The picture, or null when it is missing or cannot be read.
  Future<Uint8List?> bytes(String id) async {
    try {
      final file = await _file(id);
      if (!await file.exists()) return null;
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }
}

/// Longest side of a photo sent to Community, in pixels, and its JPEG
/// quality. APP DESIGN VALUES: small enough that two photos fit well inside
/// one Firestore document each (1 MiB limit) on the free plan; not chosen
/// for any visual standard.
const int kSharedPhotoMaxSide = 720;
const int kSharedPhotoQuality = 70;

/// The largest shared photo accepted, matching firestore.rules.
const int kSharedPhotoMaxBytes = 400 * 1024;

/// A smaller copy of [jpeg] for sharing: upright, at most
/// [kSharedPhotoMaxSide] on its longest side. Runs off the UI thread.
/// Null when the picture cannot be read or is still too large.
Future<Uint8List?> shrinkForSharing(Uint8List jpeg) async {
  final out = kDebugMode && Platform.environment.containsKey('FLUTTER_TEST')
      ? _shrink(jpeg)
      : await compute(_shrink, jpeg);
  if (out == null || out.length > kSharedPhotoMaxBytes) return null;
  return out;
}

/// Shrinks photos for sharing ahead of time. Shrinking is the slow part on
/// the phone, so it starts the moment a photo is ticked and is usually done
/// by the time Share is tapped. Photos are shrunk side by side, each on its
/// own isolate.
class SharePhotoPrep {
  final Map<String, Future<Uint8List?>> _byId = {};

  /// Starts shrinking [jpeg] under [id], once. Safe to call again.
  void prepare(String id, Uint8List jpeg) =>
      _byId.putIfAbsent(id, () => shrinkForSharing(jpeg));

  /// Drops [id], for a photo that was replaced under the same id.
  void forget(String id) => _byId.remove(id);

  /// The shrunk photos, in order; null when any cannot be shrunk. Starts any
  /// that were not prepared yet.
  Future<List<Uint8List>?> collect(
    List<({String id, Uint8List jpeg})> photos,
  ) async {
    for (final p in photos) {
      prepare(p.id, p.jpeg);
    }
    final out = await Future.wait([for (final p in photos) _byId[p.id]!]);
    for (var i = 0; i < out.length; i++) {
      // A failure is not kept, so the next try starts again.
      if (out[i] == null) _byId.remove(photos[i].id);
    }
    if (out.any((b) => b == null)) return null;
    return [for (final b in out) b!];
  }
}

Uint8List? _shrink(Uint8List jpeg) {
  final decoded = img.decodeImage(jpeg);
  if (decoded == null) return null;
  // Applies the camera's rotation flag, so the photo is not sideways once
  // the flag is gone.
  final upright = img.bakeOrientation(decoded);
  final longest = upright.width > upright.height
      ? upright.width
      : upright.height;
  final resized = longest <= kSharedPhotoMaxSide
      ? upright
      : upright.width >= upright.height
      ? img.copyResize(upright, width: kSharedPhotoMaxSide)
      : img.copyResize(upright, height: kSharedPhotoMaxSide);
  return img.encodeJpg(resized, quality: kSharedPhotoQuality);
}
