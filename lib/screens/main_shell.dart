import 'package:flutter/material.dart';

import '../notifications/app_notifications.dart';
import '../notifications/reminder_settings.dart';
import '../state/measurement_scope.dart';
import '../state/profile_scope.dart';
import '../state/program_scope.dart';
import 'home/home_screen.dart';
import 'profile/profile_screen.dart';
import 'program/program_screen.dart';
import 'progress/progress_screen.dart';
import 'scan/scan_choice_screen.dart';

/// Bottom navigation: Home, Progress, [Scan], Program, Profile.
///
/// Scan sits in the middle as a raised button rather than a tab: it opens the
/// scan choice (body proportion or body composition), a full-screen task
/// that comes back here, so it never becomes a selected destination.
/// The gap in the bar is the fifth, disabled slot it covers.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  /// Closed for this session with the bubble's X; it also goes for good
  /// once a scan is saved.
  bool _scanTipDismissed = false;

  /// What the training-day reminders were last set up from, so they are
  /// only rescheduled when the program's week or the setting changes.
  String? _reminderKey;

  @override
  void initState() {
    super.initState();
    reminderSettings.addListener(_syncReminders);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Listens to the programs, so a new active program or schedule
    // reschedules the reminders.
    context.dependOnInheritedWidgetOfExactType<ProgramScope>();
    _syncReminders();
  }

  @override
  void dispose() {
    reminderSettings.removeListener(_syncReminders);
    super.dispose();
  }

  void _syncReminders() {
    final program = context
        .getInheritedWidgetOfExactType<ProgramScope>()
        ?.notifier
        ?.activeProgram;
    final settings = reminderSettings.value;
    final key = [
      settings.encode(),
      program?.id,
      program?.name,
      if (program != null)
        for (final d in program.trainingDays)
          '${d.name}:${program.workoutsForDay(d).map((w) => w.name).join('+')}',
    ].join(';');
    if (key == _reminderKey) return;
    _reminderKey = key;
    appNotifications.syncWorkoutReminders(program, settings);
  }

  static const List<Widget> _screens = [
    HomeScreen(),
    ProgressScreen(),
    ProgramScreen(),
    ProfileScreen(),
  ];

  /// The bar has five slots; slot 2 is the hole under the Scan button.
  static const int _scanSlot = 2;

  int get _selectedSlot => _index < _scanSlot ? _index : _index + 1;

  void _onSlotSelected(int slot) {
    if (slot == _scanSlot) return; // the button handles it
    setState(() => _index = slot < _scanSlot ? slot : slot - 1);
  }

  void _openScan() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const ScanChoiceScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(index: _index, children: _screens),
          // Points new users at the Scan button rather than adding another
          // button that does the same thing. Home only, so it never sits on
          // top of another tab's bottom actions.
          if (_index == 0 && !_scanTipDismissed && needsFirstScan(context))
            Positioned(
              left: 16,
              right: 16,
              bottom: 20, // clears the part of the button above the bar
              child: Center(
                child: _ScanTip(
                  onTap: _openScan,
                  onClose: () => setState(() => _scanTipDismissed = true),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: Stack(
        clipBehavior: Clip.none,
        children: [
          NavigationBar(
            selectedIndex: _selectedSlot,
            onDestinationSelected: _onSlotSelected,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.show_chart_outlined),
                selectedIcon: Icon(Icons.show_chart),
                label: 'Progress',
              ),
              // The slot the Scan button sits over. Kept so the four real
              // destinations stay evenly spaced either side of it.
              NavigationDestination(
                enabled: false,
                icon: SizedBox(width: 56),
                label: '',
              ),
              NavigationDestination(
                icon: Icon(Icons.calendar_month_outlined),
                selectedIcon: Icon(Icons.calendar_month),
                label: 'Program',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'Profile',
              ),
            ],
          ),
          // Overlay on the bar itself so snackbars cannot move the scan
          // action away from its shell position.
          Positioned(
            top: -16,
            left: 0,
            right: 0,
            child: Center(
              child: SizedBox(
                width: 56,
                height: 56,
                child: FloatingActionButton(
                  heroTag: 'scan-fab',
                  onPressed: _openScan,
                  tooltip: 'Body scan',
                  shape: const CircleBorder(),
                  // A dot until the first scan is saved, matching the
                  // tip that points here.
                  child: Badge(
                    key: const ValueKey('scan-fab-badge'),
                    isLabelVisible: needsFirstScan(context),
                    child: const Icon(Icons.center_focus_strong),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// True when the user has a profile but has never saved a scan of either
/// kind. False until measurements have loaded, so the tip never flashes.
bool needsFirstScan(BuildContext context) {
  final profile = ProfileScope.of(context).profile;
  final measurements = MeasurementScope.of(context);
  return profile != null &&
      measurements.isLoaded &&
      measurements.measurements.isEmpty &&
      profile.compositionLog.isEmpty;
}

/// A speech bubble whose tail points down at the Scan button.
class _ScanTip extends StatelessWidget {
  const _ScanTip({required this.onTap, required this.onClose});

  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      key: const ValueKey('scan-tip'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: colors.inverseSurface,
          elevation: 4,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      'Tap here to take your first body scan',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onInverseSurface,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('scan-tip-close'),
                    onPressed: onClose,
                    tooltip: 'Dismiss',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      Icons.close,
                      size: 18,
                      color: colors.onInverseSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        CustomPaint(
          size: const Size(20, 10),
          painter: _TailPainter(colors.inverseSurface),
        ),
      ],
    );
  }
}

class _TailPainter extends CustomPainter {
  const _TailPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TailPainter old) => old.color != color;
}
