import 'package:flutter/material.dart';

import '../../auth/auth_errors.dart';
import '../../auth/auth_scope.dart';
import '../../auth/auth_validators.dart';
import '../../core/format.dart';
import '../../legal/legal_text.dart';
import '../legal/legal_screen.dart';
import '../widgets/date_of_birth_field.dart';
import 'auth_widgets.dart';

/// Create an account in three steps: email and password, then names and date
/// of birth, then a review with the terms. Nothing about training is asked
/// here; that is Profile Setup, which starts with the date of birth given here.
///
/// Every answer lives in this state, not in the step's widgets, so going Back
/// and Continue again keeps what was typed.
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  static const _stepTitles = ['Account', 'Personal', 'Review'];

  // One form per step with fields, so Continue only checks that step.
  final _accountFormKey = GlobalKey<FormState>();
  final _personalFormKey = GlobalKey<FormState>();

  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  int _step = 0;
  DateTime? _dateOfBirth;
  bool _acceptedTerms = false;
  bool _showTermsError = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _goTo(int step) => setState(() {
    _step = step;
    _error = null;
  });

  void _continue() {
    final form = _step == 0 ? _accountFormKey : _personalFormKey;
    if (!form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    _goTo(_step + 1);
  }

  void _back() {
    if (_busy || _step == 0) return;
    FocusScope.of(context).unfocus();
    _goTo(_step - 1);
  }

  Future<void> _submit() async {
    final auth = AuthScope.of(context, listen: false);
    final navigator = Navigator.of(context);

    setState(() => _showTermsError = !_acceptedTerms);
    if (!_acceptedTerms) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await auth.signUp(
        firstName: _firstName.text,
        lastName: _lastName.text,
        email: _email.text,
        password: _password.text,
        dateOfBirth: _dateOfBirth,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = describeAuthError(error, action: 'create your account');
      });
      return;
    }
    if (!mounted) return;
    // The start screen has already switched (to "verify your email").
    navigator.popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      // The back arrow steps back through the form before leaving it.
      canPop: _step == 0 && !_busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(),
        body: AuthCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Create your account',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              _StepProgress(step: _step, titles: _stepTitles),
              const SizedBox(height: 24),
              if (_error != null) AuthErrorText(_error!),
              KeyedSubtree(
                key: ValueKey('signup-step-$_step'),
                child: switch (_step) {
                  0 => _buildAccountStep(),
                  1 => _buildPersonalStep(),
                  _ => _buildReviewStep(),
                },
              ),
              const SizedBox(height: 24),
              _buildButtons(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAccountStep() {
    return Form(
      key: _accountFormKey,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
              validator: validateEmail,
            ),
            const SizedBox(height: 16),
            PasswordField(
              controller: _password,
              label: 'Password',
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newPassword],
              // Redraw the checklist on every keystroke.
              onChanged: (_) => setState(() {}),
              validator: validateNewPassword,
            ),
            const SizedBox(height: 8),
            PasswordChecklist(password: _password.text),
            const SizedBox(height: 16),
            PasswordField(
              controller: _confirm,
              label: 'Confirm password',
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _continue(),
              validator: (v) => validatePasswordConfirmation(v, _password.text),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPersonalStep() {
    return Form(
      key: _personalFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _firstName,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.givenName],
            decoration: const InputDecoration(
              labelText: 'First name',
              border: OutlineInputBorder(),
            ),
            validator: (v) => validateName(v, 'first name'),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _lastName,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.familyName],
            decoration: const InputDecoration(
              labelText: 'Last name',
              border: OutlineInputBorder(),
            ),
            validator: (v) => validateName(v, 'last name'),
          ),
          const SizedBox(height: 16),
          DateOfBirthField(
            key: const ValueKey('signup-dob-field'),
            initialValue: _dateOfBirth,
            onChanged: (picked) => _dateOfBirth = picked,
          ),
        ],
      ),
    );
  }

  Widget _buildReviewStep() {
    final theme = Theme.of(context);
    final dob = _dateOfBirth;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Check your details before creating your account.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        _ReviewSection(
          title: 'Account',
          onEdit: _busy ? null : () => _goTo(0),
          rows: {'Email': _email.text.trim()},
        ),
        const SizedBox(height: 12),
        _ReviewSection(
          title: 'Personal',
          onEdit: _busy ? null : () => _goTo(1),
          rows: {
            'Name': '${_firstName.text.trim()} ${_lastName.text.trim()}',
            'Date of birth': dob == null
                ? '-'
                : formatDate(dob, today: DateTime.now()),
          },
        ),
        const SizedBox(height: 8),
        // Ticking opens both documents; the box is only ticked after
        // "I agree" at the end of them. Unticking needs no reading.
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _acceptedTerms,
          onChanged: _busy
              ? null
              : (value) async {
                  if (value != true) {
                    setState(() => _acceptedTerms = false);
                    return;
                  }
                  final agreed = await readAndAgreeToTerms(context);
                  if (!mounted) return;
                  setState(() => _acceptedTerms = agreed);
                },
          title: const Text(
            'I have read and agree to the Terms of Service and Privacy '
            'Policy',
          ),
        ),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              key: const ValueKey('read-terms'),
              onPressed: () => openLegal(context, kTermsOfService),
              child: const Text('Read Terms of Service'),
            ),
            TextButton(
              key: const ValueKey('read-privacy'),
              onPressed: () => openLegal(context, kPrivacyPolicy),
              child: const Text('Read Privacy Policy'),
            ),
          ],
        ),
        if (_showTermsError && !_acceptedTerms)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              'Please accept the Terms of Service and Privacy Policy',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildButtons() {
    final isLast = _step == _stepTitles.length - 1;
    final Widget primary = isLast
        ? FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Create Account'),
          )
        : FilledButton(onPressed: _continue, child: const Text('Continue'));
    if (_step == 0) return primary;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _busy ? null : _back,
            child: const Text('Back'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: primary),
      ],
    );
  }
}

/// "Step 2 of 3 - Personal" over a bar with one segment per step.
class _StepProgress extends StatelessWidget {
  const _StepProgress({required this.step, required this.titles});

  final int step;
  final List<String> titles;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Step ${step + 1} of ${titles.length}',
          style: theme.textTheme.labelMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          titles[step],
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (var i = 0; i < titles.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 6,
                  decoration: BoxDecoration(
                    color: i <= step
                        ? scheme.primary
                        : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// One block on the review step: a heading with Edit, then label/value rows.
class _ReviewSection extends StatelessWidget {
  const _ReviewSection({
    required this.title,
    required this.rows,
    required this.onEdit,
  });

  final String title;
  final Map<String, String> rows;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton(onPressed: onEdit, child: Text('Edit $title')),
            ],
          ),
          for (final entry in rows.entries)
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 110,
                    child: Text(
                      entry.key,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(entry.value, style: theme.textTheme.bodyMedium),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
