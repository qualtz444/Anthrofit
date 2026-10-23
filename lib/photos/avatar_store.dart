import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../data/storage_scope.dart';

/// Stores one avatar per owner on this phone. Public Community copies are
/// stored separately in the owner's public profile.
class AvatarStore {
  AvatarStore({
    required this.scope,
    Future<Directory> Function()? baseDirectory,
  }) : _baseDirectory = baseDirectory ?? getApplicationDocumentsDirectory;

  final StorageScope scope;
  final Future<Directory> Function() _baseDirectory;

  Future<File> _file() async {
    final base = await _baseDirectory();
    final owner = scope.id.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return File('${base.path}/avatars/$owner.jpg');
  }

  Future<Uint8List?> load() async {
    final file = await _file();
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  Future<void> save(Uint8List bytes) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
  }

  Future<void> delete() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
  }
}
