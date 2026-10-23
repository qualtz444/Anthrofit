import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../models/measurement.dart';
import '../../scan/camera_permission.dart';
import '../../scan/scan_source.dart';
import '../../scan/scan_state.dart';
import '../../state/measurement_scope.dart';
import 'scan_permission_view.dart';
import 'scan_result_screen.dart';
import '../../core/snack_bar_timing.dart';

/// Body Scan.
///
/// Order matters: camera permission is asked for FIRST, and the preview is
/// only built once it is granted. The native side binds the camera as soon as
/// its view exists, so building it earlier would fail.
///
/// A finished capture is saved, then shown. Nothing is interpreted here: the
/// measurement arrives whole on the "done" event and is passed straight on.
class ScanScreen extends StatefulWidget {
  const ScanScreen({
    super.key,
    this.permission = const SystemCameraPermission(),
    this.createSource,
    this.onMeasured,
    this.onGiveUp,
  });

  /// Swapped in tests.
  final CameraPermission permission;

  /// Defaults to the real native source. Tests and demos pass a mock.
  final ScanSource Function()? createSource;

  /// When set, a finished capture is handed here instead of being saved and
  /// shown on [ScanResultScreen]: the caller (the guided scan flow) decides
  /// when to save it and what to show. Null keeps this screen's own
  /// behaviour, used wherever it is opened on its own.
  final ValueChanged<Measurement>? onMeasured;

  /// When set, Close on a failed capture calls this with the reason instead
  /// of just leaving, so the guided flow can say which step failed.
  final ValueChanged<String>? onGiveUp;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> with WidgetsBindingObserver {
  CameraAccess? _access;
  bool _asking = false;

  ScanSource? _source;

  /// Built once. The platform view must not be rebuilt on every state update,
  /// or the native side tears the camera down and starts it again.
  Widget? _preview;
  StreamSubscription<ScanState>? _states;
  ScanState _state = const ScanState(
    phase: ScanPhase.guiding,
    message: 'Starting the camera',
  );

  /// Stops a second result screen opening if more than one "done" arrives.
  bool _resultShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _states?.cancel();
    _source?.dispose();
    super.dispose();
  }

  /// Coming back from Settings is the only way a permanent refusal changes, so
  /// the check is repeated when the app is resumed.
  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.resumed &&
        _access != CameraAccess.granted) {
      _checkPermission();
    }
  }

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

  /// Builds the source (and so the preview) only after permission is granted.
  void _startSource() {
    if (_source != null) return;
    final source = (widget.createSource ?? NativeScanSource.new)();
    _source = source;
    _preview = source.preview();
    _states = source.states.listen((state) {
      if (!mounted) return;
      setState(() => _state = state);
      if (state.phase == ScanPhase.done) _showResult(state);
    });
    source.start();
  }

  /// A capture finished. Shows what it measured, then returns here so another
  /// scan can be started.
  ///
  /// "done" with no measurement should not happen: the native side only ever
  /// sends that event with one. If it does, the result screen says so rather
  /// than showing an empty page.
  Future<void> _showResult(ScanState state) async {
    if (_resultShown) return; // one result per capture
    _resultShown = true;

    final measurement = state.measurement ?? Measurement.fromNative(const {});

    // Handed to the guided flow, which saves it itself once every step
    // succeeds, and shows it on the combined results screen.
    if (widget.onMeasured != null) {
      widget.onMeasured!(measurement);
      return;
    }

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final store = MeasurementScope.of(context, listen: false);

    // An empty scan is not worth keeping, and a failed save must not stop the
    // user seeing what was measured.
    var saved = false;
    if (!measurement.isEmpty) {
      try {
        await store.add(measurement);
        saved = true;
      } catch (_) {
        messenger.showSnackBar(
          const SnackBar(duration: kSnackBarDuration, persist: false, content: Text("Couldn't save this scan.")),
        );
      }
    }
    if (!mounted) return;
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ScanResultScreen(measurement: measurement, saved: saved),
      ),
    );
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

  void _retry() {
    _resultShown = false;
    setState(
      () => _state = const ScanState(
        phase: ScanPhase.guiding,
        message: 'Stand so your whole body is in frame',
      ),
    );
    _source?.retry();
  }

  @override
  Widget build(BuildContext context) {
    final access = _access;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Body Scan'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          if (access == CameraAccess.granted)
            IconButton(
              tooltip: 'Switch camera',
              icon: const Icon(Icons.cameraswitch_outlined),
              onPressed: () => _source?.switchCamera(),
            ),
        ],
      ),
      body: SafeArea(
        child: switch (access) {
          null => const Center(child: CircularProgressIndicator()),
          CameraAccess.granted => _ScanView(
            preview: _preview ?? const SizedBox.shrink(),
            state: _state,
            onRetry: _retry,
            onGiveUp: widget.onGiveUp,
            // Embedded in the guided flow: the parent swaps this screen out
            // as soon as onMeasured fires, so there is nothing to show here.
            showComplete: widget.onMeasured == null,
          ),
          _ => ScanPermissionView(
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

/// The camera preview with the guidance laid over it.
class _ScanView extends StatelessWidget {
  const _ScanView({
    required this.preview,
    required this.state,
    required this.onRetry,
    this.onGiveUp,
    this.showComplete = true,
  });

  final Widget preview;
  final ScanState state;
  final VoidCallback onRetry;
  final ValueChanged<String>? onGiveUp;
  final bool showComplete;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        preview,
        _ScanGuidance(state: state),
        if (state.phase == ScanPhase.failed)
          _ScanFailure(state: state, onRetry: onRetry, onGiveUp: onGiveUp),
        if (state.phase == ScanPhase.done && showComplete)
          _ScanComplete(state: state, onScanAgain: onRetry),
      ],
    );
  }
}

