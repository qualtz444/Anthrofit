import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'mask_codec.dart';
import 'silhouette_features.dart';

/// Where the body-composition capture is. Mirrors the "phase" values sent by
/// CompositionPreview.kt.
enum CompositionPhase { positioning, holding, confirmed, done, failed }

/// One update from the composition capture.
class CompositionCaptureState {
  const CompositionCaptureState({
    required this.phase,
    this.step = 'front',
    this.stepIndex = 0,
    this.stepCount = 2,
    this.title = '',
    this.message = '',
    this.holdProgress = 0,
    this.front = const [],
    this.side = const [],
    this.frontPhoto,
    this.sidePhoto,
    this.failureReason,
  });

  final CompositionPhase phase;

  /// "front" or "side".
  final String step;
  final int stepIndex;
  final int stepCount;

  /// Already worded on the Android side, e.g. "Face the camera".
  final String title;
  final String message;

  /// 0-1 while the pose is held still.
  final double holdProgress;

  /// Only filled on "done". Masks that fail to decode are dropped.
  final List<SilhouetteMask> front;
  final List<SilhouetteMask> side;

  /// JPEGs of the best front and side frames.
  final Uint8List? frontPhoto;
  final Uint8List? sidePhoto;

  final String? failureReason;

  static Uint8List? _photo(Object? value) {
    if (value is Uint8List) return value.isEmpty ? null : value;
    if (value is List<int>) return value.isEmpty ? null : Uint8List.fromList(value);
    return null;
  }

  static CompositionPhase _phase(Object? value) => switch (value) {
    'holding' => CompositionPhase.holding,
    'confirmed' => CompositionPhase.confirmed,
    'done' => CompositionPhase.done,
    'failed' => CompositionPhase.failed,
    _ => CompositionPhase.positioning,
  };

  static List<SilhouetteMask> _masks(Object? value) {
    if (value is! List) return const [];
    final masks = <SilhouetteMask>[];
    for (final item in value) {
      if (item is! List) continue;
      final mask = decodeRunMask(item.whereType<int>().toList(growable: false));
      if (mask != null) masks.add(mask);
    }
    return masks;
  }

  factory CompositionCaptureState.fromEvent(Map<dynamic, dynamic> event) {
    final hold = event['holdProgress'];
    return CompositionCaptureState(
      phase: _phase(event['phase']),
      step: event['step'] as String? ?? 'front',
      stepIndex: (event['stepIndex'] as num?)?.toInt() ?? 0,
      stepCount: (event['stepCount'] as num?)?.toInt() ?? 2,
      title: event['title'] as String? ?? '',
      message: event['message'] as String? ?? '',
      holdProgress: hold is num ? hold.toDouble().clamp(0.0, 1.0) : 0,
      front: _masks(event['front']),
      side: _masks(event['side']),
      frontPhoto: _photo(event['frontPhoto']),
      sidePhoto: _photo(event['sidePhoto']),
      failureReason: event['failureReason'] as String?,
    );
  }
}

/// The boundary between Flutter and the native composition capture, so the
/// screen can be tested with a fake.
abstract class CompositionSource {
  Stream<CompositionCaptureState> get states;

  /// The live camera surface. Only built once camera permission is granted.
  Widget preview();

  void start();
  void retry();
  void dispose();
}

/// Talks to CompositionPreview.kt.
///
///   view type   anthrofit/composition_preview
///   methods     `anthrofit/composition_<id>`         start, retry
///   events      `anthrofit/composition_events_<id>`
class NativeCompositionSource implements CompositionSource {
  NativeCompositionSource();

  static const String viewType = 'anthrofit/composition_preview';

  final StreamController<CompositionCaptureState> _controller =
      StreamController<CompositionCaptureState>.broadcast();

  MethodChannel? _methods;
  StreamSubscription<dynamic>? _events;
  bool _startRequested = false;
  bool _disposed = false;

  @override
  Stream<CompositionCaptureState> get states => _controller.stream;

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
              creationParams: <String, dynamic>{
                'includePhotos': true,
              },
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
    _methods = MethodChannel('anthrofit/composition_$id');
    _events = EventChannel('anthrofit/composition_events_$id')
        .receiveBroadcastStream()
        .listen(
          (event) {
            if (event is Map && !_controller.isClosed) {
              _controller.add(CompositionCaptureState.fromEvent(event));
            }
          },
          onError: (Object error) {
            if (_controller.isClosed) return;
            _controller.add(
              const CompositionCaptureState(
                phase: CompositionPhase.failed,
                message: 'The capture stopped unexpectedly',
                failureReason: 'The capture stopped unexpectedly',
              ),
            );
          },
        );
    // The Kotlin side starts its own capture once the detector is ready;
    // "start" here is harmless if it already has.
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
  void retry() => _invoke('retry');

  @override
  void dispose() {
    _disposed = true;
    _events?.cancel();
    _controller.close();
  }
}
