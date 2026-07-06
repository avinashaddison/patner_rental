import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:companion_ranchi/core/models/conversation_model.dart';
import 'package:companion_ranchi/core/router/routes.dart';
import 'package:companion_ranchi/core/theme/app_theme.dart';
import 'package:companion_ranchi/core/utils/formatters.dart';
import 'package:companion_ranchi/features/chat/application/conversations_controller.dart';
import 'package:companion_ranchi/shared/widgets/widgets.dart';

/// Green used for the live / online indicators.
const Color _kOnline = Color(0xFF22C55E);

/// Whether a conversation has no real message yet — i.e. a fresh "connection".
bool _isNewConnection(ConversationModel c) =>
    !(c.lastMessage?.trim().isNotEmpty ?? false);

/// Inbox filters (the chips row). All fully functional:
/// unread = has unread messages, active = peer online now,
/// bookings = conversations attached to a booking.
enum _InboxFilter { all, unread, active, bookings }

/// Chat home — dating-app style inbox matching the design reference:
/// "Messages ❤" header with live support, a search bar + filter sheet, a
/// story-style "New Connections" rail (gradient rings, online dots, unread
/// badges, activity status, expandable "+N"), an Upcoming Booking banner
/// backed by the real next booking, functional filter chips and card-style
/// conversation tiles. Live-updated by socket events via
/// [ConversationsController].
class ConversationsScreen extends ConsumerStatefulWidget {
  const ConversationsScreen({super.key});

  @override
  ConsumerState<ConversationsScreen> createState() =>
      _ConversationsScreenState();
}

class _ConversationsScreenState extends ConsumerState<ConversationsScreen> {
  final _search = TextEditingController();
  String _query = '';
  _InboxFilter _filter = _InboxFilter.all;
  bool _railExpanded = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _pickFilter(_InboxFilter f) => setState(() => _filter = f);

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(conversationsControllerProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const _Header(),
            _SearchBar(
              controller: _search,
              onChanged: (v) => setState(() => _query = v),
              onFilterTap: () => _showFilterSheet(context),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => ref
                    .read(conversationsControllerProvider.notifier)
                    .refresh(),
                child: async.when(
                  loading: () => const _ConversationsSkeleton(),
                  error: (err, _) => ListView(
                    children: [
                      SizedBox(
                        height: MediaQuery.sizeOf(context).height * 0.6,
                        child: ErrorView(
                          error: err,
                          onRetry: () => ref
                              .read(conversationsControllerProvider.notifier)
                              .refresh(),
                        ),
                      ),
                    ],
                  ),
                  data: (conversations) => _buildList(conversations),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showFilterSheet(BuildContext context) async {
    final picked = await showModalBottomSheet<_InboxFilter>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            for (final f in _InboxFilter.values)
              ListTile(
                leading: Icon(
                  switch (f) {
                    _InboxFilter.all => Icons.chat_rounded,
                    _InboxFilter.unread => Icons.mark_chat_unread_rounded,
                    _InboxFilter.active => Icons.bolt_rounded,
                    _InboxFilter.bookings => Icons.event_available_rounded,
                  },
                  color: AppColors.primary,
                ),
                title: Text(switch (f) {
                  _InboxFilter.all => 'All chats',
                  _InboxFilter.unread => 'Unread',
                  _InboxFilter.active => 'Active now',
                  _InboxFilter.bookings => 'With bookings',
                }),
                trailing: _filter == f
                    ? const Icon(Icons.check_rounded, color: AppColors.primary)
                    : null,
                onTap: () => Navigator.pop(ctx, f),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null) _pickFilter(picked);
  }

  List<ConversationModel> _applyFilter(List<ConversationModel> list) {
    switch (_filter) {
      case _InboxFilter.all:
        return list;
      case _InboxFilter.unread:
        return list.where((c) => c.unreadCount > 0).toList(growable: false);
      case _InboxFilter.active:
        return list.where((c) => c.peerIsOnline).toList(growable: false);
      case _InboxFilter.bookings:
        return list
            .where((c) => (c.bookingId ?? '').isNotEmpty)
            .toList(growable: false);
    }
  }

  Widget _buildList(List<ConversationModel> all) {
    final q = _query.trim().toLowerCase();

    // Search mode: flat, filtered list of everyone.
    if (q.isNotEmpty) {
      final hits = all
          .where((c) =>
              (c.peerName ?? '').toLowerCase().contains(q) ||
              (c.lastMessage ?? '').toLowerCase().contains(q))
          .toList(growable: false);
      if (hits.isEmpty) {
        return ListView(
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.5,
              child: const EmptyView(
                icon: Icons.search_off_rounded,
                title: 'No chats found',
                message: 'Try a different name.',
              ),
            ),
          ],
        );
      }
      return ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 4, bottom: AppSpacing.lg),
        itemCount: hits.length,
        itemBuilder: (_, i) => _ConversationCard(conversation: hits[i]),
      );
    }

