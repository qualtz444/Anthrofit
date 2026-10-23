import 'package:flutter/material.dart';

import '../../auth/auth_scope.dart';

/// Shown once, right after a new account's email is verified, when this device
/// already holds guest data. Nothing is moved or kept without this answer.
///   Keep My Data  -> the guest data becomes this account's (moved, not copied)
///   Start Fresh   -> a clean account; the guest data is left where it is
class MigrationPromptScreen extends StatefulWidget {
  const MigrationPromptScreen({super.key});

  @override
  State<MigrationPromptScreen> createState() => _MigrationPromptScreenState();
}

class _MigrationPromptScreenState extends State<MigrationPromptScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _answer({required bool keep}) async {
    final auth = AuthScope.of(context, listen: false);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (keep) {
        await auth.keepGuestData();
      } else {
        await auth.startFresh();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error =
            "We couldn't move your data. It is still safe on this "
            'device. Try again, or choose Start Fresh.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Existing ANTHROFIT data found on this device.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Would you like to keep it with your new account?',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Start Fresh leaves it where it is. You can still use it '
                  'later without an account.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: _busy ? null : () => _answer(keep: true),
                  child: const Text('Keep My Data'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _busy ? null : () => _answer(keep: false),
                  child: const Text('Start Fresh'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
