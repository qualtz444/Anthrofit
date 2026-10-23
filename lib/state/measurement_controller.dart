import 'package:flutter/foundation.dart';

import '../data/measurement_repository.dart';
import '../data/storage_scope.dart';
import '../models/models.dart';

/// Holds this person's completed body scans.
///
/// A scan is a record of what was measured, so nothing here edits one: it can
/// be added, or deleted if the user asks. Every change is written to storage
/// first; memory only updates if that works.
class MeasurementController extends ChangeNotifier {
  MeasurementController(this._repository);

  final MeasurementRepository _repository;

  /// Whose scans these are, so data saved alongside them (the guided scan's
  /// pending session) lands under the same owner.
  StorageScope get scope => _repository.scope;

  List<Measurement> _measurements = const [];
  // Same list instance until something changes, so reading it is cheap.
  List<Measurement> _view = const [];
  bool _isLoaded = false;

  bool get isLoaded => _isLoaded;

  /// Every saved scan, newest first.
  List<Measurement> get measurements => _view;

  /// The most recent scan, or null.
  Measurement? get latest => _measurements.isEmpty ? null : _measurements.first;

  Measurement? byId(String id) {
    for (final m in _measurements) {
      if (m.id == id) return m;
    }
    return null;
  }

  Future<void> load() async {
    try {
      _measurements = _newestFirst(await _repository.load());
    } catch (_) {
      _measurements = const [];
    }
    _view = List.unmodifiable(_measurements);
    _isLoaded = true;
    notifyListeners();
  }

  /// Saves a finished scan. A scan with the same id is replaced rather than
  /// added twice, so a screen that saves on rebuild cannot duplicate one.
  Future<void> add(Measurement measurement) async {
    final next = [
      measurement,
      ..._measurements.where((m) => m.id != measurement.id),
    ];
    await _commit(next);
  }

  Future<void> delete(String id) =>
      _commit(_measurements.where((m) => m.id != id).toList());

  static List<Measurement> _newestFirst(List<Measurement> list) {
    final copy = [...list];
    copy.sort((a, b) => b.takenAt.compareTo(a.takenAt));
    return copy;
  }

  Future<void> _commit(List<Measurement> measurements) async {
    final ordered = _newestFirst(measurements);
    await _repository.save(ordered);
    _measurements = ordered;
    _view = List.unmodifiable(ordered);
    notifyListeners();
  }
}
