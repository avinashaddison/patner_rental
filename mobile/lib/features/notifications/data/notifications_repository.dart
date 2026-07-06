import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:companion_ranchi/core/models/notification_model.dart';
import 'package:companion_ranchi/core/network/api_client.dart';

/// A page of notifications plus whether older entries remain (infinite scroll).
class NotificationPage {
  const NotificationPage({required this.items, required this.hasMore});

  final List<NotificationModel> items;
  final bool hasMore;
}

/// REST access for the notifications domain (`/notifications/*`). Live pushes
/// arrive via the `notification:new` socket event handled by [SocketClient].
class NotificationsRepository {
  NotificationsRepository(this._api);

  final ApiClient _api;

  /// `GET /notifications` — paginated, newest-first.
  Future<NotificationPage> fetch({int page = 1, int limit = 20}) async {
    final envelope = await _api.getEnvelope(
      '/notifications',
      query: {'page': page, 'limit': limit, 'sort': 'createdAt:desc'},
    );
    final items = _asList(envelope['data']);
    final hasMore = _hasMore(envelope['meta'], page, limit, items.length);
    return NotificationPage(items: items, hasMore: hasMore);
  }

  /// `GET /notifications/unread-count` -> `{ count }`.
  Future<int> unreadCount() async {
    final data = await _api.getJson('/notifications/unread-count');
    if (data is Map && data['count'] != null) {
      return int.tryParse(data['count'].toString()) ?? 0;
    }
    return 0;
  }

  /// `POST /notifications/:id/read`.
  Future<void> markRead(String id) async {
    await _api.postJson('/notifications/$id/read');
  }

  /// `POST /notifications/read-all`.
  Future<void> markAllRead() async {
    await _api.postJson('/notifications/read-all');
  }

  List<NotificationModel> _asList(dynamic data) {
    final list = data is List
        ? data
        : data is Map && data['items'] is List
            ? data['items'] as List
            : const [];
    return list
        .whereType<Map>()
        .map((e) => NotificationModel.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  bool _hasMore(dynamic meta, int page, int limit, int received) {
    if (meta is Map && meta['total'] != null) {
      final total = int.tryParse(meta['total'].toString()) ?? 0;
      return page * limit < total;
    }
    return received >= limit;
  }
}

/// App-wide [NotificationsRepository] provider.
final notificationsRepositoryProvider =
    Provider<NotificationsRepository>((ref) {
  return NotificationsRepository(ref.watch(apiClientProvider));
});
