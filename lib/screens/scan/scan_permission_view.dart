import 'package:flutter/material.dart';

import '../../scan/camera_permission.dart';

/// Shown instead of the preview when the camera cannot be used.
///
/// Refused once -> explain and let them ask again.
/// Refused for good -> the system dialog will not appear again, so the only
/// way forward is Settings, and the screen says so plainly.
class ScanPermissionView extends StatelessWidget {
  const ScanPermissionView({
    super.key,
    required this.access,
    required this.busy,
    required this.onRequest,
    required this.onOpenSettings,
    this.purpose =
        'ANTHROFIT measures your body proportions from the camera. '
        'Nothing is recorded or uploaded: only the measurements are kept, on '
        'this device.',
  });

  /// Why the camera is needed and what is kept. Each scan states its own.
  final String purpose;

  final CameraAccess access;
  final bool busy;
  final VoidCallback onRequest;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final blocked = access == CameraAccess.permanentlyDenied;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.photo_camera_outlined,
              color: Colors.white70,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              'Camera access is needed to scan',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              blocked
                  ? 'Camera access is turned off for ANTHROFIT. Open Settings '
                        'and allow the camera, then come back to this screen.'
                  : purpose,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 24),
            if (blocked)
              FilledButton(
                onPressed: onOpenSettings,
                child: const Text('Open Settings'),
              )
            else
              FilledButton(
                onPressed: busy ? null : onRequest,
                child: const Text('Allow camera'),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Not now',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'The rest of ANTHROFIT works without the camera.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }
}
