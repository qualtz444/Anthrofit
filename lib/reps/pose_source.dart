import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'pose_frame.dart';

/// Whether the Android side of the live pose stream is registered
/// (PosePreviewFactory.kt, in MainActivity). Set it back to false to offer
/// the tap counter only: creating a platform view whose type is not
/// registered fails on the device.
const bool kNativePoseStreamReady = true;

/// The boundary between Flutter and a live MediaPipe pose stream, the same
/// way `ScanSource` is for the proportion scan. Tests and demos use
/// [MockPoseSource].
abstract class PoseSource {
  Stream<PoseFrame> get frames;

  /// The live camera surface. Only built once camera permission is granted.
  Widget preview();

  void start();
  void switchCamera();
  void dispose();
}

/// Talks to the Android platform view and its two channels.
///
/// The contract, which matches PosePreviewFactory.kt:
///   view type   anthrofit/pose_preview
///   methods     `anthrofit/pose_<id>`         start, switchCamera
///   events      `anthrofit/pose_events_<id>`  one map per processed frame:
///     {'timestampMs': int,
///      'landmarks': [[x, y, z, visibility] x 33]}   world landmarks, metres
///   with 'landmarks' empty when no person is found.
class NativePoseSource implements PoseSource {
  static const String viewType = 'anthrofit/pose_preview';

  final StreamController<PoseFrame> _controller =
      StreamController<PoseFrame>.broadcast();

  MethodChannel? _methods;
  StreamSubscription<dynamic>? _events;
  bool _startRequested = false;
  bool _disposed = false;

  @override
  Stream<PoseFrame> get frames => _controller.stream;

  @override
  Widget preview() => PlatformViewLink(
    viewType: viewType,
    surfaceFactory: (context, controller) => AndroidViewSurface(
      controller: controller as AndroidViewController,
      gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
      hitTestBehavior: PlatformViewHitTestBehavior.transparent,
    ),
    onCreatePlatformView: (params) {
      final controller =
          PlatformViewsService.initExpensiveAndroidView(
              id: params.id,
              viewType: viewType,
              layoutDirection: TextDirection.ltr,
              creationParams: const <String, dynamic>{},
              creationParamsCodec: const StandardMessageCodec(),
              onFocus: () => params.onFocusChanged(true),
            )
            ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
            ..addOnPlatformViewCreatedListener(_onViewCreated)
            ..create();
      return controller;
    },
  );

  void _onViewCreated(int id) {
    if (_disposed) return;
    _methods = MethodChannel('anthrofit/pose_$id');
    _events = EventChannel('anthrofit/pose_events_$id')
        .receiveBroadcastStream()
        .listen(
          (event) {
            if (event is Map) _controller.add(PoseFrame.fromEvent(event));
          },
          // A broken stream reads as "nobody in view"; the user can still
          // correct the count by hand.
          onError: (Object _) {},
        );
    if (_startRequested) _invoke('start');
  }

  void _invoke(String method) {
    _methods?.invokeMethod<void>(method).catchError((Object _) {});
  }

  @override
  void start() {
    _startRequested = true;
    _invoke('start');
  }

  @override
  void switchCamera() => _invoke('switchCamera');

  @override
  void dispose() {
    _disposed = true;
    _events?.cancel();
    _controller.close();
  }
}

/// A person doing slow squats, on a timer, so the screen can be demoed and
/// tested with no device. The motion is made up; only the counting is real.
class MockPoseSource implements PoseSource {
  MockPoseSource({this.period = const Duration(seconds: 2)});

  /// One rep takes this long.
  final Duration period;

  static const Duration tick = Duration(milliseconds: 50);

  final StreamController<PoseFrame> _controller =
      StreamController<PoseFrame>.broadcast();
  Timer? _timer;
  int _ms = 0;

  @override
  Stream<PoseFrame> get frames => _controller.stream;

  @override
  Widget preview() => const ColoredBox(
    color: Color(0xFF14171A),
    child: Center(
      child: Text(
        'Camera preview\n(mock)',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white24),
      ),
    ),
  );

  @override
  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(tick, (_) {
      if (_controller.isClosed) return;
      _ms += tick.inMilliseconds;
      _controller.add(squatFrame(_ms, period.inMilliseconds));
    });
  }

  @override
  void switchCamera() {}

  @override
  void dispose() {
    _timer?.cancel();
    _controller.close();
  }

  /// A pose whose knees bend between about 170 and 90 degrees, once every
  /// [periodMs], starting straight.
  static PoseFrame squatFrame(int ms, int periodMs) {
    final phase = (ms % periodMs) / periodMs * 2 * math.pi;
    final knee = 130 + 40 * math.cos(phase); // 170 -> 90 -> 170
    final rad = (180 - knee) * math.pi / 180;
    const thigh = 0.45;
    final points = List.filled(
      PoseIndex.count,
      const PoseLandmark(0, 0, 0, 0),
    );
    void put(int i, double x, double y) =>
        points[i] = PoseLandmark(x, y, 0, 0.99);
    for (final (hip, kneeI, ankle) in [
      (PoseIndex.leftHip, PoseIndex.leftKnee, PoseIndex.leftAnkle),
      (PoseIndex.rightHip, PoseIndex.rightKnee, PoseIndex.rightAnkle),
    ]) {
      put(hip, 0, 0);
      put(kneeI, 0, thigh);
      // The shin turns away from the thigh's line by (180 - knee) degrees.
      put(ankle, thigh * math.sin(rad), thigh + thigh * math.cos(rad));
    }
    return PoseFrame(landmarks: points, timestampMs: ms);
  }
}
