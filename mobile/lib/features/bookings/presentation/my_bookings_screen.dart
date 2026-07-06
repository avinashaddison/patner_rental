import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:companion_ranchi/core/auth/auth_controller.dart';
import 'package:companion_ranchi/core/models/booking_model.dart';
import 'package:companion_ranchi/core/router/routes.dart';
import 'package:companion_ranchi/core/theme/app_theme.dart';
import 'package:companion_ranchi/core/utils/formatters.dart';
import 'package:companion_ranchi/features/bookings/application/bookings_providers.dart';
import 'package:companion_ranchi/shared/widgets/widgets.dart';

/// Emoji for the activity chip ("☕ Coffee Date").
String _activityEmoji(String activity) {
  switch (activity.toLowerCase()) {
    case 'coffee':
      return '☕';
    case 'movie':
      return '🎬';
    case 'shopping':
      return '🛍';
    case 'dinner':
    case 'lunch':
      return '🍽';
    case 'city tour':
    case 'sightseeing':
      return '🗺';
    case 'event':
      return '🎉';
    case 'networking':
      return '🤝';
    case 'walk in the park':
      return '🌳';
    default:
      return '💗';
  }
}

/// The user's bookings, grouped into tabs by status — design-reference layout:
/// circle back + "My Bookings" + calendar action, underline tabs, rich booking
/// cards (status chip, activity chip, date/location panel, price + View
/// Details), a promo banner and a 24/7 help card. Role-aware on the backend:
/// customers see their bookings, companions see received requests.
class MyBookingsScreen extends ConsumerStatefulWidget {
  const MyBookingsScreen({super.key});

  @override
  ConsumerState<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends ConsumerState<MyBookingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  static const _tabs = BookingTab.values;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Account-level role (drives the empty-state "find a companion" CTA).
    final isCompanion = ref.watch(currentUserProvider)?.isCompanion ?? false;
    // Per-booking side is decided by id in each card (a companion can also be
    // the customer on a booking they made).
    final myId = ref.watch(currentUserProvider)?.id;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
              child: Row(
                children: [
                  if (context.canPop())
                    _CircleAction(
                      icon: Icons.arrow_back_rounded,
                      onTap: () => context.pop(),
                    )
                  else
                    const SizedBox(width: 42),
                  Expanded(
                    child: Text(
                      'My Bookings',
                      textAlign: TextAlign.center,
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.3,
                              ),
                    ),
                  ),
                  _CircleAction(
                    icon: Icons.calendar_month_rounded,
                    onTap: () => ref.invalidate(myBookingsProvider),
                  ),
                ],
              ),
            ),
            TabBar(
              controller: _tabController,
              indicatorColor: AppColors.primary,
              indicatorWeight: 3,
              indicatorSize: TabBarIndicatorSize.label,
              dividerColor: Colors.transparent,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.inkMuted,
              labelStyle:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              unselectedLabelStyle:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              tabs: [for (final tab in _tabs) Tab(text: tab.label)],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  for (final tab in _tabs)
                    _BookingsTabView(
                      tab: tab,
                      isCompanion: isCompanion,
                      myId: myId,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// White circular header action (back / calendar).
class _CircleAction extends StatelessWidget {
  const _CircleAction({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(icon, size: 20, color: AppColors.ink),
        ),
      ),
    );
  }
}

class _BookingsTabView extends ConsumerWidget {
  const _BookingsTabView({
    required this.tab,
    required this.isCompanion,
    required this.myId,
  });

  final BookingTab tab;
  final bool isCompanion;
  final String? myId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookingsAsync = ref.watch(bookingsForTabProvider(tab));

