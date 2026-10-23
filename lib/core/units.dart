import 'format.dart';

/// How to SHOW a height. Heights are always stored in centimetres.
enum HeightUnit {
  cm('cm', 'Centimetres'),
  feetInches("ft'in", 'Feet and inches');

  const HeightUnit(this.short, this.label);

  final String short;
  final String label;

  bool get isMetric => this == HeightUnit.cm;
}

/// How to SHOW a weight. Weights are always stored in kilograms.
///
/// Separate from [HeightUnit] on purpose: plenty of people know their height
/// in feet and their weight in kilos, and one combined setting would force
/// them to pick a unit they do not think in.
enum WeightUnit {
  kg('kg', 'Kilograms'),
  lb('lb', 'Pounds');

  const WeightUnit(this.short, this.label);

  final String short;
  final String label;

  bool get isMetric => this == WeightUnit.kg;
}

// Exact factors, so a round trip never drifts.
const double _cmPerInch = 2.54;
const double _kgPerPound = 0.45359237;

double inchesFromCm(double cm) => cm / _cmPerInch;
double cmFromInches(double inches) => inches * _cmPerInch;

double poundsFromKg(double kg) => kg / _kgPerPound;
double kgFromPounds(double pounds) => pounds * _kgPerPound;

/// Feet and the remaining inches, for a height in centimetres.
/// Rounds to the nearest inch first, so 182.9 cm reads 6'0" rather than 5'12".
({int feet, int inches}) feetAndInchesFromCm(double cm) {
  final totalInches = inchesFromCm(cm).round();
  return (feet: totalInches ~/ 12, inches: totalInches % 12);
}

double cmFromFeetAndInches(int feet, int inches) =>
    cmFromInches(feet * 12 + inches.toDouble());

/// A height for display: "175 cm" or "5'9"".
String formatHeight(double cm, HeightUnit units) {
  if (units.isMetric) return '${formatNumber(cm)} cm';
  final (:feet, :inches) = feetAndInchesFromCm(cm);
  return "$feet'$inches\"";
}

/// A body weight or a load for display: "75 kg" or "165 lb".
String formatWeight(double kg, WeightUnit units) {
  if (units.isMetric) return '${formatNumber(kg)} kg';
  return '${formatNumber(poundsFromKg(kg))} lb';
}

/// A weight the user typed, in their units, as kilograms for storage.
double kgFromEntered(double value, WeightUnit units) =>
    units.isMetric ? value : kgFromPounds(value);

/// A stored weight in the units the user types in.
double enteredFromKg(double kg, WeightUnit units) =>
    units.isMetric ? kg : poundsFromKg(kg);
