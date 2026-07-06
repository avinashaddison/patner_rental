import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:companion_ranchi/core/auth/auth_controller.dart';
import 'package:companion_ranchi/core/constants/app_constants.dart';
import 'package:companion_ranchi/core/network/api_exception.dart';
import 'package:companion_ranchi/core/router/routes.dart';
import 'package:companion_ranchi/core/theme/app_theme.dart';
import 'package:companion_ranchi/features/settings/presentation/legal_links_text.dart';
import 'package:companion_ranchi/shared/widgets/app_text_field.dart';
import 'package:companion_ranchi/shared/widgets/gradient_button.dart';

/// Profile completion for new users (`POST /auth/register`).
///
/// Collects full name, gender, date of birth (18+ enforced client-side and
/// server-side), city, role (customer / companion) and an optional referral
/// code. On success the controller stores the real access + refresh tokens and
/// sets the session; companions are routed to onboarding, customers to home.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _referralController = TextEditingController();

  String _gender = Genders.all.first; // MALE
  String _role = UserRoles.customer;
  String _city = AppConstants.defaultCity;
  DateTime? _dateOfBirth;

  // Live @username availability: 'checking' | 'available' | 'taken' | 'invalid'.
  String? _usernameStatus;
  Timer? _usernameDebounce;

  bool _submitting = false;
  bool _agreed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Prefill the name from the Google profile for a smoother sign-up.
    final pending = ref.read(authControllerProvider.notifier).pendingFullName;
    if (pending != null && pending.trim().isNotEmpty) {
      _nameController.text = pending.trim();
    }
  }

  @override
  void dispose() {
    _usernameDebounce?.cancel();
    _nameController.dispose();
    _usernameController.dispose();
    _referralController.dispose();
    super.dispose();
  }

  /// Debounced live availability check as the user types their @username.
  void _onUsernameChanged(String raw) {
    _usernameDebounce?.cancel();
    final v = raw.trim();
    if (v.isEmpty) {
      setState(() => _usernameStatus = null);
      return;
    }
    if (v.length < 3 || v.length > 20) {
      setState(() => _usernameStatus = 'invalid');
      return;
    }
    setState(() => _usernameStatus = 'checking');
    _usernameDebounce = Timer(const Duration(milliseconds: 450), () async {
      try {
        final res = await ref
            .read(authControllerProvider.notifier)
            .checkUsernameAvailable(v);
        if (!mounted || _usernameController.text.trim() != v) return; // stale
        setState(() {
          _usernameStatus = res.available
              ? 'available'
              : (res.reason == 'taken' ? 'taken' : 'invalid');
        });
      } catch (_) {
        if (!mounted) return;
        setState(() => _usernameStatus = null); // network hiccup — let submit decide
      }
    });
  }

  /// Trailing icon reflecting the live availability state.
  Widget? _usernameSuffix() {
    switch (_usernameStatus) {
      case 'checking':
        return const Padding(
          padding: EdgeInsets.all(14),
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      case 'available':
        return const Icon(Icons.check_circle_rounded, color: AppColors.success);
      case 'taken':
      case 'invalid':
        return const Icon(Icons.cancel_rounded, color: AppColors.danger);
      default:
        return null;
    }
  }

  /// Small helper line under the username field.
  Widget _usernameHint() {
    final v = _usernameController.text.trim();
    String msg;
    Color color = AppColors.inkMuted;
    switch (_usernameStatus) {
      case 'checking':
        msg = 'Checking availability…';
        break;
      case 'available':
        msg = '@$v is available';
        color = AppColors.success;
        break;
      case 'taken':
        msg = '@$v is already taken';
        color = AppColors.danger;
        break;
      case 'invalid':
        msg = '3–20 chars: lowercase letters, numbers, underscore';
        color = AppColors.danger;
        break;
      default:
        return const SizedBox(height: 4);
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 4),
      child: Text(msg, style: TextStyle(fontSize: 12, color: color)),
    );
  }

  /// Age in whole years as of today.
  int _ageFrom(DateTime dob) {
    final now = DateTime.now();
    var years = now.year - dob.year;
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      years--;
    }
    return years;
  }

  String _formatDob(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]} ${d.year}';
  }

  /// ISO `YYYY-MM-DD` for the API.
  String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate() async {
    final now = DateTime.now();
    // Latest selectable date is the user's 18th-birthday cutoff.
    final maxDate = DateTime(now.year - AppConstants.minAge, now.month, now.day);
    final initial = _dateOfBirth ??
        DateTime(now.year - 22, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(maxDate) ? maxDate : initial,
      firstDate: DateTime(now.year - 100),
      lastDate: maxDate,
      helpText: 'Select your date of birth',
      builder: (context, child) => child ?? const SizedBox.shrink(),
    );
    if (picked != null) {
      setState(() {
        _dateOfBirth = picked;
        _error = null;
      });
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _error = null);

    final formValid = _formKey.currentState?.validate() ?? false;
    final dob = _dateOfBirth;
    if (dob == null) {
      setState(() => _error = 'Please select your date of birth.');
      return;
    }
    if (_ageFrom(dob) < AppConstants.minAge) {
      setState(() => _error =
          'You must be at least ${AppConstants.minAge} years old to use '
          '${AppConstants.appName}.');
      return;
    }
    if (!_agreed) {
      setState(() => _error =
          'Please confirm you are ${AppConstants.minAge}+ and accept the Terms '
          'of Service, Privacy Policy and Community Guidelines to continue.');
      return;
    }
    if (!formValid) return;

    setState(() => _submitting = true);
    try {
      final user = await ref.read(authControllerProvider.notifier).register(
            fullName: _nameController.text.trim(),
            username: _usernameController.text.trim(),
            gender: _gender,
            dateOfBirth: _isoDate(dob),
            city: _city,
            role: _role,
            referralCode: _referralController.text.trim().isEmpty
                ? null
                : _referralController.text.trim().toUpperCase(),
          );
      if (!mounted) return;
      // Session is now active. Send companions to onboarding, others home.
      if (user.isCompanion) {
        context.go(Routes.companionOnboarding);
      } else {
        context.go(Routes.home);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _submitting = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not create your profile. Please try again.';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create your profile'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Tell us a bit about you',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'You must be ${AppConstants.minAge}+ to continue. Your details '
                  'help us keep the community safe and verified.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.inkMuted,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),

                // ---- Full name ----
                AppTextField(
                  controller: _nameController,
                  label: 'Full name',
                  hint: 'e.g. Aisha Kumari',
                  prefixIcon: const Icon(Icons.person_outline_rounded),
                  textInputAction: TextInputAction.next,
                  keyboardType: TextInputType.name,
                  enabled: !_submitting,
                  validator: (value) {
                    final v = (value ?? '').trim();
                    if (v.isEmpty) return 'Please enter your full name.';
                    if (v.length < 3) {
                      return 'Name must be at least 3 characters.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.lg),

                // ---- Username (@handle) ----
                AppTextField(
                  controller: _usernameController,
                  label: 'Username',
                  hint: 'e.g. aisha_ranchi',
                  prefixIcon: const Icon(Icons.alternate_email_rounded),
                  suffixIcon: _usernameSuffix(),
                  textInputAction: TextInputAction.next,
                  enabled: !_submitting,
                  maxLength: 20,
                  inputFormatters: [_UsernameInputFormatter()],
                  onChanged: _onUsernameChanged,
                  validator: (value) {
                    final v = (value ?? '').trim();
                    if (v.isEmpty) return 'Please choose a username.';
                    if (v.length < 3) {
                      return 'Username must be at least 3 characters.';
                    }
                    if (v.length > 20) {
                      return 'Username must be at most 20 characters.';
                    }
                    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(v)) {
                      return 'Use lowercase letters, numbers and underscores only.';
                    }
                    if (_usernameStatus == 'taken') {
                      return 'That username is already taken.';
                    }
                    return null;
                  },
                ),
                _usernameHint(),
                const SizedBox(height: AppSpacing.lg),

                // ---- Gender ----
                _FieldLabel('Gender'),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  children: Genders.all.map((g) {
                    final selected = _gender == g;
                    return ChoiceChip(
                      label: Text(Genders.label(g)),
                      selected: selected,
                      onSelected: _submitting
                          ? null
                          : (_) => setState(() => _gender = g),
                      labelStyle: TextStyle(
                        color: selected ? Colors.white : null,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: AppSpacing.lg),

                // ---- Date of birth ----
                _FieldLabel('Date of birth'),
                const SizedBox(height: AppSpacing.sm),
                _DobField(
                  value:
                      _dateOfBirth == null ? null : _formatDob(_dateOfBirth!),
                  age: _dateOfBirth == null ? null : _ageFrom(_dateOfBirth!),
                  enabled: !_submitting,
                  onTap: _submitting ? null : _pickDate,
                ),
                const SizedBox(height: AppSpacing.lg),

                // ---- City ----
                _FieldLabel('City'),
                const SizedBox(height: AppSpacing.sm),
                _CityField(
                  value: _city,
                  enabled: !_submitting,
                  onChanged: (v) => setState(() => _city = v),
                ),
                const SizedBox(height: AppSpacing.lg),

                // ---- Role ----
                _FieldLabel('I want to join as'),
                const SizedBox(height: AppSpacing.sm),
                _RoleSelector(
                  role: _role,
                  enabled: !_submitting,
                  onChanged: (r) => setState(() => _role = r),
                ),
                const SizedBox(height: AppSpacing.lg),

                // ---- Referral code (optional) ----
                AppTextField(
                  controller: _referralController,
                  label: 'Referral code (optional)',
                  hint: 'Enter a friend\'s code',
                  prefixIcon: const Icon(Icons.card_giftcard_rounded),
                  textInputAction: TextInputAction.done,
                  enabled: !_submitting,
                  onSubmitted: (_) => _submit(),
                ),

                const SizedBox(height: AppSpacing.lg),

                // ---- Consent gate (required) ----
                _ConsentCheckbox(
                  value: _agreed,
                  enabled: !_submitting,
                  onChanged: (v) => setState(() {
                    _agreed = v;
                    if (v) _error = null;
                  }),
                ),

                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _ErrorBanner(message: _error!),
                ],

                const SizedBox(height: AppSpacing.xl),
                GradientButton(
                  label: 'Create profile',
                  isLoading: _submitting,
                  onPressed: (_submitting || !_agreed) ? null : _submit,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Companion Ranchi is a companionship marketplace for public, '
                  'social activities only — never an escort or adult service.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.inkMuted,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Forces @username input to lowercase and strips anything but [a-z0-9_], so the
/// field can only ever hold a server-valid handle.
class _UsernameInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final filtered =
        newValue.text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');
    return TextEditingValue(
      text: filtered,
      selection: TextSelection.collapsed(offset: filtered.length),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
        color: theme.brightness == Brightness.dark
            ? AppColors.darkInk
            : AppColors.ink,
      ),
    );
  }
}

class _DobField extends StatelessWidget {
  const _DobField({
    required this.value,
    required this.age,
    required this.enabled,
    required this.onTap,
  });

  final String? value;
  final int? age;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final hasValue = value != null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radius),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkField : AppColors.field,
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          border: Border.all(
            color: isDark ? AppColors.darkLine : AppColors.line,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.cake_outlined, color: AppColors.inkMuted, size: 22),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                hasValue ? value! : 'Select your date of birth',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: hasValue
                      ? (isDark ? AppColors.darkInk : AppColors.ink)
                      : AppColors.inkMuted,
                  fontWeight: hasValue ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (age != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: age! >= AppConstants.minAge
                      ? AppColors.success.withValues(alpha: 0.12)
                      : AppColors.danger.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                ),
                child: Text(
                  '$age yrs',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: age! >= AppConstants.minAge
                        ? AppColors.success
                        : AppColors.danger,
                  ),
                ),
              )
            else
              const Icon(Icons.calendar_today_rounded,
                  color: AppColors.inkMuted, size: 18),
          ],
        ),
      ),
    );
  }
}

