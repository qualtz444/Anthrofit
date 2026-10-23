import '../core/json_utils.dart';

/// One recorded body weight, on one day.
///
/// The profile holds only the CURRENT weight, which is overwritten on every
/// edit, so without this nothing could show how weight has changed. Each
/// change of weight adds an entry; nothing else does.
class BodyWeightEntry {
  const BodyWeightEntry({required this.date, required this.weightKg});

  /// The day it was recorded, with no time of day.
  final DateTime date;

  /// Always kilograms, whatever the user's display units.
  final double weightKg;

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'weightKg': weightKg,
  };

  factory BodyWeightEntry.fromJson(Map<String, dynamic> json) =>
      BodyWeightEntry(
        date: parseDate(json['date']) ?? DateTime(1970),
        weightKg: parseDouble(json['weightKg']),
      );
}
