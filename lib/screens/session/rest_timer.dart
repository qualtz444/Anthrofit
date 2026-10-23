import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../notifications/app_notifications.dart';

/// Countdown for the planned rest between sets.
///   running: counts down, "Skip rest" stops it
///   idle:    shows the planned time and "Start rest"
///   done:    "Rest complete", "Restart rest" runs it again
///
/// Starts counting as soon as it appears, which is right after a set is
/// logged: resting is what happens next, so nobody should have to ask for it.
///
/// [seconds] is the planned rest of the set that was just completed
/// (PlannedSet.restSeconds, copied into the session's plan). The minus and
/// plus buttons change it through [onSecondsChanged], for this session only.
/// It ticks once per second while the app is open. When the app goes to the
/// background mid-rest, the phone is asked to show "Rest is over" when the
/// time is up, and on coming back the time spent away is taken off.
class RestTimer extends StatefulWidget {
  const RestTimer({
    super.key,
    required this.seconds,
    this.onSecondsChanged,
    this.stepSeconds = 15,
    this.onFinished,
    this.alertText,
  });

  final int seconds;

  /// Called when the user changes the rest length. Null hides the controls.
  final ValueChanged<int>? onSecondsChanged;

  /// How much one tap of minus or plus changes it.
  final int stepSeconds;

  /// Called when the countdown reaches zero (not when it is skipped).
  final VoidCallback? onFinished;

  /// The notification text when the rest ends while the app is in the
  /// background, such as "Time for Lat Pulldown." Null uses a general line.
  final String? alertText;

  @override
  State<RestTimer> createState() => _RestTimerState();
}

enum _RestPhase { idle, running, done }

class _RestTimerState extends State<RestTimer> with WidgetsBindingObserver {
  Timer? _timer;
  _RestPhase _phase = _RestPhase.idle;
  int _remaining = 0;

  /// When the app went to the background with the rest still running.
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused &&
        _phase == _RestPhase.running &&
        _pausedAt == null) {
      // Stop ticking here; the phone shows the alert when the time is up.
      _timer?.cancel();
      _pausedAt = DateTime.now();
      appNotifications.scheduleRestOver(
        after: Duration(seconds: _remaining),
        body: widget.alertText ?? 'Time for your next set.',
      );
    } else if (state == AppLifecycleState.resumed && _pausedAt != null) {
      final away = DateTime.now().difference(_pausedAt!).inSeconds;
      _pausedAt = null;
      appNotifications.cancelRestOver();
      if (_phase != _RestPhase.running) return;
      final left = _remaining - away;
      if (left <= 0) {
        _finish();
      } else {
        setState(() => _remaining = left);
        _tick();
      }
    }
  }

  /// The planned rest can change while this is on screen, from the minus and
  /// plus buttons. A running timer follows the change by the same amount, so
  /// adding 15 seconds adds 15 seconds to what is left.
  @override
  void didUpdateWidget(RestTimer old) {
    super.didUpdateWidget(old);
    final change = widget.seconds - old.seconds;
    if (change == 0) return;
    setState(() {
      if (_phase == _RestPhase.running) {
        _remaining = (_remaining + change).clamp(0, widget.seconds);
      } else if (_phase == _RestPhase.done && change > 0) {
        // More rest added after it finished: run the extra time.
        _remaining = change;
        _phase = _RestPhase.running;
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    // Closed while away (the sheet dismissed): no alert for a rest that is
    // no longer on screen.
    if (_pausedAt != null) appNotifications.cancelRestOver();
    super.dispose();
  }

  void _start() {
    _timer?.cancel();
    setState(() {
      _remaining = widget.seconds;
      _phase = _RestPhase.running;
    });
    _tick();
  }

  void _tick() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_remaining <= 1) {
        _finish();
      } else {
        setState(() => _remaining -= 1);
      }
    });
  }

  void _finish() {
    _timer?.cancel();
    setState(() {
      _remaining = 0;
      _phase = _RestPhase.done;
    });
    widget.onFinished?.call();
  }

  void _stop() {
    _timer?.cancel();
    setState(() => _phase = _RestPhase.idle);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = switch (_phase) {
      _RestPhase.idle => widget.seconds,
      _RestPhase.running => _remaining,
      _RestPhase.done => 0,
    };

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Rest', style: theme.textTheme.titleSmall),
            if (widget.onSecondsChanged != null) ...[
              const SizedBox(width: 4),
              _Adjust(
                icon: Icons.remove,
                tooltip: 'Less rest',
                onPressed: widget.seconds <= widget.stepSeconds
                    ? null
                    : () => widget.onSecondsChanged!(
                        widget.seconds - widget.stepSeconds,
                      ),
              ),
              _Adjust(
                icon: Icons.add,
                tooltip: 'More rest',
                onPressed: () => widget.onSecondsChanged!(
                  widget.seconds + widget.stepSeconds,
                ),
              ),
              Flexible(
                child: Text(
                  'planned ${formatClock(widget.seconds)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        ),
        Text(
          formatClock(shown),
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        if (_phase == _RestPhase.done)
          Text(
            'Rest complete',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
      ],
    );
    final action = switch (_phase) {
      _RestPhase.idle => FilledButton.tonal(
        onPressed: _start,
        child: const Text('Start rest'),
      ),
      _RestPhase.running => OutlinedButton(
        onPressed: _stop,
        child: const Text('Skip rest'),
      ),
      _RestPhase.done => FilledButton.tonal(
        onPressed: _start,
        child: const Text('Restart rest'),
      ),
    };

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 340) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  details,
                  const SizedBox(height: 12),
                  Align(alignment: Alignment.centerRight, child: action),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: details),
                const SizedBox(width: 8),
                IntrinsicWidth(child: action),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A small icon button for changing the rest length.
class _Adjust extends StatelessWidget {
  const _Adjust({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 18),
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      padding: EdgeInsets.zero,
      onPressed: onPressed,
    );
  }
}
