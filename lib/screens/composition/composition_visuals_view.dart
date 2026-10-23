import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../composition/composition_visuals.dart';
import '../../composition/silhouette_features.dart';
import 'outline_overlay.dart';

/// One scan's front and side outlines, and its photos behind a button.
///
/// Photos are never shown until asked for: they are sensitive, and the
/// person may be looking at their phone somewhere others can see it.
class CompositionVisualsView extends StatefulWidget {
  const CompositionVisualsView({super.key, required this.visuals});

  final CompositionVisuals visuals;

  @override
  State<CompositionVisualsView> createState() => _CompositionVisualsViewState();
}

class _CompositionVisualsViewState extends State<CompositionVisualsView> {
  bool _showPhotos = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = widget.visuals;
    final color = theme.colorScheme.primary.withValues(alpha: 0.55);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    Widget outline(String title, SilhouetteMask? mask) => Expanded(
      child: Column(
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          if (mask == null)
            SizedBox(
              height: 220,
              child: Center(child: Text('Not saved', style: muted)),
            )
          else
            OutlineOverlay(
              height: 220,
              layers: [OutlineLayer(mask: mask, color: color)],
            ),
        ],
      ),
    );

    Widget unavailablePhoto(String title) => ColoredBox(
      key: ValueKey('photo-unavailable-${title.toLowerCase()}'),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.hide_image_outlined,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 4),
              Text(
                'Original photo unavailable',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );

    Widget photo(String title, Uint8List? bytes) => Expanded(
      child: Column(
        children: [
          Text(title, style: theme.textTheme.bodySmall),
          const SizedBox(height: 4),
          AspectRatio(
            aspectRatio: 3 / 4,
            child: bytes == null
                ? unavailablePhoto(title)
                : Image.memory(
                    bytes,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        unavailablePhoto(title),
                  ),
          ),
        ],
      ),
    );

    Widget photoPair() => Row(
      children: [
        photo('Front', v.frontPhoto),
        const SizedBox(width: 8),
        photo('Side', v.sidePhoto),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          key: const ValueKey('scan-outlines'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            outline('Front', v.frontOutline),
            const SizedBox(width: 12),
            outline('Side', v.sideOutline),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Your outline from this scan. It shows no face or skin and stays '
          'on this phone.',
          style: muted,
        ),
        const SizedBox(height: 12),
        Text('Photos', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        if (v.hasPhotos) ...[
          if (!_showPhotos)
            OutlinedButton.icon(
              key: const ValueKey('show-scan-photos'),
              onPressed: () => setState(() => _showPhotos = true),
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Show photos'),
            )
          else
            photoPair(),
        ] else ...[
          Text(
            'Original scan photos are unavailable for this scan.',
            style: muted,
          ),
          const SizedBox(height: 8),
          photoPair(),
        ],
      ],
    );
  }
}
