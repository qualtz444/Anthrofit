import 'dart:async';

import 'package:flutter/material.dart';

import '../../composition/body_composition.dart';
import '../../composition/composition_models.dart';
import '../../composition/composition_runner.dart';
import '../../composition/composition_source.dart';
import '../../composition/composition_visuals.dart';
import '../../composition/profile_input.dart';
import '../../core/id.dart';
import '../../models/models.dart';
import '../../scan/camera_permission.dart';
import '../../state/profile_controller.dart';
import '../../state/profile_scope.dart';
import '../scan/scan_permission_view.dart';
import 'composition_result_screen.dart';
import '../../core/snack_bar_timing.dart';

/// Body composition estimate: a two-step capture (front, then side), then
/// the result. The camera starts straight away; a profile that cannot be
/// estimated gets an explanation instead.
///
/// The front and side photos are always kept with the scan, on this phone
/// only, alongside the outlines used for comparing scans.
///
/// Kept apart from the proportion scan and from Progress. Each estimate is
/// saved to the profile's composition history, which feeds the suggested
/// goal and the nutrition targets.
class BodyCompositionScreen extends StatefulWidget {
  const BodyCompositionScreen({
    super.key,
    this.permission = const SystemCameraPermission(),
    this.createSource,
    this.loadModels,
    this.visualStore,
    this.onEstimated,
    this.onGiveUp,
  });

  /// Swapped in tests.
  final CameraPermission permission;

  /// Given whether photos are kept, which is always true.
  final CompositionSource Function(bool includePhotos)? createSource;
  final Future<CompositionModels> Function()? loadModels;

  /// Where outlines and photos are kept, on this phone only.
  final CompositionVisualStore? visualStore;



  /// When set, a finished estimate is handed here instead of being saved and
  /// shown on [CompositionResultScreen]: the guided scan flow saves it only
  /// once every step has succeeded. Null keeps this screen's own behaviour.
  final ValueChanged<CompositionOutcome>? onEstimated;

  /// When set, Close on a failed capture calls this with the reason instead
  /// of just leaving, so the guided flow can say which step failed.
  final ValueChanged<String>? onGiveUp;

  @override
  State<BodyCompositionScreen> createState() => _BodyCompositionScreenState();
}

/// One finished estimate, not yet saved.
class CompositionOutcome {
  const CompositionOutcome({
    required this.result,
    required this.input,
    required this.visuals,
  });

  final BodyCompositionResult result;
  final CompositionInput input;

  /// Outlines and photos. Held in memory until saved; dropping this object
  /// discards them.
  final CompositionVisuals visuals;
}

/// The history entry for one estimate.
CompositionRecord compositionRecordFrom({
  required String id,
  required DateTime takenAt,
  required BodyCompositionResult result,
  required CompositionInput input,
}) {
  final m = result.measurements;
  return CompositionRecord(
    id: id,
    takenAt: takenAt,
    weightKg: input.weightKg,
    bodyFatPct: result.bodyFatPct.value,
    bodyFatLow: result.bodyFatPct.low,
    bodyFatHigh: result.bodyFatPct.high,
    leanLimbKg: result.appendicularLeanKg.value,
    fatFreeMassKg: result.fatFreeMassKg,
    fatMassKg: result.fatMassKg,
    waistCm: m.waist,
    chestCm: m.chest,
    hipCm: m.hip,
    thighCm: m.thigh,
    upperArmCm: m.bicep,
    frameCount: result.frameCount,
  );
}

/// Adds an estimate to the profile's composition history, and keeps its
/// outlines and photos on this phone.
///
/// A record with the same [id] is replaced rather than added again, so
/// retrying a save cannot duplicate it. Returns whether the numbers were
/// saved; a failed picture save only loses the comparison pictures.
Future<bool> saveCompositionEstimate({
  required ProfileController? controller,
  required CompositionVisualStore store,
  required String id,
  required DateTime takenAt,
  required BodyCompositionResult result,
  required CompositionInput input,
  required CompositionVisuals visuals,
}) async {
  final profile = controller?.profile;
  if (controller == null || profile == null) return false;
  final record = compositionRecordFrom(
    id: id,
    takenAt: takenAt,
    result: result,
    input: input,
  );
  // The pictures go first. The moment the record joins the profile, screens
  // that show the latest scan (Progress, scan history) rebuild and look for
  // its outline and photos; written after the record, they could be read as
  // missing and shown as "not saved" until the app restarts.
  var picturesSaved = false;
  try {
    await store.save(record.id, visuals);
    picturesSaved = true;
  } catch (_) {
    // The numbers still save; only the comparison pictures are missing.
  }
  try {
    // Saving the pictures took a moment: build on the profile as it is now.
    final current = controller.profile ?? profile;
    await controller.save(
      current.copyWith(compositionLog: [
        ...current.compositionLog.where((r) => r.id != id),
        record,
      ]),
    );
  } catch (_) {
    // Nothing was saved, so the pictures would never be shown.
    if (picturesSaved) {
      try {
        await store.delete(record.id);
      } catch (_) {}
    }
    return false;
  }
  return true;
}

