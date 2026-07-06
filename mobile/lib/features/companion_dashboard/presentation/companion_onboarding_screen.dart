import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import 'package:companion_ranchi/core/constants/app_constants.dart';
import 'package:companion_ranchi/core/models/category_model.dart';
import 'package:companion_ranchi/core/router/routes.dart';
import 'package:companion_ranchi/core/theme/app_theme.dart';
import 'package:companion_ranchi/features/companion_dashboard/application/onboarding_controller.dart';
import 'package:companion_ranchi/features/companion_dashboard/data/kyc_models.dart';
import 'package:companion_ranchi/features/home/application/home_providers.dart';
import 'package:companion_ranchi/shared/widgets/widgets.dart';

/// Multi-step "Become a Companion" onboarding:
/// 1. Profile — aboutMe, languages, interests, hourlyRate, categories
///    (`POST /companions/me`).
/// 2. Photos — pick + upload via `/uploads/presign` → `POST /companions/me/photos`.
/// 3. KYC — upload GOVERNMENT_ID + SELFIE via `/kyc/submit`.
/// 4. Done — submitted for approval (pending state).
class CompanionOnboardingScreen extends ConsumerWidget {
  const CompanionOnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingControllerProvider);
    final stepIndex = state.step.index;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Become a Companion'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(Routes.home);
            }
          },
        ),
      ),
      body: Column(
        children: [
          _StepIndicator(currentIndex: stepIndex),
          Expanded(
            child: switch (state.step) {
              OnboardingStep.profile => const _ProfileStep(),
              OnboardingStep.photos => const _PhotosStep(),
              OnboardingStep.kyc => const _KycStep(),
              OnboardingStep.done => const _DoneStep(),
            },
          ),
        ],
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.currentIndex});

  final int currentIndex;

  static const _labels = ['Profile', 'Photos', 'KYC', 'Review'];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(
        children: List.generate(_labels.length, (i) {
          final active = i <= currentIndex;
          final isLast = i == _labels.length - 1;
          return Expanded(
            child: Row(
              children: [
                Column(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: active ? AppColors.primary : AppColors.field,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: active ? AppColors.primary : AppColors.line,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: i < currentIndex
                          ? const Icon(Icons.check,
                              size: 16, color: Colors.white)
                          : Text(
                              '${i + 1}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color:
                                    active ? Colors.white : AppColors.inkMuted,
                              ),
                            ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _labels[i],
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        color: active ? AppColors.primary : AppColors.inkMuted,
                      ),
                    ),
                  ],
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      height: 2,
                      margin: const EdgeInsets.only(bottom: 18),
                      color: i < currentIndex
                          ? AppColors.primary
                          : AppColors.line,
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

// =============================================================================
// Step 1 — Profile
// =============================================================================

class _ProfileStep extends ConsumerStatefulWidget {
  const _ProfileStep();

  @override
  ConsumerState<_ProfileStep> createState() => _ProfileStepState();
}

class _ProfileStepState extends ConsumerState<_ProfileStep> {
  late final TextEditingController _aboutCtrl;
  late final TextEditingController _rateCtrl;

  @override
  void initState() {
    super.initState();
    final state = ref.read(onboardingControllerProvider);
    _aboutCtrl = TextEditingController(text: state.aboutMe);
    _rateCtrl = TextEditingController(
      text: state.hourlyRate > 0 ? state.hourlyRate.toStringAsFixed(0) : '',
    );
  }

  @override
  void dispose() {
    _aboutCtrl.dispose();
    _rateCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(onboardingControllerProvider);
    final controller = ref.read(onboardingControllerProvider.notifier);
    final categoriesAsync = ref.watch(homeCategoriesProvider);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        const SafetyBanner(
          message:
              'Companion Ranchi is a companionship service for public social '
              'activities only — never escort or adult services. You must be 18+.',
        ),
        const SizedBox(height: AppSpacing.lg),
        AppTextField(
          controller: _aboutCtrl,
          label: 'About you',
          hint: 'Tell customers what you enjoy and the company you offer…',
          maxLines: 4,
          maxLength: 500,
          showCounter: true,
          onChanged: controller.setAboutMe,
        ),
        const SizedBox(height: AppSpacing.lg),
        AppTextField(
          controller: _rateCtrl,
          label: 'Hourly rate (₹)',
          hint: 'e.g. 600',
          helperText:
              'Customers see this rate — the platform fee is deducted from it.',
          keyboardType: TextInputType.number,
          prefixIcon: const Icon(Icons.currency_rupee_rounded),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (v) =>
              controller.setHourlyRate(double.tryParse(v) ?? 0),
        ),
        const SizedBox(height: AppSpacing.lg),
        _ChipGroup(
          label: 'Activities you offer',
          child: categoriesAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => const Text(
              'Could not load categories.',
              style: TextStyle(color: AppColors.danger),
            ),
            data: (categories) => _CategoryWrap(
              categories: categories,
              selectedIds: state.categoryIds,
              onToggle: controller.toggleCategory,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _ChipGroup(
          label: 'Languages',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final lang in AppLanguages.all)
                CategoryChip(
                  label: lang,
                  selected: state.languages.contains(lang),
                  onTap: () => controller.toggleLanguage(lang),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _ChipGroup(
          label: 'Interests (optional)',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final interest in AppInterests.all)
                CategoryChip(
                  label: interest,
                  selected: state.interests.contains(interest),
                  onTap: () => controller.toggleInterest(interest),
                ),
            ],
          ),
        ),
        if (state.error != null) ...[
          const SizedBox(height: AppSpacing.md),
          _ErrorText(state.error!),
        ],
        const SizedBox(height: AppSpacing.xl),
        GradientButton(
          label: 'Continue',
          icon: Icons.arrow_forward_rounded,
          isLoading: state.isSubmitting,
          onPressed: state.isSubmitting ? null : controller.submitProfile,
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

class _CategoryWrap extends StatelessWidget {
  const _CategoryWrap({
    required this.categories,
    required this.selectedIds,
    required this.onToggle,
  });

  final List<CategoryModel> categories;
  final List<String> selectedIds;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) {
      return const Text(
        'No categories available.',
        style: TextStyle(color: AppColors.inkMuted),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final c in categories)
          CategoryChip(
            label: c.name,
            icon: AppCategories.bySlug(c.slug)?.icon,
            emoji: AppCategories.bySlug(c.slug)?.emoji,
            selected: selectedIds.contains(c.id),
            onTap: () => onToggle(c.id),
          ),
      ],
    );
  }
}

// =============================================================================
// Step 2 — Photos
// =============================================================================

class _PhotosStep extends ConsumerWidget {
  const _PhotosStep();

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    final picker = ImagePicker();
    XFile? file;
    try {
      file = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1280,
        imageQuality: 85,
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the photo picker.')),
        );
      }
      return;
    }
    if (file == null) return;
    await ref
        .read(onboardingControllerProvider.notifier)
        .uploadPhoto(File(file.path));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingControllerProvider);
    final controller = ref.read(onboardingControllerProvider.notifier);
    final uploaded =
        state.photos.where((p) => p.isUploaded).toList(growable: false);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Text(
          'Add your photos',
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        const Text(
          'Clear, friendly photos help customers trust and choose you. The first '
          'photo becomes your primary profile picture.',
          style: TextStyle(color: AppColors.inkMuted),
        ),
        const SizedBox(height: AppSpacing.lg),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: AppSpacing.sm,
          mainAxisSpacing: AppSpacing.sm,
          children: [
            for (final photo in uploaded)
              _PhotoTile(url: photo.uploaded!.photoUrl, isPrimary: photo.isPrimary),
            _AddPhotoTile(
              isLoading: state.isSubmitting,
              onTap: state.isSubmitting ? null : () => _pick(context, ref),
            ),
          ],
        ),
        if (state.error != null) ...[
          const SizedBox(height: AppSpacing.md),
          _ErrorText(state.error!),
        ],
        const SizedBox(height: AppSpacing.xl),
        Row(
          children: [
            Expanded(
              child: AppButton.outline(
                label: 'Back',
                onPressed: () => controller.goTo(OnboardingStep.profile),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: AppButton(
                label: 'Continue',
                icon: Icons.arrow_forward_rounded,
                onPressed: state.hasUploadedPhoto
                    ? () => controller.goTo(OnboardingStep.kyc)
                    : null,
              ),
            ),
          ],
        ),
        if (!state.hasUploadedPhoto) ...[
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Add at least one photo to continue.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.url, required this.isPrimary});

  final String url;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.radius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: AppColors.field,
              child: const Icon(Icons.broken_image_outlined,
                  color: AppColors.inkMuted),
            ),
          ),
          if (isPrimary)
            Positioned(
              left: 4,
              bottom: 4,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Primary',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AddPhotoTile extends StatelessWidget {
  const _AddPhotoTile({required this.onTap, this.isLoading = false});

  final VoidCallback? onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppSpacing.radius),
      onTap: onTap,
      child: DottedBorderBox(
        child: Center(
          child: isLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                )
              : const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_a_photo_outlined,
                        color: AppColors.primary),
                    SizedBox(height: 4),
                    Text('Add',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        )),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Simple dashed-look bordered box (uses a solid subtle border for simplicity).
