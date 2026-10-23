import 'dart:math' as math;

import 'pose_frame.dart';
import 'rep_signal.dart';

/// The counter's tuning.
///
/// APP PARAMETERS, NOT FROM A SOURCE. None of these numbers comes from a
/// study or a reference; they are starting values for the app, to be tuned
/// and validated against manual rep counts (for example, video of real sets
/// counted by a person) before any counting accuracy is reported.
///
/// The smoothing METHOD is published: the 1€ filter (Casiez, Roussel and
/// Vogel, "1€ Filter: A Simple Speed-based Low-pass Filter for Noisy Input
/// in Interactive Systems", CHI 2012). It smooths hard when the joint is
/// still (hiding landmark jitter) and hardly at all when it moves fast, so
/// a rep is not reported late. Its three values here are app starting
/// values, not the paper's.
class RepCounterSettings {
  const RepCounterSettings({
    this.minCutoffHz = 1.0,
    this.beta = 0.05,
    this.derivativeCutoffHz = 1.0,
    this.minRangeDegrees,
    this.maxAngleSpeedDegreesPerSecond = 1000,
    this.hysteresis = 0.3,
    this.minVisibility = 0.7,
    this.minRepMs = 180,
    this.maxRepMs = 10000,
    this.maxGapMs = 500,
    this.movementWindowMs = 1000,
    this.maxDriftTorsos = 1.0,
    this.maxSizeChange = 0.3,
  });

  /// 1€ filter: how much a still joint is smoothed. Lower is smoother.
  final double minCutoffHz;

  /// 1€ filter: how quickly smoothing lets go as the joint speeds up.
  /// Higher means less lag on fast reps, more jitter let through.
  final double beta;

  /// 1€ filter: smoothing of the speed estimate itself.
  final double derivativeCutoffHz;

  /// Overrides the joint's own [RepSignal.minRangeDegrees] when set.
  final double? minRangeDegrees;

  /// Rejects implausible single-frame landmark jumps before they can stretch
  /// the learned range. The 1€ filter remains the only temporal smoother.
  final double maxAngleSpeedDegreesPerSecond;

  /// How far into its own range the joint must go to reach an end of the
  /// movement: 0.3 means within the outer 30% at either end. The range is
  /// learned from this set's movement; joint-specific absolute endpoints
  /// still gate calibration.
  final double hysteresis;

  /// Landmarks MediaPipe rates below this visibility are ignored. The same
  /// cut-off the proportion scan uses (VIS_MIN in Measurement.kt), so the app
  /// has one visibility rule rather than two.
  final double minVisibility;

  // The guards below stop movement that is not exercise from being counted.
  // They need real timestamps and are skipped when frames carry none.

  /// Time spent outside the start-end band faster than this is treated as a
  /// twitch or landmark glitch.
  final int minRepMs;

  /// Time spent outside the start-end band longer than this is not counted.
  /// Long enough for a slow tempo and pauses between reps.
  final int maxRepMs;

  /// A gap this long with the joint out of view (walked out of frame, turned
  /// away) cancels the rep in progress.
  final int maxGapMs;

  /// The stretch of time over which walking around is looked for.
  final int movementWindowMs;

  /// Hips moving sideways across the image by more than this many torso
  /// lengths within [movementWindowMs] is walking, not a rep. Hinges and
  /// squats shift the hips far less; walking pace is about 2-3 torsos a
  /// second.
  final double maxDriftTorsos;

  /// The torso looking this much bigger or smaller (as a fraction) within
  /// [movementWindowMs] means walking towards or away from the phone.
  final double maxSizeChange;
}

/// The 1€ filter (Casiez et al., 2012), for one angle.
class _OneEuro {
  _OneEuro(this.settings);

  final RepCounterSettings settings;
  double? _x;
  double _dx = 0;
  int? _t;

  /// Frame gap used when timestamps do not move forward (made-up test
  /// poses): one thirtieth of a second. App value.
  static const double _fallbackDt = 1 / 30;

  static double _alpha(double cutoffHz, double dt) {
    final tau = 1 / (2 * math.pi * cutoffHz);
    return 1 / (1 + tau / dt);
  }

