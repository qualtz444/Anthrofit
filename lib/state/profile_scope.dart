import 'package:flutter/widgets.dart';

import '../core/units.dart';
import 'profile_controller.dart';

/// Makes the ProfileController available anywhere below MaterialApp.
///   build methods:     ProfileScope.of(context)
///   button callbacks:  ProfileScope.of(context, listen: false)
class ProfileScope extends InheritedNotifier<ProfileController> {
  const ProfileScope({
    super.key,
    required ProfileController controller,
    required super.child,
  }) : super(notifier: controller);

  static ProfileController of(BuildContext context, {bool listen = true}) {
    final ProfileScope? scope = listen
        ? context.dependOnInheritedWidgetOfExactType<ProfileScope>()
        : context.getInheritedWidgetOfExactType<ProfileScope>();
    assert(scope != null, 'No ProfileScope found above this widget.');
    return scope!.notifier!;
  }
}

/// Which unit to SHOW loads in, from the saved profile.
///
/// Kilograms until a profile exists, which matches how a profile loads.
/// Storage is always kilograms: this only affects what is displayed and what
/// a typed number is taken to mean.
WeightUnit unitsOf(BuildContext context, {bool listen = true}) {
  final scope = listen
      ? context.dependOnInheritedWidgetOfExactType<ProfileScope>()
      : context.getInheritedWidgetOfExactType<ProfileScope>();
  return scope?.notifier?.profile?.weightUnit ?? WeightUnit.kg;
}

/// Which unit to SHOW a height in. Heights are always stored in centimetres.
HeightUnit heightUnitOf(BuildContext context, {bool listen = true}) {
  final scope = listen
      ? context.dependOnInheritedWidgetOfExactType<ProfileScope>()
      : context.getInheritedWidgetOfExactType<ProfileScope>();
  return scope?.notifier?.profile?.heightUnit ?? HeightUnit.cm;
}