class _CityField extends StatelessWidget {
  const _CityField({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkField : AppColors.field,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: Border.all(
          color: isDark ? AppColors.darkLine : AppColors.line,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_city_rounded,
              color: AppColors.inkMuted, size: 22),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: AppConstants.cities.contains(value)
                    ? value
                    : AppConstants.cities.first,
                isExpanded: true,
                borderRadius: BorderRadius.circular(AppSpacing.radius),
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: isDark ? AppColors.darkInk : AppColors.ink,
                  fontWeight: FontWeight.w600,
                ),
                items: AppConstants.cities
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: enabled
                    ? (v) {
                        if (v != null) onChanged(v);
                      }
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleSelector extends StatelessWidget {
  const _RoleSelector({
    required this.role,
    required this.enabled,
    required this.onChanged,
  });

  final String role;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _RoleCard(
            title: 'Find a companion',
            subtitle: 'Book verified companions for social activities.',
            icon: Icons.person_search_rounded,
            selected: role == UserRoles.customer,
            enabled: enabled,
            onTap: () => onChanged(UserRoles.customer),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: _RoleCard(
            title: 'Become a companion',
            subtitle: 'Earn by offering your time. KYC required.',
            icon: Icons.workspace_premium_rounded,
            selected: role == UserRoles.companion,
            enabled: enabled,
            onTap: () => onChanged(UserRoles.companion),
          ),
        ),
      ],
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(AppSpacing.radius),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.08)
              : (isDark ? AppColors.darkField : AppColors.field),
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : (isDark ? AppColors.darkLine : AppColors.line),
            width: selected ? 1.8 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(
                  icon,
                  color: selected ? AppColors.primary : AppColors.inkMuted,
                  size: 26,
                ),
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected ? AppColors.primary : AppColors.inkMuted,
                  size: 20,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: selected
                    ? AppColors.primary
                    : (isDark ? AppColors.darkInk : AppColors.ink),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.inkMuted,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Required agreement checkbox gating the "Create profile" button. The label
/// links to the Terms of Service, Privacy Policy and Community Guidelines.
class _ConsentCheckbox extends StatelessWidget {
  const _ConsentCheckbox({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 24,
          width: 24,
          child: Checkbox(
            value: value,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: enabled ? (v) => onChanged(v ?? false) : null,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: const Padding(
            padding: EdgeInsets.only(top: 2),
            child: LegalConsentText(
              prefix: 'I am ${AppConstants.minAge}+ and agree to the ',
              confirmAge: false,
              textAlign: TextAlign.start,
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppColors.danger, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppColors.danger, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
