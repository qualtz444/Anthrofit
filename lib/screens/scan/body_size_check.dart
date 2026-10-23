import 'package:flutter/material.dart';

import '../../core/input_limits.dart';
import '../../core/units.dart';
import '../../models/models.dart';
import '../../state/profile_scope.dart';
import '../widgets/scrubber_input.dart';
import '../../core/snack_bar_timing.dart';

/// Asks the user to check their height and weight before a scan, filled in
/// from the profile.
///
/// The body composition step uses both, and a weight typed months ago at
/// profile setup may be out of date. Returns true when the scan can go
/// ahead: the values were confirmed and, if changed, saved to the profile
/// (which also records the new weight in the weight log). Returns false when
/// the sheet is closed or the save fails.
///
/// App design choice: the values update the profile rather than being used
/// for this one scan only, so the scan, the profile and the nutrition
/// targets all use the same height and weight.
Future<bool> confirmHeightAndWeight(BuildContext context) async {
  final profiles = ProfileScope.of(context, listen: false);
  final profile = profiles.profile;
  if (profile == null) return false;

  final picked = await showModalBottomSheet<({double heightCm, double weightKg})>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _BodySizeSheet(profile: profile),
  );
  if (picked == null || !context.mounted) return false;

  final changed =
      picked.heightCm != profile.heightCm ||
      picked.weightKg != profile.weightKg;
  if (!changed) return true;

  try {
    await profiles.save(
      profile.copyWith(heightCm: picked.heightCm, weightKg: picked.weightKg),
    );
    return true;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(duration: kSnackBarDuration, persist: false,
          content: Text(
            "Couldn't save your height and weight. Please try again.",
          ),
        ),
      );
    }
    return false;
  }
}

class _BodySizeSheet extends StatefulWidget {
  const _BodySizeSheet({required this.profile});

  final UserProfile profile;

  @override
  State<_BodySizeSheet> createState() => _BodySizeSheetState();
}

class _BodySizeSheetState extends State<_BodySizeSheet> {
  late double _heightCm = widget.profile.heightCm;
  late double _weightKg = widget.profile.weightKg;

  HeightUnit get _heightUnit => widget.profile.heightUnit;
  WeightUnit get _weightUnit => widget.profile.weightUnit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Same ranges and units as the profile setup pickers.
    final metricHeight = _heightUnit.isMetric;
    final metricWeight = _weightUnit.isMetric;

    return SafeArea(
      child: SingleChildScrollView(
        key: const ValueKey('body-check-sheet'),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Check your height and weight',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Used for your body composition results. Changes here also update '
              'your profile.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            Text('Height', style: theme.textTheme.titleSmall),
            KeyedSubtree(
              key: const ValueKey('body-check-height'),
              child: ScrubberInput(
                value: metricHeight
                    ? _heightCm
                    : inchesFromCm(_heightCm).roundToDouble(),
                min: metricHeight ? kMinHeightCm : 48,
                max: metricHeight ? kMaxHeightCm : 87,
                unit: metricHeight ? 'cm' : 'in',
                majorEvery: metricHeight ? 10 : 12,
                onChanged: (v) => setState(() {
                  _heightCm = metricHeight ? v : cmFromInches(v);
                }),
              ),
            ),
            if (!metricHeight)
              Center(
                child: Text(
                  formatHeight(_heightCm, _heightUnit),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            const SizedBox(height: 16),
            Text('Weight', style: theme.textTheme.titleSmall),
            KeyedSubtree(
              key: const ValueKey('body-check-weight'),
              child: ScrubberInput(
                value: metricWeight
                    ? _weightKg
                    : poundsFromKg(_weightKg).roundToDouble(),
                min: metricWeight ? kMinWeightKg : 66,
                max: metricWeight ? kMaxWeightKg : 550,
                unit: _weightUnit.short,
                onChanged: (v) => setState(() {
                  _weightKg = metricWeight ? v : kgFromPounds(v);
                }),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              key: const ValueKey('body-check-continue'),
              onPressed: () => Navigator.of(
                context,
              ).pop((heightCm: _heightCm, weightKg: _weightKg)),
              child: const Text('Looks right, start'),
            ),
          ],
        ),
      ),
    );
  }
}
