import 'dart:async';

import 'package:flutter/material.dart';

import '../../composition/composition_models.dart';
import '../../composition/composition_source.dart';
import '../../composition/composition_visuals.dart';
import '../../core/id.dart';
import '../../data/scan_session_journal.dart';
import '../../models/models.dart';
import '../../scan/camera_permission.dart';
import '../../scan/scan_source.dart';
import '../../state/measurement_scope.dart';
import '../../state/profile_scope.dart';
import '../../state/scan_session_commit.dart';
import '../composition/body_composition_screen.dart';
import 'scan_screen.dart';

/// How a guided scan session ended. Handed back to the protocol screen
/// ([ScanChoiceScreen]) as the route's result.
sealed class GuidedScanEnd {
  const GuidedScanEnd();
}

/// Both steps succeeded. [saved] says whether both were stored.
class GuidedScanFinished extends GuidedScanEnd {
  const GuidedScanFinished({
    required this.measurement,
    required this.composition,
    required this.compositionId,
    required this.takenAt,
    required this.saved,
  });

  final Measurement measurement;
  final CompositionOutcome composition;

  /// Fixed for the session, so retrying a failed save replaces rather than
  /// duplicates the record.
  final String compositionId;
  final DateTime takenAt;
  final bool saved;
}

/// The session was abandoned: a step ultimately failed, or the user cancelled
/// ([failedStep] is null). Nothing from it was saved.
class GuidedScanStopped extends GuidedScanEnd {
  const GuidedScanStopped({this.failedStep, this.reason});

  /// Plain-language name of the step that failed, e.g. "Step 1, body
  /// proportions".
  final String? failedStep;
  final String? reason;

  bool get cancelled => failedStep == null;
}

/// Saves one finished session, all or nothing: the proportion scan into the
/// scan history, the estimate into the profile's composition history (kept
/// apart as before), and the estimate's outlines and photos on this
/// phone.
///
/// The pictures are written first, under the record's id. Then the two
/// records are committed together in one write (see [ScanSessionJournal]).
/// If either step fails, the pictures are removed again and nothing is saved.
/// Calling this again for the same session (same ids) cannot duplicate
/// anything.
Future<bool> saveGuidedScan(
  BuildContext context, {
  required Measurement measurement,
  required CompositionOutcome composition,
  required String compositionId,
  required DateTime takenAt,
  CompositionVisualStore? visualStore,
}) async {
  final scans = context
      .getInheritedWidgetOfExactType<MeasurementScope>()
      ?.notifier;
  final profiles = context
      .getInheritedWidgetOfExactType<ProfileScope>()
      ?.notifier;
  if (scans == null || profiles == null || profiles.profile == null) {
    return false;
  }
  final store = visualStore ?? CompositionVisualStore();
  final record = compositionRecordFrom(
    id: compositionId,
    takenAt: takenAt,
    result: composition.result,
    input: composition.input,
  );

  Future<void> removePictures() async {
    try {
      await store.delete(record.id);
    } catch (_) {
      // Left behind only if the phone refuses this too. Without a record
      // they are never shown.
    }
  }

  try {
    await store.save(record.id, composition.visuals);
  } catch (_) {
    await removePictures();
    return false;
  }
  final committed = await commitScanSession(
    journal: ScanSessionJournal(scope: scans.scope),
    session: PendingScanSession(measurement: measurement, record: record),
    profiles: profiles,
    scans: scans,
  );
  if (!committed) await removePictures();
  return committed;
}

enum _Stage { proportion, handoff, composition, saving }

/// One continuous scan session: Step 1 the body proportion capture, then
/// Step 2 the body composition capture (front, then side, then the
/// estimate), then a single save.
///
/// The existing capture screens do the capturing, with their own checks and
/// their own in-place "Try again" for an unusable capture. This screen only
/// holds the results in memory between steps and saves them once both have
/// succeeded. Closing a failed step, or leaving, pops with a
/// [GuidedScanStopped]: everything held here is dropped with the screen.
class GuidedScanScreen extends StatefulWidget {
  const GuidedScanScreen({
    super.key,
    this.permission = const SystemCameraPermission(),
    this.createScanSource,
    this.createCompositionSource,
    this.loadModels,
    this.visualStore,
    this.handoff = const Duration(seconds: 3),
  });

