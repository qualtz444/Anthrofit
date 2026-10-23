import '../models/measurement.dart';

// How each ratio is worded on screen. Kept in one place so the measurement
// pipeline never has to know how anything is phrased, and so a new ratio only
// needs a line here.

/// A ratio the app knows how to describe.
class RatioInfo {
  const RatioInfo({
    required this.key,
    required this.name,
    required this.note,
    required this.fromSilhouette,
  });

  /// The pipeline's own id, for example "femur_torso_ratio".
  final String key;

  final String name;

  /// Plain-language explanation of what the number compares.
  final String note;

  /// True for measurements taken from the body outline rather than the
  /// skeleton. Grouped separately because the two are measured differently.
  final bool fromSilhouette;
}

const List<RatioInfo> kKnownRatios = [
  RatioInfo(
    key: 'femur_torso_ratio',
    name: 'Femur to torso',
    note:
        'Your thigh measured against your trunk. A higher value means a '
        'proportionally longer thigh.',
    fromSilhouette: false,
  ),
  RatioInfo(
    key: 'arm_torso_ratio',
    name: 'Arm to torso',
    note:
        'Your full arm measured against your trunk. A higher value means a '
        'proportionally longer arm.',
    fromSilhouette: false,
  ),
  RatioInfo(
    key: 'upperbody_stature_ratio',
    name: 'Upper body to stature',
    note: 'Head-to-hip length as a share of your standing height.',
    fromSilhouette: false,
  ),
  RatioInfo(
    key: 'lm_shoulder_hip_ratio',
    name: 'Shoulder to hip',
    note:
        'The distance between your shoulder joints against the distance '
        'between your hip joints.',
    fromSilhouette: false,
  ),
  RatioInfo(
    key: 'sil_shoulder_hip_ratio',
    name: 'Shoulder to hip (outline)',
    note: 'Measured from the body outline rather than the skeleton.',
    fromSilhouette: true,
  ),
  RatioInfo(
    key: 'sil_waist_hip_ratio',
    name: 'Waist to hip (outline)',
    note: 'Measured from the body outline.',
    fromSilhouette: true,
  ),
  RatioInfo(
    key: 'sil_waist_chest_ratio',
    name: 'Waist to chest (outline)',
    note: 'Measured from the body outline.',
    fromSilhouette: true,
  ),
];

/// The description for [key], or null if the app has no wording for it.
RatioInfo? ratioInfoFor(String key) {
  for (final info in kKnownRatios) {
    if (info.key == key) return info;
  }
  return null;
}

/// One ratio ready to show: its value, its wording and its spread.
class RatioReading {
  const RatioReading({
    required this.key,
    required this.name,
    required this.note,
    required this.value,
    required this.fromSilhouette,
    this.spreadPct,
  });

  final String key;
  final String name;
  final String note;
  final double value;
  final bool fromSilhouette;

  /// How much this ratio varied across frames, as a percentage. Null when the
  /// pipeline did not report it.
  final double? spreadPct;

  /// "1.08"
  String get valueLabel => value.toStringAsFixed(2);
}

/// Everything in [measurement] that the app can describe, in the order of
/// [kKnownRatios]. Ratios from a newer pipeline are left out rather than shown
/// under a made-up name; see unknownRatioKeys.
List<RatioReading> readingsFor(Measurement measurement) {
  final readings = <RatioReading>[];
  for (final info in kKnownRatios) {
    final value = measurement.ratios[info.key];
    if (value == null) continue;
    readings.add(
      RatioReading(
        key: info.key,
        name: info.name,
        note: info.note,
        value: value,
        fromSilhouette: info.fromSilhouette,
        spreadPct: measurement.precision[info.key]?.iqrPct,
      ),
    );
  }
  return readings;
}

/// Keys the scan produced that this version has no wording for.
List<String> unknownRatioKeys(Measurement measurement) =>
    measurement.ratios.keys.where((k) => ratioInfoFor(k) == null).toList();

/// Plain wording for the pipeline's own quality verdict.
String captureQualityLabel(String quality) {
  switch (quality) {
    case 'good':
      return 'Steady';
    case 'acceptable':
      return 'Acceptable';
    case 'unstable':
      return 'Unsteady';
    default:
      return quality.isEmpty ? 'Not reported' : quality;
  }
}

/// What the verdict means for trusting the numbers.
String captureQualityNote(String quality) {
  switch (quality) {
    case 'good':
      return 'The readings barely moved between frames.';
    case 'acceptable':
      return 'The readings moved a little between frames.';
    case 'unstable':
      return 'The readings moved a lot between frames. Scanning again, with '
          'better light and a steadier pose, should give closer numbers.';
    default:
      return '';
  }
}
