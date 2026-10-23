import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../data/setup_options.dart';
import '../../data/workout_templates.dart';
import '../../models/models.dart';
import '../../state/profile_scope.dart';
import 'muscle_picker_sheet.dart';
import 'program_planner_screen.dart';
import '../widgets/muscle_image.dart';

/// The one way to start creating a program.
void startProgramCreation(BuildContext context) {
  Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const CreateProgramScreen()));
}

/// Program setup: first how to build it, then one question per page, Back
/// and Continue between them.
///
/// The first page offers two ways (app design choice):
///   Follow a training plan  the questions below, then a ready structure
///                           (Push Pull Legs, Upper Lower, Full Body)
///   Freestyle               only the goal and a name; the planner starts
///                           empty and the user adds every workout
///
/// The plan's questions:
///
/// Paged rather than one long scroll, so each question fits a phone screen
/// without hunting. The pages are driven only by the buttons (swiping is off),
/// so the order is the same every time.
///
///   1. goal              (starts from the profile)
///   2. session duration  (starts from the profile)
///   3. training focus    (long-press one to pick its muscles)
///   4. where you train   (starts from the profile)
///   5. the equipment in those places
///   6. structure
///   7. name, and Generate program
///
/// Every answer starts from the profile where there is one, so the whole
/// wizard can be clicked through unchanged. Changing an answer here changes
/// only this program, never the profile.
///
/// Nothing is saved until the planner saves it.
class CreateProgramScreen extends StatefulWidget {
  const CreateProgramScreen({super.key});

  @override
  State<CreateProgramScreen> createState() => _CreateProgramScreenState();
}

/// The questions, in order. Used for the step count and the page list.
enum _Step {
  start,
  goal,
  duration,
  focus,
  equipmentPlaces,
  equipmentItems,
  structure,
  name,
}

class _CreateProgramScreenState extends State<CreateProgramScreen> {
  final PageController _pages = PageController();
  final TextEditingController _name = TextEditingController();

  // The answers. Unchanged from the single-page version, and still gathered
  // into one ProgramSetup at the end.
  TrainingGoal? _goal;
  SessionDuration? _duration;
  TrainingFocus _focus = TrainingFocus.fullBody;
  late List<MuscleGroup> _muscles;
  late Set<EquipmentCategory> _categories;
  late List<EquipmentItem> _equipment;

  /// Ticked admin-added equipment, by id.
  late List<String> _extra;
  ProgramTemplate? _template;

  _Step _step = _Step.start;
  bool _nameEdited = false;

  /// Freestyle: skip the plan questions and start from an empty program.
  /// A training plan is the highlighted choice on the first page.
  bool _freestyle = false;

  /// The pages in this run, in order.
  List<_Step> get _flow =>
      _freestyle ? const [_Step.start, _Step.goal, _Step.name] : _Step.values;

  void _chooseStart({required bool freestyle}) {
    setState(() {
      _freestyle = freestyle;
      // Freestyle always starts empty; a plan asks for its structure later.
      _template = freestyle ? ProgramTemplate.custom : null;
      if (!_nameEdited) {
        _name.text = freestyle ? ProgramTemplate.custom.defaultName : '';
      }
      _showError = false;
    });
  }

  /// Set when Continue is pressed on a step that is not answered yet, so the
  /// explanation only appears once the user has tried to move on.
  bool _showError = false;

  @override
  void initState() {
    super.initState();
    // The profile only supplies the starting answers. It is never written to.
    final profile = ProfileScope.of(context, listen: false).profile;
    _goal = profile?.goal;
    _duration = profile?.sessionDuration;
    _muscles = defaultMusclesForFocus(_focus);
    _categories = categoriesFromProfile(profile);
    _equipment = equipmentForCategories(_categories);
    _extra = [for (final e in extraEquipmentForCategories(_categories)) e.id];
  }

  @override
  void dispose() {
    _pages.dispose();
    _name.dispose();
    super.dispose();
  }

  // ---- answers ----

