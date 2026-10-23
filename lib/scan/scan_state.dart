import '../models/measurement.dart';

/// Where the capture flow currently is. Mirrors CaptureSession.State on the
/// Android side ("guiding" covers both IDLE and POSITIONING).
enum ScanPhase { guiding, holding, measuring, done, failed }

/// One update from the capture flow.
///
/// Built straight from the native event map.
class ScanState {
  const ScanState({
    required this.phase,
    required this.message,
    this.holdProgress = 0,
    this.framesCaptured = 0,
    this.framesTotal = 20,
    this.failureReason,
    this.measurement,
  });

  final ScanPhase phase;

  /// Already worded for someone standing a few metres away: the Android side
  /// turns its own rejection reasons into guidance before sending them.
  final String message;

  /// 0-1. Fills the hold timer while the pose is steady.
  final double holdProgress;

  final int framesCaptured;
  final int framesTotal;

  /// Why a capture was abandoned. Also written to [message] by the native side.
  final String? failureReason;

  /// The finished scan. Only the final "done" event carries one.
  final Measurement? measurement;

  bool get hasMeasurement => measurement != null;

  static ScanPhase _phase(Object? raw) => switch (raw) {
    'holding' => ScanPhase.holding,
    'measuring' => ScanPhase.measuring,
    'done' => ScanPhase.done,
    'failed' => ScanPhase.failed,
    _ => ScanPhase.guiding,
  };

  static double _double(Object? raw, [double fallback = 0]) =>
      raw is num && raw.isFinite ? raw.toDouble() : fallback;

  static int _int(Object? raw, [int fallback = 0]) =>
      raw is num && raw.isFinite ? raw.toInt() : fallback;

  /// Reads one event from the native side. Anything missing or odd falls back
  /// to a safe value, so a bad event can never crash the screen.
  factory ScanState.fromEvent(Map<dynamic, dynamic> event) {
    final progress = _double(event['holdProgress']).clamp(0.0, 1.0);
    final total = _int(event['framesTotal'], 20);
    final captured = _int(
      event['framesCaptured'],
    ).clamp(0, total < 0 ? 0 : total);
    final reason = event['failureReason'];
    final raw = event['measurement'];
    return ScanState(
      phase: _phase(event['phase']),
      message: event['message'] is String ? event['message'] as String : '',
      holdProgress: progress.toDouble(),
      framesCaptured: captured.toInt(),
      framesTotal: total,
      failureReason: reason is String && reason.isNotEmpty ? reason : null,
      // The native side sends the whole measurement with the "done" event.
      measurement: raw is Map ? Measurement.fromNative(raw) : null,
    );
  }
}
