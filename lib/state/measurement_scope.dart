import 'package:flutter/widgets.dart';

import 'measurement_controller.dart';

/// Makes the MeasurementController available anywhere below MaterialApp.
///   build methods:     MeasurementScope.of(context)
///   button callbacks:  MeasurementScope.of(context, listen: false)
class MeasurementScope extends InheritedNotifier<MeasurementController> {
  const MeasurementScope({
    super.key,
    required MeasurementController controller,
    required super.child,
  }) : super(notifier: controller);

  static MeasurementController of(BuildContext context, {bool listen = true}) {
    final MeasurementScope? scope = listen
        ? context.dependOnInheritedWidgetOfExactType<MeasurementScope>()
        : context.getInheritedWidgetOfExactType<MeasurementScope>();
    assert(scope != null, 'No MeasurementScope found above this widget.');
    return scope!.notifier!;
  }
}
