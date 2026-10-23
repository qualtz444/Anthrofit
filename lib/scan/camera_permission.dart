import 'package:permission_handler/permission_handler.dart';

/// What the app may do with the camera right now.
enum CameraAccess {
  /// Not asked yet, or asked and dismissed. Asking again will show the dialog.
  notRequested,

  /// Granted. The camera preview may be created.
  granted,

  /// Refused this time. Asking again is allowed.
  denied,

  /// Refused for good (or blocked by device policy). Only Settings can change
  /// it, so the app must send the user there instead of asking again.
  permanentlyDenied,
}

/// The one place that talks to the permission plugin, so the scan screen can
/// be tested with a fake.
abstract class CameraPermission {
  /// The current state, without showing a dialog.
  Future<CameraAccess> check();

  /// Shows the system dialog if that is still possible.
  Future<CameraAccess> request();

  /// Opens the app's page in system Settings. True if it opened.
  Future<bool> openSettings();
}

/// The real one, backed by permission_handler.
class SystemCameraPermission implements CameraPermission {
  const SystemCameraPermission();

  static CameraAccess _map(PermissionStatus status) {
    if (status.isGranted || status.isLimited) return CameraAccess.granted;
    if (status.isPermanentlyDenied || status.isRestricted) {
      return CameraAccess.permanentlyDenied;
    }
    if (status.isDenied) return CameraAccess.denied;
    return CameraAccess.notRequested;
  }

  @override
  Future<CameraAccess> check() async {
    final status = await Permission.camera.status;
    // "denied" before the first ask means the dialog has never been shown.
    if (status.isDenied &&
        !await Permission.camera.shouldShowRequestRationale) {
      return CameraAccess.notRequested;
    }
    return _map(status);
  }

  @override
  Future<CameraAccess> request() async =>
      _map(await Permission.camera.request());

  @override
  Future<bool> openSettings() => openAppSettings();
}

/// Makes sure the camera can be opened, asking once if it has not been
/// asked. The caller says what to do when the answer is not granted.
Future<CameraAccess> ensureCameraAccess([
  CameraPermission permission = const SystemCameraPermission(),
]) async {
  var access = await permission.check();
  if (access == CameraAccess.notRequested || access == CameraAccess.denied) {
    access = await permission.request();
  }
  return access;
}
