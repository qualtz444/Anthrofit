import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../auth/auth_scope.dart';
import '../../community/community_models.dart';
import '../../community/community_service.dart';
import '../../coaching/warm_cool.dart';
import '../../core/theme_mode_controller.dart';
import '../../core/units.dart';
import '../../data/storage_scope.dart';
import '../../models/user_profile.dart';
import '../../notifications/reminder_settings.dart';
import '../../photos/avatar_store.dart';
import '../../photos/progress_photo_store.dart';
import '../../state/measurement_scope.dart';
import '../../state/profile_scope.dart';
import '../../state/program_scope.dart';
import '../../state/session_scope.dart';
import '../auth/sign_in_screen.dart';
import '../auth/sign_up_screen.dart';
import '../community/community_screen.dart';
import '../legal/legal_screen.dart';
import '../../legal/legal_text.dart';
import '../nutrition/nutrition_targets_screen.dart';
import 'profile_setup_screen.dart';
import 'reminder_settings_screen.dart';
import '../../core/snack_bar_timing.dart';

/// The user's profile page: who they are (avatar, name, username), what they
/// have done (workouts, programs, scans), their training profile, settings,
/// account and community.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.picker, this.avatarStore});

  final ImagePicker? picker;
  final AvatarStore? avatarStore;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final ImagePicker _picker = widget.picker ?? ImagePicker();
  Uint8List? _avatarBytes;
  String? _loadedScopeId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = AuthScope.of(context);
    final scope = auth.dataScope;
    if (scope == null && !auth.isGuest) {
      _loadedScopeId = 'unavailable';
      _avatarBytes = null;
      return;
    }
    final resolvedScope = scope ?? StorageScope.guest;
    if (_loadedScopeId == resolvedScope.id) return;
    _loadedScopeId = resolvedScope.id;
    _avatarBytes = null;
    _loadAvatar(resolvedScope, auth.user?.uid);
  }

  Future<void> _loadAvatar(StorageScope scope, String? uid) async {
    Uint8List? localBytes;
    try {
      localBytes = await (widget.avatarStore ?? AvatarStore(scope: scope)).load();
    } catch (_) {
      if (!mounted) return;
    }
    var bytes = localBytes;
    if (uid != null) {
      try {
        bytes = (await communityService.profileOf(uid))?.avatarBytes ?? bytes;
      } catch (_) {
        // Keep the initials fallback when Community is offline.
      }
    }
    if (mounted && _loadedScopeId == scope.id) {
      setState(() => _avatarBytes = bytes);
    }
  }

  Future<void> _changeAvatar() async {
    final messenger = ScaffoldMessenger.of(context);
    final auth = AuthScope.of(context, listen: false);
    final scope = auth.dataScope;
    if (scope == null && !auth.isGuest) {
      _showAvatarMessage(messenger, 'Sign in to change your avatar.');
      return;
    }
    final resolvedScope = scope ?? StorageScope.guest;
    XFile? selected;
    try {
      selected = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );
    } catch (_) {
      if (mounted) _showAvatarMessage(messenger, "Couldn't open your gallery.");
      return;
    }
    if (selected == null || !mounted) return;

    final Uint8List bytes;
    try {
      bytes = await selected.readAsBytes();
      await (widget.avatarStore ?? AvatarStore(scope: resolvedScope)).save(bytes);
    } catch (_) {
      if (mounted) {
        _showAvatarMessage(
          messenger,
          "Couldn't save your avatar on this device. Please try again.",
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() => _avatarBytes = bytes);

    final uid = auth.isGuest ? null : auth.user?.uid;
    if (uid == null) {
      _showAvatarMessage(messenger, 'Avatar updated on this device.');
      return;
    }

    try {
      final publicProfile = await communityService.profileOf(uid);
      if (!mounted) return;
      if (publicProfile == null) {
        _showAvatarMessage(
          messenger,
          'Avatar saved on this device. Set up Community to share it with friends.',
        );
        return;
      }
      final shareable = await shrinkForSharing(bytes);
      if (!mounted) return;
      if (shareable == null) {
        _showAvatarMessage(
          messenger,
          "Avatar saved on this device, but couldn't be prepared for Community.",
        );
        return;
      }
      final error = await communityService.setAvatar(uid, shareable);
      if (mounted) {
        _showAvatarMessage(messenger, error ?? 'Avatar updated.');
      }
    } catch (_) {
      if (mounted) {
        _showAvatarMessage(
          messenger,
          'Avatar saved on this device, but could not be shared with friends. Try again when online.',
        );
      }
    }
  }

  void _showAvatarMessage(ScaffoldMessengerState messenger, String message) {
    messenger.showSnackBar(
      SnackBar(
        duration: kSnackBarDuration,
        persist: false,
        content: Text(message),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ProfileScope.of(context).profile;
    final auth = AuthScope.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    if (profile == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: const Center(child: Text('No profile yet.')),
      );
    }

    final initial = profile.name.trim().isEmpty
        ? '?'
        : profile.name.trim().substring(0, 1).toUpperCase();

    final workouts = SessionScope.of(context).completedSessions.length;
    final programs = ProgramScope.of(context).programs.length;
    final scans =
        MeasurementScope.of(context).measurements.length +
        profile.compositionLog.length;
    void edit(ProfileEditSection s) => _editProfile(context, profile, s);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          // ---- Who: avatar, name, username ----
          Card(
            key: const ValueKey('profile-header'),
            elevation: 0,
            color: colors.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              child: Column(
                children: [
                  Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      CircleAvatar(
                        key: const ValueKey('profile-avatar'),
                        radius: 40,
                        backgroundColor: colors.primary,
                        foregroundColor: colors.onPrimary,
                        backgroundImage: _avatarBytes == null
                            ? null
                            : MemoryImage(_avatarBytes!),
                        child: _avatarBytes == null
                            ? Text(
                                initial,
                                style: theme.textTheme.headlineMedium?.copyWith(
                                  color: colors.onPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                              )
                            : null,
                      ),
                      IconButton.filledTonal(
                        key: const ValueKey('profile-change-avatar'),
                        tooltip: 'Change avatar',
                        visualDensity: VisualDensity.compact,
                        onPressed: _changeAvatar,
                        icon: const Icon(Icons.camera_alt_outlined, size: 16),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    profile.name,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: colors.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  if (auth.isGuest)
                    Text(
                      'Guest Mode',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onPrimaryContainer,
                      ),
                    )
                  else
                    _HandleLine(uid: auth.user?.uid),
                  const SizedBox(height: 16),
                  // ---- What they have done ----
                  Row(
                    key: const ValueKey('profile-stats'),
                    children: [
                      _Stat(value: '$workouts', label: 'Workouts'),
                      _Stat(value: '$programs', label: 'Programs'),
                      _Stat(value: '$scans', label: 'Scans'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => edit(ProfileEditSection.basics),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Edit profile'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ---- Training profile: a grid, each opening its section ----
          const _SectionHeading('Training profile'),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.9,
            children: [
              _InfoTile(
                icon: Icons.track_changes_outlined,
                label: 'Goal',
                value: profile.goal.label,
                onTap: () => edit(ProfileEditSection.training),
              ),
              _InfoTile(
                icon: Icons.star_outline,
                label: 'Experience',
                value: profile.experience.label,
                onTap: () => edit(ProfileEditSection.training),
              ),
              _InfoTile(
                icon: Icons.calendar_today_outlined,
                label: 'Frequency',
                value: '${profile.trainingFrequency.label} days a week',
                onTap: () => edit(ProfileEditSection.training),
              ),
              _InfoTile(
                icon: Icons.timer_outlined,
                label: 'Time for exercise',
                value:
                    profile.timeBudget?.label ?? profile.sessionDuration.label,
                onTap: () => edit(ProfileEditSection.lifestyle),
              ),
              _InfoTile(
                icon: Icons.height,
                label: 'Height',
                value: formatHeight(profile.heightCm, heightUnitOf(context)),
                onTap: () => edit(ProfileEditSection.body),
              ),
              _InfoTile(
                icon: Icons.monitor_weight_outlined,
                label: 'Weight',
                value: formatWeight(profile.weightKg, unitsOf(context)),
                onTap: () => edit(ProfileEditSection.body),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _SettingsTile(
            icon: Icons.fitness_center_outlined,
            title: 'Equipment',
            subtitle: profile.equipment.isEmpty
                ? 'Bodyweight'
                : profile.equipment.map((e) => e.label).join(' · '),
            onTap: () => edit(ProfileEditSection.training),
          ),
          const SizedBox(height: 20),

          // ---- Settings ----
          const _SectionHeading('Settings'),
          const SizedBox(height: 8),
          _SettingsTile(
            key: const ValueKey('units-setting'),
            icon: Icons.scale_outlined,
            title: 'Units',
            subtitle:
                'Weights in ${profile.weightUnit.short} · height in '
                '${profile.heightUnit.short}',
            onTap: () => _pickUnits(context, profile),
          ),
          _SettingsTile(
            icon: Icons.restaurant_outlined,
            title: 'Nutrition targets',
            subtitle: profile.activityLevel?.label ?? 'Set your daily activity',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const NutritionTargetsScreen(),
              ),
            ),
          ),
          ValueListenableBuilder<ReminderSettings>(
            valueListenable: reminderSettings,
            builder: (context, s, _) => _SettingsTile(
              icon: Icons.notifications_outlined,
              title: 'Reminders',
              subtitle: s.enabled
                  ? 'Training days at '
                        '${TimeOfDay(hour: s.hour, minute: s.minute).format(context)}'
                  : 'Off',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ReminderSettingsScreen(),
                ),
              ),
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: warmCoolSettings,
            builder: (context, on, _) => SwitchListTile(
              key: const ValueKey('warm-cool-setting'),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 2,
              ),
              secondary: Icon(
                Icons.self_improvement,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: const Text('Warm-up and cool-down'),
              subtitle: Text(
                on ? 'Suggested before and after each workout' : 'Off',
              ),
              value: on,
              onChanged: warmCoolSettings.set,
            ),
          ),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeMode,
            builder: (context, mode, _) => _SettingsTile(
              icon: Icons.dark_mode_outlined,
              title: 'Appearance',
              subtitle: themeModeLabel(mode),
              onTap: () => _pickThemeMode(context, mode),
            ),
          ),
          const SizedBox(height: 20),

          // ---- Community ----
          const _SectionHeading('Community'),
          const SizedBox(height: 8),
          _CommunityCard(isGuest: auth.isGuest, uid: auth.user?.uid),
          const SizedBox(height: 20),

          // ---- Account ----
          const _SectionHeading('Account'),
          const SizedBox(height: 8),
          if (auth.isGuest) ...[
            _SettingsTile(
              icon: Icons.person_add_alt_1_outlined,
              title: 'Create Account',
              subtitle: 'Register to use account features',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const SignUpScreen()),
                );
              },
            ),
            _SettingsTile(
              icon: Icons.login_outlined,
              title: 'Sign In',
              subtitle: 'Already have an account?',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const SignInScreen()),
                );
              },
            ),
          ] else ...[
            Card(
              elevation: 0,
              color: colors.surfaceContainerLow,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (auth.account != null) ...[
                      _InfoRow(
                        label: 'First Name',
                        value: auth.account!.firstName,
                      ),
                      _InfoRow(
                        label: 'Last Name',
                        value: auth.account!.lastName,
                      ),
                      const SizedBox(height: 4),
                    ],
                    _InfoRow(
                      label: 'Email',
                      value:
                          auth.account?.email ??
                          auth.user?.email ??
                          'Not available',
                    ),
                    _InfoRow(
                      label: 'Email Verified',
                      value: (auth.user?.emailVerified ?? false) ? 'Yes' : 'No',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            _SettingsTile(
              icon: Icons.logout,
              title: 'Sign Out',
              subtitle: 'Sign out of your account on this device',
              onTap: () => AuthScope.of(context, listen: false).signOut(),
            ),
          ],
          _SettingsTile(
            key: const ValueKey('profile-legal'),
            icon: Icons.policy_outlined,
            title: 'Terms and Privacy',
            subtitle: 'What the app does with your data',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const LegalScreen(
                  documents: [kTermsOfService, kPrivacyPolicy],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Text(
              'ANTHROFIT',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.onSurfaceVariant,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Weight unit (body weight and every lifted weight) and height unit.
  /// Saved straight to the profile; stored values never change, only how
  /// they are shown and what a typed number means.
  Future<void> _pickUnits(BuildContext context, UserProfile profile) async {
    final messenger = ScaffoldMessenger.of(context);
    final controller = ProfileScope.of(context, listen: false);
    var weight = profile.weightUnit;
    var height = profile.heightUnit;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialog) => AlertDialog(
          title: const Text('Units'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Weights'),
              const SizedBox(height: 4),
              const Text(
                'Your body weight and the weights you lift.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              SegmentedButton<WeightUnit>(
                key: const ValueKey('units-weight'),
                showSelectedIcon: false,
                segments: [
                  for (final u in WeightUnit.values)
                    ButtonSegment(value: u, label: Text(u.short)),
                ],
                selected: {weight},
                onSelectionChanged: (s) => setDialog(() => weight = s.first),
              ),
              const SizedBox(height: 16),
              const Text('Height'),
              const SizedBox(height: 8),
              SegmentedButton<HeightUnit>(
                key: const ValueKey('units-height'),
                showSelectedIcon: false,
                segments: [
                  for (final u in HeightUnit.values)
                    ButtonSegment(value: u, label: Text(u.short)),
                ],
                selected: {height},
                onSelectionChanged: (s) => setDialog(() => height = s.first),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('units-save'),
              onPressed: () => Navigator.of(c).pop(true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (weight == profile.weightUnit && height == profile.heightUnit) return;
    try {
      await controller.save(
        profile.copyWith(weightUnit: weight, heightUnit: height),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(duration: kSnackBarDuration, persist: false, content: Text("Couldn't save your units. Try again.")),
      );
    }
  }

  void _editProfile(
    BuildContext context,
    UserProfile profile, [
    ProfileEditSection section = ProfileEditSection.basics,
  ]) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ProfileSetupScreen(initialProfile: profile, openSection: section),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      leading: Icon(icon, color: colors.primary),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

Future<void> _pickThemeMode(BuildContext context, ThemeMode current) async {
  final picked = await showDialog<ThemeMode>(
    context: context,
    builder: (c) => SimpleDialog(
      title: const Text('Appearance'),
      children: [
        for (final m in ThemeMode.values)
          ListTile(
            key: ValueKey('theme-${m.name}'),
            leading: Icon(
              m == current
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
            ),
            title: Text(themeModeLabel(m)),
            onTap: () => Navigator.of(c).pop(m),
          ),
      ],
    ),
  );
  if (picked != null) await themeMode.set(picked);
}

/// "@ben" under the name, once a Community username exists.
class _HandleLine extends StatefulWidget {
  const _HandleLine({required this.uid});

  final String? uid;

  @override
  State<_HandleLine> createState() => _HandleLineState();
}

class _HandleLineState extends State<_HandleLine> {
  late Future<CommunityProfile?> _profile = _load();

  Future<CommunityProfile?> _load() async {
    final uid = widget.uid;
    if (uid == null) return null;
    try {
      return await communityService.profileOf(uid);
    } catch (_) {
      return null; // offline: show the plain line
    }
  }

  @override
  void didUpdateWidget(_HandleLine old) {
    super.didUpdateWidget(old);
    if (old.uid != widget.uid) _profile = _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<CommunityProfile?>(
      future: _profile,
      builder: (context, snap) => Text(
        snap.data == null ? 'ANTHROFIT member' : '@${snap.data!.handle}',
        key: const ValueKey('profile-handle'),
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

/// A number and what it counts, in the header.
class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onPrimaryContainer;
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(label, style: theme.textTheme.bodySmall?.copyWith(color: color)),
        ],
      ),
    );
  }
}

/// One fact of the training profile, as a small box.
class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: colors.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Icon(icon, color: colors.primary, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The Community part of the profile: the username friends add, and the
/// way in. Guests are told an account is needed.
class _CommunityCard extends StatelessWidget {
  const _CommunityCard({required this.isGuest, required this.uid});

  final bool isGuest;
  final String? uid;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      key: const ValueKey('profile-community'),
      elevation: 0,
      color: colors.surfaceContainerLow,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Icon(Icons.groups_outlined, color: colors.primary, size: 28),
        title: const Text('Friends and sharing'),
        subtitle: Text(
          isGuest
              ? 'Sign in to add friends and share your progress.'
              : 'Share progress, give kudos and see what friends are doing. '
                    'Only friends you accept see what you share.',
        ),
        trailing: isGuest ? null : const Icon(Icons.chevron_right),
        onTap: isGuest || uid == null
            ? null
            : () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const CommunityScreen()),
              ),
      ),
    );
  }
}
