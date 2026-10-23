// Small helpers for reading JSON safely.
// Enums are stored by their `.name` (e.g. "buildMuscle").

T enumByName<T extends Enum>(List<T> values, Object? raw, T fallback) {
  if (raw is String) {
    for (final value in values) {
      if (value.name == raw) return value;
    }
  }
  return fallback;
}

List<T> enumListByName<T extends Enum>(List<T> values, Object? raw) {
  if (raw is! List) return <T>[];
  final result = <T>[];
  for (final item in raw) {
    for (final value in values) {
      if (value.name == item) {
        result.add(value);
        break;
      }
    }
  }
  return result;
}

List<String> enumNames<T extends Enum>(List<T> values) =>
    values.map((v) => v.name).toList();

DateTime? parseDate(Object? raw) =>
    raw is String ? DateTime.tryParse(raw) : null;

int parseInt(Object? raw, [int fallback = 0]) =>
    raw is num ? raw.toInt() : fallback;

int? parseNullableInt(Object? raw) => raw is num ? raw.toInt() : null;

double parseDouble(Object? raw, [double fallback = 0]) =>
    raw is num ? raw.toDouble() : fallback;

double? parseNullableDouble(Object? raw) => raw is num ? raw.toDouble() : null;

String parseString(Object? raw, [String fallback = '']) =>
    raw is String ? raw : fallback;

List<Map<String, dynamic>> parseMapList(Object? raw) {
  if (raw is! List) return <Map<String, dynamic>>[];
  return raw.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
}
