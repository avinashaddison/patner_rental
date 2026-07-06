import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:companion_ranchi/core/auth/auth_controller.dart';
import 'package:companion_ranchi/core/models/companion_model.dart';
import 'package:companion_ranchi/features/companion_dashboard/application/companion_dashboard_providers.dart';
import 'package:companion_ranchi/features/companion_dashboard/data/companion_dashboard_repository.dart';
import 'package:companion_ranchi/features/companion_dashboard/data/kyc_models.dart';

/// The discrete steps of the become-a-companion flow.
enum OnboardingStep { profile, photos, kyc, done }

/// A locally-selected photo not yet uploaded, or one already uploaded.
class OnboardingPhoto {
  const OnboardingPhoto({this.localFile, this.uploaded, this.isPrimary = false});

  /// Set while the photo is pending upload.
  final File? localFile;

  /// Set once uploaded and registered.
  final CompanionPhoto? uploaded;
  final bool isPrimary;

  bool get isUploaded => uploaded != null;
}

/// Aggregate state for the multi-step onboarding wizard.
class OnboardingState {
  const OnboardingState({
    this.step = OnboardingStep.profile,
    this.aboutMe = '',
    this.hourlyRate = 0,
    this.languages = const [],
    this.interests = const [],
    this.categoryIds = const [],
    this.city = 'Ranchi',
    this.photos = const [],
    this.kyc = KycStatus.empty,
    this.profileCreated = false,
    this.isSubmitting = false,
    this.error,
  });

  final OnboardingStep step;

  // Profile form
  final String aboutMe;
  final double hourlyRate;
  final List<String> languages;
  final List<String> interests;

  /// Selected category **ids** (companion_categories expects ids).
  final List<String> categoryIds;
  final String city;

  // Photos
  final List<OnboardingPhoto> photos;

  // KYC
  final KycStatus kyc;

  final bool profileCreated;
  final bool isSubmitting;
  final String? error;

  bool get profileValid =>
      aboutMe.trim().length >= 10 &&
      hourlyRate > 0 &&
      languages.isNotEmpty &&
      categoryIds.isNotEmpty;

  bool get hasUploadedPhoto => photos.any((p) => p.isUploaded);

  bool get kycComplete => kyc.hasBothDocuments;

  OnboardingState copyWith({
    OnboardingStep? step,
    String? aboutMe,
    double? hourlyRate,
    List<String>? languages,
    List<String>? interests,
    List<String>? categoryIds,
    String? city,
    List<OnboardingPhoto>? photos,
    KycStatus? kyc,
    bool? profileCreated,
    bool? isSubmitting,
    Object? error = _noChange,
  }) {
    return OnboardingState(
      step: step ?? this.step,
      aboutMe: aboutMe ?? this.aboutMe,
      hourlyRate: hourlyRate ?? this.hourlyRate,
      languages: languages ?? this.languages,
      interests: interests ?? this.interests,
      categoryIds: categoryIds ?? this.categoryIds,
      city: city ?? this.city,
      photos: photos ?? this.photos,
      kyc: kyc ?? this.kyc,
      profileCreated: profileCreated ?? this.profileCreated,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      error: identical(error, _noChange) ? this.error : error as String?,
    );
  }

  static const _noChange = Object();
}

/// Drives the multi-step onboarding: profile create → photo upload → KYC
/// submit → submit-for-approval. Each network step matches API.md.
class OnboardingController extends Notifier<OnboardingState> {
  CompanionDashboardRepository get _repo =>
      ref.read(companionDashboardRepositoryProvider);

  @override
  OnboardingState build() => const OnboardingState();

  // ---- Profile form mutators ----
  void setAboutMe(String v) => state = state.copyWith(aboutMe: v, error: null);
  void setHourlyRate(double v) =>
      state = state.copyWith(hourlyRate: v, error: null);
  void setCity(String v) => state = state.copyWith(city: v);

  void toggleLanguage(String lang) {
    final next = List<String>.of(state.languages);
    if (next.contains(lang)) {
      next.remove(lang);
    } else {
      next.add(lang);
    }
    state = state.copyWith(languages: next, error: null);
  }

  void toggleInterest(String interest) {
    final next = List<String>.of(state.interests);
    if (next.contains(interest)) {
      next.remove(interest);
    } else {
      next.add(interest);
    }
    state = state.copyWith(interests: next);
  }

