import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'scan_state.dart';

/// The boundary between Flutter and the native measurement pipeline.
///
/// Nothing above this line knows Kotlin exists. Swap [NativeScanSource] for
/// [MockScanSource] and the whole screen still works, which is how the scan
/// flow is tested without a device.
abstract class ScanSource {
  Stream<ScanState> get states;

  /// The live camera surface. For the mock, a placeholder panel.
  /// Only built once camera permission has been granted.
  Widget preview();

  void start();
  void switchCamera();
  void retry();
  void dispose();
}

/// Talks to the Android platform view and its two channels.
///
/// The contract, which matches ScanPreviewFactory.kt:
///   view type        anthrofit/scan_preview
///   methods          `anthrofit/scan_<id>`          start, switchCamera, retry
///   events           `anthrofit/scan_events_<id>`
class NativeScanSource implements ScanSource {
  static const String viewType = 'anthrofit/scan_preview';

  final StreamController<ScanState> _controller =
      StreamController<ScanState>.broadcast();

  MethodChannel? _methods;
  StreamSubscription<dynamic>? _events;

  /// start() is called before the platform view exists, so the request waits
  /// until the view reports its id.
  bool _startRequested = false;
  bool _disposed = false;

  @override
  Stream<ScanState> get states => _controller.stream;

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

    _methods = MethodChannel('anthrofit/scan_$id');
    _events = EventChannel('anthrofit/scan_events_$id')
        .receiveBroadcastStream()
        .listen(
          (event) {
            if (event is Map) _controller.add(ScanState.fromEvent(event));
          },
          onError: (Object error) {
            _controller.add(
              const ScanState(
                phase: ScanPhase.failed,
                message: 'The scan stopped unexpectedly',
                failureReason: 'The scan stopped unexpectedly',
              ),
            );
          },
        );

    if (_startRequested) _invoke('start');
  }

  /// Channel calls fail if the view has gone. Nothing useful can be done
  /// about that here, and the stream already reports real scan failures.
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
  void retry() => _invoke('retry');

  @override
  void dispose() {
    _disposed = true;
    _events?.cancel();
    _controller.close();
  }
}