  double filter(double x, int timestampMs) {
    final last = _t;
    final dt = last == null || timestampMs <= last
        ? _fallbackDt
        : (timestampMs - last) / 1000;
    _t = timestampMs;
    final prev = _x;
    if (prev == null) {
      _x = x;
      return x;
    }
    final rawSpeed = (x - prev) / dt;
    _dx += _alpha(settings.derivativeCutoffHz, dt) * (rawSpeed - _dx);
    final cutoff = settings.minCutoffHz + settings.beta * _dx.abs();
    final value = prev + _alpha(cutoff, dt) * (x - prev);
    _x = value;
    return value;
  }

  void reset() {
    _x = null;
    _dx = 0;
    _t = null;
  }
}

enum _End { low, high }

/// Counts one side (left or right) of the body.
///
/// Self-calibrating: it learns the joint's range from the movement itself,
/// then requires both joint-specific endpoints before counting a return to
/// the start. The start end is the one the joint was at before it first moved.
///
/// After [interrupt] (walking around, out of view) the joint must come back
/// to the start end before the next rep can begin, so half a movement made
/// while not exercising is never finished off into a rep.
class _SideCounter {
  _SideCounter(this.settings, this.signal)
    : minRange = settings.minRangeDegrees ?? signal.minRangeDegrees,
      _filter = _OneEuro(settings);

  final RepCounterSettings settings;
  final RepSignal signal;
  final double minRange;
  final _OneEuro _filter;

  double? _lastRaw;
  int? _lastRawMs;
  double? _min;
  double? _max;
  _End? _start;
  _End? _at;

  /// Set by [interrupt]: no rep until the joint is back at the start end.
  bool _rearm = false;

  /// The last frame time the joint was at the start end, and the last frame
  /// time it was seen at all. Null until known.
  int? _atStartMs;
  int? _lastMs;

  /// When the lowest and highest angles so far were last reached.
  int? _minMs;
  int? _maxMs;
  int reps = 0;

  /// Frames where this side's joint was visible.
  int seen = 0;

  /// The smoothed angle, for display and tests.
  double? smoothed;

  double get range => (_max ?? 0) - (_min ?? 0);

  /// Abandons the rep in progress, if any.
  void interrupt() {
    if (_start == null && _min == null && _max == null) return;
    _filter.reset();
    _lastRaw = null;
    _lastRawMs = null;
    smoothed = null;
    if (_start != null) {
      _rearm = true;
    } else {
      _min = null;
      _max = null;
      _at = null;
      _minMs = null;
      _maxMs = null;
    }
  }

  void add(double angle, int timestampMs) {
    final last = _lastMs;
    final timed = last != null && timestampMs > last;
    if (timed && timestampMs - last > settings.maxGapMs) interrupt();
    final rawMs = _lastRawMs;
    final raw = _lastRaw;
    if (raw != null) {
      final deltaMs = rawMs != null && timestampMs > rawMs
          ? timestampMs - rawMs
          : 1000 / 30;
      final speed = (angle - raw).abs() / (deltaMs / 1000);
      if (speed > settings.maxAngleSpeedDegreesPerSecond) return;
    }
    if (last == null || timestampMs > last) _lastMs = timestampMs;
    seen++;
    _lastRaw = angle;
    _lastRawMs = timestampMs;
    final value = _filter.filter(angle, timestampMs);
    smoothed = value;
    if (_min == null || value <= _min!) {
      _min = value;
      _minMs = timestampMs;
    }
    if (_max == null || value >= _max!) {
      _max = value;
      _maxMs = timestampMs;
    }

    final range = _max! - _min!;
    if (range < minRange ||
        _min! > signal.maxFlexedAngle ||
        _max! < signal.minExtendedAngle) {
      return;
    }

    final band = settings.hysteresis * range;
    final _End? end = value <= _min! + band
        ? _End.low
        : value >= _max! - band
        ? _End.high
        : null;
    if (end == null) return;

    if (_start == null) {
      // The range has just become big enough, so the joint is moving away
      // from where it began: it began at the other end.
      _start = end == _End.low ? _End.high : _End.low;
      _at = end;
      // It was last at the start end when that extreme was last reached.
      _atStartMs = _start == _End.high ? _maxMs : _minMs;
      return;
    }
    if (_rearm) {
      if (end != _start) return;
      _rearm = false;
      _at = end;
      _atStartMs = timestampMs;
      return;
    }
    if (end == _at) {
      if (end == _start) _atStartMs = timestampMs;
      return;
    }
    _at = end;
    if (end != _start) return;
    final began = _atStartMs;
    _atStartMs = timestampMs;
    // Only judged when the frames carry real time.
    if (began != null && timestampMs > began) {
      final took = timestampMs - began;
      if (took < settings.minRepMs || took > settings.maxRepMs) return;
    }
    reps++;
  }

