import 'dart:async';

import 'package:flutter/material.dart';

import '../content/app_content.dart';
import '../content/content_models.dart';
import '../data/exercise_catalog_repository.dart';
import '../models/models.dart';
import 'admin_service.dart';

/// What every admin page reads: the built-in catalogue, and the admin's
/// exercises, equipment and settings, kept live from Firestore.
class AdminData extends ChangeNotifier {
  AdminData(this.service);

  final AdminService service;

  List<Exercise> builtIn = const [];
  List<ExerciseOverride> overrides = const [];
  List<EquipmentDef> equipment = const [];
  ContentConfig config = ContentConfig.empty;

  bool loaded = false;
  String? error;

  final List<StreamSubscription<Object?>> _subs = [];

  Future<void> start() async {
    try {
      builtIn = await const AssetExerciseCatalog().load();
    } catch (e) {
      error = 'The built-in exercise list could not be read: $e';
    }
    void failed(Object e) {
      error = 'Could not read from Firestore: $e';
      notifyListeners();
    }

    _subs.addAll([
      service.exercises().listen((v) {
        overrides = v;
        notifyListeners();
      }, onError: failed),
      service.equipment().listen((v) {
        equipment = [...v]..sort((a, b) => a.label.compareTo(b.label));
        notifyListeners();
      }, onError: failed),
      service.config().listen((v) {
        config = v;
        loaded = true;
        notifyListeners();
      }, onError: failed),
    ]);
    notifyListeners();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  bool isBuiltIn(String id) => builtIn.any((e) => e.id == id);

  ExerciseOverride? overrideOf(String id) {
    for (final o in overrides) {
      if (o.exercise.id == id) return o;
    }
    return null;
  }

  /// Every exercise as the phone app will see it, hidden ones included.
  List<Exercise> get allExercises =>
      mergeCatalog(builtIn, overrides).exercises;

  Exercise? exerciseById(String id) {
    for (final e in allExercises) {
      if (e.id == id) return e;
    }
    return null;
  }

  String exerciseName(String id) => exerciseById(id)?.name ?? '$id (missing)';

  String equipmentLabel(String id) {
    for (final e in equipment) {
      if (e.id == id) return e.label;
    }
    return id;
  }
}

class AdminScope extends InheritedNotifier<AdminData> {
  const AdminScope({super.key, required AdminData data, required super.child})
    : super(notifier: data);

  static AdminData of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AdminScope>()!.notifier!;
}