    final newCount = all.where(_isNewConnection).length;
    final totalUnread =
        all.fold<int>(0, (sum, c) => sum + (c.unreadCount > 0 ? 1 : 0));
    final messages = _applyFilter(
      all.where((c) => !_isNewConnection(c)).toList(growable: false),
    );

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      children: [
        if (all.isNotEmpty)
          _ConnectionsRail(
            conversations: all,
            newCount: newCount,
            expanded: _railExpanded,
            onToggleExpand: () =>
                setState(() => _railExpanded = !_railExpanded),
          ),
        _FilterChips(
          selected: _filter,
          unreadCount: totalUnread,
          onChanged: _pickFilter,
        ),
        if (messages.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, AppSpacing.lg),
            child: Column(
              children: [
                const Text('💌', style: TextStyle(fontSize: 40)),
                const SizedBox(height: 10),
                Text(
                  switch (_filter) {
                    _InboxFilter.unread => 'All caught up!',
                    _InboxFilter.active => 'Nobody is online right now',
                    _InboxFilter.bookings => 'No booking chats yet',
                    _ => 'No chats yet',
                  },
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _filter == _InboxFilter.all
                      ? 'Book a companion to start a conversation 💕'
                      : 'Try the All filter to see every chat.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppColors.inkMuted, fontSize: 13),
                ),
              ],
            ),
          )
        else
          for (final c in messages) _ConversationCard(conversation: c),
      ],
    );
  }
}

/// Big, friendly screen header with live support on the right.
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
      child: Row(
        children: [
          Text(
            'Messages',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 30,
            height: 30,
            decoration: const BoxDecoration(
              gradient: AppGradients.primary,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.favorite_rounded,
                color: Colors.white, size: 16),
          ),
          const Spacer(),
          const _SupportButton(),
        ],
      ),
    );
  }
}