  void toggleCategory(String categoryId) {
    final next = List<String>.of(state.categoryIds);
    if (next.contains(categoryId)) {
      next.remove(categoryId);
    } else {
      next.add(categoryId);
    }
    state = state.copyWith(categoryIds: next, error: null);
  }

  void goTo(OnboardingStep step) => state = state.copyWith(step: step);

  /// Step 1 → create the companion profile (`POST /companions/me`), then
  /// advance to the photos step.
  Future<void> submitProfile() async {
    if (!state.profileValid) {
      state = state.copyWith(
        error: 'Please complete your bio, rate, language and category.',
      );
      return;
    }
    state = state.copyWith(isSubmitting: true, error: null);
    try {
      if (state.profileCreated) {
        await _repo.updateProfile(
          aboutMe: state.aboutMe.trim(),
          languages: state.languages,
          interests: state.interests,
          hourlyRate: state.hourlyRate,
          city: state.city,
          categoryIds: state.categoryIds,
        );
      } else {
        await _repo.createProfile(
          aboutMe: state.aboutMe.trim(),
          languages: state.languages,
          interests: state.interests,
          hourlyRate: state.hourlyRate,
          city: state.city,
          categoryIds: state.categoryIds,
        );
      }
      ref.invalidate(myCompanionProfileProvider);
      state = state.copyWith(
        isSubmitting: false,
        profileCreated: true,
        step: OnboardingStep.photos,
      );
    } catch (e) {
      state = state.copyWith(isSubmitting: false, error: _message(e));
    }
  }

  /// Step 2 → upload a photo (presign → PUT → `POST /companions/me/photos`).
  Future<void> uploadPhoto(File file) async {
    final isPrimary = !state.hasUploadedPhoto; // first photo becomes primary
    state = state.copyWith(isSubmitting: true, error: null);
    try {
      final photo = await _repo.uploadPhoto(file, isPrimary: isPrimary);
      state = state.copyWith(
        isSubmitting: false,
        photos: [
          ...state.photos,
          OnboardingPhoto(uploaded: photo, isPrimary: isPrimary),
        ],
      );
      ref.invalidate(myCompanionProfileProvider);
    } catch (e) {
      state = state.copyWith(isSubmitting: false, error: _message(e));
    }
  }

  /// Step 3 → submit a KYC document (`POST /kyc/submit`).
  Future<void> submitKyc({
    required String documentType,
    required File file,
    String? documentNumber,
  }) async {
    state = state.copyWith(isSubmitting: true, error: null);
    try {
      await _repo.submitKyc(
        documentType: documentType,
        file: file,
        documentNumber: documentNumber,
      );
      final status = await _repo.fetchKycStatus();
      state = state.copyWith(isSubmitting: false, kyc: status);
    } catch (e) {
      state = state.copyWith(isSubmitting: false, error: _message(e));
    }
  }

  /// Refresh the KYC status from the server.
  Future<void> refreshKyc() async {
    try {
      final status = await _repo.fetchKycStatus();
      state = state.copyWith(kyc: status);
    } catch (_) {
      // Non-fatal.
    }
  }

  /// Final step → mark the application as submitted for approval. The profile
  /// already exists (PENDING). We simply refresh auth + dashboard and move the
  /// wizard to the pending/done state.
  Future<void> finish() async {
    if (!state.kycComplete) {
      state = state.copyWith(
        error: 'Please upload both your Government ID and a Selfie.',
      );
      return;
    }
    state = state.copyWith(isSubmitting: true, error: null);
    try {
      // Refresh the user (role may now be COMPANION) and the companion profile.
      await ref.read(authControllerProvider.notifier).refreshUser();
      ref.invalidate(myCompanionProfileProvider);
      invalidateCompanionDashboard(ref);
      state = state.copyWith(isSubmitting: false, step: OnboardingStep.done);
    } catch (e) {
      state = state.copyWith(isSubmitting: false, error: _message(e));
    }
  }

  String _message(Object e) {
    final s = e.toString();
    // ApiException.toString() includes the code; show only the message tail.
    final idx = s.indexOf(': ');
    return idx >= 0 && idx < s.length - 2 ? s.substring(idx + 2) : s;
  }
}

final onboardingControllerProvider =
    NotifierProvider<OnboardingController, OnboardingState>(
  OnboardingController.new,
);
