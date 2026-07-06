import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:companion_ranchi/core/constants/app_constants.dart';
import 'package:companion_ranchi/core/models/user_model.dart';
import 'package:companion_ranchi/core/network/api_exception.dart';
import 'package:companion_ranchi/core/theme/app_theme.dart';
import 'package:companion_ranchi/features/profile/application/profile_providers.dart';
import 'package:companion_ranchi/shared/widgets/widgets.dart';

/// Bottom sheet to edit the editable profile fields exposed by
/// `PATCH /users/me`: full name, city, email. Mobile number and date of birth
/// are immutable (identity / age verification).
class EditProfileSheet extends ConsumerStatefulWidget {
  const EditProfileSheet({super.key, required this.user});

  final UserModel user;

  @override
  ConsumerState<EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends ConsumerState<EditProfileSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late String _city;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.user.fullName);
    _emailController = TextEditingController(text: widget.user.email ?? '');
    _city = (widget.user.city != null &&
            AppConstants.cities.contains(widget.user.city))
        ? widget.user.city!
        : AppConstants.cities.first;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final email = _emailController.text.trim();
    final ok = await ref.read(profileEditControllerProvider.notifier).save(
          fullName: _nameController.text.trim(),
          city: _city,
          email: email.isEmpty ? null : email,
        );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final editState = ref.watch(profileEditControllerProvider);
    final isSaving = editState.isLoading;
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg + viewInsets,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Edit profile',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppTextField(
                controller: _nameController,
                label: 'Full name',
                hint: 'Your name',
                prefixIcon: const Icon(Icons.person_outline_rounded),
                textInputAction: TextInputAction.next,
                validator: (v) {
                  final value = v?.trim() ?? '';
                  if (value.length < 2) return 'Enter your full name';
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                controller: _emailController,
                label: 'Email (optional)',
                hint: 'you@example.com',
                keyboardType: TextInputType.emailAddress,
                prefixIcon: const Icon(Icons.email_outlined),
                textInputAction: TextInputAction.done,
                validator: (v) {
                  final value = v?.trim() ?? '';
                  if (value.isEmpty) return null;
                  final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                  if (!emailRegex.hasMatch(value)) {
                    return 'Enter a valid email address';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'City',
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _city,
                items: AppConstants.cities
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setState(() => _city = v ?? _city),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.location_city_rounded),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _ReadOnlyRow(
                icon: Icons.phone_rounded,
                label: 'Mobile number',
                value: widget.user.mobileNumber,
              ),
              if (widget.user.dateOfBirth != null)
                _ReadOnlyRow(
                  icon: Icons.cake_rounded,
                  label: 'Date of birth',
                  value: '${widget.user.dateOfBirth!.day.toString().padLeft(2, '0')}'
                      '/${widget.user.dateOfBirth!.month.toString().padLeft(2, '0')}'
                      '/${widget.user.dateOfBirth!.year}',
                ),
              if (editState.hasError) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  editState.error is ApiException
                      ? (editState.error as ApiException).message
                      : 'Could not save. Please try again.',
                  style: const TextStyle(color: AppColors.danger, fontSize: 13),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              GradientButton(
                label: 'Save changes',
                icon: Icons.check_rounded,
                isLoading: isSaving,
                onPressed: isSaving ? null : _save,
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadOnlyRow extends StatelessWidget {
  const _ReadOnlyRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.inkMuted),
          const SizedBox(width: 10),
          Text(
            '$label: ',
            style: const TextStyle(color: AppColors.inkMuted, fontSize: 13),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
