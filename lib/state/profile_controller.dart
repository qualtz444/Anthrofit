import 'package:flutter/foundation.dart';

import '../data/profile_repository.dart';
import '../models/models.dart';
import '../progress/body_progress.dart';

/// Holds the current profile for the whole app.
/// Screens read it through ProfileScope and rebuild when it changes.
class ProfileController extends ChangeNotifier {
  ProfileController(this._repository);

  final ProfileRepository _repository;

  UserProfile? _profile;
  bool _isLoaded = false;

  /// Null means the user hasn't finished profile setup.
  UserProfile? get profile => _profile;

  /// False until the first load from storage has finished.
  bool get isLoaded => _isLoaded;

  Future<void> load() async {
    try {
      _profile = await _repository.load();
    } catch (_) {
      _profile = null;
    }
    _isLoaded = true;
    notifyListeners();
  }

  /// Saves to storage first. The in-memory profile only changes if that works.
  /// Saves [profile], recording its weight in the weight log when it has
  /// changed. [now] is for tests.
  Future<void> save(UserProfile profile, {DateTime? now}) async {
    final withLog = profile.copyWith(
      weightLog: recordBodyWeight(
        profile.weightLog,
        profile.weightKg,
        now ?? DateTime.now(),
      ),
    );
    await _repository.save(withLog);
    _profile = withLog;
    notifyListeners();
  }
}
