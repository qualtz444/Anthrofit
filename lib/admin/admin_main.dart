import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../firebase_options.dart';
import 'admin_app.dart';

/// The admin web panel's own entry point. It is not part of the phone app:
/// nothing in lib/main.dart or lib/app.dart leads here.
///
/// Run it in Chrome:
///   flutter run -d chrome -t lib/admin/admin_main.dart
/// Build it for hosting:
///   flutter build web -t lib/admin/admin_main.dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const AdminApp());
}