  void reset() {
    _filter.reset();
    _lastRaw = null;
    _lastRawMs = null;
    _min = null;
    _max = null;
    _start = null;
    _at = null;
    _rearm = false;
    _atStartMs = null;
    _lastMs = null;
    _minMs = null;
    _maxMs = null;
    reps = 0;
    seen = 0;
    smoothed = null;
  }
}

/// Counts reps from a stream of poses by following one joint angle on each
/// side of the body ([RepSignal]).
///
/// Both sides are counted separately and ONE is reported: the side that
/// moves more, as long as the camera saw it at least half as often as the
/// other side. The side turned away from the camera is often half hidden,
/// and its jittery landmarks used to add reps that never happened when the
/// higher count was reported. One-arm and one-leg work still counts on the
/// side that moves; alternating exercises report one side's reps.
/// APP DESIGN RULE, NOT FROM A SOURCE.
///
/// Nothing is counted while the person walks about (across the image, or
/// towards or away from the phone): joint angles alone cannot tell a step
/// from a squat, so the rep in progress is dropped instead.
class RepCounter {
  RepCounter(this.signal, {this.settings = const RepCounterSettings()})
    : _left = _SideCounter(settings, signal),
      _right = _SideCounter(settings, signal);

  final RepSignal signal;
  final RepCounterSettings settings;
  final _SideCounter _left;
  final _SideCounter _right;

  bool _inView = false;
  bool _moving = false;

  /// Recent body positions, oldest first, within [RepCounterSettings
  /// .movementWindowMs] of the newest.
  final List<(int, PoseBody)> _track = [];

  /// Whether the person is walking about, so nothing is being counted.
  bool get moving => _moving;

  int get reps => _reported.reps;

  _SideCounter get _reported {
    final l = _left, r = _right;
    // A side seen in fewer than half as many frames is not trusted.
    if (l.seen * 2 < r.seen) return r;
    if (r.seen * 2 < l.seen) return l;
    if (l.range != r.range) return l.range > r.range ? l : r;
    return l.reps >= r.reps ? l : r;
  }

  /// Whether the last frame showed the joint on at least one side.
  bool get inView => _inView;

  void add(PoseFrame frame) {
    final l = signal.angle(
      frame,
      leftSide: true,
      minVisibility: settings.minVisibility,
    );
    final r = signal.angle(
      frame,
      leftSide: false,
      minVisibility: settings.minVisibility,
    );
    _inView = l != null || r != null;
    _moving = _isMoving(frame);
    if (_moving) {
      _left.interrupt();
      _right.interrupt();
      return;
    }
    if (l != null) _left.add(l, frame.timestampMs);
    if (r != null) _right.add(r, frame.timestampMs);
  }

  bool _isMoving(PoseFrame frame) {
    final body = frame.body;
    final now = frame.timestampMs;
    // Unknown position or no real time: cannot judge, so do not block.
    if (body == null ||
        !body.isValid ||
        (_track.isNotEmpty && now <= _track.last.$1)) {
      if (body == null || !body.isValid) _track.clear();
      return false;
    }
    _track.add((now, body));
    while (now - _track.first.$1 > settings.movementWindowMs) {
      _track.removeAt(0);
    }
    final (_, then) = _track.first;
    final drift = (body.hipX - then.hipX).abs() / ((body.torso + then.torso) / 2);
    final size = body.torso / then.torso - 1;
    return drift > settings.maxDriftTorsos || size.abs() > settings.maxSizeChange;
  }

  void reset() {
    _left.reset();
    _right.reset();
    _inView = false;
    _moving = false;
    _track.clear();
  }
}
