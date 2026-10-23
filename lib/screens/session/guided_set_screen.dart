import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../coaching/set_coach.dart';
import '../../core/set_input.dart';
import '../../core/units.dart';
import '../../models/models.dart';
import '../../reps/pose_frame.dart';
import '../../reps/pose_source.dart';
import '../../reps/rep_counter.dart';
import '../../reps/rep_signal.dart';
import '../../scan/camera_permission.dart';
import '../scan/scan_permission_view.dart';
import '../../core/snack_bar_timing.dart';

enum _Stage { howTo, camera, tap }

class GuidedSetResult {
  const GuidedSetResult({required this.reps, required this.weight});

  final int reps;
  final String weight;
}

/// One guided set: how to do the exercise, then a rep counter.
///
/// The camera counts reps by following one joint ([repSignalFor]); the tap
/// counter is the fallback for exercises the camera cannot count, or when
/// the camera is not available. Either way the count can be corrected by
/// hand, and nothing is logged here: the count is handed back to the workout
/// screen, where the user checks it and completes the set as usual.
///
/// Pops with the rep count and entered weight, or null if the user left.
class GuidedSetScreen extends StatefulWidget {
  const GuidedSetScreen({
    super.key,
    required this.exercise,
    required this.setNumber,
    this.workoutName,
    this.target,
    this.initialWeight = '',
    this.weightUnit = WeightUnit.kg,
    this.permission = const SystemCameraPermission(),
    this.createSource,
    this.cameraAvailable = kNativePoseStreamReady,
    this.settings = const RepCounterSettings(),
    this.startDelay = const Duration(seconds: 5),
  });

  final Exercise exercise;
  final int setNumber;
  final String? workoutName;

  /// The planned target, already worded ("10 reps · 40 kg"), if any.
  final String? target;

  /// Previously entered load, in [weightUnit], if present.
  final String initialWeight;
  final WeightUnit weightUnit;

  final CameraPermission permission;

  /// Defaults to the native pose stream. Tests pass a mock.
  final PoseSource Function()? createSource;

  /// False offers the tap counter only (see [kNativePoseStreamReady]).
  final bool cameraAvailable;

  final RepCounterSettings settings;

  /// Time to walk back into position before counting starts, so the walk is
  /// not counted as reps. A UX choice, not a measured value.
  final Duration startDelay;

  @override
  State<GuidedSetScreen> createState() => _GuidedSetScreenState();
}

