import 'dart:async';

import 'package:flutter/material.dart';

import '../models/measurement.dart';
import 'scan_source.dart';
import 'scan_state.dart';

/// Walks through the same phases on a timer, so the scan screen can be built,
/// demoed and tested with no device and no MediaPipe.
///
/// The timings are only there to make the screen move. They are not the real
/// pipeline's timings, which come from CaptureSession (a 1.5 s hold, then 20
/// frames).
class MockScanSource implements ScanSource {
  MockScanSource({this.failInstead = false});

  /// Ends in [ScanPhase.failed] instead of a measurement, so the failure state
  /// can be checked without breaking a real scan.
  final bool failInstead;

  static const Duration tick = Duration(milliseconds: 120);
  static const int _guidingTicks = 10;
  static const int _holdingTicks = 13;
  static const int _frames = 20;

  final StreamController<ScanState> _controller =
      StreamController<ScanState>.broadcast();
  Timer? _timer;
  int _tick = 0;
  bool _isFrontCamera = false;

  @override
  Stream<ScanState> get states => _controller.stream;

  @override
  Widget preview() => Container(
    color: const Color(0xFF14171A),
    alignment: Alignment.center,
    child: const Text(
      'Camera preview\n(mock scan)',
      textAlign: TextAlign.center,
      style: TextStyle(color: Colors.white24, fontSize: 16),
    ),
  );

  @override
  void start() {
    _tick = 0;
    _timer?.cancel();
    _timer = Timer.periodic(tick, _step);
  }

  @override
  void switchCamera() {
    _isFrontCamera = !_isFrontCamera;
    _controller.add(
      ScanState(
        phase: ScanPhase.guiding,
        message: 'Switched to ${_isFrontCamera ? 'front' : 'back'} camera',
      ),
    );
  }

  @override
  void retry() => start();

  void _step(Timer _) {
    if (_controller.isClosed) return;
    _tick++;

    const holdingEnd = _guidingTicks + _holdingTicks;
    const measuringEnd = holdingEnd + _frames;

    if (_tick <= _guidingTicks) {
      _controller.add(
        const ScanState(
          phase: ScanPhase.guiding,
          message: 'Step back so your whole body fits',
        ),
      );
    } else if (_tick <= holdingEnd) {
      _controller.add(
        ScanState(
          phase: ScanPhase.holding,
          message: 'Hold still',
          holdProgress: (_tick - _guidingTicks) / _holdingTicks,
        ),
      );
    } else if (_tick <= measuringEnd) {
      _controller.add(
        ScanState(
          phase: ScanPhase.measuring,
          message: 'Measuring - keep still',
          holdProgress: 1,
          framesCaptured: _tick - holdingEnd,
          framesTotal: _frames,
        ),
      );
    } else {
      _timer?.cancel();
      _controller.add(
        failInstead
            ? const ScanState(
                phase: ScanPhase.failed,
                message: 'Only 8 of 20 frames were usable',
                failureReason:
                    'Only 8 of 20 frames were usable. Most common '
                    'problem: subject not square to camera',
              )
            : ScanState(
                phase: ScanPhase.done,
                message: 'Done',
                framesCaptured: _frames,
                framesTotal: _frames,
                measurement: mockMeasurement(),
              ),
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.close();
  }
}

/// A stand-in result, so the result screen can be built and tested without a
/// device. The numbers are made up for the mock only: nothing in the app
/// treats them as real, and the native pipeline never uses this.
Measurement mockMeasurement() => Measurement.fromNative({
  'takenAt': DateTime.now().millisecondsSinceEpoch,
  'ratios': {
    'femur_torso_ratio': 1.08,
    'arm_torso_ratio': 1.31,
    'upperbody_stature_ratio': 0.52,
    'lm_shoulder_hip_ratio': 1.42,
    'sil_shoulder_hip_ratio': 1.39,
    'sil_waist_hip_ratio': 0.84,
    'sil_waist_chest_ratio': 0.81,
  },
  'precision': {
    'femur_torso_ratio': {'iqr': 0.01, 'iqrPct': 0.9, 'min': 1.07, 'max': 1.09},
    'arm_torso_ratio': {'iqr': 0.02, 'iqrPct': 1.5, 'min': 1.29, 'max': 1.33},
    'lm_shoulder_hip_ratio': {
      'iqr': 0.04,
      'iqrPct': 2.8,
      'min': 1.39,
      'max': 1.45,
    },
  },
  'framesUsed': 18,
  'framesTotal': 20,
  'worstIqrPct': 2.8,
  'captureQuality': 'acceptable',
});