class _BodyCompositionScreenState extends State<BodyCompositionScreen>
    with WidgetsBindingObserver {
  CameraAccess? _access;
  bool _asking = false;

  CompositionSource? _source;
  Widget? _preview; // built once, see ScanScreen
  StreamSubscription<CompositionCaptureState>? _states;
  CompositionCaptureState _state = const CompositionCaptureState(
    phase: CompositionPhase.positioning,
    message: 'Starting the camera',
  );

  bool _analysing = false;
  String? _error;

  /// Photos are always kept with a finished scan.
  static const bool _savePhotos = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The profile is read from context, so wait for the first frame. A
    // profile that cannot be estimated never starts the camera.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _blocker(_input(context, listen: false)) == null) {
        _checkPermission();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _states?.cancel();
    _source?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.resumed &&
        _access != CameraAccess.granted) {
      _checkPermission();
    }
  }

  /// Read without asserting, so the screen still builds where no profile
  /// scope exists.
  CompositionInput? _input(BuildContext context, {bool listen = true}) {
    final scope = listen
        ? context.dependOnInheritedWidgetOfExactType<ProfileScope>()
        : context.getInheritedWidgetOfExactType<ProfileScope>();
    final profile = scope?.notifier?.profile;
    return profile == null ? null : compositionInputFrom(profile);
  }

  /// Why no estimate can be made for this profile, or null when it can.
  static String? _blocker(CompositionInput? input) => input == null
      ? 'Body composition needs your sex set to Male or Female in your profile.'
      : input.problem;

  Future<void> _checkPermission() async {
    final access = await widget.permission.check();
    if (!mounted) return;
    if (access == CameraAccess.notRequested) {
      await _requestPermission();
      return;
    }
    _applyAccess(access);
  }

  Future<void> _requestPermission() async {
    if (_asking) return;
    setState(() => _asking = true);
    final access = await widget.permission.request();
    if (!mounted) return;
    setState(() => _asking = false);
    _applyAccess(access);
  }

  void _applyAccess(CameraAccess access) {
    setState(() => _access = access);
    if (access == CameraAccess.granted) _startSource();
  }

  void _startSource() {
    if (_source != null) return;
    final source = widget.createSource?.call(_savePhotos) ??
        NativeCompositionSource();
    _source = source;
    _preview = source.preview();
    _states = source.states.listen((state) {
      if (!mounted) return;
      setState(() => _state = state);
      if (state.phase == CompositionPhase.done) _analyse(state);
    });
    source.start();
  }

  Future<void> _analyse(CompositionCaptureState state) async {
    if (_analysing) return;
    final input = _input(context, listen: false);
    if (input == null) {
      // The blocker (or the guided flow's protocol screen) already stops this.
      widget.onGiveUp?.call('Your profile has no sex set to Male or Female.');
      return;
    }
    final navigator = Navigator.of(context);
    setState(() {
      _analysing = true;
      _error = null;
    });

    try {
      final models = await (widget.loadModels ?? loadCompositionModels)();
      final result = estimateComposition(
        models: models,
        front: state.front,
        side: state.side,
        input: input,
      );
      if (!mounted) return;
      final onEstimated = widget.onEstimated;
      if (onEstimated != null) {
        onEstimated(CompositionOutcome(
          result: result,
          input: input,
          visuals: _visualsFrom(state),
        ));
        return;
      }
      final id = generateId();
      final saved = await saveCompositionEstimate(
        controller: context.getInheritedWidgetOfExactType<ProfileScope>()
            ?.notifier,
        store: widget.visualStore ?? CompositionVisualStore(),
        id: id,
        takenAt: DateTime.now(),
        result: result,
        input: input,
        visuals: _visualsFrom(state),
      );
      if (!mounted) return;
      // Replaces the camera, so Back from the result returns to where the
      // estimate was started.
      unawaited(navigator.pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => CompositionResultScreen(
            result: result,
            input: input,
            saved: saved,
            visuals: _visualsFrom(state),
            // Shows what changed since the last scan, once saved.
            recordId: saved ? id : null,
            visualStore: widget.visualStore,
          ),
        ),
      ));
    } on CompositionException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = "Couldn't run the estimate. Try again.");
      }
    } finally {
      if (mounted) setState(() => _analysing = false);
    }
  }

  /// What this scan keeps to show: the best front and side outline, and the
  /// photos. The lists are best first.
  CompositionVisuals _visualsFrom(CompositionCaptureState state) =>
      CompositionVisuals(
        frontOutline: state.front.isEmpty ? null : state.front.first,
        sideOutline: state.side.isEmpty ? null : state.side.first,
        frontPhoto: state.frontPhoto,
        sidePhoto: state.sidePhoto,
      );

  void _retry() {
    setState(() {
      _error = null;
      _state = const CompositionCaptureState(
        phase: CompositionPhase.positioning,
        message: 'Stand so your whole body is in frame',
      );
    });
    _source?.retry();
  }

  Future<void> _openSettings() async {
    final messenger = ScaffoldMessenger.of(context);
    final opened = await widget.permission.openSettings();
    if (!opened && mounted) {
      messenger.showSnackBar(
        const SnackBar(duration: kSnackBarDuration, persist: false, content: Text("Couldn't open Settings on this device.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_blocker(_input(context)) case final blocker?) {
      return _Blocked(message: blocker);
    }

    final access = _access;
    final failure = _error ??
        (_state.phase == CompositionPhase.failed
            ? (_state.failureReason ?? _state.message)
            : null);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Body composition'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: switch (access) {
          null => const Center(child: CircularProgressIndicator()),
          CameraAccess.granted => Stack(
            fit: StackFit.expand,
            children: [
              _preview ?? const SizedBox.shrink(),
              _Guidance(state: _state),
              if (_analysing) const _Analysing(),
              if (failure != null && !_analysing)
                _Failure(
                  message: failure,
                  onRetry: _retry,
                  onClose: widget.onGiveUp == null
                      ? null
                      : () => widget.onGiveUp!(failure),
                ),
            ],
          ),
          _ => ScanPermissionView(
            purpose:
                'ANTHROFIT estimates body composition with the camera. No video '
                'is recorded, and your photos and outline stay on this phone.',
            access: access,
            busy: _asking,
            onRequest: _requestPermission,
            onOpenSettings: _openSettings,
          ),
        },
      ),
    );
  }
}

