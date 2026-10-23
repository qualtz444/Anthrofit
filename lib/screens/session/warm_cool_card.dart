import 'dart:async';

import 'package:flutter/material.dart';

import '../../coaching/warm_cool.dart';
import '../../core/format.dart';
import '../../models/models.dart';

enum WarmCoolKind { warmUp, coolDown }

/// "Warm up first" before the first set, or "Cool down" on the summary: what
/// to do, an optional timer, and Hide. Nothing here is logged: it never
/// counts toward sets, volume, time or calories.
class WarmCoolCard extends StatefulWidget {
  const WarmCoolCard({
    super.key,
    required this.kind,
    required this.onHide,
    this.muscles = const [],
  });

  final WarmCoolKind kind;
  final VoidCallback onHide;

  /// Cool-down only: the muscles trained, named in the stretch line.
  final List<MuscleGroup> muscles;

  @override
  State<WarmCoolCard> createState() => _WarmCoolCardState();
}

class _WarmCoolCardState extends State<WarmCoolCard> {
  Timer? _timer;
  int _left = kWarmCoolTimer.inSeconds;
  bool _running = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _toggle() {
    if (_running) {
      _timer?.cancel();
      setState(() => _running = false);
      return;
    }
    if (_left <= 0) _left = kWarmCoolTimer.inSeconds;
    setState(() => _running = true);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_left <= 1) {
        _timer?.cancel();
        setState(() {
          _left = 0;
          _running = false;
        });
      } else {
        setState(() => _left -= 1);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warm = widget.kind == WarmCoolKind.warmUp;
    final done = _left == 0;
    return Card(
      key: ValueKey(warm ? 'warm-up-card' : 'cool-down-card'),
      margin: EdgeInsets.zero,
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  warm ? Icons.local_fire_department_outlined : Icons.spa,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    warm ? 'Warm up first' : 'Cool down',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
                Text(
                  done ? 'Time is up' : formatClock(_left),
                  key: const ValueKey('warm-cool-clock'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              warm ? kWarmUpText : kCoolDownText,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
            if (!warm && widget.muscles.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Trained today: '
                '${widget.muscles.map((m) => m.label).join(', ')}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ],
            Row(
              children: [
                TextButton.icon(
                  key: const ValueKey('warm-cool-timer'),
                  onPressed: _toggle,
                  icon: Icon(_running ? Icons.pause : Icons.timer_outlined),
                  label: Text(_running ? 'Pause timer' : 'Start timer'),
                ),
                TextButton(
                  key: const ValueKey('warm-cool-more'),
                  onPressed: () => setState(() => _left += 60),
                  child: const Text('+1 min'),
                ),
                const Spacer(),
                TextButton(
                  key: const ValueKey('warm-cool-hide'),
                  onPressed: widget.onHide,
                  child: const Text('Hide'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
