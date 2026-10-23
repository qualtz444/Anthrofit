import 'package:flutter/material.dart';

/// A single row of read-only chips that scrolls sideways.
///
/// Used wherever a list of short labels would otherwise wrap over several
/// lines: muscles, equipment and schedule days.
class ChipRow extends StatelessWidget {
  const ChipRow({
    super.key,
    required this.labels,
    this.emptyText,
    this.emphasised = false,
  });

  final List<String> labels;

  /// Shown instead of the row when there is nothing to list.
  final String? emptyText;

  /// Draws the chips in the primary colour, for primary muscles.
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (labels.isEmpty) {
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
        children: [
          for (final label in labels)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Chip(
                label: Text(label),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                backgroundColor: emphasised
                    ? theme.colorScheme.primaryContainer
                    : null,
                labelStyle: emphasised
                    ? TextStyle(color: theme.colorScheme.onPrimaryContainer)
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}

/// Three filled stars for a three-step rating, used for experience and
/// complexity. Both are ordered enums, so the star count is just the index.
class StarRating extends StatelessWidget {
  const StarRating({super.key, required this.filled, this.total = 3});

  final int filled;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < total; i++)
          Icon(
            i < filled ? Icons.star : Icons.star_border,
            size: 18,
            color: i < filled
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
      ],
    );
  }
}
