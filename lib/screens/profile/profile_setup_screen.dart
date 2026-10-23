import 'package:flutter/material.dart';

import '../../auth/auth_scope.dart';
import '../../community/community_models.dart';
import '../../community/community_service.dart';
import '../../core/input_limits.dart';
import '../../core/units.dart';
import '../../models/models.dart';
import '../../state/profile_scope.dart';
import '../widgets/date_of_birth_field.dart';
import '../widgets/scrubber_input.dart';
import 'choice_fields.dart';
import '../../core/snack_bar_timing.dart';

/// The same questions for first-time setup and for editing, laid out two ways.
///   isOnboarding = true:  shown by the app root on first launch. One question
///                         per page with Back and Continue, like program
///                         setup. Saving makes the root switch to the main
///                         app, so we don't pop.
///   isOnboarding = false: pushed from the Profile tab. The questions are
///                         grouped into folding sections ([ProfileEditSection])
///                         so the page stays short; Save is always at the
///                         bottom. Saving pops back.
class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({
    super.key,
    this.initialProfile,
    this.isOnboarding = false,
    this.suggestedName,
    this.suggestedDateOfBirth,
    this.openSection = ProfileEditSection.basics,
  });

  final UserProfile? initialProfile;

  /// Editing only: the section that starts open, such as Goals and training
  /// when the user tapped their goal on the Profile tab.
  final ProfileEditSection openSection;

  /// Fills the name box for a new profile (for example the account's name).
  /// It stays editable: it is the display name, not the account name.
  final String? suggestedName;

  /// Fills the date of birth for a new profile, from account creation.
  final DateTime? suggestedDateOfBirth;
  final bool isOnboarding;

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

/// The folding sections of the Edit profile page.
enum ProfileEditSection {
  basics('Basic information', Icons.badge_outlined),
  body('Body and units', Icons.straighten),
  training('Goals and training', Icons.fitness_center),
  lifestyle('Lifestyle', Icons.schedule),
  health('Health and limitations', Icons.health_and_safety_outlined),
  food('Food', Icons.restaurant_outlined);

