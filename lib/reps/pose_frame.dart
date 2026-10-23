import 'dart:math' as math;

/// One body landmark from MediaPipe Pose Landmarker, in its "world"
/// coordinates: metres, centred between the hips, so angles do not depend
/// on how far the person stands from the camera.
class PoseLandmark {
  const PoseLandmark(this.x, this.y, this.z, this.visibility);

  final double x;
  final double y;
  final double z;

  /// 0-1, MediaPipe's own estimate that the point is visible.
  final double visibility;

  bool get isValid =>
      x.isFinite &&
      y.isFinite &&
      z.isFinite &&
      visibility.isFinite &&
      visibility >= 0 &&
      visibility <= 1;
}

/// The 33-point MediaPipe Pose landmark indices used here (from the
/// MediaPipe Pose Landmarker model card).
abstract final class PoseIndex {
  static const leftShoulder = 11;
  static const rightShoulder = 12;
  static const leftElbow = 13;
  static const rightElbow = 14;
  static const leftWrist = 15;
  static const rightWrist = 16;
  static const leftHip = 23;
  static const rightHip = 24;
  static const leftKnee = 25;
  static const rightKnee = 26;
  static const leftAnkle = 27;
  static const rightAnkle = 28;
  static const leftFootIndex = 31;
  static const rightFootIndex = 32;

  static const int count = 33;
}

/// Where the body sits in the camera image, so walking around can be told
/// apart from exercising (world landmarks are hip-centred and cannot show
/// it). All three values are in image heights, so they compare across axes.
class PoseBody {
  const PoseBody(this.hipX, this.hipY, this.torso);

  /// Midpoint of the hips.
  final double hipX;
  final double hipY;

  /// Shoulder midpoint to hip midpoint: grows as the person comes closer.
  final double torso;

  bool get isValid =>
      hipX.isFinite && hipY.isFinite && torso.isFinite && torso > 0;
}

/// One camera frame's pose, or no pose when nobody was found.
class PoseFrame {
  const PoseFrame({
    required this.landmarks,
    required this.timestampMs,
    this.body,
  });

  /// Empty when no person was detected in this frame.
  final List<PoseLandmark> landmarks;
  final int timestampMs;

  /// Null when the hips and shoulders were not clearly visible.
  final PoseBody? body;

  bool get hasPose => landmarks.length == PoseIndex.count;

  /// Reads one native event: `{'timestampMs': int, 'landmarks': [[x, y, z,
  /// visibility] x 33], 'body': [hipX, hipY, torso]}`, with `landmarks`
  /// missing or empty for no pose and `body` missing when not clearly seen.
  /// Anything malformed is read as "no pose" rather than guessed at.
  factory PoseFrame.fromEvent(Map<dynamic, dynamic> event) {
    final time = event['timestampMs'];
    final raw = event['landmarks'];
    final rawBody = event['body'];
    final body =
        rawBody is List &&
            rawBody.length == 3 &&
            rawBody.every((v) => v is num && v.isFinite) &&
            (rawBody[2] as num) > 0
        ? PoseBody(
            (rawBody[0] as num).toDouble(),
            (rawBody[1] as num).toDouble(),
            (rawBody[2] as num).toDouble(),
          )
        : null;
    final points = <PoseLandmark>[];
    if (raw is List && raw.length == PoseIndex.count) {
      for (final p in raw) {
        if (p is! List || p.length < 4 || p.any((v) => v is! num)) {
          points.clear();
          break;
        }
        final point = PoseLandmark(
          (p[0] as num).toDouble(),
          (p[1] as num).toDouble(),
          (p[2] as num).toDouble(),
          (p[3] as num).toDouble(),
        );
        if (!point.isValid) {
          points.clear();
          break;
        }
        points.add(point);
      }
    }
    return PoseFrame(
      landmarks: points,
      timestampMs: time is num ? time.toInt() : 0,
      body: points.isEmpty ? null : body,
    );
  }
}

/// The angle at [b], in degrees (0-180), between the segments to [a] and
/// [c]. Null when either segment has no length.
double? jointAngle(PoseLandmark a, PoseLandmark b, PoseLandmark c) {
  if (!a.isValid || !b.isValid || !c.isValid) return null;
  final ux = a.x - b.x, uy = a.y - b.y, uz = a.z - b.z;
  final vx = c.x - b.x, vy = c.y - b.y, vz = c.z - b.z;
  final lu = math.sqrt(ux * ux + uy * uy + uz * uz);
  final lv = math.sqrt(vx * vx + vy * vy + vz * vz);
  if (lu == 0 || lv == 0) return null;
  final cos = ((ux * vx + uy * vy + uz * vz) / (lu * lv)).clamp(-1.0, 1.0);
  return math.acos(cos) * 180 / math.pi;
}