    return RefreshIndicator(
      onRefresh: () => ref.refresh(myBookingsProvider.future),
      color: AppColors.primary,
      child: bookingsAsync.when(
        loading: () => const LoadingView(message: 'Loading bookings…'),
        error: (e, _) => ListView(
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.25),
            ErrorView(
              error: e,
              onRetry: () => ref.invalidate(myBookingsProvider),
            ),
          ],
        ),
        data: (bookings) {
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              if (bookings.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xl),
                  child: EmptyView(
                    icon: Icons.calendar_month_rounded,
                    title: 'No ${tab.label.toLowerCase()} bookings',
                    message: _emptyMessage,
                    actionLabel: tab == BookingTab.upcoming && !isCompanion
                        ? 'Find a companion'
                        : null,
                    onAction: tab == BookingTab.upcoming && !isCompanion
                        ? () => context.go(Routes.search)
                        : null,
                  ),
                )
              else
                for (final b in bookings) ...[
                  _BookingCard(
                    booking: b,
                    isCompanion: myId != null && b.customerId != myId,
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
              const SizedBox(height: AppSpacing.sm),
              const _PromoBanner(),
              const SizedBox(height: AppSpacing.md),
              const _HelpCard(),
              const SizedBox(height: AppSpacing.lg),
            ],
          );
        },
      ),
    );
  }

  String get _emptyMessage {
    switch (tab) {
      case BookingTab.upcoming:
        return isCompanion
            ? 'New booking requests will appear here.'
            : 'Book a verified companion for coffee, a movie or a city tour.';
      case BookingTab.active:
        return 'Bookings in progress will show up here.';
      case BookingTab.completed:
        return 'Your completed meetups will be listed here.';
      case BookingTab.cancelled:
        return 'Cancelled and refunded bookings appear here.';
    }
  }
}

/// Design-reference booking card: avatar + name + status chip, activity chip
/// + duration, a tinted date/location panel, then Total Price + View Details.
class _BookingCard extends StatelessWidget {
  const _BookingCard({required this.booking, required this.isCompanion});

  final BookingModel booking;
  final bool isCompanion;

  @override
  Widget build(BuildContext context) {
    // Customers see the companion; companions see the customer.
    final party = isCompanion ? booking.customer : booking.companion;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => context.go(Routes.bookingDetailPath(booking.id)),
        child: Ink(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.fieldBorder),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.06),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  UserAvatar(
                    photoUrl: party?.photoUrl,
                    name: party?.name ?? booking.activity,
                    radius: 26,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          party?.name ??
                              (isCompanion ? 'Customer' : 'Companion'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.primary
                                    .withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(
                                    AppSpacing.radiusPill),
                              ),
                              child: Text(
                                '${_activityEmoji(booking.activity)} ${booking.activity} Date',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                Formatters.durationHours(
                                    booking.durationHours),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.inkMuted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  BookingStatusBadge(status: booking.status),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              // Date & Time | Location panel.
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.fieldBorder),
                ),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _PanelColumn(
                          icon: Icons.calendar_month_rounded,
                          label: 'Date & Time',
                          value: booking.bookingDate != null
                              ? Formatters.dateShort(booking.bookingDate!)
                              : 'To be confirmed',
                          sub: booking.bookingDate != null
                              ? Formatters.time12(booking.startTime)
                              : null,
                        ),
                      ),
                      const VerticalDivider(
                        width: AppSpacing.lg,
                        thickness: 1,
                        color: AppColors.fieldBorder,
                      ),
                      Expanded(
                        child: _PanelColumn(
                          icon: Icons.place_rounded,
                          label: 'Location',
                          value: booking.meetingLocation,
                          sub: booking.meetingPlaceType,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.sell_rounded,
                        size: 18, color: AppColors.primary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Total Price',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.inkMuted),
                        ),
                        Text(
                          Formatters.money(booking.totalAmount),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16.5,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 13, vertical: 9),
                    decoration: BoxDecoration(
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusPill),
                      border: Border.all(
                          color: AppColors.primary
                              .withValues(alpha: 0.55)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.description_rounded,
                            size: 14, color: AppColors.primary),
                        SizedBox(width: 5),
                        Text(
                          'View Details',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded,
                            size: 16, color: AppColors.primary),
                      ],
                    ),
                  ),
                ],
              ),
              if (booking.awaitingPayment && !isCompanion) ...[
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: AppButton(
                    label: 'Complete payment',
                    icon: Icons.lock_rounded,
                    onPressed: () =>
                        context.go(Routes.paymentPath(booking.id)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One column of the date/location panel.
class _PanelColumn extends StatelessWidget {
  const _PanelColumn({
    required this.icon,
    required this.label,
    required this.value,
    this.sub,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: AppColors.primary),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.inkMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
          ),
        ),
        if (sub != null) ...[
          const SizedBox(height: 1),
          Text(
            sub!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                const TextStyle(fontSize: 12, color: AppColors.inkMuted),
          ),
        ],
      ],
    );
  }
}