/// Header action that opens the live support chat.
class _SupportButton extends StatelessWidget {
  const _SupportButton();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Live support',
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => context.push(Routes.supportChat),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.fieldBorder),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(Icons.headset_mic_rounded,
                    size: 20, color: AppColors.primary),
                Positioned(
                  top: 9,
                  right: 9,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: _kOnline,
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: AppColors.scaffold, width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Rounded search field + the pink filter button (opens the filter sheet).
class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.onChanged,
    required this.onFilterTap,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onFilterTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search chats, people…',
                prefixIcon: const Icon(Icons.search_rounded,
                    size: 20, color: AppColors.primary),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                  borderSide: const BorderSide(color: AppColors.fieldBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                  borderSide: const BorderSide(color: AppColors.fieldBorder),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: onFilterTap,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: AppGradients.primary,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(Icons.tune_rounded,
                  color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// New Connections story rail
// ---------------------------------------------------------------------------

class _ConnectionsRail extends StatelessWidget {
  const _ConnectionsRail({
    required this.conversations,
    required this.newCount,
    required this.expanded,
    required this.onToggleExpand,
  });

  final List<ConversationModel> conversations;
  final int newCount;
  final bool expanded;
  final VoidCallback onToggleExpand;

  static const int _collapsedCount = 6;

  @override
  Widget build(BuildContext context) {
    final visible = expanded
        ? conversations
        : conversations.take(_collapsedCount).toList(growable: false);
    final hidden = conversations.length - visible.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 8),
          child: Row(
            children: [
              const Text('✨ ', style: TextStyle(fontSize: 13)),
              const Text(
                'New Connections',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (newCount > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius:
                        BorderRadius.circular(AppSpacing.radiusPill),
                  ),
                  child: Text(
                    '$newCount',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              GestureDetector(
                onTap: onToggleExpand,
                child: Row(
                  children: [
                    Text(
                      expanded ? 'Show Less' : 'View All',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    Icon(
                      expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.chevron_right_rounded,
                      size: 18,
                      color: AppColors.primary,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 122,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            itemCount: visible.length + (hidden > 0 ? 1 : 0),
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (_, i) {
              if (i == visible.length) {
                return _MoreBubble(count: hidden, onTap: onToggleExpand);
              }
              return _StoryAvatar(conversation: visible[i]);
            },
          ),
        ),
      ],
    );
  }
}

/// A story-style avatar: gradient ring, online dot, unread badge, name and
/// live activity status.
class _StoryAvatar extends ConsumerWidget {
  const _StoryAvatar({required this.conversation});

  final ConversationModel conversation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = conversation.peerName ?? 'Companion';
    final first = name.split(' ').first;
    final hasUnread = conversation.unreadCount > 0;

    return GestureDetector(
      onTap: () => _open(context, ref, conversation),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 72,
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    gradient: hasUnread || _isNewConnection(conversation)
                        ? AppGradients.primary
                        : null,
                    color: hasUnread || _isNewConnection(conversation)
                        ? null
                        : AppColors.fieldBorder,
                    shape: BoxShape.circle,
                  ),
                  child: CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.white,
                    child: UserAvatar(
                      photoUrl: conversation.peerPhotoUrl,
                      name: conversation.peerName,
                      radius: 28,
                    ),
                  ),
                ),
                if (conversation.peerIsOnline)
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: Container(
                      width: 15,
                      height: 15,
                      decoration: BoxDecoration(
                        color: _kOnline,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: AppColors.scaffold, width: 2.5),
                      ),
                    ),
                  ),
                if (hasUnread)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      constraints:
                          const BoxConstraints(minWidth: 19, minHeight: 19),
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      decoration: BoxDecoration(
                        gradient: AppGradients.primary,
                        borderRadius: BorderRadius.circular(10),
                        border:
                            Border.all(color: AppColors.scaffold, width: 2),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${conversation.unreadCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              first,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 1),
            if (conversation.peerIsOnline)
              const Text(
                'Active now',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: _kOnline),
              )
            else if (conversation.peerLastActiveAt != null)
              Text(
                'Active ${Formatters.relative(conversation.peerLastActiveAt)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 10, color: AppColors.inkMuted),
              )
            else
              const Text(
                'New ✨',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary),
              ),
          ],
        ),
      ),
    );
  }
}

