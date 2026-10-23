import 'package:flutter/material.dart';

import '../../data/training_stats.dart';

/// 1W / 1M / 3M / 6M / All.
class RangeSelector extends StatelessWidget {
  const RangeSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final ProgressRange selected;
  final ValueChanged<ProgressRange> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final range in ProgressRange.values)
          ChoiceChip(
            label: Text(range.label),
            selected: selected == range,
            onSelected: (_) => onChanged(range),
          ),
      ],
    );
  }
}
