import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:companion_ranchi/core/auth/auth_controller.dart';
import 'package:companion_ranchi/core/models/user_model.dart';
import 'package:companion_ranchi/features/profile/data/profile_repository.dart';

/// Referral summary for the profile referral card (`GET /referrals/me`).
final referralSummaryProvider =
    FutureProvider.autoDispose<ReferralSummary>((ref) async {
  final repo = ref.watch(profileRepositoryProvider);
  return repo.fetchReferralSummary();
});

/// Drives profile edits (PATCH /users/me) and the avatar upload. On success it
/// pushes the updated [UserModel] into [authControllerProvider] so the whole app
/// reflects the change immediately.
class ProfileEditController extends AutoDisposeAsyncNotifier<void> {
  ProfileRepository get _repo => ref.read(profileRepositoryProvider);

  @override
  Future<void> build() async {}

  /// Save edited profile fields. Returns true on success.
  Future<bool> save({
    String? fullName,
    String? city,
    String? email,
    String? profilePhotoUrl,
  }) async {
    state = const AsyncLoading();
    try {
      final user = await _repo.updateProfile(
        fullName: fullName,
        city: city,
        email: email,
        profilePhotoUrl: profilePhotoUrl,
      );
      ref.read(authControllerProvider.notifier).setUser(user);
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }

  /// Upload [bytes] as the new avatar then persist its URL on the profile.
  /// Returns the updated [UserModel] on success, or null on failure.
  Future<UserModel?> updateAvatar({
    required Uint8List bytes,
    required String fileName,
    required String contentType,
  }) async {
    state = const AsyncLoading();
    try {
      final url = await _repo.uploadProfilePhoto(
        bytes: bytes,
        fileName: fileName,
        contentType: contentType,
      );
      final user = await _repo.updateProfile(profilePhotoUrl: url);
      ref.read(authControllerProvider.notifier).setUser(user);
      state = const AsyncData(null);
      return user;
    } catch (e, st) {
      state = AsyncError(e, st);
      return null;
    }
  }
}

final profileEditControllerProvider =
    AutoDisposeAsyncNotifierProvider<ProfileEditController, void>(
  ProfileEditController.new,
);