  /// A tap picks the focus and takes every muscle it covers. The old
  /// selection is dropped, because it may not belong to the new focus at all.
  /// "Choose muscles" has nothing sensible to default to, so it opens the
  /// picker straight away.
  Future<void> _chooseFocus(TrainingFocus focus) async {
    setState(() {
      _focus = focus;
      _muscles = defaultMusclesForFocus(focus);
      _showError = false;
    });
    if (focus == TrainingFocus.chooseMuscles) await _customiseFocus(focus);
  }

  /// A long-press picks the focus too, then opens the picker so individual
  /// muscles can be turned off. Long-pressing the focus already chosen keeps
  /// the current selection; long-pressing another one starts from that
  /// focus's full set.
  ///
  /// The result replaces [_muscles], so the setup records the muscles the user
  /// actually chose, not just the name of the focus.
  Future<void> _customiseFocus(TrainingFocus focus) async {
    final startingPoint = focus == _focus && _muscles.isNotEmpty
        ? _muscles
        : defaultMusclesForFocus(focus);

    final picked = await showMusclePicker(
      context,
      focus: focus,
      selected: startingPoint,
    );
    if (picked == null || !mounted) return; // dismissed: change nothing
    setState(() {
      _focus = focus;
      _muscles = picked;
      _showError = false;
    });
  }

  /// Turning a place on or off changes which items exist, so the chosen items
  /// are re-filtered. Items the user already ticked stay ticked.
  void _toggleCategory(EquipmentCategory category, bool isOn) {
    final categories = {..._categories};
    if (isOn) {
      categories.add(category);
    } else {
      categories.remove(category);
    }
    final available = equipmentForCategories(categories);
    final kept = _equipment.toSet();
    // Worked out against the OLD places, so an item that has just become
    // available can be told from one the user deliberately unticked.
    final wasAvailable = equipmentForCategories(_categories).toSet();
    // The same for admin-added equipment.
    final keptExtra = _extra.toSet();
    final extraWasAvailable = {
      for (final e in extraEquipmentForCategories(_categories)) e.id,
    };
    setState(() {
      _categories = categories;
      _equipment = available
          .where((item) => kept.contains(item) || !wasAvailable.contains(item))
          .toList();
      _extra = [
        for (final e in extraEquipmentForCategories(categories))
          if (keptExtra.contains(e.id) || !extraWasAvailable.contains(e.id))
            e.id,
      ];
    });
  }

  void _toggleEquipment(EquipmentItem item, bool isOn) {
    final next = {..._equipment};
    if (isOn) {
      next.add(item);
    } else {
      next.remove(item);
    }
    setState(
      () => _equipment = equipmentForCategories(
        _categories,
      ).where(next.contains).toList(),
    );
  }

  void _toggleExtra(String id, bool isOn) {
    final next = {..._extra};
    if (isOn) {
      next.add(id);
    } else {
      next.remove(id);
    }
    setState(
      () => _extra = [
        for (final e in extraEquipmentForCategories(_categories))
          if (next.contains(e.id)) e.id,
      ],
    );
  }

  void _chooseTemplate(ProgramTemplate template) {
    setState(() {
      _template = template;
      // The default name follows the structure until the user types one.
      if (!_nameEdited) _name.text = template.defaultName;
    });
  }

  // ---- validation: the same rules as before, one step at a time ----

  /// Why the current step cannot be left yet, or null when it can.
  String? get _blocker {
    switch (_step) {
      case _Step.start:
        return null;
      case _Step.goal:
        return _goal == null ? 'Choose a goal' : null;
      case _Step.duration:
        return _duration == null ? 'Choose a session length' : null;
      case _Step.focus:
        return _muscles.isEmpty ? 'Choose at least one muscle' : null;
      case _Step.equipmentPlaces:
        return _categories.isEmpty ? 'Choose where you train' : null;
      case _Step.equipmentItems:
        return _equipment.isEmpty && _extra.isEmpty
            ? 'Choose at least one piece of equipment'
            : null;
      case _Step.structure:
        return _template == null ? 'Choose a program structure' : null;
      case _Step.name:
        return _name.text.trim().isEmpty ? 'Enter a program name' : null;
    }
  }

