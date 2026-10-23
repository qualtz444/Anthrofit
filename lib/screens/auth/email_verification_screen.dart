import 'package:flutter/material.dart';

import '../../auth/auth_errors.dart';
import '../../auth/auth_scope.dart';

/// "Verify your email". The app cannot be used with an account until Firebase
/// reports the email as verified. No custom code or OTP is involved.
class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({super.key});

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  bool _busy = false;
  String? _message;
  bool _messageIsError = false;

  void _show(String text, {required bool isError}) {
    setState(() {
      _busy = false;
      _message = text;
      _messageIsError = isError;
    });
  }

  Future<void> _resend() async {
    final auth = AuthScope.of(context, listen: false);
    setState(() => _busy = true);
    try {
      await auth.resendVerificationEmail();
      auth.clearNotice();
      if (!mounted) return;
      _show('Verification email sent.', isError: false);
    } catch (error) {
      if (!mounted) return;
      _show(describeAuthError(error, action: 'send the email'), isError: true);
    }
  }

  Future<void> _check() async {
    final auth = AuthScope.of(context, listen: false);
    setState(() => _busy = true);
    try {
      final verified = await auth.refreshVerification();
      if (!mounted) return;
      if (!verified) {
        _show(
          'Your email is not verified yet. Open the link in the email we '
          'sent, then try again.',
          isError: true,
        );
      }
      // If it is verified, the start screen has already moved on.
    } catch (error) {
      if (!mounted) return;
      _show(
        describeAuthError(error, action: 'check your email'),
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = AuthScope.of(context);
    final email = auth.user?.email ?? auth.account?.email ?? '';
    final notice = auth.notice;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.mark_email_read_outlined,
                  size: 72,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 20),
                Text(
                  'Verify your email',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'A verification email was sent to:',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  email,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (notice != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    notice,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                if (_message != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _message!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: _messageIsError
                          ? theme.colorScheme.error
                          : theme.colorScheme.primary,
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: _busy ? null : _check,
                  child: const Text("I've Verified My Email"),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _busy ? null : _resend,
                  child: const Text('Resend Verification Email'),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => AuthScope.of(context, listen: false).signOut(),
                  child: const Text('Sign Out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
