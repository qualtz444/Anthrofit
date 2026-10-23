/// App-defined input limits for the profile height and weight pickers.
///
/// These are NOT from a published standard or from the bodycomp models
/// (its training script filters by age only, not height or weight).
/// They exist to stop typos or impossible values reaching calculations.
const double kMinHeightCm = 120;
const double kMaxHeightCm = 220;
const double kMinWeightKg = 30;
const double kMaxWeightKg = 250;