  final CameraPermission permission;
  final ScanSource Function()? createScanSource;
  final CompositionSource Function(bool includePhotos)? createCompositionSource;
  final Future<CompositionModels> Function()? loadModels;
  final CompositionVisualStore? visualStore;

  /// The pause between the steps, so the person can get into position and
  /// the first camera is released before the second starts.
  final Duration handoff;

  static const String step1 = 'Step 1, body proportions';
  static const String step2 = 'Step 2, body composition';

  @override
  State<GuidedScanScreen> createState() => _GuidedScanScreenState();
}

class _GuidedScanScreenState extends State<GuidedScanScreen> {
  _Stage _stage = _Stage.proportion;

  // Session state. Never saved until both steps succeed.
  Measurement? _measurement;
  final String _compositionId = generateId();
  bool _ended = false;

  Timer? _handoffTimer;

  @override
  void dispose() {
    _handoffTimer?.cancel();
    super.dispose();
  }

  void _end(GuidedScanEnd end) {
    if (_ended) return;
    _ended = true;
    _handoffTimer?.cancel();
    _measurement = null;
    Navigator.of(context).pop(end);
  }

  void _onMeasured(Measurement measurement) {
    if (_stage != _Stage.proportion || _ended) return;
    if (measurement.isEmpty) {
      _end(
        const GuidedScanStopped(
          failedStep: GuidedScanScreen.step1,
          reason: 'The scan finished without any usable measurements.',
        ),
      );
      return;
    }
    setState(() {
      _measurement = measurement;
      _stage = _Stage.handoff;
    });
    _handoffTimer = Timer(widget.handoff, _startComposition);
  }

  void _startComposition() {
    _handoffTimer?.cancel();
    if (!mounted || _stage != _Stage.handoff) return;
    setState(() => _stage = _Stage.composition);
  }

  Future<void> _onEstimated(CompositionOutcome outcome) async {
    final measurement = _measurement;
    if (_stage != _Stage.composition || _ended || measurement == null) return;
    setState(() => _stage = _Stage.saving);
    final takenAt = DateTime.now();
    final saved = await saveGuidedScan(
      context,
      measurement: measurement,
      composition: outcome,
      compositionId: _compositionId,
      takenAt: takenAt,
      visualStore: widget.visualStore,
    );
    if (!mounted) return;
    _end(
      GuidedScanFinished(
        measurement: measurement,
        composition: outcome,
        compositionId: _compositionId,
        takenAt: takenAt,
        saved: saved,
      ),
    );
  }

  void _giveUp(String step, String reason) =>
      _end(GuidedScanStopped(failedStep: step, reason: reason));

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _stage == _Stage.saving) return;
        _end(const GuidedScanStopped());
      },
      child: switch (_stage) {
        _Stage.proportion => ScanScreen(
          key: const ValueKey('guided-step-1'),
          permission: widget.permission,
          createSource: widget.createScanSource,
          onMeasured: _onMeasured,
          onGiveUp: (reason) => _giveUp(GuidedScanScreen.step1, reason),
        ),
        _Stage.handoff => _Handoff(onContinue: _startComposition),
        _Stage.composition => BodyCompositionScreen(
          key: const ValueKey('guided-step-2'),
          permission: widget.permission,
          createSource: widget.createCompositionSource,
          loadModels: widget.loadModels,
          visualStore: widget.visualStore,
          onEstimated: _onEstimated,
          onGiveUp: (reason) => _giveUp(GuidedScanScreen.step2, reason),
        ),
        _Stage.saving => const _Saving(),
      },
    );
  }
}

class _Handoff extends StatelessWidget {
  const _Handoff({required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Scan')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              Icons.check_circle,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Step 1 of 2 done',
              key: const ValueKey('guided-handoff'),
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Next: body composition. Stay where you are. Face the camera '
              'with your arms slightly out, then turn 90 degrees to your right '
              'when asked.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 24),
            TextButton(onPressed: onContinue, child: const Text('Start now')),
          ],
        ),
      ),
    );
  }
}

class _Saving extends StatelessWidget {
  const _Saving();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Saving your results'),
        ],
      ),
    ),
  );
}
