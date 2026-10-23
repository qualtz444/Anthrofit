import 'package:flutter/material.dart';

import '../../auth/auth_scope.dart';
import '../widgets/app_logo.dart';
import 'sign_in_screen.dart';
import 'sign_up_screen.dart';

/// First screen for anyone who is not signed in and has not chosen Guest mode.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = AuthScope.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AppLogo(size: 140),
                const SizedBox(height: 24),
                Text(
                  'Welcome to ANTHROFIT',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Plan your training, log every set, and see your progress.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge,
                ),
                if (auth.accountsUnavailable) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Accounts are unavailable right now. You can still use '
                    'ANTHROFIT without an account.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SignInScreen(),
                      ),
                    );
                  },
                  child: const Text('Sign In'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SignUpScreen(),
                      ),
                    );
                  },
                  child: const Text('Create Account'),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text('or', style: theme.textTheme.bodyMedium),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () =>
                      AuthScope.of(context, listen: false).continueAsGuest(),
                  child: const Text('Continue without an account'),
                ),
                const SizedBox(height: 4),
                Text(
                  'Without an account your data stays on this device.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
