import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:companion_ranchi/core/config/app_config.dart';
import 'package:companion_ranchi/core/constants/app_constants.dart';
import 'package:companion_ranchi/core/models/category_model.dart';
import 'package:companion_ranchi/core/models/companion_model.dart';
import 'package:companion_ranchi/core/network/api_exception.dart';
import 'package:companion_ranchi/core/router/routes.dart';
import 'package:companion_ranchi/core/theme/app_theme.dart';
import 'package:companion_ranchi/core/utils/app_sounds.dart';
import 'package:companion_ranchi/core/utils/formatters.dart';
import 'package:companion_ranchi/features/booking/application/booking_flow_controller.dart';
import 'package:companion_ranchi/features/booking/application/booking_providers.dart';
import 'package:companion_ranchi/features/booking/data/booking_quote.dart';
import 'package:companion_ranchi/features/home/application/home_providers.dart';
import 'package:companion_ranchi/features/tracking/presentation/place_autocomplete_field.dart';
import 'package:companion_ranchi/shared/widgets/widgets.dart';

/// 3-step booking flow:
/// 1) **When** — duration + date + time slot,
/// 2) **Details** — activity + public meeting place + notes,
/// 3) **Review & Pay** — server quote (`POST /bookings/quote`) + confirm
///    (`POST /bookings`) -> `/payment/:bookingId`.
///
/// A sticky bottom bar shows a live running price on every step.
class BookingFlowScreen extends ConsumerWidget {
  const BookingFlowScreen({super.key, required this.companionId});

  final String companionId;

