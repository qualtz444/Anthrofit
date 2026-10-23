import 'package:flutter/widgets.dart';

import 'program_controller.dart';

/// Makes the ProgramController available anywhere below MaterialApp.
///   build methods:     ProgramScope.of(context)
///   button callbacks:  ProgramScope.of(context, listen: false)
class ProgramScope extends InheritedNotifier<ProgramController> {
  const ProgramScope({
    super.key,
    required ProgramController controller,
    required super.child,
  }) : super(notifier: controller);

  static ProgramController of(BuildContext context, {bool listen = true}) {
    final ProgramScope? scope = listen
        ? context.dependOnInheritedWidgetOfExactType<ProgramScope>()
        : context.getInheritedWidgetOfExactType<ProgramScope>();
    assert(scope != null, 'No ProgramScope found above this widget.');
    return scope!.notifier!;
  }
}
