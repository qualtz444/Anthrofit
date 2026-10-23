/// Parsing and validation for one logged set (weight + reps).
///
/// Input-length limits: there is no source in the baseline for realistic
/// maximum loads or reps, so these are NOT claims about what is possible.
/// They only stop absurdly long numbers from being typed. Change them here.
const int kWeightInputMaxLength = 7;
const int kRepsInputMaxLength = 4;

/// Result of reading the two text fields.
/// [weightKg] is null when the weight was left blank (bodyweight / no load).
class SetInput {
  const SetInput({this.weightKg, this.reps, this.weightError, this.repsError});

  final double? weightKg;
  final int? reps;
  final String? weightError;
  final String? repsError;

  bool get isValid => weightError == null && repsError == null && reps != null;
}

final RegExp _digitsOnly = RegExp(r'^\d+$');
final RegExp _plainNumber = RegExp(r'^(\d+\.?\d*|\.\d+)$');

/// Digits only: no sign, decimal point, spaces or exponent.
/// Null if [text] is not a whole number, or is too large to hold.
int? parseWholeNumber(String text) {
  final t = text.trim();
  if (!_digitsOnly.hasMatch(t)) return null;
  return int.tryParse(t);
}

/// A weight typed by the user. Blank is fine and means "no weight" (value
/// null). Otherwise it must be a plain number, 0 or more.
({double? value, String? error}) parseOptionalWeight(String text) {
  final w = text.trim().replaceAll(',', '.');
  if (w.isEmpty) return (value: null, error: null);
  if (w.startsWith('-')) {
    return (value: null, error: "Weight can't be negative");
  }
  if (!_plainNumber.hasMatch(w)) {
    return (value: null, error: 'Enter weight as a number, like 40 or 42.5');
  }
  final parsed = double.tryParse(w);
  if (parsed == null || !parsed.isFinite) {
    return (value: null, error: 'Enter a smaller number');
  }
  return (value: parsed, error: null);
}

SetInput parseSetInput({required String weightText, required String repsText}) {
  // ---- reps: required, whole number, 1 or more ----
  int? reps;
  String? repsError;
  final r = repsText.trim();
  if (r.isEmpty) {
    repsError = 'Enter reps';
  } else if (!_digitsOnly.hasMatch(r)) {
    repsError = 'Enter reps as a whole number';
  } else {
    reps = int.tryParse(r);
    if (reps == null) {
      repsError = 'Enter a smaller number';
    } else if (reps < 1) {
      reps = null;
      repsError = 'Reps must be 1 or more';
    }
  }

  // ---- weight: optional, 0 or more, plain decimal only ----
  final weight = parseOptionalWeight(weightText);

  return SetInput(
    weightKg: weight.value,
    reps: reps,
    weightError: weight.error,
    repsError: repsError,
  );
}
