import 'package:flutter/widgets.dart';

import '../cloud/cloud_store.dart';

import '../data/exercise_library_repository.dart';
import '../data/measurement_repository.dart';
import '../data/profile_repository.dart';
import '../data/scan_session_journal.dart';
import '../data/program_repository.dart';
import '../data/session_repository.dart';
import '../data/storage_scope.dart';
import '../data/sync_service.dart';
import 'exercise_library_controller.dart';
import 'exercise_library_scope.dart';
import 'measurement_controller.dart';
import 'measurement_scope.dart';
import 'profile_controller.dart';
import 'profile_scope.dart';
import 'program_controller.dart';
import 'program_scope.dart';
import 'scan_session_commit.dart';
import 'session_controller.dart';
import 'session_scope.dart';

/// Creates the profile, program, session and scan controllers for ONE owner (the
/// guest or one account) and makes them available below.
///
/// Give it a key made from the scope. A different owner means a different key,
/// which throws these controllers away and builds new ones, so one person's
/// data can never still be in memory when someone else signs in.
class UserDataHost extends StatefulWidget {
  const UserDataHost({
    super.key,
    required this.scope,
    required this.child,
    this.cloud,
    this.uid = '',
  });

  final StorageScope scope;
  final Widget child;

  /// Mirrors this owner's data to the cloud. Null means local only, which is
  /// always the case for a guest.
  final CloudStore? cloud;

  /// The account this data belongs to. Empty for a guest.
  final String uid;

  @override
  State<UserDataHost> createState() => _UserDataHostState();
}

class _UserDataHostState extends State<UserDataHost> {
  late final ProfileController _profile;
  late final ProgramController _program;
  late final SessionController _session;
  late final MeasurementController _measurements;
  late final ExerciseLibraryController _library;

  @override
  void initState() {
    super.initState();
    final scope = widget.scope;
    // One sync service for this owner, shared by all four repositories. It
    // does nothing at all for a guest.
    final sync = SyncService(
      cloud: widget.cloud,
      scope: scope,
      uid: widget.uid,
    );
    _profile = ProfileController(ProfileRepository(scope: scope, sync: sync));
    _program = ProgramController(ProgramRepository(scope: scope, sync: sync));
    _session = SessionController(SessionRepository(scope: scope, sync: sync));
    _measurements = MeasurementController(
      MeasurementRepository(scope: scope, sync: sync),
    );
    _library = ExerciseLibraryController(
      ExerciseLibraryRepository(scope: scope, sync: sync),
    );
    final profileLoaded = _profile.load();
    _program.load();
    _session.load();
    final scansLoaded = _measurements.load();
    _library.load();
    // Finishes saving a guided scan that was committed but interrupted
    // before both parts were copied in (see ScanSessionJournal).
    Future.wait([profileLoaded, scansLoaded]).then((_) {
      if (!mounted) return;
      applyPendingScanSession(
        journal: ScanSessionJournal(scope: scope),
        profiles: _profile,
        scans: _measurements,
      );
    });
  }

  @override
  void dispose() {
    _profile.dispose();
    _program.dispose();
    _session.dispose();
    _measurements.dispose();
    _library.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ProfileScope(
      controller: _profile,
      child: ProgramScope(
        controller: _program,
        child: SessionScope(
          controller: _session,
          child: MeasurementScope(
            controller: _measurements,
            child: ExerciseLibraryScope(
              controller: _library,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