/// "Make every moment Special 💕" promo banner → discovery.
class _PromoBanner extends StatelessWidget {
  const _PromoBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.fieldBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Make every moment',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                    height: 1.2,
                  ),
                ),
                const Text(
                  'Special 💕',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    fontStyle: FontStyle.italic,
                    color: AppColors.primary,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Book amazing experiences and create beautiful memories.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.inkMuted,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () => context.go(Routes.search),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: AppGradients.primary,
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusPill),
                      boxShadow: [
                        BoxShadow(
                          color:
                              AppColors.primary.withValues(alpha: 0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Explore More',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded,
                            color: Colors.white, size: 18),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Decorative calendar-with-heart.
          SizedBox(
            width: 96,
            height: 100,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.calendar_month_rounded,
                  size: 84,
                  color: AppColors.primary.withValues(alpha: 0.22),
                ),
                const Positioned(
                  bottom: 26,
                  child: Icon(Icons.favorite_rounded,
                      size: 30, color: AppColors.primary),
                ),
                Positioned(
                  top: 2,
                  right: 6,
                  child: Icon(Icons.favorite_rounded,
                      size: 14,
                      color: AppColors.primary.withValues(alpha: 0.5)),
                ),
                Positioned(
                  bottom: 0,
                  left: 4,
                  child: Icon(Icons.favorite_rounded,
                      size: 11,
                      color: AppColors.primary.withValues(alpha: 0.4)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 24/7 support entry card.
class _HelpCard extends StatelessWidget {
  const _HelpCard();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => context.push(Routes.supportChat),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.fieldBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.headset_mic_rounded,
                    size: 20, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Need help with your booking?',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      "We're here to assist you 24/7",
                      style: TextStyle(
                          fontSize: 12, color: AppColors.inkMuted),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }
}

/// A coloured pill showing a booking's status (with a status icon). Exposed
/// for reuse on the detail screen.
class BookingStatusBadge extends StatelessWidget {
  const BookingStatusBadge({super.key, required this.status});

  final String status;

  Color get _color {
    switch (status) {
      case BookingStatus.pending:
        return AppColors.warning;
      case BookingStatus.confirmed:
        return AppColors.success;
      case BookingStatus.inProgress:
        return AppColors.primary;
      case BookingStatus.completed:
        return AppColors.info;
      case BookingStatus.cancelled:
        return AppColors.danger;
      case BookingStatus.refunded:
        return AppColors.inkMuted;
      default:
        return AppColors.inkMuted;
    }
  }

  IconData get _icon {
    switch (status) {
      case BookingStatus.pending:
        return Icons.hourglass_top_rounded;
      case BookingStatus.confirmed:
        return Icons.check_circle_rounded;
      case BookingStatus.inProgress:
        return Icons.play_circle_rounded;
      case BookingStatus.completed:
        return Icons.verified_rounded;
      case BookingStatus.cancelled:
        return Icons.cancel_rounded;
      case BookingStatus.refunded:
        return Icons.replay_rounded;
      default:
        return Icons.info_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, size: 13, color: _color),
          const SizedBox(width: 4),
          Text(
            BookingStatus.label(status),
            style: TextStyle(
              color: _color,
              fontWeight: FontWeight.w700,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}
