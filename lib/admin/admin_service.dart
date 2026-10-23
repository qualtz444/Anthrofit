import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../content/content_models.dart';
import '../content/content_source.dart';

/// Every read and write the admin panel makes. Firestore rules allow the
/// writes only for accounts listed in admins/{uid}.
class AdminService {
  AdminService({FirebaseFirestore? db, FirebaseAuth? auth})
    : _dbOverride = db,
      _authOverride = auth;

  final FirebaseFirestore? _dbOverride;
  final FirebaseAuth? _authOverride;

  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;
  FirebaseAuth get auth => _authOverride ?? FirebaseAuth.instance;

  /// Who made a change, for the record kept with it.
  String get _who => auth.currentUser?.email ?? auth.currentUser?.uid ?? '';

  Map<String, dynamic> get _stamp => {
    'updatedAt': DateTime.now().toUtc().toIso8601String(),
    'updatedBy': _who,
  };

  Future<bool> isAdmin(String uid) async {
    final doc = await ContentPaths.admin(_db, uid).get();
    return doc.exists;
  }

  // ---- exercises ---------------------------------------------------------

  Stream<List<ExerciseOverride>> exercises() =>
      ContentPaths.exercises(_db).snapshots().map(
        (q) => [
          for (final d in q.docs)
            ExerciseOverride.fromJson({...d.data(), 'id': d.id}),
        ],
      );

  Future<void> saveExercise(ExerciseOverride exercise) =>
      ContentPaths.exercises(
        _db,
      ).doc(exercise.exercise.id).set({...exercise.toJson(), ..._stamp});

  /// For a built-in exercise this reverts it; for an added one it removes it.
  Future<void> deleteExercise(String id) =>
      ContentPaths.exercises(_db).doc(id).delete();

  // ---- equipment ---------------------------------------------------------

  Stream<List<EquipmentDef>> equipment() =>
      ContentPaths.equipment(_db).snapshots().map(
        (q) => [
          for (final d in q.docs)
            EquipmentDef.fromJson({...d.data(), 'id': d.id}),
        ],
      );

  Future<void> saveEquipment(EquipmentDef item) => ContentPaths.equipment(
    _db,
  ).doc(item.id).set({...item.toJson(), ..._stamp});

  Future<void> deleteEquipment(String id) =>
      ContentPaths.equipment(_db).doc(id).delete();

  // ---- recommendation settings -------------------------------------------

  Stream<ContentConfig> config() => ContentPaths.config(_db).snapshots().map(
    (d) => ContentConfig.fromJson(d.data() ?? const <String, dynamic>{}),
  );

  /// Reads the settings, applies [change] and writes them back in one
  /// transaction, so two admins saving at once cannot undo each other.
  Future<void> updateConfig(
    ContentConfig Function(ContentConfig current) change,
  ) {
    final ref = ContentPaths.config(_db);
    return _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final current = ContentConfig.fromJson(
        snap.data() ?? const <String, dynamic>{},
      );
      final next = change(current).copyWith(
        updatedAt: DateTime.now().toUtc(),
        updatedBy: _who,
      );
      tx.set(ref, next.toJson());
    });
  }
}
