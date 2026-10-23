import 'package:flutter/material.dart';

import 'auth/auth_controller.dart';
import 'auth/auth_scope.dart';
import 'auth/auth_service.dart';
import 'auth/firebase_auth_service.dart';
import 'screens/auth/email_verification_screen.dart';
import 'screens/auth/migration_prompt_screen.dart';
import 'screens/auth/welcome_screen.dart';
import 'screens/main_shell.dart';
import 'screens/profile/profile_setup_screen.dart';
import 'state/profile_scope.dart';
import 'state/program_scope.dart';
import 'state/session_scope.dart';
import 'state/user_data_host.dart';
import 'cloud/firestore_store.dart';
import 'core/app_theme.dart';
import 'core/theme_mode_controller.dart';

class AnthrofitApp extends StatefulWidget {
  /// [authService] is for tests. The app uses Firebase Authentication by default.
  const AnthrofitApp({super.key, this.authService});

  final AuthService? authService;

  @override
  State<AnthrofitApp> createState() => _AnthrofitAppState();
}

class _AnthrofitAppState extends State<AnthrofitApp> {
  late final AuthController _auth;

  @override
  void initState() {
    super.initState();
    _auth = AuthController(
      service: widget.authService ?? FirebaseAuthService(),
    );
    _auth.start();
  }

  @override
  void dispose() {
    _auth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
        valueListenable: themeMode,
        builder: (context, mode, _) => MaterialApp(
          title: 'Anthrofit',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: mode,
      // Everything below the Navigator (so pushed screens too) can see the auth
      // state, and, once someone is in, that person's own data.
      builder: (context, child) {
        // On wide screens (tablets) keep the content a readable width.
        final content = ColoredBox(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: child,
            ),
          ),
        );
        return AuthScope(
          controller: _auth,
          child: _DataScopes(auth: _auth, child: content),
        );
      },
      home: const _Root(),
        ),
    );
  }
}

/// Adds the profile/program/session controllers for whoever is using the app.
/// A new owner gets new controllers (see UserDataHost); nobody signed in means
/// no data is loaded at all.
class _DataScopes extends StatelessWidget {
  const _DataScopes({required this.auth, required this.child});

  final AuthController auth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: auth,
      builder: (context, _) {
        final scope = auth.dataScope;
        if (scope == null) return child;

        final uid = auth.user?.uid ?? '';

        return UserDataHost(
          key: ValueKey(scope.id),
          scope: scope,
          cloud: uid.isEmpty ? null : FirestoreStore(),
          uid: uid,
          child: child,
        );
      },
    );
  }
}

/// The start screen, chosen from the one authentication state:
///   starting up              -> loading
///   not signed in            -> Welcome
///   signed in, unverified    -> Verify your email
///   verified, guest data?    -> Keep your data?
///   guest or verified        -> the app (profile setup first if needed)
class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final auth = AuthScope.of(context);
    switch (auth.status) {
      case AuthStatus.initializing:
        return const _LoadingScreen();
      case AuthStatus.signedOut:
        return const WelcomeScreen();
      case AuthStatus.unverified:
        return const EmailVerificationScreen();
      case AuthStatus.verified:
        return auth.migrationPending
            ? const MigrationPromptScreen()
            : const _DataGate();
      case AuthStatus.guest:
        return const _DataGate();
    }
  }
}

/// Once there is an owner: wait for their data to load, then show profile
/// setup (no profile yet) or the main app.
class _DataGate extends StatelessWidget {
  const _DataGate();

  @override
  Widget build(BuildContext context) {
    final profile = ProfileScope.of(context);
    final programs = ProgramScope.of(context);
    final sessions = SessionScope.of(context);
    if (!profile.isLoaded || !programs.isLoaded || !sessions.isLoaded) {
      return const _LoadingScreen();
    }
    if (profile.profile == null) {
      return ProfileSetupScreen(
        isOnboarding: true,
        // The account's name is only a starting point for the display name.
        suggestedName: AuthScope.of(context).account?.fullName,
        suggestedDateOfBirth: AuthScope.of(context).account?.dateOfBirth,
      );
    }
    return const MainShell();
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
