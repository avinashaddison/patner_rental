import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:companion_ranchi/core/models/json_utils.dart';
import 'package:companion_ranchi/core/models/user_model.dart';
import 'package:companion_ranchi/core/network/api_client.dart';
import 'package:companion_ranchi/core/network/uploads_repository.dart';

/// A single referral entry inside `GET /referrals/me`.
class ReferralEntry {
  const ReferralEntry({
    required this.id,
    required this.status,
    required this.rewardAmount,
    required this.rewarded,
    this.referredName,
    this.createdAt,
    this.rewardedAt,
  });

  final String id;

  /// `PENDING` | `COMPLETED` | `EXPIRED`.
  final String status;
  final double rewardAmount;
  final bool rewarded;
  final String? referredName;
  final DateTime? createdAt;
  final DateTime? rewardedAt;

  factory ReferralEntry.fromJson(Map<String, dynamic> json) {
    // The referred user may arrive nested as `referred: { fullName }` or flat.
    String? name = J.asStringOrNull(json['referredName']);
    if (name == null && json['referred'] is Map) {
      name = J.asStringOrNull((json['referred'] as Map)['fullName']);
    }
    return ReferralEntry(
      id: J.asString(json['id']),
      status: J.asString(json['status'], 'PENDING'),
      rewardAmount: J.asDouble(json['rewardAmount'], 100),
      rewarded: J.asBool(json['rewarded']),
      referredName: name,
      createdAt: J.asDate(json['createdAt']),
      rewardedAt: J.asDate(json['rewardedAt']),
    );
  }
}

/// Aggregated referral summary for the profile referral card
/// (`GET /referrals/me`).
class ReferralSummary {
  const ReferralSummary({
    required this.referralCode,
    required this.totalReferred,
    required this.totalCompleted,
    required this.totalEarned,
    required this.referrals,
  });

  final String referralCode;
  final int totalReferred;

  /// Referees who completed a qualifying booking (reward earned).
  final int totalCompleted;
  final double totalEarned;
  final List<ReferralEntry> referrals;

  /// Invited friends who haven't earned a reward yet.
  int get totalPending =>
      (totalReferred - totalCompleted).clamp(0, totalReferred);

  factory ReferralSummary.fromJson(Map<String, dynamic> json) {
    final list = json['referrals'];
    return ReferralSummary(
      referralCode: J.asString(json['referralCode']),
      totalReferred: J.asInt(json['totalReferred']),
      totalCompleted: J.asInt(json['totalCompleted']),
      totalEarned: J.asDouble(json['totalEarned']),
      referrals: (list is List ? list : const [])
          .whereType<Map>()
          .map((e) => ReferralEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false),
    );
  }
}

/// Data access for the profile domain. Talks to `/users/me`, `/uploads/presign`
/// and `/referrals/me` (API.md sections 2, 13, 15).
class ProfileRepository {
  ProfileRepository(this._api, this._uploads);

  final ApiClient _api;
  final UploadsRepository _uploads;

  /// `GET /users/me` → the signed-in user's profile.
  Future<UserModel> fetchMe() async {
    final data = await _api.getJson('/users/me');
    final map = J.asMap(data);
    final userJson = map['user'] is Map ? J.asMap(map['user']) : map;
    if (map['companion'] != null) userJson['companion'] = map['companion'];
    return UserModel.fromJson(userJson);
  }

  /// `PATCH /users/me` → update editable fields. Only non-null values are sent.
  Future<UserModel> updateProfile({
    String? fullName,
    String? city,
    String? email,
    String? profilePhotoUrl,
  }) async {
    final body = <String, dynamic>{
      if (fullName != null) 'fullName': fullName,
      if (city != null) 'city': city,
      if (email != null) 'email': email,
      if (profilePhotoUrl != null) 'profilePhotoUrl': profilePhotoUrl,
    };
    final data = await _api.patchJson('/users/me', body: body);
    final map = J.asMap(data);
    final userJson = map['user'] is Map ? J.asMap(map['user']) : map;
    if (map['companion'] != null) userJson['companion'] = map['companion'];
    return UserModel.fromJson(userJson);
  }

  /// `GET /referrals/me` → referral code, totals and the list of referrals.
  Future<ReferralSummary> fetchReferralSummary() async {
    final data = await _api.getJson('/referrals/me');
    return ReferralSummary.fromJson(J.asMap(data));
  }

  /// Upload a profile photo to R2 (folder `profile`) and return its public URL.
  /// Delegates to the shared [UploadsRepository] so the upload flow is identical
  /// to every other media upload in the app.
  Future<String> uploadProfilePhoto({
    required List<int> bytes,
    required String fileName,
    required String contentType,
  }) {
    return _uploads.uploadBytes(
      bytes: bytes,
      fileName: fileName,
      contentType: contentType,
      folder: 'profile',
    );
  }
}

/// App-wide [ProfileRepository] provider, wired to the shared [ApiClient].
final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(
    ref.watch(apiClientProvider),
    ref.watch(uploadsRepositoryProvider),
  );
});
