import 'package:flutter/material.dart';

/// Pick exactly one option. Works inside a Form: validate() fails until
/// something is chosen. No option is pre-selected.
class SingleChoiceField<T> extends FormField<T> {
  SingleChoiceField({
    super.key,
    String? label,
    required List<T> options,
    required String Function(T) labelOf,
    required ValueChanged<T> onChanged,
    super.initialValue,
    bool isRequired = true,
  }) : super(
         validator: (value) =>
             isRequired && value == null ? 'Choose one' : null,
         builder: (state) {
           return _ChoiceLayout(
             label: label,
             errorText: state.errorText,
             chips: [
               for (final option in options)
                 ChoiceChip(
                   label: Text(labelOf(option)),
                   selected: state.value == option,
                   onSelected: (_) {
                     state.didChange(option);
                     onChanged(option);
                   },
                 ),
             ],
           );
         },
       );
}

/// Pick one or more options. validate() fails until at least one is chosen.
class MultiChoiceField<T> extends FormField<List<T>> {
  MultiChoiceField({
    super.key,
    String? label,
    String? helper,
    required List<T> options,
    required String Function(T) labelOf,
    required ValueChanged<List<T>> onChanged,
    required List<T> initialValue,
    bool isRequired = true,
  }) : super(
         initialValue: initialValue,
         validator: (value) => isRequired && (value == null || value.isEmpty)
             ? 'Choose at least one'
             : null,
         builder: (state) {
           final selected = state.value ?? <T>[];
           return _ChoiceLayout(
             label: label,
             helper: helper,
             errorText: state.errorText,
             chips: [
               for (final option in options)
                 FilterChip(
                   label: Text(labelOf(option)),
                   selected: selected.contains(option),
                   onSelected: (isOn) {
                     final next = {...selected};
                     if (isOn) {
                       next.add(option);
                     } else {
                       next.remove(option);
                     }
                     // Keep the original option order.
                     final ordered = options.where(next.contains).toList();
                     state.didChange(ordered);
                     onChanged(ordered);
                   },
                 ),
             ],
           );
         },
       );
}

/// Pick exactly one, where each option needs a sentence to explain it.
/// Shown as a list of tappable rows instead of chips.
class DescribedChoiceField<T> extends FormField<T> {
  DescribedChoiceField({
    super.key,
    String? label,
    required List<T> options,
    required String Function(T) titleOf,
    required String Function(T) descriptionOf,
    required ValueChanged<T> onChanged,
    super.initialValue,
    bool isRequired = true,
  }) : super(
         validator: (value) =>
             isRequired && value == null ? 'Choose one' : null,
         builder: (state) {
           final theme = Theme.of(state.context);
           return _ChoiceLayout(
             label: label,
             errorText: state.errorText,
             vertical: true,
             chips: [
               for (final option in options)
                 Card(
                   margin: EdgeInsets.zero,
                   color: state.value == option
                       ? theme.colorScheme.secondaryContainer
                       : null,
                   child: ListTile(
                     title: Text(titleOf(option)),
                     subtitle: Text(descriptionOf(option)),
                     trailing: state.value == option
                         ? Icon(
                             Icons.check_circle,
                             color: theme.colorScheme.primary,
                           )
                         : null,
                     onTap: () {
                       state.didChange(option);
                       onChanged(option);
                     },
                   ),
                 ),
             ],
           );
         },
       );
}

class _ChoiceLayout extends StatelessWidget {
  const _ChoiceLayout({
    this.label,
    required this.chips,
    this.helper,
    this.errorText,
    this.vertical = false,
  });

  /// One option per row, for options with descriptions.
  final bool vertical;

  /// Left out when the page heading already asks the question.
  final String? label;
  final String? helper;
  final String? errorText;
  final List<Widget> chips;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) Text(label!, style: theme.textTheme.titleSmall),
        if (helper != null)
          Text(
            helper!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        const SizedBox(height: 8),
        if (vertical)
          for (final chip in chips)
            Padding(padding: const EdgeInsets.only(bottom: 8), child: chip)
        else
          Wrap(spacing: 8, runSpacing: 8, children: chips),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              errorText!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }
}
