import 'dart:async';

import 'package:anthrofit/coaching/warm_cool.dart';
import 'package:anthrofit/content/app_content.dart';

/// Runs before every test file.
///
/// The warm-up and cool-down cards are off for the existing screen tests,
/// so they keep their layout; warm_cool_test.dart turns them on where it
/// checks them. Admin content is never fetched from Firebase in tests:
/// every test starts from the built-in values.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  warmCoolSettings.value = false;
  AppContent.remote = null;
  await testMain();
}