class DottedBorderBox extends StatelessWidget {
  const DottedBorderBox({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.4),
          width: 1.4,
        ),
      ),
      child: child,
    );
  }
}

// =============================================================================
// Step 3 — KYC
// =============================================================================

class _KycStep extends ConsumerWidget {
  const _KycStep();

  Future<void> _uploadDoc(
    BuildContext context,
    WidgetRef ref, {
    required String docType,
    required ImageSource source,
  }) async {
    final picker = ImagePicker();
    XFile? file;
    try {
      file = await picker.pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 85,
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the camera/gallery.')),
        );
      }
      return;
    }
    if (file == null) return;
    await ref.read(onboardingControllerProvider.notifier).submitKyc(
          documentType: docType,
          file: File(file.path),
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingControllerProvider);
    final controller = ref.read(onboardingControllerProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Text(
          'Verify your identity',
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        const Text(
          'For everyone\'s safety, we verify every companion. Upload a clear '
          'government ID and a selfie. Your documents are private and reviewed '
          'by our team.',
          style: TextStyle(color: AppColors.inkMuted),
        ),
        const SizedBox(height: AppSpacing.lg),
        _KycDocTile(
          title: 'Government ID',
          subtitle: 'Aadhaar, PAN, Driving Licence or Voter ID',
          icon: Icons.badge_outlined,
          status: _docStatus(state.kyc, KycDocType.governmentId),
          isBusy: state.isSubmitting,
          onUpload: () => _uploadDoc(
            context,
            ref,
            docType: KycDocType.governmentId,
            source: ImageSource.gallery,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _KycDocTile(
          title: 'Selfie',
          subtitle: 'A clear photo of your face',
          icon: Icons.face_outlined,
          status: _docStatus(state.kyc, KycDocType.selfie),
          isBusy: state.isSubmitting,
          onUpload: () => _uploadDoc(
            context,
            ref,
            docType: KycDocType.selfie,
            source: ImageSource.camera,
          ),
        ),
        if (state.error != null) ...[
          const SizedBox(height: AppSpacing.md),
          _ErrorText(state.error!),
        ],
        const SizedBox(height: AppSpacing.xl),
        Row(
          children: [
            Expanded(
              child: AppButton.outline(
                label: 'Back',
                onPressed: () => controller.goTo(OnboardingStep.photos),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: AppButton(
                label: 'Submit for review',
                icon: Icons.check_rounded,
                isLoading: state.isSubmitting,
                onPressed: state.kycComplete && !state.isSubmitting
                    ? controller.finish
                    : null,
              ),
            ),
          ],
        ),
        if (!state.kycComplete) ...[
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Upload both documents to submit your application.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }

  String? _docStatus(KycStatus kyc, String docType) {
    final matches = kyc.documents.where((d) => d.docType == docType);
    return matches.isEmpty ? null : matches.first.status;
  }
}

class _KycDocTile extends StatelessWidget {
  const _KycDocTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onUpload,
    this.status,
    this.isBusy = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onUpload;
  final String? status;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final uploaded = status != null;
    final approved = status == KycStatusValue.approved;
    final rejected = status == KycStatusValue.rejected;

    final Color accent = approved
        ? AppColors.success
        : rejected
            ? AppColors.danger
            : uploaded
                ? AppColors.info
                : AppColors.primary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: accent.withValues(alpha: 0.12),
              child: Icon(icon, color: accent),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    uploaded ? KycStatusValue.label(status!) : subtitle,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: uploaded ? accent : AppColors.inkMuted,
                      fontWeight:
                          uploaded ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            if (isBusy)
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              )
            else
              TextButton(
                onPressed: onUpload,
                child: Text(
                  uploaded && !rejected ? 'Replace' : 'Upload',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Step 4 — Done / pending approval
// =============================================================================

class _DoneStep extends ConsumerWidget {
  const _DoneStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.hourglass_top_rounded,
                  size: 48, color: AppColors.success),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Application submitted!',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your companion profile and KYC documents are under review. We '
              'usually verify within 24–48 hours. You will be notified once '
              'approved, and your profile will go live.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.inkMuted),
            ),
            const SizedBox(height: AppSpacing.xl),
            GradientButton(
              label: 'Go to dashboard',
              icon: Icons.dashboard_rounded,
              onPressed: () => context.go(Routes.companionDashboard),
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton.text(
              label: 'Back to home',
              onPressed: () => context.go(Routes.home),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Small shared bits
// =============================================================================

class _ChipGroup extends StatelessWidget {
  const _ChipGroup({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: AppSpacing.sm),
        child,
      ],
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 18, color: AppColors.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.danger,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
