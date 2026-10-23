import 'package:cloud_firestore/cloud_firestore.dart';

import 'content_models.dart';

/// Where the admin's content lives in Firestore. Shared by the phone app
/// (read only) and the admin panel (read and write).
///
///   content/config                    recommendation settings (one doc)
///   content/catalog/equipment/{id}    admin-added equipment
///   content/catalog/exercises/{id}    added or replaced exercises
///   admins/{uid}                      who may use the admin panel
class ContentPaths {
  const ContentPaths._();

  static DocumentReference<Map<String, dynamic>> config(FirebaseFirestore db) =>
      db.collection('content').doc('config');

  static CollectionReference<Map<String, dynamic>> equipment(
    FirebaseFirestore db,
  ) => db.collection('content').doc('catalog').collection('equipment');

  static CollectionReference<Map<String, dynamic>> exercises(
    FirebaseFirestore db,
  ) => db.collection('content').doc('catalog').collection('exercises');

  static DocumentReference<Map<String, dynamic>> admin(
    FirebaseFirestore db,
    String uid,
  ) => db.collection('admins').doc(uid);
}

abstract class ContentSource {
  Future<ContentSnapshot> fetch();
}

/// Reads the admin's content from Firestore. Everyone can read it, guests
/// included; only admins can write (see firestore.rules).
class FirestoreContentSource implements ContentSource {
  factory FirestoreContentSource({FirebaseFirestore? instance}) =>
      FirestoreContentSource._(instance);

  FirestoreContentSource._(this._instance);

  final FirebaseFirestore? _instance;

  /// Resolved on first use, so building this before Firebase starts (or in
  /// a test) never throws.
  FirebaseFirestore get _db => _instance ?? FirebaseFirestore.instance;

  @override
  Future<ContentSnapshot> fetch() async {
    final results = await Future.wait([
      ContentPaths.config(_db).get(),
      ContentPaths.equipment(_db).get(),
      ContentPaths.exercises(_db).get(),
    ]);
    final config = results[0] as DocumentSnapshot<Map<String, dynamic>>;
    final equipment = results[1] as QuerySnapshot<Map<String, dynamic>>;
    final exercises = results[2] as QuerySnapshot<Map<String, dynamic>>;

    // Through the same JSON reader the saved copy uses, so both paths
    // accept and reject exactly the same things.
    return ContentSnapshot.fromJson({
      'config': config.data() ?? const <String, dynamic>{},
      'equipment': [
        for (final d in equipment.docs) {...d.data(), 'id': d.id},
      ],
      'exercises': [
        for (final d in exercises.docs) {...d.data(), 'id': d.id},
      ],
    });
  }
}
