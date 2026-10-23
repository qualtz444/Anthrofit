import 'package:flutter/widgets.dart';

import 'exercise_library_controller.dart';

/// Makes the ExerciseLibraryController available anywhere below MaterialApp.
///   build methods:     ExerciseLibraryScope.of(context)
///   button callbacks:  ExerciseLibraryScope.of(context, listen: false)
class ExerciseLibraryScope
    extends InheritedNotifier<ExerciseLibraryController> {
  const ExerciseLibraryScope({
    super.key,
    required ExerciseLibraryController controller,
    required super.child,
  }) : super(notifier: controller);

  static ExerciseLibraryController of(
    BuildContext context, {
    bool listen = true,
  }) {
    final ExerciseLibraryScope? scope = listen
        ? context.dependOnInheritedWidgetOfExactType<ExerciseLibraryScope>()
        : context.getInheritedWidgetOfExactType<ExerciseLibraryScope>();
    assert(scope != null, 'No ExerciseLibraryScope found above this widget.');
    return scope!.notifier!;
  }
}
