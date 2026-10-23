import 'package:flutter/material.dart';

import '../../intelligence/ai_explainer.dart';

/// "Explain more" for a finding the app already worked out. Calls the AI
/// only when tapped, shows the checked reply labelled as AI, and falls back
/// to a short message if it is unavailable. The finding itself is always
/// shown above this by the screen, so nothing depends on the AI.
class AiExplainButton extends StatefulWidget {
  const AiExplainButton({super.key, required this.request, this.explainer});

  final ExplainRequest request;

  /// Defaults to the app-wide [aiExplainer]; tests pass a fake.
  final AiExplainer? explainer;

  @override
  State<AiExplainButton> createState() => _AiExplainButtonState();
}

class _AiExplainButtonState extends State<AiExplainButton> {
  bool _loading = false;
  bool _failed = false;
  String? _text;

  @override
  void didUpdateWidget(AiExplainButton old) {
    super.didUpdateWidget(old);
    // A new finding (the next set, another period) clears the old reply.
    if (old.request.facts.join('\n') != widget.request.facts.join('\n')) {
      _text = null;
      _failed = false;
    }
  }

  Future<void> _ask() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    final reply = await (widget.explainer ?? aiExplainer).explain(
      widget.request,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _text = reply;
      _failed = reply == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final text = _text;
    if (text != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text, key: const ValueKey('ai-explanation')),
            const SizedBox(height: 4),
            Text(
              'AI explanation of the findings above. It can be imperfect; '
              'the numbers above are what the app uses.',
              style: muted,
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('ai-explain'),
            onPressed: _loading ? null : _ask,
            icon: _loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome, size: 18),
            label: const Text('Explain more'),
          ),
        ),
        if (_failed)
          Text(
            'No explanation available right now. The findings above still '
            'apply.',
            key: const ValueKey('ai-unavailable'),
            style: muted,
          ),
      ],
    );
  }
}