/// The message, the hold timer and the frame counter.
class _ScanGuidance extends StatelessWidget {
  const _ScanGuidance({required this.state});

  final ScanState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMeasuring = state.phase == ScanPhase.measuring;
    final showsProgress = state.phase == ScanPhase.holding || isMeasuring;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        decoration: const BoxDecoration(color: Colors.black54),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              state.message,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (showsProgress) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: isMeasuring && state.framesTotal > 0
                      ? state.framesCaptured / state.framesTotal
                      : state.holdProgress,
                  minHeight: 6,
                  backgroundColor: Colors.white24,
                ),
              ),
            ],
            if (isMeasuring) ...[
              const SizedBox(height: 8),
              Text(
                '${state.framesCaptured} of ${state.framesTotal} frames',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white70,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Covers the preview when a capture is abandoned.
class _ScanFailure extends StatelessWidget {
  const _ScanFailure({
    required this.state,
    required this.onRetry,
    this.onGiveUp,
  });

  final ScanState state;
  final VoidCallback onRetry;

  /// Null just leaves the screen.
  final ValueChanged<String>? onGiveUp;

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
                "The scan didn't finish",
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                state.failureReason ?? state.message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(onPressed: onRetry, child: const Text('Try again')),
              TextButton(
                onPressed: onGiveUp == null
                    ? () => Navigator.of(context).pop()
                    : () => onGiveUp!(state.failureReason ?? state.message),
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

/// Covers the preview once a capture finishes. The result screen has already
/// been shown; this is what the user comes back to.
class _ScanComplete extends StatelessWidget {
  const _ScanComplete({required this.state, required this.onScanAgain});

  final ScanState state;
  final VoidCallback onScanAgain;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final measurement = state.measurement;
    final count = measurement?.ratios.length ?? 0;

    return ColoredBox(
      color: Colors.black87,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.check_circle_outline,
                color: Colors.white,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                'Scan complete',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                count == 0
                    ? 'This scan produced no measurements.'
                    : '${pluralize(count, 'measurement')} recorded.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 24),
              if (measurement != null)
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            ScanResultScreen(measurement: measurement),
                      ),
                    );
                  },
                  child: const Text('View result'),
                ),
              TextButton(
                onPressed: onScanAgain,
                child: const Text(
                  'Scan again',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
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
