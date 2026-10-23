import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import 'admin_data.dart';
import 'admin_service.dart';
import 'pages/equipment_page.dart';
import 'pages/exercises_page.dart';
import 'pages/proportions_page.dart';
import 'pages/recommendation_page.dart';
import 'pages/templates_page.dart';

/// The admin web panel: sign in, check the account is an admin, then the
/// editing pages.
///
/// Its own theme (the app's colour, standard button sizes): the phone app's
/// theme makes buttons full width, which does not suit a desktop page.
class AdminApp extends StatelessWidget {
  const AdminApp({super.key, this.service});

  /// For tests. The panel uses Firebase by default.
  final AdminService? service;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Anthrofit Admin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: AppTheme.brand),
      home: _AuthGate(service: service ?? AdminService()),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate({required this.service});

  final AdminService service;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: service.auth.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final user = snap.data;
        if (user == null) return _SignInPage(service: service);
        return FutureBuilder<bool>(
          key: ValueKey(user.uid),
          future: service.isAdmin(user.uid),
          builder: (context, admin) {
            if (admin.connectionState != ConnectionState.done) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            if (admin.data != true) {
              return _NotAdminPage(service: service, user: user);
            }
            return _AdminHome(service: service);
          },
        );
      },
    );
  }
}

class _SignInPage extends StatefulWidget {
  const _SignInPage({required this.service});

  final AdminService service;

  @override
  State<_SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<_SignInPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.auth.signInWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? 'Sign-in failed.');
    } catch (_) {
      setState(() => _error = 'Sign-in failed.');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: AutofillGroup(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Anthrofit Admin', style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 4),
                    Text(
                      'Sign in with an Anthrofit account that is listed as an '
                      'admin.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      key: const ValueKey('admin-email'),
                      controller: _email,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey('admin-password'),
                      controller: _password,
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      onSubmitted: (_) => _busy ? null : _signIn(),
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      key: const ValueKey('admin-sign-in'),
                      onPressed: _busy ? null : _signIn,
                      child: Text(_busy ? 'Signing in…' : 'Sign in'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NotAdminPage extends StatelessWidget {
  const _NotAdminPage({required this.service, required this.user});

  final AdminService service;
  final User user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This account is not an admin',
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'In Firestore, add a document to the "admins" collection with '
                  'this user ID as its ID, then sign in again.',
                ),
                const SizedBox(height: 12),
                SelectableText(
                  'User ID: ${user.uid}',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 20),
                OutlinedButton(
                  onPressed: () => service.auth.signOut(),
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminHome extends StatefulWidget {
  const _AdminHome({required this.service});

  final AdminService service;

  @override
  State<_AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<_AdminHome> {
  late final AdminData _data = AdminData(widget.service)..start();
  int _page = 0;

  static const _pages = <(IconData, String)>[
    (Icons.fitness_center, 'Exercises'),
    (Icons.handyman_outlined, 'Equipment'),
    (Icons.view_list_outlined, 'Templates'),
    (Icons.tune, 'Recommendation'),
    (Icons.straighten, 'Proportions'),
  ];

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  Widget _body() => switch (_page) {
    0 => const ExercisesPage(),
    1 => const EquipmentPage(),
    2 => const TemplatesPage(),
    3 => const RecommendationPage(),
    _ => const ProportionsPage(),
  };

  @override
  Widget build(BuildContext context) {
    return AdminScope(
      data: _data,
      child: Builder(
        builder: (context) {
          final data = AdminScope.of(context);
          return Scaffold(
            appBar: AppBar(
              title: Text('Anthrofit Admin · ${_pages[_page].$2}'),
              actions: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Center(
                    child: Text(widget.service.auth.currentUser?.email ?? ''),
                  ),
                ),
                IconButton(
                  tooltip: 'Sign out',
                  icon: const Icon(Icons.logout),
                  onPressed: () => widget.service.auth.signOut(),
                ),
              ],
            ),
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _page,
                  labelType: NavigationRailLabelType.all,
                  onDestinationSelected: (i) => setState(() => _page = i),
                  destinations: [
                    for (final p in _pages)
                      NavigationRailDestination(
                        icon: Icon(p.$1),
                        label: Text(p.$2),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: data.error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(data.error!),
                          ),
                        )
                      : !data.loaded
                      ? const Center(child: CircularProgressIndicator())
                      : _body(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
