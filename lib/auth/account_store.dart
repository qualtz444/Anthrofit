import 'package:shared_preferences/shared_preferences.dart';

import '../data/profile_repository.dart';
import '../data/program_repository.dart';
import '../data/session_repository.dart';
import '../data/storage_scope.dart';
import '../data/stored_json.dart';
import 'account.dart';

/// Local, non-secret facts about accounts on this device, saved through the
/// same storage as everything else:
///   - whether the user chose Guest mode
///   - each account's names and email (inside that account's own scope)
///   - whether the "keep your guest data?" question has been answered
///   - moving guest data into an account
/// Passwords and tokens are never stored here. Firebase owns the session.
class AccountStore {
  /// "guest" when the user chose Continue without an account.
  static const String guestModeKey = 'auth.mode';
  static const String _accountKey = 'account';
  static const String _migrationKey = 'migration';

  Future<bool> isGuestChosen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(guestModeKey) == 'guest';
  }

  Future<void> setGuestChosen(bool chosen) async {
    final prefs = await SharedPreferences.getInstance();
    if (chosen) {
      await prefs.setString(guestModeKey, 'guest');
    } else {
      await prefs.remove(guestModeKey);
    }
  }

  Future<AccountInfo?> loadAccount(String uid) async {
    final map = await readSavedObject(StorageScope.user(uid).key(_accountKey));
    if (map == null) return null;
    final info = AccountInfo.fromJson(map);
    return info.uid.isEmpty ? null : info;
  }

  Future<void> saveAccount(AccountInfo account) => writeSavedObject(
    StorageScope.user(account.uid).key(_accountKey),
    account.toJson(),
  );

  /// null = the question has not been answered for this account yet.
  Future<String?> migrationMarker(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(StorageScope.user(uid).key(_migrationKey));
  }

  Future<void> setMigrationMarker(String uid, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageScope.user(uid).key(_migrationKey), value);
  }

  /// True if [scope] holds a profile, a program, or any workout session.
  Future<bool> scopeHasData(StorageScope scope) async {
    if (await ProfileRepository(scope: scope).load() != null) return true;
    if ((await ProgramRepository(scope: scope).load()).programs.isNotEmpty) {
      return true;
    }
    final sessions = await SessionRepository(scope: scope).load();
    return sessions.activeSession != null || sessions.sessions.isNotEmpty;
  }

  /// Moves the guest's profile, programs and sessions (including an unfinished
  /// workout) to [target]. Nothing is re-created, so nothing is duplicated.
  ///
  /// Safe by order: every item is first copied and read back. Only when ALL
  /// copies are confirmed are the guest originals removed. If anything fails,
  /// the copies are undone, the guest data is left exactly as it was, and an
  /// error is thrown. An item the target already has is never overwritten.
  Future<void> moveGuestDataTo(StorageScope target) async {
    final prefs = await SharedPreferences.getInstance();
    final bases = [
      ProfileRepository.storageKey,
      ProgramRepository.storageKey,
      SessionRepository.storageKey,
    ];
    final copied = <String>[];

    Future<void> undoCopies() async {
      for (final base in copied) {
        await prefs.remove(target.key(base));
      }
    }

    for (final base in bases) {
      final raw = prefs.getString(StorageScope.guest.key(base));
      if (raw == null) continue;
      if (prefs.getString(target.key(base)) != null) continue;
      final ok = await prefs.setString(target.key(base), raw);
      if (!ok || prefs.getString(target.key(base)) != raw) {
        await undoCopies();
        throw StateError('Could not copy "$base".');
      }
      copied.add(base);
    }

    for (final base in copied) {
      await prefs.remove(StorageScope.guest.key(base));
    }
  }
}
