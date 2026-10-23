import 'package:flutter/widgets.dart';

import 'session_controller.dart';

/// Makes the SessionController available anywhere below MaterialApp.
///   build methods:     SessionScope.of(context)
///   button callbacks:  SessionScope.of(context, listen: false)
class SessionScope extends InheritedNotifier<SessionController> {
  const SessionScope({
    super.key,
    required SessionController controller,
    required super.child,
  }) : super(notifier: controller);

  static SessionController of(BuildContext context, {bool listen = true}) {
    final SessionScope? scope = listen
        ? context.dependOnInheritedWidgetOfExactType<SessionScope>()
        : context.getInheritedWidgetOfExactType<SessionScope>();
    assert(scope != null, 'No SessionScope found above this widget.');
    return scope!.notifier!;
  }
}
