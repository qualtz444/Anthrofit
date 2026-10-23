import '../data/scan_session_journal.dart';
import 'measurement_controller.dart';
import 'profile_controller.dart';

/// Saves a finished guided scan as one unit (see [ScanSessionJournal]).
///
/// Returns false only when the commit itself failed, in which case nothing
/// was saved. True means the session is saved: it is copied into the scan
/// history and the profile now, or, if that fails, on the next load.
Future<bool> commitScanSession({
  required ScanSessionJournal journal,
  required PendingScanSession session,
  required ProfileController profiles,
  required MeasurementController scans,
}) async {
  // There is one pending slot. An earlier session still waiting in it must
  // be finished first, or this write would replace (lose) it.
  final slotFree = await applyPendingScanSession(
    journal: journal,
    profiles: profiles,
    scans: scans,
  );
  if (!slotFree) return false;
  try {
    await journal.write(session);
  } catch (_) {
    return false;
  }
  await applyPendingScanSession(
    journal: journal,
    profiles: profiles,
    scans: scans,
  );
  return true;
}

/// Copies a committed session into the scan history and the profile's
/// composition history, then clears it. Does nothing if none is pending.
///
/// Called right after a commit, and again once the owner's data has loaded,
/// to finish a copy that was interrupted. Never throws: whatever is left
/// stays pending and is tried again next time. Returns whether nothing is
/// left pending.
Future<bool> applyPendingScanSession({
  required ScanSessionJournal journal,
  required ProfileController profiles,
  required MeasurementController scans,
}) async {
  try {
    final pending = await journal.read();
    if (pending == null) return true;

    final profile = profiles.profile;
    // No profile yet (still loading, or none): keep it for later.
    if (profile == null) return false;

    if (scans.byId(pending.measurement.id) == null) {
      await scans.add(pending.measurement);
    }
    final record = pending.record;
    if (!profile.compositionLog.any((r) => r.id == record.id)) {
      await profiles.save(
        profile.copyWith(compositionLog: [...profile.compositionLog, record]),
      );
    }
    await journal.clear();
    return true;
  } catch (_) {
    return false;
  }
}
