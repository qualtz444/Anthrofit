import 'body_composition.dart';
import 'composition_models.dart';
import 'silhouette_features.dart';

/// Loads the bundled models once per app run and reuses them.
Future<CompositionModels>? _cached;

Future<CompositionModels> loadCompositionModels() {
  final pending = _cached ??= CompositionModels.loadFromAssets();
  // A failed load is not cached, so the next attempt tries again.
  return pending.catchError((Object error, StackTrace stack) {
    _cached = null;
    Error.throwWithStackTrace(error, stack);
  });
}

/// Pairs the captured front and side masks in order and runs the pipeline.
///
/// Throws [CompositionException] with a user-facing message when there is
/// nothing usable.
BodyCompositionResult estimateComposition({
  required CompositionModels models,
  required List<SilhouetteMask> front,
  required List<SilhouetteMask> side,
  required CompositionInput input,
}) {
  final count = front.length < side.length ? front.length : side.length;
  if (count == 0) {
    throw const CompositionException(
      'No usable front and side frames were captured. Try again.',
    );
  }
  return BodyCompositionPipeline(models).analyseMany([
    for (var i = 0; i < count; i++) (front: front[i], side: side[i]),
  ], input);
}
