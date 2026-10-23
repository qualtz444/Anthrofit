import 'package:flutter/material.dart';

import '../../composition/composition_models.dart';
import '../../composition/composition_source.dart';
import '../../composition/composition_visuals.dart';
import '../../composition/profile_input.dart';
import '../../scan/camera_permission.dart';
import '../../scan/scan_source.dart';
import '../../state/profile_scope.dart';
import '../composition/body_composition_screen.dart';
import 'body_size_check.dart';
import 'combined_scan_result_screen.dart';
import 'guided_scan_screen.dart';
import 'scan_screen.dart';

/// The scanning protocol: where the shell's Scan button lands.
///
/// Explains what to wear, the lighting, where the phone goes and the poses,
/// and the order of the two captures, then starts one guided session
/// ([GuidedScanScreen]). A session that fails or is cancelled comes back
/// here, says what happened, and can be started again from Step 1.
///
/// The two scans can still be run on their own from the links at the bottom,
/// as before.
class ScanChoiceScreen extends StatefulWidget {
  const ScanChoiceScreen({
    super.key,
    this.permission = const SystemCameraPermission(),
    this.createScanSource,
    this.createCompositionSource,
    this.loadModels,
    this.visualStore,
    this.handoff = const Duration(seconds: 3),
  });

  /// All swapped in tests; passed straight to the guided session.
  final CameraPermission permission;
  final ScanSource Function()? createScanSource;
  final CompositionSource Function(bool includePhotos)? createCompositionSource;
  final Future<CompositionModels> Function()? loadModels;
  final CompositionVisualStore? visualStore;
  final Duration handoff;

  @override
  State<ScanChoiceScreen> createState() => _ScanChoiceScreenState();
}

class _ScanChoiceScreenState extends State<ScanChoiceScreen> {
  /// Why the last session ended early, if it did.
  GuidedScanStopped? _stopped;

  Future<void> _start() async {
    final navigator = Navigator.of(context);
    // Height and weight first, filled in from the profile.
    if (!await confirmHeightAndWeight(context) || !mounted) return;
    setState(() => _stopped = null);
    final end = await navigator.push<GuidedScanEnd>(
      MaterialPageRoute(
        builder: (_) => GuidedScanScreen(
          permission: widget.permission,
          createScanSource: widget.createScanSource,
          createCompositionSource: widget.createCompositionSource,
          loadModels: widget.loadModels,
          visualStore: widget.visualStore,
          handoff: widget.handoff,
        ),
      ),
    );
    if (!mounted) return;
    switch (end) {
      case final GuidedScanFinished finished:
        // Back from the results goes to wherever Scan was opened from.
        await navigator.pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => CombinedScanResultScreen(
              session: finished,
              visualStore: widget.visualStore,
            ),
          ),
        );
      case final GuidedScanStopped stopped:
        setState(() => _stopped = stopped);
      case null:
        setState(() => _stopped = const GuidedScanStopped());
    }
  }

  void _openAlone(Widget screen) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => screen));

  /// The composition scan on its own also needs a current height and weight.
  Future<void> _openCompositionAlone() async {
    if (!await confirmHeightAndWeight(context) || !mounted) return;
    _openAlone(const BodyCompositionScreen());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = context
        .dependOnInheritedWidgetOfExactType<ProfileScope>()
        ?.notifier
        ?.profile;
    final input = profile == null ? null : compositionInputFrom(profile);
    final blocker = input == null
        ? 'The body composition step needs your sex set to Male or Female in '
              'your profile.'
        : input.problem;
    final stopped = _stopped;

    return Scaffold(
      appBar: AppBar(title: const Text('Scan')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (stopped != null)
            Card(
              key: const ValueKey('scan-session-ended'),
              margin: const EdgeInsets.only(bottom: 16),
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  stopped.cancelled
                      ? 'Scan cancelled. Nothing from it was saved.'
                      : "${stopped.failedStep} didn't finish"
                            "${stopped.reason == null ? '' : ': ${stopped.reason}'}"
                            '\n\nNothing from this scan was saved, and your '
                            'earlier results are unchanged. You can start '
                            'again from Step 1.',
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
            ),
          Text('Body scan', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Two steps, about two minutes. Results are saved only when both '
            'steps finish.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Text('Before you start', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const _Bullet(
            'Clothing: fitted clothes such as leggings or shorts and a fitted '
            'top. Loose clothes hide your outline and push estimates up.',
            icon: Icons.checkroom_outlined,
          ),
          const _Bullet(
            'Lighting: a bright, evenly lit room, with no strong light behind '
            'you, against a plain background.',
            icon: Icons.wb_sunny_outlined,
          ),
          const _Bullet(
            'Camera: prop the phone upright at about waist height, then step '
            'back until your whole body, head to feet, is in frame.',
            icon: Icons.phone_android,
          ),
          const _Bullet(
            'Stay in the same spot for both steps. The app tells you when to '
            'hold still and when to turn.',
            icon: Icons.accessibility_new,
          ),
          const SizedBox(height: 16),
          Text('The steps', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const _Bullet(
            'Step 1, body proportions: face the camera and hold still while '
            'it measures. Follow the prompts on screen.',
          ),
          const _Bullet(
            'Step 2, body composition: face the camera with your arms out '
            'about 30 degrees, then turn 90 degrees to your right, arms '
            'relaxed at your sides.',
          ),
          const _Bullet(
            'Then: results screen and your next steps.',
          ),
          if (blocker != null) ...[
            const SizedBox(height: 8),
            Text(
              blocker,
              key: const ValueKey('composition-blocker'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text('Run one scan on its own', style: theme.textTheme.titleSmall),
          Wrap(
            children: [
              TextButton(
                key: const ValueKey('choose-proportion-scan'),
                onPressed: () => _openAlone(const ScanScreen()),
                child: const Text('Body proportions only'),
              ),
              TextButton(
                key: const ValueKey('choose-body-composition'),
                onPressed: _openCompositionAlone,
                child: const Text('Body composition only'),
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            key: const ValueKey('start-guided-scan'),
            onPressed: blocker == null ? _start : null,
            child: Text(stopped == null ? 'Start Scan' : 'Start again'),
          ),
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text, {this.icon});

  final String text;

  /// Shown in place of the dot, so each tip can be spotted at a glance.
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon case final icon?) ...[
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
        ] else
          const Text('•  '),
        Expanded(child: Text(text)),
      ],
    ),
  );
}
