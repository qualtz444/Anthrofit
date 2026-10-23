import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anthrofit/data/storage_scope.dart';
import 'package:anthrofit/photos/avatar_store.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('avatar_store_test');
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('saves avatars separately for each owner', () async {
    final guest = AvatarStore(
      scope: StorageScope.guest,
      baseDirectory: () async => directory,
    );
    final user = AvatarStore(
      scope: StorageScope.user('account-1'),
      baseDirectory: () async => directory,
    );
    final bytes = Uint8List.fromList([1, 2, 3]);

    expect(await guest.load(), isNull);
    await guest.save(bytes);
    await user.save(Uint8List.fromList([4, 5, 6]));

    expect(await guest.load(), bytes);
    expect(await user.load(), [4, 5, 6]);
  });
}