/// Shown instead of the camera when this profile cannot be estimated.
class _Blocked extends StatelessWidget {
  const _Blocked({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Body composition')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          message,
          key: const ValueKey('composition-blocker'),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      ),
    );
  }
}

class _Guidance extends StatelessWidget {
  const _Guidance({required this.state});

  final CompositionCaptureState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final holding = state.phase == CompositionPhase.holding;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        color: Colors.black54,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (state.title.isNotEmpty)
              Text(
                'Step ${state.stepIndex + 1} of ${state.stepCount}: '
                '${state.title}',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white70,
                ),
              ),
            const SizedBox(height: 4),
            Text(
              state.message,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (holding) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: state.holdProgress,
                  minHeight: 6,
                  backgroundColor: Colors.white24,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Analysing extends StatelessWidget {
  const _Analysing();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black87,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            'Estimating',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: Colors.white),
          ),
        ],
      ),
    ),
  );
}

class _Failure extends StatelessWidget {
  const _Failure({
    required this.message,
    required this.onRetry,
    this.onClose,
  });

  final String message;
  final VoidCallback onRetry;

  /// Null just leaves the screen.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: Colors.black87,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.white70, size: 48),
              const SizedBox(height: 16),
              Text(
                "The capture didn't finish",
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(onPressed: onRetry, child: const Text('Try again')),
              TextButton(
                onPressed: onClose ?? () => Navigator.of(context).pop(),
                child: const Text(
                  'Close',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
