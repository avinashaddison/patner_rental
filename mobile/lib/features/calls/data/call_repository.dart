import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:companion_ranchi/core/network/api_client.dart';

/// Credentials for joining one Agora RTC channel. Minted server-side per
/// conversation (`POST /calls/token`) so only the two participants can join.
class CallToken {
  const CallToken({
    required this.token,
    required this.channel,
    required this.userAccount,
    required this.appId,
  });

  final String token;
  final String channel;

  /// Our own user id — Agora "user account" (string uid) we join with.
  final String userAccount;
  final String appId;

  factory CallToken.fromJson(Map<String, dynamic> json) => CallToken(
        token: json['token'] as String? ?? '',
        channel: json['channel'] as String? ?? '',
        userAccount: json['userAccount'] as String? ?? '',
        appId: json['appId'] as String? ?? '',
      );
}

/// REST access for voice/video calls. Ringing happens over the socket
/// (`call:invite` → `call:incoming` …); this only fetches the media token.
class CallRepository {
  CallRepository(this._api);

  final ApiClient _api;

  Future<CallToken> fetchToken(String conversationId) async {
    final data = await _api.postJson(
      '/calls/token',
      body: {'conversationId': conversationId},
    );
    return CallToken.fromJson(Map<String, dynamic>.from(data as Map));
  }
}

final callRepositoryProvider = Provider<CallRepository>(
  (ref) => CallRepository(ref.watch(apiClientProvider)),
);
