import 'package:flutter/material.dart';

import 'package:companion_ranchi/core/models/booking_model.dart';
import 'package:companion_ranchi/core/theme/app_theme.dart';
import 'package:companion_ranchi/core/utils/formatters.dart';
import 'package:companion_ranchi/shared/widgets/widgets.dart';

/// Card for an incoming/active booking on the companion dashboard. Shows the
/// customer, activity, schedule, meeting place and payout, plus contextual
/// action buttons (accept/reject when PENDING, start when CONFIRMED, complete
/// when IN_PROGRESS).
class IncomingBookingCard extends StatelessWidget {
  const IncomingBookingCard({
    super.key,
    required this.booking,
    this.isBusy = false,
    this.onAccept,
    this.onReject,
    this.onStart,
    this.onComplete,
    this.onTap,
  });

  final BookingModel booking;
  final bool isBusy;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  final VoidCallback? onStart;
  final VoidCallback? onComplete;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customerName = booking.customer?.name ?? 'Customer';

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                    backgroundImage: booking.customer?.photoUrl != null
                        ? NetworkImage(booking.customer!.photoUrl!)
                        : null,
                    child: booking.customer?.photoUrl == null
                        ? Text(
                            customerName.isNotEmpty
                                ? customerName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          customerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '#${booking.bookingCode}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.inkMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _StatusPill(status: booking.status),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _infoRow(
                Icons.local_activity_outlined,
                booking.activity,
              ),
              if (booking.bookingDate != null)
                _infoRow(
                  Icons.event_outlined,
                  '${Formatters.date(booking.bookingDate!)} · '
                  '${Formatters.time12(booking.startTime)}–'
                  '${Formatters.time12(booking.endTime)} '
                  '(${Formatters.durationHours(booking.durationHours)})',
                ),
              _infoRow(
                Icons.place_outlined,
                '${booking.meetingLocation} · ${booking.meetingPlaceType}',
              ),
              _infoRow(
                Icons.payments_outlined,
                'You earn ${Formatters.money(booking.companionPayout)} '
                'of ${Formatters.money(booking.totalAmount)}',
              ),
              const SizedBox(height: AppSpacing.md),
              _actions(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.inkMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actions(BuildContext context) {
    if (booking.isPending) {
      return Row(
        children: [
          Expanded(
            child: AppButton.outline(
              label: 'Reject',
              color: AppColors.danger,
              isLoading: false,
              onPressed: isBusy ? null : onReject,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: AppButton(
              label: 'Accept',
              icon: Icons.check_rounded,
              isLoading: isBusy,
              onPressed: isBusy ? null : onAccept,
            ),
          ),
        ],
      );
    }
    if (booking.isConfirmed) {
      return AppButton(
        label: 'Start meeting',
        icon: Icons.play_arrow_rounded,
        isLoading: isBusy,
        onPressed: isBusy ? null : onStart,
      );
    }
    if (booking.isInProgress) {
      return AppButton(
        label: 'Mark complete',
        icon: Icons.done_all_rounded,
        color: AppColors.success,
        isLoading: isBusy,
        onPressed: isBusy ? null : onComplete,
      );
    }
    return const SizedBox.shrink();
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final String status;

  Color get _color {
    switch (status) {
      case BookingStatus.pending:
        return AppColors.warning;
      case BookingStatus.confirmed:
        return AppColors.info;
      case BookingStatus.inProgress:
        return AppColors.primary;
      case BookingStatus.completed:
        return AppColors.success;
      default:
        return AppColors.inkMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: Text(
        BookingStatus.label(status),
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: _color,
        ),
      ),
    );
  }
}