  const ProfileEditSection(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// The first-time setup pages, in order, grouped into six sections:
///   1 basics, 2 goals and training, 3 lifestyle, 4 health and limitations,
///   5 food, 6 review.
/// Date of birth comes from account creation, so it is only asked when there
/// is none (Continue without an account).
enum _Step {
  name(_Section.basics),
  dateOfBirth(_Section.basics),
  sex(_Section.basics),
  height(_Section.basics),
  weight(_Section.basics),
  goal(_Section.training),
  experience(_Section.training),
  frequency(_Section.training),
  equipment(_Section.training),
  routine(_Section.lifestyle),
  duration(_Section.lifestyle),
  health(_Section.health),
  limitations(_Section.health),
  food(_Section.food),
  review(_Section.review);

  const _Step(this.section);
  final _Section section;
}

enum _Section {
  basics('Basic information'),
  training('Goals and training'),
  lifestyle('Lifestyle'),
  health('Health and limitations'),
  food('Food'),
  review('Review');

  const _Section(this.label);
  final String label;
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  /// The edit form. First-time setup gives each page its own form instead,
  /// so Continue checks only the question on screen.
  final _formKey = GlobalKey<FormState>();
  final Map<_Step, GlobalKey<FormState>> _stepForms = {
    for (final step in _Step.values) step: GlobalKey<FormState>(),
  };
  final PageController _pages = PageController();
  _Step _step = _Step.name;

  /// The pages this setup shows: every step, minus date of birth when the
  /// account already gave one.
  late final List<_Step> _steps;
  int get _pos => _steps.indexOf(_step);

  late final TextEditingController _name;

  /// Community username. Only for signed-in accounts: a guest has no
  /// identity friends could add. Optional, and set once.
  final TextEditingController _handle = TextEditingController();
  String? _existingHandle;
  String? _handleError;
  bool _canHaveHandle = false;

  /// Always centimetres and kilograms. The scrubbers show whatever [_units]
  /// says and convert on the way in and out.
  late double _heightCm;
  late double _weightKg;
  late HeightUnit _heightUnit;
  late WeightUnit _weightUnit;

  Sex? _sex;
  DateTime? _dateOfBirth;
  TrainingGoal? _goal;
  ExperienceLevel? _experience;
  TrainingFrequency? _frequency;
  List<EquipmentAccess> _equipment = [];

  /// PAR-Q+ answers, null until answered.
  late final List<bool?> _parq;
  List<LimitationArea> _limitations = [];
  late final TextEditingController _limitationNote;
  DailyRoutine? _routine;
  TimeBudget? _time;
  DietPattern? _diet;
  late final TextEditingController _allergies;

  bool _saving = false;
  AutovalidateMode _autovalidate = AutovalidateMode.disabled;

  /// Edit page: which sections are open. Bumping [_openGeneration] rebuilds
  /// the sections so they take [_open] again (used to open every section
  /// when a field needs fixing).
  late Set<ProfileEditSection> _open = {widget.openSection};
  int _openGeneration = 0;

  @override
  void initState() {
    super.initState();
    final p = widget.initialProfile;
    _name = TextEditingController(text: p?.name ?? widget.suggestedName ?? '');
    _dateOfBirth = p?.dateOfBirth ?? widget.suggestedDateOfBirth;
    // Mid-range starting points, so the scrubbers open somewhere sensible
    // for someone who has not set them yet.
    _heightCm = p?.heightCm ?? 165;
    _weightKg = p?.weightKg ?? 65;
    _heightUnit = p?.heightUnit ?? HeightUnit.cm;
    _weightUnit = p?.weightUnit ?? WeightUnit.kg;
    _sex = p?.sex;
    _goal = p?.goal;
    _experience = p?.experience;
    _frequency = p?.trainingFrequency;
    _equipment = List.of(p?.equipment ?? const <EquipmentAccess>[]);
    _parq = List<bool?>.of(
      p?.parqAnswers ?? List<bool?>.filled(kParqQuestions.length, null),
    );
    _limitations = List.of(p?.limitations ?? const <LimitationArea>[]);
    _limitationNote = TextEditingController(text: p?.limitationNote ?? '');
    _routine = p?.dailyRoutine;
    // An older profile shows the answer matching its session length.
    _time =
        p?.timeBudget ??
        (p == null ? null : TimeBudget.fromDuration(p.sessionDuration));
    _diet = p?.dietPattern;
    _allergies = TextEditingController(text: p?.foodAllergies ?? '');
    _steps = [
      for (final step in _Step.values)
        if (step != _Step.dateOfBirth || _dateOfBirth == null) step,
    ];
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Looked up softly: a screen shown without accounts simply has no field.
    final auth = context.getInheritedWidgetOfExactType<AuthScope>()?.notifier;
    final uid = auth?.user?.uid;
    final can = auth != null && !auth.isGuest && uid != null;
    if (can == _canHaveHandle) return;
    _canHaveHandle = can;
    if (can) _loadHandle(uid);
  }

  Future<void> _loadHandle(String uid) async {
    try {
      final existing = await communityService.profileOf(uid);
      if (mounted && existing != null) {
        setState(() => _existingHandle = existing.handle);
      }
    } catch (_) {
      // Offline: the field stays empty and can be filled in Community later.
    }
  }

  /// Claims the typed username. Returns false only when the user must fix
  /// it (taken or badly formed); a connection problem does not block saving
  /// the profile, since Community can ask again later.
  Future<bool> _claimHandle(ScaffoldMessengerState messenger) async {
    final handle = _handle.text.trim().toLowerCase().replaceFirst('@', '');
    if (!_canHaveHandle || _existingHandle != null || handle.isEmpty) {
      return true;
    }
    final uid = AuthScope.of(context, listen: false).user!.uid;
    final error = await communityService.claimHandle(
      uid: uid,
      handle: handle,
      displayName: _name.text.trim(),
    );
    if (!mounted) return false;
    if (error == null) {
      setState(() => _existingHandle = handle);
      return true;
    }
    if (error == kHandleTaken || validateHandle(handle) != null) {
      setState(() => _handleError = error);
      return false;
    }
    messenger.showSnackBar(
      const SnackBar(duration: kSnackBarDuration, persist: false,
        content: Text(
          "Your username couldn't be saved right now. You can set it in "
          'Community later.',
        ),
      ),
    );
    return true;
  }

  @override
  void dispose() {
    _name.dispose();
    _handle.dispose();
    _limitationNote.dispose();
    _allergies.dispose();
    _pages.dispose();
    super.dispose();
  }

  // Height and weight come from scrubbers, which cannot produce a bad value,
  // so only the typed fields are validated. The scrubber ranges are generous limits
  // for a usable ruler, not a claim about what is realistic.

  static String? _validateName(String? text) =>
      (text == null || text.trim().isEmpty) ? 'Enter your name' : null;

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final controller = ProfileScope.of(context, listen: false);

    // First-time setup has already checked every page on the way here.
    if (!widget.isOnboarding && !_formKey.currentState!.validate()) {
      setState(() {
        _autovalidate = AutovalidateMode.onUserInteraction;
        // Open every section, so the field to fix can be seen.
        _open = {...ProfileEditSection.values};
        _openGeneration++;
      });
      messenger.showSnackBar(
        const SnackBar(duration: kSnackBarDuration, persist: false,
          content: Text('Fix the highlighted fields to continue.'),
        ),
      );
      return;
    }

    // Age always comes from the date of birth. A profile saved before dates
    // of birth existed keeps its stored age until one is chosen.
    final dob = _dateOfBirth;
    final age = dob != null ? calculateAge(dob) : widget.initialProfile!.age;
    final old = widget.initialProfile;

    // Session length follows the time answer, except when an older profile
    // still shows the answer read from its own length (15 or 90+ minutes
    // would otherwise be changed without being asked).
    final keepDuration =
        old != null &&
        old.timeBudget == null &&
        _time == TimeBudget.fromDuration(old.sessionDuration);
    final duration = keepDuration ? old.sessionDuration : _time!.duration;
    // Daily activity follows the routine answer only when that answer
    // changed, so a level picked on the Nutrition card is not overwritten
    // by an unrelated profile edit.
    final activity = _routine != null && _routine != old?.dailyRoutine
        ? _routine!.activityLevel
        : old?.activityLevel;
    final parq = _parq.contains(null) ? old?.parqAnswers : _parq.cast<bool>();
    // A clearance was given for the old answers; new answers need a new one.
    final sameAnswers =
        old?.parqAnswers != null &&
        parq != null &&
        List.generate(parq.length, (i) => parq[i] == old!.parqAnswers![i])
            .every((same) => same);
    final cleared = sameAnswers && old!.medicallyCleared;

    final profile = UserProfile(
      name: _name.text.trim(),
      age: age,
      dateOfBirth: dob,
      sex: _sex!,
      heightCm: _heightCm,
      weightKg: _weightKg,
      heightUnit: _heightUnit,
      weightUnit: _weightUnit,
      goal: _goal!,
      experience: _experience!,
      trainingFrequency: _frequency!,
      sessionDuration: duration,
      equipment: _equipment,
      parqAnswers: parq,
      medicallyCleared: cleared,
      limitations: _limitations,
      limitationNote: _limitationNote.text.trim(),
      dailyRoutine: _routine,
      timeBudget: _time,
      dietPattern: _diet,
      foodAllergies: _allergies.text.trim(),
      // Carried over, not edited here: without them every profile edit
      // would wipe the weight history, the activity answer and the saved
      // body composition estimates.
      weightLog: widget.initialProfile?.weightLog ?? const [],
      activityLevel: activity,
      compositionLog: widget.initialProfile?.compositionLog ?? const [],
    );

    setState(() => _saving = true);
    if (!await _claimHandle(messenger)) {
      if (!mounted) return;
      setState(() => _saving = false);
      // The username error is shown on the first page.
      if (widget.isOnboarding) _goTo(_Step.name);
      return;
    }
    try {
      await controller.save(profile);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        const SnackBar(duration: kSnackBarDuration, persist: false, content: Text("Couldn't save your profile. Try again.")),
      );
      return;
    }

    if (!mounted) return;
    if (!widget.isOnboarding) Navigator.of(context).pop();
  }

