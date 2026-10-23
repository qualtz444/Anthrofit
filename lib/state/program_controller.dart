import 'package:flutter/foundation.dart';

import '../data/program_repository.dart';
import '../models/models.dart';

/// Holds all saved programs and which one is active.
///
/// Rules:
///  - At most ONE program is active, stored once as an id.
///  - An archived program can never be active.
///  - If the active program is archived or deleted, nothing becomes active
///    automatically. The user chooses.
///  - The only automatic activation: the very first program ever created.
///  - Completed workout sessions are stored elsewhere and are never touched
///    here, so archiving or deleting a program keeps its history.
///
/// Every change is written to storage first; memory only updates if that works.
class ProgramController extends ChangeNotifier {
  ProgramController(this._repository);

  final ProgramRepository _repository;

  List<TrainingProgram> _programs = const [];
  String? _activeProgramId;
  bool _isLoaded = false;

  bool get isLoaded => _isLoaded;
  List<TrainingProgram> get programs => List.unmodifiable(_programs);
  String? get activeProgramId => _activeProgramId;

  TrainingProgram? programById(String id) {
    for (final p in _programs) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Null when no program is active.
  TrainingProgram? get activeProgram {
    final id = _activeProgramId;
    return id == null ? null : programById(id);
  }

  Future<void> load() async {
    try {
      final data = await _repository.load();
      _programs = data.programs;
      final id = data.activeProgramId;
      // A saved id only counts if that program still exists and is not archived.
      _activeProgramId =
          (id != null && data.programs.any((p) => p.id == id && !p.archived))
          ? id
          : null;
    } catch (_) {
      _programs = const [];
      _activeProgramId = null;
    }
    _isLoaded = true;
    notifyListeners();
  }

  /// Adds the program, or replaces the one with the same id.
  /// The first program ever created becomes active. Later ones do not.
  Future<void> saveProgram(TrainingProgram program) async {
    final next = [..._programs];
    final index = next.indexWhere((p) => p.id == program.id);
    final isFirstEver = _programs.isEmpty && index < 0;
    if (index >= 0) {
      next[index] = program;
    } else {
      next.add(program);
    }

    var active = _activeProgramId;
    if (program.archived && active == program.id) active = null;
    if (isFirstEver && !program.archived) active = program.id;
    await _commit(next, active);
  }

  /// Deleting the active program leaves no active program.
  Future<void> deleteProgram(String id) async {
    final next = _programs.where((p) => p.id != id).toList();
    await _commit(next, _activeProgramId == id ? null : _activeProgramId);
  }

  /// Makes [id] the one active program. The previously active program simply
  /// stops being active. An archived program is un-archived by activating it.
  /// Makes no program active, without changing any program.
  ///
  /// The program keeps its workouts, schedule and history: it is simply not
  /// the one being followed. Archiving is a separate, stronger thing.
  Future<void> deactivateProgram(String id) async {
    if (_activeProgramId != id) return;
    await _commit(_programs, null);
  }

  Future<void> setActiveProgram(String id) async {
    final program = programById(id);
    if (program == null) return;
    final next = [
      for (final p in _programs)
        if (p.id == id && p.archived) p.copyWith(archived: false) else p,
    ];
    await _commit(next, id);
  }

  /// Keeps the program but marks it archived. If it was active, no program
  /// is active afterward.
  Future<void> archiveProgram(String id) async {
    final program = programById(id);
    if (program == null || program.archived) return;
    final next = [
      for (final p in _programs)
        if (p.id == id) p.copyWith(archived: true) else p,
    ];
    await _commit(next, _activeProgramId == id ? null : _activeProgramId);
  }

  /// Saves an independent copy (see TrainingProgram.duplicate). The copy is
  /// not active. Returns it, or null if [id] does not exist.
  Future<TrainingProgram?> duplicateProgram(String id) async {
    final original = programById(id);
    if (original == null) return null;
    final copy = original.duplicate();
    await _commit([..._programs, copy], _activeProgramId);
    return copy;
  }

  Future<void> _commit(List<TrainingProgram> programs, String? activeId) async {
    await _repository.save(
      ProgramData(programs: programs, activeProgramId: activeId),
    );
    _programs = programs;
    _activeProgramId = activeId;
    notifyListeners();
  }
}