  static const List<String> _stepTitles = ['When', 'Details', 'Review & Pay'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(bookingFlowProvider(companionId));
    final controller = ref.read(bookingFlowProvider(companionId).notifier);
    final companionAsync = ref.watch(bookingCompanionProvider(companionId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Book a companion'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (state.step.index == 0) {
              context.pop();
            } else {
              controller.back();
            }
          },
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _StepProgress(
              current: state.step.index,
              total: BookingStep.count,
              label: _stepTitles[state.step.index],
            ),
            Expanded(
              child: companionAsync.when(
                loading: () => const LoadingView(message: 'Loading…'),
                error: (e, _) => ErrorView(
                  error: e,
                  onRetry: () =>
                      ref.invalidate(bookingCompanionProvider(companionId)),
                ),
                data: (companion) => _StepBody(
                  companionId: companionId,
                  companion: companion,
                  state: state,
                  controller: controller,
                ),
              ),
            ),
            _BottomBar(
              companion: companionAsync.valueOrNull,
              state: state,
              controller: controller,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Progress header
// ---------------------------------------------------------------------------

class _StepProgress extends StatelessWidget {
  const _StepProgress({
    required this.current,
    required this.total,
    required this.label,
  });

  final int current;
  final int total;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Step ${current + 1} of $total',
                style: const TextStyle(
                  color: AppColors.inkMuted,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            child: LinearProgressIndicator(
              value: (current + 1) / total,
              minHeight: 6,
              backgroundColor: AppColors.line,
              valueColor: const AlwaysStoppedAnimation(AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Per-step body
// ---------------------------------------------------------------------------

class _StepBody extends ConsumerWidget {
  const _StepBody({
    required this.companionId,
    required this.companion,
    required this.state,
    required this.controller,
  });

  final String companionId;
  final CompanionModel companion;
  final BookingFlowState state;
  final BookingFlowController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final body = switch (state.step) {
      BookingStep.when => _WhenStep(
          companionId: companionId,
          companion: companion,
          state: state,
          controller: controller,
        ),
      BookingStep.details =>
        _DetailsStep(state: state, controller: controller),
      BookingStep.review => _ReviewStep(
          companion: companion,
          state: state,
          controller: controller,
        ),
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      children: [
        _CompanionStrip(companion: companion),
        const SizedBox(height: AppSpacing.lg),
        body,
        const SizedBox(height: AppSpacing.lg),
        const SafetyBanner(),
      ],
    );
  }
}

/// Compact companion summary shown at the top of every step.
class _CompanionStrip extends StatelessWidget {
  const _CompanionStrip({required this.companion});

  final CompanionModel companion;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          UserAvatar(
            photoUrl: companion.primaryPhotoUrl,
            name: companion.name,
            radius: 24,
            isOnline: companion.isOnline,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        companion.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    if (companion.isVerified) ...[
                      const SizedBox(width: 6),
                      const VerifiedBadge(compact: true),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${companion.city} · ${Formatters.ratePerHour(companion.hourlyRate)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.inkMuted,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              const Icon(Icons.star_rounded, size: 16, color: AppColors.star),
              const SizedBox(width: 2),
              Text(
                companion.rating.toStringAsFixed(1),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepHeading extends StatelessWidget {
  const _StepHeading({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: const TextStyle(color: AppColors.inkMuted, fontSize: 14),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

/// Small uppercase section label used to separate the grouped sub-sections.
class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.7,
          color: AppColors.inkMuted,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 1 — WHEN (duration + date + time)
// ---------------------------------------------------------------------------

class _WhenStep extends ConsumerWidget {
  const _WhenStep({
    required this.companionId,
    required this.companion,
    required this.state,
    required this.controller,
  });

  final String companionId;
  final CompanionModel companion;
  final BookingFlowState state;
  final BookingFlowController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepHeading(
          title: 'When would you like to meet?',
          subtitle: 'Pick a duration, day and time. You only pay for the '
              'time you book.',
        ),
        const _GroupLabel('Duration'),
        _DurationSelector(
          companion: companion,
          selected: state.durationHours,
          onSelect: controller.setDuration,
        ),
        const SizedBox(height: AppSpacing.lg),
        const _GroupLabel('Date'),
        _DateStrip(
          selected: state.bookingDate,
          onSelect: controller.setDate,
        ),
        const SizedBox(height: AppSpacing.lg),
        const _GroupLabel('Time'),
        _TimeSlots(
          companionId: companionId,
          state: state,
          controller: controller,
        ),
      ],
    );
  }
}

/// A compact 4-up duration selector ("1 hr / ₹600").
class _DurationSelector extends StatelessWidget {
  const _DurationSelector({
    required this.companion,
    required this.selected,
    required this.onSelect,
  });

  final CompanionModel companion;
  final int? selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    const durations = AppConstants.bookingDurations;
    return Row(
      children: [
        for (var i = 0; i < durations.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _DurationCard(
              hours: durations[i],
              price: companion.hourlyRate * durations[i],
              selected: selected == durations[i],
              onTap: () => onSelect(durations[i]),
            ),
          ),
        ],
      ],
    );
  }
}

class _DurationCard extends StatelessWidget {
  const _DurationCard({
    required this.hours,
    required this.price,
    required this.selected,
    required this.onTap,
  });

  final int hours;
  final double price;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md, horizontal: 4),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.08)
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.line,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Column(
          children: [
            Text(
              '$hours',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 20,
                color: selected ? AppColors.primary : AppColors.ink,
                height: 1,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              hours == 1 ? 'hour' : 'hours',
              style: const TextStyle(fontSize: 11, color: AppColors.inkMuted),
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                Formatters.money(price),
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const List<String> _weekdayAbbr = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// A horizontal strip of the next 14 days plus a "More" chip that opens a date
/// picker for the full 60-day window. Keeps the When step compact.
class _DateStrip extends StatelessWidget {
  const _DateStrip({required this.selected, required this.onSelect});

  final DateTime? selected;
  final ValueChanged<DateTime> onSelect;

  static const int _quickDays = 14;
  static const int _maxDays = 60;

  Future<void> _pickMore(BuildContext context, DateTime today) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selected ?? today,
      firstDate: today,
      lastDate: today.add(const Duration(days: _maxDays)),
      helpText: 'Pick a date',
    );
    if (picked != null) onSelect(picked);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = [for (var i = 0; i < _quickDays; i++) today.add(Duration(days: i))];
    final selectedNorm = selected == null
        ? null
        : DateTime(selected!.year, selected!.month, selected!.day);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 74,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: days.length + 1,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
            itemBuilder: (context, i) {
              if (i == days.length) {
                return _MoreDatesChip(onTap: () => _pickMore(context, today));
              }
              final day = days[i];
              final isSel = selectedNorm != null && day == selectedNorm;
              final label = i == 0
                  ? 'Today'
                  : i == 1
                      ? 'Tmrw'
                      : _weekdayAbbr[day.weekday - 1];
              return _DayChip(
                label: label,
                dayNumber: day.day,
                selected: isSel,
                onTap: () => onSelect(day),
              );
            },
          ),
        ),
        if (selectedNorm != null) ...[
          const SizedBox(height: AppSpacing.md),
          _InfoPill(
            icon: Icons.event_rounded,
            text: Formatters.dateLong(selectedNorm),
          ),
        ],
      ],
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.label,
    required this.dayNumber,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int dayNumber;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 58,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.line,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white70 : AppColors.inkMuted,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              '$dayNumber',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: selected ? Colors.white : AppColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoreDatesChip extends StatelessWidget {
  const _MoreDatesChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 58,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          border: Border.all(color: AppColors.line),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.calendar_month_rounded,
                size: 20, color: AppColors.primary),
            SizedBox(height: 3),
            Text(
              'More',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeSlots extends ConsumerWidget {
  const _TimeSlots({
    required this.companionId,
    required this.state,
    required this.controller,
  });

  final String companionId;
  final BookingFlowState state;
  final BookingFlowController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = state.bookingDate;
    if (date == null) {
      return const _MutedCard(
        icon: Icons.schedule_rounded,
        text: 'Pick a date to see available times.',
      );
    }

    final args = AvailabilityArgs(companionId: companionId, date: date);
    final slotsAsync = ref.watch(availabilityProvider(args));

    return slotsAsync.when(
      loading: () => const _SlotSkeleton(),
      error: (e, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: ErrorView(
          error: e,
          onRetry: () => ref.invalidate(availabilityProvider(args)),
        ),
      ),
      data: (slots) {
        if (slots.isEmpty) {
          return const EmptyView(
            icon: Icons.event_busy_rounded,
            title: 'No slots available',
            message: 'No open times on this day. Try another date.',
          );
        }
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final slot in slots)
              CategoryChip(
                label: Formatters.time12(slot.startTime),
                icon: Icons.access_time_rounded,
                selected: state.selectedSlot == slot,
                onTap: () => controller.setSlot(slot),
              ),
          ],
        );
      },
    );
  }
}

class _SlotSkeleton extends StatelessWidget {
  const _SlotSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        ShimmerBox(width: 92, height: 40, radius: AppSpacing.radiusPill),
        ShimmerBox(width: 80, height: 40, radius: AppSpacing.radiusPill),
        ShimmerBox(width: 100, height: 40, radius: AppSpacing.radiusPill),
        ShimmerBox(width: 84, height: 40, radius: AppSpacing.radiusPill),
        ShimmerBox(width: 96, height: 40, radius: AppSpacing.radiusPill),
        ShimmerBox(width: 78, height: 40, radius: AppSpacing.radiusPill),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Step 2 — DETAILS (activity + meeting place + notes)
// ---------------------------------------------------------------------------

class _DetailsStep extends StatelessWidget {
  const _DetailsStep({required this.state, required this.controller});

  final BookingFlowState state;
  final BookingFlowController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepHeading(
          title: 'A few details',
          subtitle: 'What you\'ll do and where you\'ll meet — public places only.',
        ),
        const _GroupLabel('Activity'),
        _ActivityCategoryGrid(state: state, controller: controller),
        const SizedBox(height: AppSpacing.lg),
        const _GroupLabel('Meeting place'),
        PlaceAutocompleteField(
          label: 'Meeting location',
          hint: 'e.g. Nucleus Mall, Main Road',
          initialValue: state.meetingLocation,
          onChanged: controller.setMeetingLocation,
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final type in MeetingPlaceTypes.all)
              CategoryChip(
                label: type,
                selected: state.meetingPlaceType == type,
                onTap: () => controller.setMeetingPlaceType(type),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        const _GroupLabel('Notes (optional)'),
        AppTextField(
          label: 'Notes',
          hint: 'Anything the companion should know',
          initialValue: state.notes,
          prefixIcon: const Icon(Icons.notes_rounded),
          maxLines: 3,
          onChanged: controller.setNotes,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Activity picker — the app's real categories with their icons
// ---------------------------------------------------------------------------

/// Friendly activity label per category slug (matches the Home rail).
String _activityLabel(CategoryModel c) {
  switch (c.slug) {
    case 'coffee-partner':
      return 'Coffee';
    case 'movie-partner':
      return 'Movies';
    case 'shopping-partner':
      return 'Shopping';
    case 'event-companion':
      return 'Events';
    case 'city-guide':
      return 'City Tour';
    case 'travel-companion':
      return 'Travel';
    case 'networking-partner':
      return 'Network';
    default:
      return c.name;
  }
}

IconData _activityGlyph(CategoryModel c) {
  switch (c.slug) {
    case 'coffee-partner':
      return Icons.local_cafe_rounded;
    case 'movie-partner':
      return Icons.movie_rounded;
    case 'shopping-partner':
      return Icons.shopping_bag_rounded;
    case 'event-companion':
      return Icons.celebration_rounded;
    case 'city-guide':
      return Icons.map_rounded;
    case 'travel-companion':
      return Icons.flight_rounded;
    case 'networking-partner':
      return Icons.groups_rounded;
    default:
      return Icons.category_rounded;
  }
}

/// Grid of the app's real categories (same icons as the Home rail) used as
/// the booking's activity picker. Tapping a tile plays a click, selects the
/// activity AND records the real categoryId on the booking. Falls back to the
/// classic text chips while categories load or if they fail.
class _ActivityCategoryGrid extends ConsumerWidget {
  const _ActivityCategoryGrid({required this.state, required this.controller});

  final BookingFlowState state;
  final BookingFlowController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(homeCategoriesProvider);
    final iconScale =
        ref.watch(appConfigProvider).valueOrNull?.categoryIconScale ?? 0.46;
    final categories = async.valueOrNull ?? const <CategoryModel>[];

    if (categories.isEmpty) {
      // Loading / error → keep the flow usable with plain chips.
      return Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          for (final activity in Activities.all)
            CategoryChip(
              label: activity,
              selected: state.activity == activity,
              onTap: () {
                AppSounds.pop();
                controller.setActivity(activity,
                    categoryId: state.categoryId);
              },
            ),
        ],
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: AppSpacing.md,
      children: [
        for (final c in categories)
          _ActivityTile(
            label: _activityLabel(c),
            glyph: _activityGlyph(c),
            iconUrl: c.iconUrl,
            iconScale: iconScale,
            selected: state.activity == _activityLabel(c),
            onTap: () {
              AppSounds.pop();
              controller.setActivity(_activityLabel(c), categoryId: c.id);
            },
          ),
      ],
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({
    required this.label,
    required this.glyph,
    required this.iconUrl,
    required this.iconScale,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData glyph;
  final String? iconUrl;
  final double iconScale;
  final bool selected;
  final VoidCallback onTap;

  static const double _circle = 62;
  static const double _ring = 2.5;

  @override
  Widget build(BuildContext context) {
    const inner = _circle - 2 * _ring;
    final iconSize = (inner * iconScale).clamp(12.0, inner - 2.0);
    final inset = (inner - iconSize) / 2;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: AnimatedScale(
        scale: selected ? 1.06 : 1.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        child: SizedBox(
          width: 76,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon disc — pink gradient ring + soft glow when selected.
              Container(
                width: _circle,
                height: _circle,
                padding: const EdgeInsets.all(_ring),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: selected
                      ? const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFFF6FA0), Color(0xFFE63B5E)],
                        )
                      : null,
                  color: selected ? null : AppColors.line,
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  alignment: Alignment.center,
                  padding: EdgeInsets.all(inset),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.surface,
                  ),
                  child: (iconUrl != null && iconUrl!.isNotEmpty)
                      ? CachedNetworkImage(
                          imageUrl: iconUrl!,
                          fit: BoxFit.contain,
                          placeholder: (_, __) => Icon(glyph,
                              color: AppColors.goldDeep, size: iconSize),
                          errorWidget: (_, __, ___) => Icon(glyph,
                              color: AppColors.goldDeep, size: iconSize),
                        )
                      : Icon(glyph, color: AppColors.goldDeep, size: iconSize),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? AppColors.primary : AppColors.inkMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 3 — REVIEW & PAY (summary with edit jumps + price breakdown)
// ---------------------------------------------------------------------------

class _ReviewStep extends ConsumerWidget {
  const _ReviewStep({
    required this.companion,
    required this.state,
    required this.controller,
  });

  final CompanionModel companion;
  final BookingFlowState state;
  final BookingFlowController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quote = state.quote;
    final date = state.bookingDate;
    final slot = state.selectedSlot;

    final whenText = [
      if (state.durationHours != null)
        Formatters.durationHours(state.durationHours!),
      if (date != null) Formatters.dateLong(date),
      if (slot != null) Formatters.time12(slot.startTime),
    ].join(' · ');

    final placeText = [
      if (state.meetingLocation.trim().isNotEmpty) state.meetingLocation.trim(),
      if (state.meetingPlaceType != null) '(${state.meetingPlaceType})',
    ].join(' ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepHeading(
          title: 'Review & confirm',
          subtitle: 'Check everything, then confirm and pay.',
        ),
        _SummaryCard(
          rows: [
            _SummaryRow(
              'When',
              whenText.isEmpty ? '—' : whenText,
              onEdit: () => controller.goToStep(BookingStep.when),
            ),
            _SummaryRow(
              'Activity',
              state.activity ?? '—',
              onEdit: () => controller.goToStep(BookingStep.details),
            ),
            _SummaryRow(
              'Meeting place',
              placeText.isEmpty ? '—' : placeText,
              onEdit: () => controller.goToStep(BookingStep.details),
            ),
            if (state.notes.trim().isNotEmpty)
              _SummaryRow(
                'Notes',
                state.notes.trim(),
                onEdit: () => controller.goToStep(BookingStep.details),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        if (quote != null)
          _PriceBreakdown(quote: quote)
        else if (state.submitError != null)
          ErrorView(
            error: state.submitError,
            message: state.submitError is ApiException
                ? (state.submitError as ApiException).message
                : 'Could not load the price. Please try again.',
            onRetry: controller.refreshQuote,
          )
        else
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: LoadingView(message: 'Calculating price…'),
          ),
        if (quote != null)
          _PaymentMethodPicker(
            selected: state.paymentMethod,
            controller: controller,
          ),
        if (quote != null && state.submitError != null) ...[
          const SizedBox(height: AppSpacing.md),
          _ErrorNote(error: state.submitError!),
        ],
      ],
    );
  }
}

/// Payment method chooser shown on the review step. Only renders when BOTH
/// online and cash are enabled by the admin; with a single method it silently
/// selects it (no picker). Reads the admin toggles from [appConfigProvider].
class _PaymentMethodPicker extends ConsumerWidget {
  const _PaymentMethodPicker({required this.selected, required this.controller});

  final String selected;
  final BookingFlowController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(appConfigProvider).asData?.value ?? AppConfig.empty;
    final methods = <String>[
      if (cfg.onlinePaymentEnabled) 'razorpay',
      if (cfg.cashPaymentEnabled) 'cash',
    ];
    final available = methods.isEmpty ? const ['razorpay'] : methods;
    final effective = available.contains(selected) ? selected : available.first;
    // Keep the flow state in sync when the current choice isn't offered.
    if (effective != selected) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => controller.setPaymentMethod(effective),
      );
    }
    // One method only → no choice to make.
    if (available.length <= 1) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Payment method',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _PayOption(
          selected: effective == 'razorpay',
          icon: Icons.credit_card_rounded,
          title: 'Pay online',
          subtitle: 'Card, UPI or netbanking — now',
          onTap: () => controller.setPaymentMethod('razorpay'),
        ),
        const SizedBox(height: AppSpacing.sm),
        _PayOption(
          selected: effective == 'cash',
          icon: Icons.payments_rounded,
          title: 'Cash on delivery',
          subtitle: 'Pay in cash at the meeting',
          onTap: () => controller.setPaymentMethod('cash'),
        ),
      ],
    );
  }
}

class _PayOption extends StatelessWidget {
  const _PayOption({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radius),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.06)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : AppColors.line,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                color: selected ? AppColors.primary : AppColors.inkMuted,
                size: 24),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? AppColors.primary : AppColors.inkMuted,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

class _PriceBreakdown extends StatelessWidget {
  const _PriceBreakdown({required this.quote});

  final BookingQuote quote;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          _PriceRow(
            label:
                '${Formatters.ratePerHour(quote.hourlyRate)} × ${quote.durationHours}',
            value: Formatters.money(quote.totalAmount),
          ),
          const Divider(height: AppSpacing.lg),
          _PriceRow(
            label: 'Total payable',
            value: Formatters.money(quote.totalAmount),
            emphasised: true,
          ),
        ],
      ),
    );
  }
}

class _PriceRow extends StatelessWidget {
  const _PriceRow({
    required this.label,
    required this.value,
    this.emphasised = false,
  });

