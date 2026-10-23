import '../models/models.dart';

/// "Active", "Archived", or "Not active". Which program is active is decided
/// by ProgramController, so it is passed in.
String programStatusLabel(TrainingProgram program, {required bool isActive}) {
  if (isActive) return 'Active';
  return program.archived ? 'Archived' : 'Not active';
}

/// "M/W/F", "M/T/Th/F"
String compactDays(List<Weekday> days) =>
    days.map((d) => d.compactLabel).join('/');

/// "Active · M/W/F". With no training days: "Active · No training days".
String programStatusLine(TrainingProgram program, {required bool isActive}) {
  final days = program.trainingDays;
  return '${programStatusLabel(program, isActive: isActive)} · '
      '${days.isEmpty ? 'No training days' : compactDays(days)}';
}
