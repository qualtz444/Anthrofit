import '../core/id.dart';
import '../core/json_utils.dart';

/// How repeatable one ratio was across the frames of a single capture.
/// Straight from the native side; nothing is recalculated here.
class MeasurementPrecision {
  const MeasurementPrecision({
    required this.iqr,
    required this.iqrPct,
    required this.min,
    required this.max,
  });

  /// Interquartile range of this ratio across the usable frames.
  final double iqr;

  /// The same spread as a percentage of the median.
  final double iqrPct;

  final double min;
  final double max;

  factory MeasurementPrecision.fromJson(Map<String, dynamic> json) =>
      MeasurementPrecision(
        iqr: parseDouble(json['iqr']),
        iqrPct: parseDouble(json['iqrPct']),
        min: parseDouble(json['min']),
        max: parseDouble(json['max']),
      );

  Map<String, dynamic> toJson() => {
    'iqr': iqr,
    'iqrPct': iqrPct,
    'min': min,
    'max': max,
  };
}

/// One finished scan, exactly as the native pipeline reported it.
///
/// [ratios] are unitless body proportions keyed by the pipeline's own ids
/// (for example "femur_torso_ratio"). There is no metric calibration anywhere
/// in the pipeline, so nothing here is a length in centimetres.
///
/// Values are stored under the native keys, never under display labels, so
/// wording can change without touching a saved scan and a key the app does
/// not recognise yet still survives.
class Measurement {
  const Measurement({
    required this.id,
    required this.takenAt,
    required this.ratios,
    required this.precision,
    required this.framesUsed,
    required this.framesTotal,
    required this.worstIqrPct,
    required this.captureQuality,
  });

  /// Local id, made when the scan arrives. The pipeline does not supply one.
  final String id;

  final DateTime takenAt;

  /// Ratio id -> median value across the usable frames.
  final Map<String, double> ratios;

  /// Ratio id -> how much that ratio varied. May be missing for a ratio.
  final Map<String, MeasurementPrecision> precision;

  /// How many frames produced a usable pose, out of how many were recorded.
  final int framesUsed;
  final int framesTotal;

  /// The widest spread of any ratio, as a percentage. Lower is steadier.
  final double worstIqrPct;

  /// The pipeline's own verdict: "good", "acceptable" or "unstable".
  /// Kept as the native string rather than an enum, so a new value from a
  /// later pipeline still arrives intact.
  final String captureQuality;

  bool get isEmpty => ratios.isEmpty;

  /// Reads the native payload. Anything missing or malformed is dropped
  /// rather than throwing, so one odd value cannot lose a whole scan.
  factory Measurement.fromNative(Map<dynamic, dynamic> raw) {
    final ratios = <String, double>{};
    final rawRatios = raw['ratios'];
    if (rawRatios is Map) {
      rawRatios.forEach((key, value) {
        if (key is String && value is num && value.isFinite) {
          ratios[key] = value.toDouble();
        }
      });
    }

    final precision = <String, MeasurementPrecision>{};
    final rawPrecision = raw['precision'];
    if (rawPrecision is Map) {
      rawPrecision.forEach((key, value) {
        if (key is String && value is Map) {
          precision[key] = MeasurementPrecision.fromJson(
            Map<String, dynamic>.from(value),
          );
        }
      });
    }

    final takenAt = raw['takenAt'];
    final savedId = raw['id'];
    return Measurement(
      id: savedId is String && savedId.isNotEmpty ? savedId : generateId(),
      takenAt: takenAt is num
          ? DateTime.fromMillisecondsSinceEpoch(takenAt.toInt())
          : DateTime.now(),
      ratios: ratios,
      precision: precision,
      framesUsed: parseInt(raw['framesUsed']),
      framesTotal: parseInt(raw['framesTotal']),
      worstIqrPct: parseDouble(raw['worstIqrPct']),
      captureQuality: parseString(raw['captureQuality']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'takenAt': takenAt.millisecondsSinceEpoch,
    'ratios': ratios,
    'precision': precision.map((k, v) => MapEntry(k, v.toJson())),
    'framesUsed': framesUsed,
    'framesTotal': framesTotal,
    'worstIqrPct': worstIqrPct,
    'captureQuality': captureQuality,
  };

  factory Measurement.fromJson(Map<String, dynamic> json) =>
      Measurement.fromNative(json);
}
