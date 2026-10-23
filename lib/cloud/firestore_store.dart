import 'package:cloud_firestore/cloud_firestore.dart';

import 'cloud_store.dart';

/// Cloud Firestore, laid out as one document per kind of data:
///
///   users/{uid}/data/profile
///   users/{uid}/data/programs
///   users/{uid}/data/sessions
///   users/{uid}/data/measurements
///
/// Everything lives under users/{uid}, so one security rule can keep each
/// account to its own data.
///
/// Firestore keeps its own offline cache, so reads work without a connection
/// and writes queue until there is one. That is why this class has no retry
/// logic of its own.
class FirestoreStore implements CloudStore {
  /// The parameter is named `instance` rather than `firestore` so it does not
  /// shadow the field: the analyzer asks for an initializing formal when the
  /// two names match, which a nullable lazy field cannot use.
  FirestoreStore({FirebaseFirestore? instance}) : _firestore = instance;

  final FirebaseFirestore? _firestore;

  /// Resolved on first use, not at construction. Building this store before
  /// Firebase has started (or in a test, where it never does) must not throw;
  /// a failed read or write is caught by SyncService and falls back to the
  /// device's own copy.
  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _doc(String uid, String key) =>
      _db.collection('users').doc(uid).collection('data').doc(key);

  @override
  Future<Map<String, dynamic>?> read({
    required String uid,
    required String key,
  }) async {
    final snapshot = await _doc(uid, key).get();
    return snapshot.exists ? snapshot.data() : null;
  }

  @override
  Future<void> write({
    required String uid,
    required String key,
    required Map<String, dynamic> value,
  }) => _doc(uid, key).set(value);
}
