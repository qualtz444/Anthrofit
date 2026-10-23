import 'package:flutter/material.dart';

import '../../models/models.dart';

/// The illustration for [muscle] in assets/muscles/, named after the
/// muscle's id in snake_case: frontDelts -> front_delts.png.
String muscleAsset(MuscleGroup muscle) {
  final file = muscle.name.replaceAllMapped(
    RegExp('[A-Z]'),
    (m) => '_${m[0]!.toLowerCase()}',
  );
  return 'assets/muscles/$file.png';
}

/// One muscle's illustration on a rounded tile. A muscle without an
/// illustration yet shows a generic body icon instead.
class MuscleImage extends StatelessWidget {
  const MuscleImage(this.muscle, {super.key, this.size = 48});

  final MuscleGroup muscle;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final pixels = (size * MediaQuery.devicePixelRatioOf(context)).round();
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.06),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(size * 0.2),
      ),
      child: Image.asset(
        muscleAsset(muscle),
        key: ValueKey('muscle-image-${muscle.name}'),
        fit: BoxFit.contain,
        cacheWidth: pixels,
        // The label next to it already names the muscle.
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) => Icon(
          Icons.accessibility_new,
          size: size * 0.6,
          color: colors.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// A muscle's illustration with its name underneath. Used as a chip label,
/// so pickers keep their chips and simply show the muscle too.
class MuscleTileLabel extends StatelessWidget {
  const MuscleTileLabel(this.muscle, {super.key, this.size = 48});

  final MuscleGroup muscle;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size + 16,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MuscleImage(muscle, size: size),
          const SizedBox(height: 4),
          Text(
            muscle.label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ],
      ),
    );
  }
}

/// A sideways-scrolling row of muscles, each pictured and named.
///
/// [emphasised] outlines each tile in the primary colour, for primary
/// muscles, as ChipRow does with its chips.
class MuscleGallery extends StatelessWidget {
  const MuscleGallery({
    super.key,
    required this.muscles,
    this.size = 56,
    this.emptyText,
    this.emphasised = false,
  });

  final List<MuscleGroup> muscles;
  final double size;

  /// Shown instead of the row when there is nothing to list.
  final String? emptyText;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (muscles.isEmpty) {
      if (emptyText == null) return const SizedBox.shrink();
      return Text(
        emptyText!,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final muscle in muscles)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: emphasised
                    ? BoxDecoration(
                        border: Border.all(
                          color: theme.colorScheme.primary,
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(size * 0.25),
                      )
                    : null,
                child: MuscleTileLabel(muscle, size: size),
              ),
            ),
        ],
      ),
    );
  }
}
