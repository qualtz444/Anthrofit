import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../models/models.dart';

/// The youngest age ANTHROFIT is for.
const int kMinimumAge = 18;

/// Why [dateOfBirth] cannot be used, or null when it can.
String? validateDateOfBirth(DateTime? dateOfBirth, {DateTime? today}) {
  if (dateOfBirth == null) return 'Select your date of birth';
  if (calculateAge(dateOfBirth, today) < kMinimumAge) {
    return 'You must be at least $kMinimumAge years old to use Anthrofit';
  }
  return null;
}

/// A date of birth, picked from a calendar. Used by account creation and by
/// profile setup, so both check it the same way.
class DateOfBirthField extends FormField<DateTime> {
  DateOfBirthField({
    super.key,
    super.initialValue,
    required ValueChanged<DateTime> onChanged,
    bool isRequired = true,
  }) : super(
         validator: (value) => value == null && !isRequired
             ? null
             : validateDateOfBirth(value),
         builder: (field) {
           final context = field.context;
           final theme = Theme.of(context);
           final value = field.value;
           return InkWell(
             borderRadius: BorderRadius.circular(4),
             onTap: () async {
               final now = DateTime.now();
               final picked = await showDatePicker(
                 context: context,
                 initialDate:
                     value ?? DateTime(now.year - 25, now.month, now.day),
                 firstDate: DateTime(1900),
                 lastDate: now,
                 helpText: 'Select your date of birth',
               );
               if (picked == null) return;
               field.didChange(picked);
               onChanged(picked);
             },
             child: InputDecorator(
               decoration: InputDecoration(
                 labelText: 'Date of birth',
                 helperText: 'You must be $kMinimumAge or older',
                 border: const OutlineInputBorder(),
                 errorText: field.errorText,
                 suffixIcon: const Icon(Icons.calendar_today),
               ),
               child: Text(
                 value == null
                     ? 'Select date of birth'
                     : formatDate(value, today: DateTime.now()),
                 style: theme.textTheme.bodyLarge,
               ),
             ),
           );
         },
       );
}
