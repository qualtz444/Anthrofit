import 'package:flutter/widgets.dart';

import 'auth_controller.dart';

/// Makes the AuthController available to every screen.
///   build methods:     AuthScope.of(context)
///   button callbacks:  AuthScope.of(context, listen: false)
class AuthScope extends InheritedNotifier<AuthController> {
  const AuthScope({
    super.key,
    required AuthController controller,
    required super.child,
  }) : super(notifier: controller);

  static AuthController of(BuildContext context, {bool listen = true}) {
    final AuthScope? scope = listen
        ? context.dependOnInheritedWidgetOfExactType<AuthScope>()
        : context.getInheritedWidgetOfExactType<AuthScope>();
    assert(scope != null, 'No AuthScope found above this widget.');
    return scope!.notifier!;
  }
}