class _GuidedSetScreenState extends State<GuidedSetScreen>
    with WidgetsBindingObserver {
  _Stage _stage = _Stage.howTo;

  late final RepSignal? _signal = repSignalFor(widget.exercise);
  RepCounter? _counter;

  CameraAccess? _access;
  bool _asking = false;
  PoseSource? _source;
  Widget? _preview;
  StreamSubscription<PoseFrame>? _frames;
  late final TextEditingController _weight = TextEditingController(
    text: widget.initialWeight,
  );

  /// Tap count, or the hand correction added to the camera's count.
  int _manual = 0;

  /// Seconds left before the camera starts counting; 0 once counting.
  int _countdown = 0;
  Timer? _countdownTimer;

  bool get _canUseCamera => widget.cameraAvailable && _signal != null;

  int get _count => ((_counter?.reps ?? 0) + _manual).clamp(0, 999);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    _frames?.cancel();
    _source?.dispose();
    _weight.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (_stage == _Stage.camera &&
        lifecycle == AppLifecycleState.resumed &&
        _access != CameraAccess.granted) {
      _checkPermission();
    }
  }

  void _startCamera() {
    setState(() {
      _stage = _Stage.camera;
      _counter = RepCounter(_signal!, settings: widget.settings);
      _manual = 0;
    });
    _checkPermission();
  }

  void _startTapping() => setState(() {
    _stage = _Stage.tap;
    _manual = 0;
  });

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
    if (access != CameraAccess.granted || _source != null) return;
    final source = widget.createSource?.call() ?? NativePoseSource();
    _source = source;
    _preview = source.preview();
    _startCountdown();
    _frames = source.frames.listen((frame) {
      if (!mounted || _countdown > 0) return;
      final before = _counter!.reps;
      final wasInView = _counter!.inView;
      final wasMoving = _counter!.moving;
      _counter!.add(frame);
      if (_counter!.reps != before ||
          _counter!.inView != wasInView ||
          _counter!.moving != wasMoving) {
        setState(() {});
      }
    });
    source.start();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    final seconds = widget.startDelay.inSeconds;
    setState(() => _countdown = seconds);
    if (seconds <= 0) return;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _countdown--);
      if (_countdown <= 0) t.cancel();
    });
  }

  Future<void> _openSettings() async {
    final messenger = ScaffoldMessenger.of(context);
    final opened = await widget.permission.openSettings();
    if (!opened && mounted) {
      messenger.showSnackBar(
        const SnackBar(
          duration: kSnackBarDuration,
          persist: false,
          content: Text("Couldn't open Settings on this device."),
        ),
      );
    }
  }

  void _adjust(int by) => setState(() {
    if (_count + by >= 0) _manual += by;
  });

  void _done() => Navigator.of(
    context,
  ).pop(GuidedSetResult(reps: _count, weight: _weight.text.trim()));

  @override
  Widget build(BuildContext context) => switch (_stage) {
    _Stage.howTo => _howTo(context),
    _Stage.camera => _camera(context),
    _Stage.tap => _tap(context),
  };

  Widget _header(BuildContext context, {Color? color}) {
    final theme = Theme.of(context);
    return Text(
      'Set ${widget.setNumber}'
      '${widget.target == null ? '' : ' · Target: ${widget.target}'}',
      textAlign: TextAlign.center,
      style: theme.textTheme.titleMedium?.copyWith(color: color),
    );
  }

  Widget _screenTitle(BuildContext context, {bool dark = false}) {
    final theme = Theme.of(context);
    final foreground = dark ? Colors.white : null;
    final workoutName = widget.workoutName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          workoutName ?? widget.exercise.name,
          key: const ValueKey('guided-workout-header'),
          style: theme.textTheme.titleMedium?.copyWith(color: foreground),
        ),
        if (workoutName != null)
          Text(
            widget.exercise.name,
            style: theme.textTheme.bodySmall?.copyWith(
              color: dark ? Colors.white70 : theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }

  Future<void> _editWeight() async {
    final previousWeight = _weight.text;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Weight (${widget.weightUnit.short})'),
        content: TextField(
          key: const ValueKey('guided-weight'),
          controller: _weight,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            LengthLimitingTextInputFormatter(kWeightInputMaxLength),
          ],
          decoration: const InputDecoration(
            labelText: 'Weight',
            helperText: 'Leave blank for bodyweight',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (saved != true) _weight.text = previousWeight;
    _weight.text = _weight.text.trim();
    setState(() {});
  }

  Widget _weightControl() {
    final value = _weight.text.trim();
    return TextButton.icon(
      key: const ValueKey('guided-weight-control'),
      onPressed: _editWeight,
      icon: const Icon(Icons.edit_outlined, size: 18),
      label: Text(
        value.isEmpty
            ? 'Add weight'
            : 'Weight: $value ${widget.weightUnit.short}',
      ),
    );
  }

  Widget _howTo(BuildContext context) {
    final theme = Theme.of(context);
    final steps = widget.exercise.instructions;
    final signal = _signal;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Scaffold(
      appBar: AppBar(title: _screenTitle(context)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _header(context),
          const SizedBox(height: 16),
          if (_canUseCamera && signal != null) ...[
            Card(
              key: const ValueKey('guided-setup'),
              margin: EdgeInsets.zero,
              color: theme.colorScheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Set up your phone',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    const _SetupStep(
                      Icons.stay_current_portrait,
                      'Stand the phone upright on something steady, like a '
                      'bench or a shelf, with the screen facing you.',
                    ),
                    _SetupStep(Icons.accessibility_new, '${signal.facing}.'),
                    _SetupStep(
                      Icons.fit_screen,
                      'Step back until you can see ${signal.inFrame} on '
                      'the screen.',
                    ),
                    const _SetupStep(
                      Icons.timer_outlined,
                      'After you tap Count with camera, you have a few '
                      'seconds to get into position before counting starts.',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Text('How to do it', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (steps.isEmpty)
            Text(
              'No step-by-step guide for this exercise yet.',
              style: theme.textTheme.bodyMedium,
            )
          else
            for (var i = 0; i < steps.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 12,
                      child: Text(
                        '${i + 1}',
                        style: theme.textTheme.labelSmall,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(steps[i])),
                  ],
                ),
              ),
          const SizedBox(height: 16),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Counting reps', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  if (_canUseCamera && signal != null)
                    Text(
                      'The camera follows your ${signal.joint} to count. It '
                      'can miss or add a rep, so check the number and fix '
                      'it with + and −.',
                      key: const ValueKey('guided-camera-note'),
                    )
                  else if (signal == null)
                    const Text(
                      "The camera can't count this exercise. Tap once for "
                      'each rep instead.',
                      key: ValueKey('guided-no-camera'),
                    )
                  else
                    const Text(
                      'Camera counting is not available yet. Tap once for '
                      'each rep instead.',
                      key: ValueKey('guided-camera-unavailable'),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    'Video is not recorded or saved. The rep count and weight '
                    'return to your workout.',
                    style: muted,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(kCoachSafetyNote, style: muted),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_canUseCamera) ...[
                FilledButton.icon(
                  key: const ValueKey('guided-start-camera'),
                  onPressed: _startCamera,
                  icon: const Icon(Icons.videocam_outlined),
                  label: const Text('Count with camera'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  key: const ValueKey('guided-start-tap'),
                  onPressed: _startTapping,
                  child: const Text('Count by tapping'),
                ),
              ] else
                FilledButton(
                  key: const ValueKey('guided-start-tap'),
                  onPressed: _startTapping,
                  child: const Text('Start counting'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _countDisplay(
    BuildContext context, {
    required Color color,
    double fontSize = 96,
  }) {
    final theme = Theme.of(context);
    return Text(
      '$_count',
      key: const ValueKey('guided-count'),
      textAlign: TextAlign.center,
      style: theme.textTheme.displayLarge?.copyWith(
        color: color,
        fontWeight: FontWeight.w700,
        fontSize: fontSize,
      ),
    );
  }

  Widget _controls({required bool dark}) {
    final fg = dark ? Colors.white : null;
    return Row(
      children: [
        IconButton.outlined(
          key: const ValueKey('guided-minus'),
          tooltip: 'One rep fewer',
          onPressed: _count > 0 ? () => _adjust(-1) : null,
          color: fg,
          icon: const Icon(Icons.remove),
        ),
        const SizedBox(width: 8),
        IconButton.outlined(
          key: const ValueKey('guided-plus'),
          tooltip: 'One rep more',
          onPressed: () => _adjust(1),
          color: fg,
          icon: const Icon(Icons.add),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: FilledButton(
            key: const ValueKey('guided-done'),
            onPressed: _done,
            child: const Text('Done'),
          ),
        ),
      ],
    );
  }

  Widget _camera(BuildContext context) {
    final theme = Theme.of(context);
    final access = _access;
    final counter = _counter!;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: _screenTitle(context, dark: true),
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
          CameraAccess.granted => Stack(
            fit: StackFit.expand,
            children: [
              _preview ?? const SizedBox.shrink(),
              if (_countdown > 0)
                Center(
                  child: Container(
                    key: const ValueKey('guided-countdown'),
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Get into position',
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          '$_countdown',
                          style: theme.textTheme.displayMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Align(
                alignment: Alignment.topCenter,
                child: Container(
                  width: double.infinity,
                  color: Colors.black54,
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _header(context, color: Colors.white70),
                      const SizedBox(height: 4),
                      Text(
                        _signal!.placement,
                        key: const ValueKey('guided-placement'),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      if (_countdown == 0 && !counter.inView) ...[
                        const SizedBox(height: 4),
                        Text(
                          "Can't see you yet. Step into view.",
                          key: const ValueKey('guided-not-in-view'),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: Colors.amberAccent,
                          ),
                        ),
                      ] else if (_countdown == 0 && counter.moving) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Paused while you move about.',
                          key: const ValueKey('guided-moving'),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: Colors.amberAccent,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: double.infinity,
                  color: Colors.black54,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _weightControl(),
                      _countDisplay(context, color: Colors.white, fontSize: 88),
                      Text(
                        'reps',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _controls(dark: true),
                    ],
                  ),
                ),
              ),
            ],
          ),
          _ => ScanPermissionView(
            purpose:
                'ANTHROFIT counts your reps from the camera. Video is not '
                'recorded or saved; only the count is used.',
            access: access,
            busy: _asking,
            onRequest: _requestPermission,
            onOpenSettings: _openSettings,
          ),
        },
      ),
    );
  }

  Widget _tap(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: _screenTitle(context)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context),
              const SizedBox(height: 16),
              Expanded(
                child: Material(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(24),
                  child: InkWell(
                    key: const ValueKey('guided-tap-area'),
                    borderRadius: BorderRadius.circular(24),
                    onTap: () => _adjust(1),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _countDisplay(
                            context,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                          Text(
                            'Tap anywhere here after each rep',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Align(alignment: Alignment.centerLeft, child: _weightControl()),
              const SizedBox(height: 8),
              _controls(dark: false),
            ],
          ),
        ),
      ),
    );
  }
}

class _SetupStep extends StatelessWidget {
  const _SetupStep(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 20,
          color: Theme.of(context).colorScheme.onSecondaryContainer,
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
      ],
    ),
  );
}