/// The "+N" bubble at the end of the rail — expands it in place.
class _MoreBubble extends StatelessWidget {
  const _MoreBubble({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 72,
        child: Column(
          children: [
            Container(
              width: 65,
              height: 65,
              decoration: BoxDecoration(
                gradient: AppGradients.primary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.group_rounded,
                      color: Colors.white, size: 20),
                  Text(
                    '+$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'More',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Filter chips
// ---------------------------------------------------------------------------

class _FilterChips extends StatelessWidget {
  const _FilterChips({
    required this.selected,
    required this.unreadCount,
    required this.onChanged,
  });

  final _InboxFilter selected;
  final int unreadCount;
  final ValueChanged<_InboxFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: 4),
        children: [
          _chip(
            label: 'All',
            icon: Icons.chat_rounded,
            filter: _InboxFilter.all,
          ),
          const SizedBox(width: 8),
          _chip(
            label: 'Unread',
            filter: _InboxFilter.unread,
            badge: unreadCount > 0 ? '$unreadCount' : null,
          ),
          const SizedBox(width: 8),
          _chip(
            label: 'Active Now',
            filter: _InboxFilter.active,
            leadingDot: _kOnline,
          ),
          const SizedBox(width: 8),
          _chip(
            label: 'Bookings',
            icon: Icons.event_available_rounded,
            filter: _InboxFilter.bookings,
          ),
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required _InboxFilter filter,
    IconData? icon,
    String? badge,
    Color? leadingDot,
  }) {
    final active = selected == filter;
    return GestureDetector(
      onTap: () => onChanged(filter),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? AppColors.primary.withValues(alpha: 0.12)
              : Colors.white,
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          border: Border.all(
            color: active ? AppColors.primary : AppColors.fieldBorder,
            width: active ? 1.4 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon,
                  size: 14,
                  color: active ? AppColors.primary : AppColors.inkMuted),
              const SizedBox(width: 5),
            ],
            if (leadingDot != null) ...[
              Container(
                width: 8,
                height: 8,
                decoration:
                    BoxDecoration(color: leadingDot, shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: active ? AppColors.primary : AppColors.ink,
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 5),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF8F3C),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  badge,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Conversation cards
// ---------------------------------------------------------------------------

void _open(BuildContext context, WidgetRef ref, ConversationModel c) {
  ref.read(conversationsControllerProvider.notifier).markThreadRead(c.id);
  context.push(Routes.chatThreadPath(c.id), extra: c);
}

/// White card-style conversation row: ringed avatar + online dot, name,
/// preview, activity status, time-ago and an unread badge.
class _ConversationCard extends ConsumerWidget {
  const _ConversationCard({required this.conversation});

  final ConversationModel conversation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hasUnread = conversation.unreadCount > 0;
    final online = conversation.peerIsOnline;
    final empty = _isNewConnection(conversation);
    final mine = conversation.lastMessageMine && !empty;
    final preview = empty
        ? (online ? 'Active now — say hi 👋' : 'Say hello 👋')
        : (mine
            ? 'You: ${conversation.lastMessage!.trim()}'
            : conversation.lastMessage!.trim());

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: 5),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _open(context, ref, conversation),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: hasUnread
                    ? AppColors.primary.withValues(alpha: 0.45)
                    : AppColors.fieldBorder,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary
                      .withValues(alpha: hasUnread ? 0.08 : 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    gradient: hasUnread ? AppGradients.primary : null,
                    color: hasUnread ? null : AppColors.fieldBorder,
                    shape: BoxShape.circle,
                  ),
                  child: CircleAvatar(
                    radius: 26,
                    backgroundColor: Colors.white,
                    child: UserAvatar(
                      photoUrl: conversation.peerPhotoUrl,
                      name: conversation.peerName,
                      radius: 24,
                      isOnline: online,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        conversation.peerName ?? 'Companion',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight:
                              hasUnread ? FontWeight.w900 : FontWeight.w700,
                          fontSize: 15.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (mine) ...[
                            Icon(
                              Icons.done_all_rounded,
                              size: 14,
                              color: hasUnread
                                  ? AppColors.primary
                                  : AppColors.inkMuted
                                      .withValues(alpha: 0.7),
                            ),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(
                              preview,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontSize: 13.5,
                                color: hasUnread
                                    ? (theme.brightness == Brightness.dark
                                        ? AppColors.darkInk
                                        : AppColors.ink)
                                    : AppColors.inkMuted,
                                fontWeight: hasUnread
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      if (online)
                        const Row(
                          children: [
                            SizedBox(
                              width: 7,
                              height: 7,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: _kOnline,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                            SizedBox(width: 5),
                            Text(
                              'Online now',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _kOnline,
                              ),
                            ),
                          ],
                        )
                      else if (conversation.peerLastActiveAt != null)
                        Text(
                          'Active ${Formatters.relative(conversation.peerLastActiveAt)} ago',
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.inkMuted),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (conversation.lastMessageAt != null)
                      Text(
                        '${Formatters.relative(conversation.lastMessageAt)} ago',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: hasUnread
                              ? AppColors.primary
                              : AppColors.inkMuted,
                          fontWeight: hasUnread
                              ? FontWeight.w800
                              : FontWeight.w500,
                        ),
                      ),
                    const SizedBox(height: 8),
                    if (hasUnread)
                      _UnreadBadge(count: conversation.unreadCount)
                    else
                      const SizedBox(height: 22),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 22),
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        gradient: AppGradients.primary,
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ConversationsSkeleton extends StatelessWidget {
  const _ConversationsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      children: [
        // Stories rail skeleton.
        SizedBox(
          height: 104,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            itemCount: 5,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (_, __) => const Column(
              children: [
                ShimmerBox(width: 65, height: 65, radius: 33),
                SizedBox(height: 8),
                ShimmerBox(width: 44, height: 10),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < 6; i++)
          const Padding(
            padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
            child: Row(
              children: [
                ShimmerBox(width: 54, height: 54, radius: 27),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShimmerBox(width: 140, height: 13),
                      SizedBox(height: 8),
                      ShimmerBox(width: 200, height: 11),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
