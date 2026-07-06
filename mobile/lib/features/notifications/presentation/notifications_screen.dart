import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:companion_ranchi/core/models/notification_model.dart';
import 'package:companion_ranchi/core/router/routes.dart';
import 'package:companion_ranchi/core/theme/app_theme.dart';
import 'package:companion_ranchi/core/utils/formatters.dart';
import 'package:companion_ranchi/features/notifications/application/notifications_controller.dart';
import 'package:companion_ranchi/shared/widgets/widgets.dart';

/// In-app notifications list (`GET /notifications`). Tapping a notification
/// marks it read and deep-links by type (booking -> booking detail, chat ->
/// thread, payment -> wallet, etc.). Live `notification:new` pushes prepend.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >=
        _scroll.position.maxScrollExtent - 200) {
      ref.read(notificationsControllerProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(notificationsControllerProvider);
    final state = async.valueOrNull;
    final hasUnread = (state?.unreadCount ?? 0) > 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (hasUnread)
            TextButton(
              onPressed: () => ref
                  .read(notificationsControllerProvider.notifier)
                  .markAllRead(),
              child: const Text('Mark all read'),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(notificationsControllerProvider.notifier).refresh(),
        child: async.when(
          loading: () => const _NotificationsSkeleton(),
          error: (err, _) => ListView(
            children: [
              SizedBox(
                height: MediaQuery.sizeOf(context).height * 0.7,
                child: ErrorView(
                  error: err,
                  onRetry: () => ref.invalidate(
                    notificationsControllerProvider,
                  ),
                ),
              ),
            ],
          ),
          data: (data) {
            if (data.items.isEmpty) {
              return ListView(
                children: [
                  SizedBox(
                    height: MediaQuery.sizeOf(context).height * 0.7,
                    child: const EmptyView(
                      icon: Icons.notifications_off_rounded,
                      title: 'No notifications',
                      message:
                          'Booking updates, payments, messages and offers '
                          'will show up here.',
                    ),
                  ),
                ],
              );
            }
            return ListView.separated(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              itemCount: data.items.length + (data.hasMore ? 1 : 0),
              separatorBuilder: (_, __) =>
                  const Divider(indent: 76, height: 1),
              itemBuilder: (context, i) {
                if (i >= data.items.length) {
                  return const Padding(
                    padding: EdgeInsets.all(AppSpacing.lg),
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      ),
                    ),
                  );
                }
                return _NotificationTile(
                  notification: data.items[i],
                  onTap: () => _handleTap(data.items[i]),
                );
              },
            );
          },
        ),
      ),
    );
  }

  void _handleTap(NotificationModel n) {
    ref.read(notificationsControllerProvider.notifier).markRead(n.id);
    final route = NotificationRouter.routeFor(n);
    if (route != null) context.push(route);
  }
}

/// Maps a notification's type + data payload to an in-app route.
class NotificationRouter {
  NotificationRouter._();

  static String? routeFor(NotificationModel n) {
    final data = n.data;
    final bookingId = data['bookingId']?.toString();
    final conversationId = data['conversationId']?.toString();
    final companionId = data['companionId']?.toString();

    switch (n.type) {
      case 'BOOKING':
        return bookingId != null
            ? Routes.bookingDetailPath(bookingId)
            : Routes.bookings;
      case 'PAYMENT':
        return Routes.wallet;
      case 'CHAT':
        return conversationId != null
            ? Routes.chatThreadPath(conversationId)
            : Routes.chat;
      case 'REVIEW':
        return companionId != null
            ? Routes.reviewsPath(companionId)
            : null;
      case 'REFERRAL':
        return Routes.wallet;
      case 'KYC':
        return Routes.companionDashboard;
      case 'SOS':
      case 'SYSTEM':
      default:
        return null;
    }
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final NotificationModel notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUnread = !notification.isRead;
    final style = _NotificationStyle.forType(notification.type);

    return Material(
      color: isUnread
          ? AppColors.primary.withValues(alpha: 0.05)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: style.color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(style.icon, color: style.color, size: 22),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: isUnread
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          Formatters.relative(notification.createdAt),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.inkMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      notification.body,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.inkMuted,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              if (isUnread)
                Container(
                  margin: const EdgeInsets.only(left: 8, top: 6),
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Icon + colour per [NotificationType].
class _NotificationStyle {
  const _NotificationStyle(this.icon, this.color);

  final IconData icon;
  final Color color;

  static _NotificationStyle forType(String type) {
    switch (type) {
      case 'BOOKING':
        return const _NotificationStyle(
          Icons.event_available_rounded,
          AppColors.primary,
        );
      case 'PAYMENT':
        return const _NotificationStyle(
          Icons.payments_rounded,
          AppColors.success,
        );
      case 'CHAT':
        return const _NotificationStyle(
          Icons.chat_bubble_rounded,
          AppColors.info,
        );
      case 'KYC':
        return const _NotificationStyle(
          Icons.verified_user_rounded,
          AppColors.verified,
        );
      case 'REVIEW':
        return const _NotificationStyle(
          Icons.star_rounded,
          AppColors.star,
        );
      case 'REFERRAL':
        return const _NotificationStyle(
          Icons.card_giftcard_rounded,
          AppColors.accent,
        );
      case 'SOS':
        return const _NotificationStyle(
          Icons.emergency_rounded,
          AppColors.danger,
        );
      case 'SYSTEM':
      default:
        return const _NotificationStyle(
          Icons.notifications_rounded,
          AppColors.inkMuted,
        );
    }
  }
}

class _NotificationsSkeleton extends StatelessWidget {
  const _NotificationsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemCount: 8,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (_, __) => const Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShimmerBox(width: 44, height: 44, radius: 22),
            SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShimmerBox(width: 140, height: 14),
                  SizedBox(height: 8),
                  ShimmerBox(height: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