  bool get _isLastStep => _step == _Step.name;

  // ---- moving between steps ----

  void _goTo(_Step step) {
    setState(() {
      _step = step;
      _showError = false;
    });
    _pages.animateToPage(
      _flow.indexOf(step),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _back() {
    final at = _flow.indexOf(_step);
    if (at <= 0) {
      Navigator.of(context).pop();
      return;
    }
    _goTo(_flow[at - 1]);
  }

  void _continue() {
    if (_blocker != null) {
      setState(() => _showError = true);
      return;
    }
    if (_isLastStep) {
      _generate();
      return;
    }
    _goTo(_flow[_flow.indexOf(_step) + 1]);
  }

  void _generate() {
    final template = _template;
    final goal = _goal;
    final duration = _duration;
    if (template == null || goal == null) return;
    if (!_freestyle && duration == null) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ProgramPlannerScreen(
          template: template,
          goal: goal,
          initialName: _name.text.trim(),
          // Freestyle records no setup: none of those questions were asked.
          setup: _freestyle
              ? null
              : ProgramSetup(
                  goal: goal,
                  sessionDuration: duration!,
                  focus: _focus,
                  muscles: _muscles,
                  equipmentCategories: _categories,
                  equipment: _equipment,
                  extraEquipment: _extra,
                ),
        ),
      ),
    );
  }

  // ---- UI ----

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The first page (how to build it) is not counted as a question.
    final flow = _flow;
    final total = flow.length - 1;
    final number = flow.indexOf(_step);
    final blocker = _blocker;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Set up program'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  number == 0
                      ? 'Choose how to start'
                      : 'Step $number of $total',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: number / total,
                    minHeight: 4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: PageView(
          controller: _pages,
          // Driven by the buttons only, so the order is always the same.
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final step in flow)
              switch (step) {
                _Step.start => _startPage(),
                _Step.goal => _goalPage(),
                _Step.duration => _durationPage(),
                _Step.focus => _focusPage(),
                _Step.equipmentPlaces => _placesPage(),
                _Step.equipmentItems => _itemsPage(),
                _Step.structure => _structurePage(),
                _Step.name => _namePage(),
              },
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_showError && blocker != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    blocker,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const ValueKey('wizard-back'),
                      onPressed: _back,
                      child: Text(number == 0 ? 'Cancel' : 'Back'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      key: const ValueKey('wizard-continue'),
                      onPressed: _continue,
                      child: Text(
                        _isLastStep ? 'Generate program' : 'Continue',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Each page is its own scroll view, so a long list of chips still fits.
  Widget _page({required String title, String? hint, required Widget child}) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.headlineSmall),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                hint,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }

  Widget _startPage() => _page(
    title: 'How do you want to build this program?',
    hint: 'Questions you already answered in your profile start with your '
        'answer picked.',
    child: Column(
      children: [
        _StructureTile(
          key: const ValueKey('start-plan'),
          title: 'Follow a training plan',
          subtitle:
              'Answer a few questions, then start from Push Pull Legs, Upper '
              'Lower or Full Body. You can change everything later.',
          selected: !_freestyle,
          onTap: () => _chooseStart(freestyle: false),
        ),
        _StructureTile(
          key: const ValueKey('start-freestyle'),
          title: 'Freestyle',
          subtitle:
              'Skip the questions. Pick a goal and a name, then add your own '
              'workouts and training days.',
          selected: _freestyle,
          onTap: () => _chooseStart(freestyle: true),
        ),
      ],
    ),
  );