  // ---- moving between pages (first-time setup only) ----

  bool get _isLastStep => _step == _steps.last;

  void _goTo(_Step step) {
    FocusScope.of(context).unfocus();
    setState(() => _step = step);
    _pages.animateToPage(
      _steps.indexOf(step),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _back() {
    if (_saving || _pos == 0) return;
    _goTo(_steps[_pos - 1]);
  }

  void _continue() {
    if (!(_stepForms[_step]!.currentState?.validate() ?? true)) return;
    if (_isLastStep) {
      _save();
      return;
    }
    _goTo(_steps[_pos + 1]);
  }

  // ---- UI ----

  @override
  Widget build(BuildContext context) =>
      widget.isOnboarding ? _buildWizard() : _buildEditForm();

  Widget _buildWizard() {
    final theme = Theme.of(context);
    final total = _steps.length;

    return PopScope(
      // The system back button steps back a page instead of leaving setup.
      canPop: _pos == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Set up your profile'),
          automaticallyImplyLeading: false,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(28),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_step.section.label} · Step ${_pos + 1} of $total',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (_pos + 1) / total,
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
            children: [for (final step in _steps) _wizardPage(step)],
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                if (_pos > 0) ...[
                  Expanded(
                    child: OutlinedButton(
                      key: const ValueKey('wizard-back'),
                      onPressed: _saving ? null : _back,
                      child: const Text('Back'),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    key: const ValueKey('wizard-continue'),
                    onPressed: _saving ? null : _continue,
                    child: Text(_isLastStep ? 'Save profile' : 'Continue'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// One question, with its own form so Continue checks only this page.
  /// Each page scrolls on its own, so a long list of chips still fits.
  Widget _wizardPage(_Step step) {
    final theme = Theme.of(context);
    final (title, hint, child) = switch (step) {
      _Step.name => (
        'What should we call you?',
        'Tell us a bit about you to get started. This is the name shown '
            'in the app.',
        _nameFields(),
      ),
      _Step.dateOfBirth => (
        'When were you born?',
        'Used to work out your age for your targets.',
        _dateOfBirthField(),
      ),
      _Step.sex => (
        'What is your sex?',
        'Used for body composition and nutrition estimates.',
        _sexField(label: null),
      ),
      _Step.height => (
        'How tall are you?',
        'Drag the ruler to set it.',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _heightUnitToggle(),
            const SizedBox(height: 20),
            _heightField(),
          ],
        ),
      ),
      _Step.weight => (
        'How much do you weigh?',
        'Drag the ruler to set it. You can log changes later.',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _weightUnitToggle(),
            const SizedBox(height: 20),
            _weightField(),
          ],
        ),
      ),
      _Step.health => (
        'A few health questions',
        'A standard safety check before you get more active. Your answers stay '
            'private and do not change your program.',
        _healthFields(),
      ),
      _Step.limitations => (
        'Any injuries or pain?',
        'Optional. New programs avoid exercises that load these areas where '
            'possible and flag the rest for review.',
        _limitationFields(),
      ),
      _Step.goal => (
        'What is your main goal?',
        'New programs start from this goal.',
        _goalField(label: null),
      ),
      _Step.experience => (
        'Have you done weight training before?',
        'Choose the one closest to you.',
        _experienceField(label: null),
      ),
      _Step.routine => (
        'What does a typical day look like for you?',
        'Used for your nutrition targets.',
        _routineField(label: null),
      ),
      _Step.frequency => (
        'How many days a week can you work out?',
        "Count the days you could realistically make time for, even if you "
            "don't work out yet. You can change this later.",
        _frequencyField(label: null),
      ),
      _Step.duration => (
        'How much time can you realistically set aside for exercise?',
        'Think about your usual schedule, not your ideal schedule.',
        _durationField(label: null),
      ),
      _Step.equipment => (
        'What equipment can you use?',
        'Choose all that apply.',
        _equipmentField(label: null, helper: null),
      ),
      _Step.food => (
        'Anything you don\'t eat?',
        'Optional. Used to filter the example meals and shown with your '
            'nutrition targets. It does not change your calorie or protein '
            'numbers.',
        _foodFields(),
      ),
      _Step.review => (
        'Review your profile',
        'Check your answers before saving. Tap Edit to change a section.',
        _reviewSummary(),
      ),
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _stepForms[step],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.headlineSmall),
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
      ),
    );
  }

  Widget _buildEditForm() {
    final theme = Theme.of(context);
    const gap = SizedBox(height: 20);
    String orDash(String? s) => s == null || s.isEmpty ? 'Not set' : s;

    Widget section(
      ProfileEditSection s, {
      required String summary,
      required List<Widget> children,
    }) => Card(
      key: ValueKey('edit-section-${s.name}'),
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        // A new generation re-reads [_open]; otherwise the tile keeps its
        // own open or closed state.
        key: ValueKey('edit-tile-${s.name}-$_openGeneration'),
        initiallyExpanded: _open.contains(s),
        // Closed sections stay built, so Save still checks their fields.
        maintainState: true,
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(s.icon, color: theme.colorScheme.primary),
        title: Text(s.label, style: theme.textTheme.titleMedium),
        subtitle: Text(
          summary,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        onExpansionChanged: (open) =>
            open ? _open.add(s) : _open.remove(s),
        children: children,
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          autovalidateMode: _autovalidate,
          // Not a lazy list: every section stays built, so Save checks all
          // of them.
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                section(
                  ProfileEditSection.basics,
                  summary: [
                    orDash(_name.text.trim()),
                    if (_sex != null) _sex!.label,
                  ].join(' · '),
                  children: [
                    _nameFields(),
                    gap,
                    _dateOfBirthField(),
                    gap,
                    _sexField(),
                  ],
                ),
                section(
                  ProfileEditSection.body,
                  summary:
                      '${formatHeight(_heightCm, _heightUnit)} · '
                      '${formatWeight(_weightKg, _weightUnit)}',
                  children: [
                    // Height and weight are chosen separately: someone may
                    // know their height in feet and their weight in kilos.
                    Text('Units', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Text(
                      'The weight unit is used for your body weight and for '
                      'the weights you lift.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: _heightUnitToggle()),
                        const SizedBox(width: 16),
                        Expanded(child: _weightUnitToggle()),
                      ],
                    ),
                    gap,
                    _heightField(),
                    gap,
                    _weightField(),
                  ],
                ),
                section(
                  ProfileEditSection.training,
                  summary: [
                    if (_goal != null) _goal!.label,
                    if (_frequency != null) '${_frequency!.label} days a week',
                  ].join(' · '),
                  children: [
                    _goalField(),
                    gap,
                    _experienceField(),
                    gap,
                    _frequencyField(),
                    gap,
                    _equipmentField(),
                  ],
                ),
                section(
                  ProfileEditSection.lifestyle,
                  summary: orDash(_time?.label),
                  children: [_routineField(), gap, _durationField()],
                ),
                section(
                  ProfileEditSection.health,
                  summary: _limitations.isEmpty
                      ? 'Health questions · no injuries noted'
                      : 'Health questions · '
                            '${_limitations.map((l) => l.label).join(', ')}',
                  children: [
                    Text(
                      'Health questions',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    _healthFields(),
                    gap,
                    Text('Injuries or pain', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    _limitationFields(),
                  ],
                ),
                section(
                  ProfileEditSection.food,
                  summary: orDash(_diet?.label),
                  children: [_foodFields()],
                ),
              ],
            ),
          ),
        ),
      ),
      // Always in reach, however many sections are open.
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: const Text('Save profile'),
          ),
        ),
      ),
    );
  }

  // ---- the questions, shared by both layouts ----
  //
  // A choice field's label is left out on a setup page, where the page
  // heading already asks the question. Answers go straight into this state,
  // so a page rebuilt after Back starts from what was chosen.

  Widget _nameFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Name',
            border: OutlineInputBorder(),
          ),
          validator: _validateName,
        ),
        if (_canHaveHandle) ...[
          const SizedBox(height: 20),
          if (_existingHandle != null)
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Community username',
                helperText: 'Friends add you by this name.',
                border: OutlineInputBorder(),
              ),
              child: Text('@$_existingHandle'),
            )
          else
            TextFormField(
              key: const ValueKey('handle-field'),
              controller: _handle,
              autocorrect: false,
              decoration: InputDecoration(
                prefixText: '@',
                labelText: 'Nickname(optional)',
                helperText:
                    'Friends add you by this name.',
                errorText: _handleError,
                border: const OutlineInputBorder(),
              ),
              validator: (text) {
                final t = (text ?? '').trim().toLowerCase();
                return t.isEmpty ? null : validateHandle(t);
              },
              onChanged: (_) {
                if (_handleError != null) {
                  setState(() => _handleError = null);
                }
              },
            ),
        ],
      ],
    );
  }

  Widget _dateOfBirthField() => DateOfBirthField(
    key: const ValueKey('dob-field'),
    initialValue: _dateOfBirth,
    // Only an older profile with no date of birth may skip it.
    isRequired:
        widget.initialProfile?.dateOfBirth != null ||
        widget.initialProfile == null,
    onChanged: (picked) => setState(() => _dateOfBirth = picked),
  );

  Widget _sexField({String? label = 'Sex'}) => SingleChoiceField<Sex>(
    label: label,
    options: Sex.values,
    labelOf: (v) => v.label,
    initialValue: _sex,
    onChanged: (v) => setState(() => _sex = v),
  );

  Widget _heightUnitToggle() => _UnitToggle<HeightUnit>(
    caption: 'Height',
    options: HeightUnit.values,
    selected: _heightUnit,
    labelOf: (v) => v.short,
    onChanged: (v) => setState(() => _heightUnit = v),
  );

  Widget _weightUnitToggle() => _UnitToggle<WeightUnit>(
    caption: 'Weight',
    options: WeightUnit.values,
    selected: _weightUnit,
    labelOf: (v) => v.short,
    onChanged: (v) => setState(() => _weightUnit = v),
  );

  Widget _heightField() => _ScrubberField(
    label: 'Height',
    value: _heightUnit.isMetric
        ? _heightCm
        : inchesFromCm(_heightCm).roundToDouble(),
    min: _heightUnit.isMetric ? kMinHeightCm : 48,
    max: _heightUnit.isMetric ? kMaxHeightCm : 87,
    unit: _heightUnit.isMetric ? 'cm' : 'in',
    majorEvery: _heightUnit.isMetric ? 10 : 12,
    caption: _heightUnit.isMetric
        ? null
        : formatHeight(_heightCm, _heightUnit), // 5'9"
    onChanged: (value) => setState(() {
      _heightCm = _heightUnit.isMetric ? value : cmFromInches(value);
    }),
  );

  Widget _weightField() => _ScrubberField(
    label: 'Weight',
    value: _weightUnit.isMetric
        ? _weightKg
        : poundsFromKg(_weightKg).roundToDouble(),
    min: _weightUnit.isMetric ? kMinWeightKg : 66,
    max: _weightUnit.isMetric ? kMaxWeightKg : 550,
    unit: _weightUnit.short,
    onChanged: (value) => setState(() {
      _weightKg = _weightUnit.isMetric ? value : kgFromPounds(value);
    }),
  );

  Widget _goalField({String? label = 'Main goal'}) =>
      SingleChoiceField<TrainingGoal>(
        label: label,
        options: TrainingGoal.values,
        labelOf: (v) => v.label,
        initialValue: _goal,
        onChanged: (v) => setState(() => _goal = v),
      );

  Widget _experienceField({String? label = 'Weight training experience'}) =>
      DescribedChoiceField<ExperienceLevel>(
        label: label,
        options: ExperienceLevel.values,
        titleOf: (v) => v.question,
        descriptionOf: (v) => v.description,
        initialValue: _experience,
        onChanged: (v) => setState(() => _experience = v),
      );

  Widget _routineField({String? label = 'Typical day'}) =>
      DescribedChoiceField<DailyRoutine>(
        label: label,
        options: DailyRoutine.values,
        titleOf: (v) => v.label,
        descriptionOf: (v) => v.description,
        initialValue: _routine,
        // Older profiles may leave it; new ones must answer.
        isRequired: widget.isOnboarding,
        onChanged: (v) => setState(() => _routine = v),
      );

  /// The PAR-Q+ questions, with its advice shown as soon as any is YES.
  /// Required in first-time setup; an older profile may leave them.
  Widget _healthFields() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < kParqQuestions.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: SingleChoiceField<bool>(
              key: ValueKey('parq-$i'),
              label: '${i + 1}. ${kParqQuestions[i]}',
              options: const [true, false],
              labelOf: (v) => v ? 'Yes' : 'No',
              initialValue: _parq[i],
              isRequired: widget.isOnboarding,
              onChanged: (v) => setState(() => _parq[i] = v),
            ),
          ),
        if (parqAdvice(
              parqConcern(_parq.map((a) => a ?? false).toList()),
            )
            case final advice?)
          Card(
            key: const ValueKey('parq-advice'),
            margin: EdgeInsets.zero,
            color: theme.colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                advice,
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),
          ),
      ],
    );
  }

  Widget _limitationFields() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      MultiChoiceField<LimitationArea>(
        options: LimitationArea.values,
        labelOf: (v) => v.label,
        initialValue: _limitations,
        isRequired: false,
        onChanged: (v) => setState(() => _limitations = v),
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _limitationNote,
        maxLength: 200,
        decoration: const InputDecoration(
          labelText: 'Anything else? (optional)',
          border: OutlineInputBorder(),
        ),
      ),
    ],
  );

  Widget _foodFields() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SingleChoiceField<DietPattern>(
        options: DietPattern.values,
        labelOf: (v) => v.label,
        initialValue: _diet,
        isRequired: false,
        onChanged: (v) => setState(() => _diet = v),
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _allergies,
        maxLength: 200,
        decoration: const InputDecoration(
          labelText: 'Allergies, intolerances or foods you avoid (optional)',
          hintText: 'For example: shrimp, peanuts, milk',
          border: OutlineInputBorder(),
        ),
      ),
    ],
  );

  /// The answers so far, one card per section, each with what it is used for
  /// and an Edit button back to its first page.
  Widget _reviewSummary() {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    String or(String? v) => v ?? 'Not answered';
    final parqYes = _parq.where((a) => a == true).length;
    final allergies = _allergies.text.trim();
    final note = _limitationNote.text.trim();

    final sections = <(_Section, List<String>, String)>[
      (
        _Section.basics,
        [
          _name.text.trim(),
          if (_dateOfBirth != null)
            'Age ${calculateAge(_dateOfBirth!)}',
          or(_sex?.label),
          formatHeight(_heightCm, _heightUnit),
          formatWeight(_weightKg, _weightUnit),
        ],
        'Used for body analysis and your nutrition targets.',
      ),
      (
        _Section.training,
        [
          or(_goal?.label),
          or(_experience?.question),
          _frequency == null
              ? 'Days a week: not answered'
              : '${_frequency!.label} days a week',
          _equipment.isEmpty
              ? 'Equipment: not answered'
              : _equipment.map((e) => e.label).join(', '),
        ],
        'Shapes the exercises, sets and schedule of your programs.',
      ),
      (
        _Section.lifestyle,
        [or(_routine?.label), or(_time?.label)],
        'Your typical day sets the activity level for nutrition. Your time '
            'sets how long program sessions are.',
      ),
      (
        _Section.health,
        [
          _parq.contains(null)
              ? 'Health questions: not finished'
              : parqYes == 0
              ? 'Health questions: all NO'
              : 'Health questions: $parqYes YES',
          _limitations.isEmpty
              ? 'No injuries noted'
              : _limitations.map((l) => l.label).join(', '),
          if (note.isNotEmpty) note,
        ],
        'Health answers only give safety tips. Injuries make new programs avoid '
            'exercises that load those areas.',
      ),
      (
        _Section.food,
        [
          _diet?.label ?? 'No restrictions given',
          if (allergies.isNotEmpty) 'Avoid: $allergies',
        ],
        'Filters the example meals. Does not change calorie or protein '
            'targets.',
      ),
    ];

    return Column(
      children: [
        for (final (section, lines, use) in sections)
          Card(
            key: ValueKey('review-${section.name}'),
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          section.label,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      TextButton(
                        onPressed: () => _goTo(
                          _steps.firstWhere((s) => s.section == section),
                        ),
                        child: const Text('Edit'),
                      ),
                    ],
                  ),
                  for (final line in lines) Text(line),
                  const SizedBox(height: 6),
                  Text(use, style: muted),
                ],
              ),
            ),
          ),
        if (parqAdvice(parqConcern(_parq.map((a) => a ?? false).toList()))
            case final advice?)
          Text(
            advice,
            style: TextStyle(color: theme.colorScheme.error),
          ),
      ],
    );
  }

  Widget _frequencyField({String? label = 'Days a week you can work out'}) =>
      SingleChoiceField<TrainingFrequency>(
        label: label,
        options: TrainingFrequency.values,
        labelOf: (v) => v.label,
        initialValue: _frequency,
        onChanged: (v) => setState(() => _frequency = v),
      );

  Widget _durationField({String? label = 'Time for exercise'}) =>
      SingleChoiceField<TimeBudget>(
        label: label,
        options: TimeBudget.values,
        labelOf: (v) => v.label,
        initialValue: _time,
        onChanged: (v) => setState(() => _time = v),
      );

  Widget _equipmentField({
    String? label = 'Equipment',
    String? helper = 'Choose all that apply.',
  }) => MultiChoiceField<EquipmentAccess>(
    label: label,
    helper: helper,
    options: EquipmentAccess.values,
    labelOf: (v) => v.label,
    initialValue: _equipment,
    onChanged: (v) => setState(() => _equipment = v),
  );
}

/// A labelled scrubber, laid out like the other fields on this screen.
class _ScrubberField extends StatelessWidget {
  const _ScrubberField({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.unit,
    required this.onChanged,
    this.majorEvery = 10,
    this.caption,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String unit;
  final ValueChanged<double> onChanged;
  final int majorEvery;

  /// Shown under the ruler, for a value that reads better another way, such
  /// as inches also shown as feet and inches.
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.titleSmall),
        ScrubberInput(
          value: value,
          min: min,
          max: max,
          unit: unit,
          majorEvery: majorEvery,
          onChanged: onChanged,
        ),
        if (caption != null)
          Center(
            child: Text(
              caption!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

/// A two-option unit toggle with a small caption above it.
class _UnitToggle<T> extends StatelessWidget {
  const _UnitToggle({
    required this.caption,
    required this.options,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
  });

  final String caption;
  final List<T> options;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          caption,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        SegmentedButton<T>(
          segments: [
            for (final option in options)
              ButtonSegment<T>(value: option, label: Text(labelOf(option))),
          ],
          selected: {selected},
          showSelectedIcon: false,
          onSelectionChanged: (choice) => onChanged(choice.first),
        ),
      ],
    );
  }
}
