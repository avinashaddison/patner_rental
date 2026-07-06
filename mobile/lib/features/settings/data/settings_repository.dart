import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:companion_ranchi/core/models/json_utils.dart';
import 'package:companion_ranchi/core/network/api_client.dart';

/// A user the signed-in account has blocked (`GET /users/blocks`). The block
/// row references the blocked user; the API embeds enough to render a row.
class BlockedUser {
  const BlockedUser({
    required this.id,
    required this.blockedId,
    this.fullName,
    this.profilePhotoUrl,
    this.createdAt,
  });

  /// The block record id (not the user id) — needed for the unblock call.
  final String id;

  /// The blocked user's id.
  final String blockedId;
  final String? fullName;
  final String? profilePhotoUrl;
  final DateTime? createdAt;

  factory BlockedUser.fromJson(Map<String, dynamic> json) {
    // The blocked user may be nested under `blocked` / `user`, or flat.
    final nested = json['blocked'] is Map
        ? J.asMap(json['blocked'])
        : (json['user'] is Map ? J.asMap(json['user']) : const {});

    final blockedId = J.asStringOrNull(json['blockedId']) ??
        J.asStringOrNull(nested['id']) ??
        J.asString(json['id']);

    return BlockedUser(
      id: J.asString(json['id']),
      blockedId: blockedId,
      fullName: J.asStringOrNull(json['fullName']) ??
          J.asStringOrNull(nested['fullName']),
      profilePhotoUrl: J.asStringOrNull(json['profilePhotoUrl']) ??
          J.asStringOrNull(nested['profilePhotoUrl']),
      createdAt: J.asDate(json['createdAt']),
    );
  }
}

/// Data access for account-settings concerns that hit the API: the blocked
/// users list and unblocking (`/users/blocks`, `/users/block/:blockedId`).
class SettingsRepository {
  SettingsRepository(this._api);

  final ApiClient _api;

  /// `GET /users/blocks` → users the account has blocked.
  Future<List<BlockedUser>> fetchBlockedUsers() async {
    final data = await _api.getJson('/users/blocks');
    final list = data is List
        ? data
        : (data is Map && data['items'] is List
            ? data['items'] as List
            : const []);
    return list
        .whereType<Map>()
        .map((e) => BlockedUser.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  /// `POST /users/block` → block a user so they can't message or book you.
  Future<void> block(String blockedId) async {
    await _api.postJson('/users/block', body: {'blockedId': blockedId});
  }

  /// `DELETE /users/block/:blockedId` → unblock a user.
  Future<void> unblock(String blockedId) async {
    await _api.delete('/users/block/$blockedId');
  }
}

/// App-wide [SettingsRepository] provider, wired to the shared [ApiClient].
final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(ref.watch(apiClientProvider));
});