  Widget _goalPage() => _page(
    title: 'What is the main goal for this program?',
    hint:
        'It starts as your profile goal. Changing it here changes only '
        'this program, not your profile.',
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final goal in TrainingGoal.values)
          ChoiceChip(
            label: Text(goal.label),
            selected: _goal == goal,
            onSelected: (_) => setState(() => _goal = goal),
          ),
      ],
    ),
  );

  Widget _durationPage() => _page(
    title: 'How long should a session be?',
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final duration in SessionDuration.values)
          ChoiceChip(
            label: Text(duration.label),
            selected: _duration == duration,
            onSelected: (_) => setState(() => _duration = duration),
          ),
      ],
    ),
  );

  Widget _focusPage() {
    final theme = Theme.of(context);
    final covered = musclesForFocus(_focus);
    final isCustomised =
        _focus != TrainingFocus.chooseMuscles &&
        _muscles.length != covered.length;

    return _page(
      title: 'What should this program train?',
      hint:
          'Tap to choose. Long-press one to pick exactly which of its '
          'muscles to include.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final focus in TrainingFocus.values)
                GestureDetector(
                  key: ValueKey('focus-${focus.name}'),
                  onLongPress: () => _customiseFocus(focus),
                  child: ChoiceChip(
                    label: Text(focus.label),
                    selected: _focus == focus,
                    onSelected: (_) => _chooseFocus(focus),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            _muscles.isEmpty
                ? 'No muscles chosen'
                : '${pluralize(_muscles.length, 'muscle')} included'
                      '${isCustomised ? ' of ${covered.length}' : ''}',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          MuscleGallery(
            key: const ValueKey('focus-muscle-gallery'),
            muscles: _muscles,
            emptyText: 'Pick the muscles this program should train.',
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const ValueKey('edit-muscles'),
              icon: const Icon(Icons.tune),
              label: const Text('Edit muscles'),
              onPressed: () => _customiseFocus(_focus),
            ),
          ),
        ],
      ),
    );
  }

  Widget _placesPage() => _page(
    title: 'What equipment can you train with?',
    hint: 'Starts from your profile. Choose every place that applies.',
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final category in EquipmentCategory.values)
          FilterChip(
            label: Text(category.label),
            selected: _categories.contains(category),
            onSelected: (isOn) => _toggleCategory(category, isOn),
          ),
      ],
    ),
  );

  Widget _itemsPage() {
    final theme = Theme.of(context);
    final available = equipmentForCategories(_categories);
    return _page(
      title: 'Which of these do you have?',
      hint: available.isEmpty
          ? null
          : 'Only equipment from the places you chose is listed.',
      child: available.isEmpty
          ? Text(
              'Go back and choose where you train to see the equipment.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in available)
                  FilterChip(
                    label: Text(item.label),
                    selected: _equipment.contains(item),
                    onSelected: (isOn) => _toggleEquipment(item, isOn),
                  ),
                for (final item in extraEquipmentForCategories(_categories))
                  FilterChip(
                    key: ValueKey('extra-equipment-${item.id}'),
                    label: Text(item.label),
                    selected: _extra.contains(item.id),
                    onSelected: (isOn) => _toggleExtra(item.id, isOn),
                  ),
              ],
            ),
    );
  }

  Widget _structurePage() => _page(
    title: 'Program structure',
    hint:
        'This sets the workouts you start with. You can rename, add, '
        'remove and change everything afterward.',
    child: Column(
      children: [
        for (final template in ProgramTemplate.values)
          _StructureTile(
            key: ValueKey('structure-${template.name}'),
            title: template.label,
            subtitle: template.workouts.isEmpty
                ? 'Create your own workouts'
                : 'Creates ${template.workouts.map((w) => w.label).join(' · ')}',
            selected: _template == template,
            onTap: () => _chooseTemplate(template),
          ),
      ],
    ),
  );

  Widget _namePage() => _page(
    title: 'Name this program',
    hint: 'You can change it later.',
    child: TextField(
      key: const ValueKey('program-name'),
      controller: _name,
      textCapitalization: TextCapitalization.words,
      onChanged: (_) {
        _nameEdited = true;
        if (_showError) setState(() => _showError = false);
      },
      decoration: const InputDecoration(
        labelText: 'Program name',
        border: OutlineInputBorder(),
      ),
    ),
  );
}

class _StructureTile extends StatelessWidget {
  const _StructureTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected ? theme.colorScheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: ListTile(
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(subtitle),
          trailing: Icon(
            selected ? Icons.check_circle : Icons.circle_outlined,
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}