  final String label;
  final String value;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final weight = emphasised ? FontWeight.w800 : FontWeight.w500;
    final size = emphasised ? 17.0 : 14.5;
    final valueColor = emphasised ? AppColors.primary : AppColors.ink;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: weight,
              fontSize: size,
              color: AppColors.ink,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: weight,
            fontSize: size,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.rows});

  final List<_SummaryRow> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            rows[i],
          ],
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow(this.label, this.value, {this.onEdit});

  final String label;
  final String value;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.inkMuted,
                fontSize: 13.5,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
          if (onEdit != null)
            GestureDetector(
              onTap: onEdit,
              child: const Padding(
                padding: EdgeInsets.only(left: AppSpacing.sm),
                child: Text(
                  'Edit',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom action bar — running price + Back / Continue / Confirm.
// ---------------------------------------------------------------------------

class _BottomBar extends ConsumerWidget {
  const _BottomBar({
    required this.companion,
    required this.state,
    required this.controller,
  });

  final CompanionModel? companion;
  final BookingFlowState state;
  final BookingFlowController controller;

  Future<void> _onPrimary(BuildContext context, WidgetRef ref) async {
    if (state.step == BookingStep.review) {
      // Final confirmation -> create the booking. Online -> payment screen;
      // cash (pay in person) -> straight to the booking, no online payment.
      final booking = await controller.submit();
      if (booking != null && context.mounted) {
        if (state.paymentMethod == 'cash') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Booking requested — pay in cash at the meeting.'),
            ),
          );
          context.go(Routes.bookingDetailPath(booking.id));
        } else {
          context.go(Routes.paymentPath(booking.id));
        }
      }
      return;
    }
    final blocked = await controller.next();
    if (blocked != null && context.mounted) {
      AppSounds.error();
      final message = blocked is ApiException
          ? blocked.message
          : 'Could not get a price. Please try again.';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ));
    }
  }

  /// What exactly is still missing on the current step — shown when the user
  /// taps a not-yet-ready Continue, so they're never left guessing.
  String _missingHint(BookingFlowState s) {
    switch (s.step) {
      case BookingStep.when:
        if (s.durationHours == null) return 'Choose how many hours you want.';
        if (s.bookingDate == null) return 'Pick a date for the meeting.';
        return 'Pick a time slot.';
      case BookingStep.details:
        if (!s.canContinueFromActivity) {
          return 'Choose an activity first.';
        }
        if (s.meetingLocation.trim().length < 3) {
          return 'Enter your meeting location.';
        }
        return 'Pick a meeting place type — Mall, Cafe, Restaurant…';
      case BookingStep.review:
        return 'Getting your price — one moment…';
    }
  }

  /// The live total to surface in the bar: the server quote on the review step,
  /// otherwise a local estimate from rate × duration.
  double? get _runningTotal {
    if (state.step == BookingStep.review && state.quote != null) {
      return state.quote!.totalAmount;
    }
    if (companion != null && state.durationHours != null) {
      return companion!.hourlyRate * state.durationHours!;
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isReview = state.step == BookingStep.review;
    final label = isReview
        ? (state.paymentMethod == 'cash' ? 'Confirm booking' : 'Confirm & Pay')
        : 'Continue';
    final total = _runningTotal;
    final priceLabel = isReview ? 'Total payable' : 'Estimated total';

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: const Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        priceLabel,
                        style: const TextStyle(
                          color: AppColors.inkMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            total != null ? Formatters.money(total) : '—',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w800,
                              fontSize: 20,
                            ),
                          ),
                          if (!isReview && state.durationHours != null) ...[
                            const SizedBox(width: 6),
                            Text(
                              '· ${Formatters.durationHours(state.durationHours!)}',
                              style: const TextStyle(
                                color: AppColors.inkMuted,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              if (state.step.index > 0) ...[
                Expanded(
                  child: AppButton.outline(
                    label: 'Back',
                    onPressed:
                        state.isSubmitting ? null : () => controller.back(),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
              ],
              Expanded(
                flex: 2,
                child: GradientButton(
                  label: label,
                  icon: isReview
                      ? Icons.lock_rounded
                      : Icons.arrow_forward_rounded,
                  isLoading: state.isSubmitting,
                  // Greyed-out until the step is complete, but still
                  // tappable so we can SAY what's missing.
                  dimmed: !state.canContinue,
                  onPressed: state.isSubmitting
                      ? null
                      : () {
                          if (!state.canContinue) {
                            AppSounds.error();
                            ScaffoldMessenger.of(context)
                              ..hideCurrentSnackBar()
                              ..showSnackBar(SnackBar(
                                content: Text(_missingHint(state)),
                                behavior: SnackBarBehavior.floating,
                              ));
                            return;
                          }
                          AppSounds.pop();
                          _onPrimary(context, ref);
                        },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small shared pieces
// ---------------------------------------------------------------------------

class _MutedCard extends StatelessWidget {
  const _MutedCard({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.field,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.inkMuted),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: AppColors.inkMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorNote extends StatelessWidget {
  const _ErrorNote({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final message = error is ApiException
        ? (error as ApiException).message
        : 'We couldn\'t create your booking. Please try again.';
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
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.danger,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
