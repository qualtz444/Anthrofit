import 'dart:math';

final Random _random = Random();
int _counter = 0;

/// Generates a unique-enough local ID without extra packages.
/// Format: `time-counter-random`, each part in base 36.
String generateId() {
  _counter = (_counter + 1) % 1000000;
  final time = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final count = _counter.toRadixString(36);
  final rand = _random.nextInt(0x7fffffff).toRadixString(36);
  return '$time-$count-$rand';
}
