import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import 'package:companion_ranchi/core/auth/auth_controller.dart';
import 'package:companion_ranchi/core/models/booking_model.dart';
import 'package:companion_ranchi/core/network/api_exception.dart';
import 'package:companion_ranchi/core/router/routes.dart';
import 'package:companion_ranchi/core/theme/app_theme.dart';
import 'package:companion_ranchi/core/utils/app_sounds.dart';
import 'package:companion_ranchi/core/utils/formatters.dart';
import 'package:companion_ranchi/features/bookings/application/bookings_providers.dart';
import 'package:companion_ranchi/features/bookings/data/booking_detail_actions.dart';
import 'package:companion_ranchi/features/bookings/presentation/widgets/start_code_dialog.dart';
import 'package:companion_ranchi/features/bookings/presentation/my_bookings_screen.dart'
    show BookingStatusBadge;
import 'package:companion_ranchi/shared/widgets/widgets.dart';

/// Full booking detail: parties, schedule, meeting place, price breakdown, a
/// status timeline and role-aware actions. The customer can cancel; the
/// companion can accept / start / complete. An SOS button is shown while the
/// booking is IN_PROGRESS, plus a chat shortcut to the other party.
class BookingDetailScreen extends ConsumerWidget {
  const BookingDetailScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(bookingDetailProvider(bookingId));
    final myId = ref.watch(currentUserProvider)?.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Booking'),
        actions: [
          detailAsync.maybeWhen(
            data: (b) => IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => ref.invalidate(bookingDetailProvider(bookingId)),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: SafeArea(
        child: detailAsync.when(
          loading: () => const LoadingView(message: 'Loading booking…'),
          error: (e, _) => ErrorView(
            error: e,
            onRetry: () => ref.invalidate(bookingDetailProvider(bookingId)),
          ),
          // Which side you're on is per-booking, not your global role: a
          // companion who booked another companion is the CUSTOMER here.
          // If you aren't the customer on this booking, you're the companion.
          data: (booking) => _DetailBody(
            booking: booking,
            isCompanion: myId != null && booking.customerId != myId,
          ),
        ),
      ),
    );
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.booking, required this.isCompanion});

  final BookingModel booking;
  final bool isCompanion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final party = isCompanion ? booking.customer : booking.companion;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        _HeaderCard(booking: booking, party: party, isCompanion: isCompanion),
        // Meet-at-location start code: the customer shows it, the companion enters it.
        if (booking.isConfirmed) ...[
          const SizedBox(height: AppSpacing.lg),
          if (!isCompanion && (booking.startCode?.isNotEmpty ?? false))
            _StartCodeCard(code: booking.startCode!)
          else if (isCompanion)
            const _CompanionStartHint(),
        ],
        const SizedBox(height: AppSpacing.lg),
        _ScheduleCard(booking: booking),
        const SizedBox(height: AppSpacing.lg),
        _PriceCard(booking: booking, isCompanion: isCompanion),
        const SizedBox(height: AppSpacing.lg),
        _Timeline(booking: booking),
        const SizedBox(height: AppSpacing.lg),
        // Live location is offered for the whole active window (CONFIRMED →
        // IN_PROGRESS) so both parties can navigate to the meeting point.
        if (booking.isConfirmed || booking.isInProgress) ...[
          _LiveLocationButton(booking: booking, peerName: party?.name),
          const SizedBox(height: AppSpacing.lg),
        ],
        if (booking.isInProgress) ...[
          _SosButton(booking: booking),
          const SizedBox(height: AppSpacing.lg),
        ],
        const SafetyBanner(),
        const SizedBox(height: AppSpacing.xl),
        _Actions(
          booking: booking,
          isCompanion: isCompanion,
          party: party,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.booking,
    required this.party,
    required this.isCompanion,
  });

  final BookingModel booking;
  final BookingParty? party;
  final bool isCompanion;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  booking.bookingCode,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    letterSpacing: 1,
                    color: AppColors.ink,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              BookingStatusBadge(status: booking.status),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.md),
          Row(
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
                    const SizedBox(height: 2),
                    Text(
                      booking.activity,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.inkMuted,
                        fontSize: 13.5,
                      ),
                    ),
                  ],
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
// Schedule + meeting place
// ---------------------------------------------------------------------------

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({required this.booking});

  final BookingModel booking;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        children: [
          _IconRow(
            icon: Icons.event_rounded,
            label: 'Date',
            value: booking.bookingDate != null
                ? Formatters.dateLong(booking.bookingDate!)
                : '—',
          ),
          const SizedBox(height: AppSpacing.md),
          _IconRow(
            icon: Icons.schedule_rounded,
            label: 'Time',
            value:
                '${Formatters.time12(booking.startTime)} – ${Formatters.time12(booking.endTime)}'
                ' (${Formatters.durationHours(booking.durationHours)})',
          ),
          const SizedBox(height: AppSpacing.md),
          _IconRow(
            icon: Icons.location_on_rounded,
            label: 'Meeting place',
            value: booking.meetingLocation,
          ),
          const SizedBox(height: AppSpacing.md),
          _IconRow(
            icon: Icons.public_rounded,
            label: 'Place type',
            value: booking.meetingPlaceType,
          ),
          if (booking.notes != null && booking.notes!.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            _IconRow(
              icon: Icons.notes_rounded,
              label: 'Notes',
              value: booking.notes!.trim(),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Price
// ---------------------------------------------------------------------------

class _PriceCard extends StatelessWidget {
  const _PriceCard({required this.booking, required this.isCompanion});

  final BookingModel booking;
  final bool isCompanion;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        children: [
          _PriceRow(
            label:
                '${Formatters.ratePerHour(booking.hourlyRate)} × ${booking.durationHours}',
            value: Formatters.money(booking.totalAmount),
          ),
          const Divider(height: AppSpacing.lg),
          _PriceRow(
            label: 'Total',
            value: Formatters.money(booking.totalAmount),
            emphasised: true,
          ),
          // The companion sees their net payout after commission.
          if (isCompanion) ...[
            const SizedBox(height: AppSpacing.sm),
            _PriceRow(
              label:
                  'Your payout (after ${booking.commissionRate.toStringAsFixed(0)}% commission)',
              value: Formatters.money(booking.companionPayout),
              muted: true,
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Status timeline
// ---------------------------------------------------------------------------

class _Timeline extends StatelessWidget {
  const _Timeline({required this.booking});

  final BookingModel booking;

  @override
  Widget build(BuildContext context) {
    final history = booking.statusHistory;
    // Fall back to a synthetic single entry if the backend didn't include one.
    final entries = history.isNotEmpty
        ? history
        : [
            BookingStatusEntry(
              status: booking.status,
              createdAt: booking.createdAt,
            ),
          ];

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Status timeline',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5),
          ),
          const SizedBox(height: AppSpacing.md),
          for (var i = 0; i < entries.length; i++)
            _TimelineTile(
              entry: entries[i],
              isFirst: i == 0,
              isLast: i == entries.length - 1,
            ),
        ],
      ),
    );
  }
}

class _TimelineTile extends StatelessWidget {
  const _TimelineTile({
    required this.entry,
    required this.isFirst,
    required this.isLast,
  });

  final BookingStatusEntry entry;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 14,
                height: 14,
                margin: const EdgeInsets.only(top: 2),
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: AppColors.line,
                  ),
                ),
            ],
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    BookingStatus.label(entry.status),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  if (entry.createdAt != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      Formatters.dateTime(entry.createdAt!),
                      style: const TextStyle(
                        color: AppColors.inkMuted,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                  if (entry.note != null && entry.note!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      entry.note!,
                      style: const TextStyle(
                        color: AppColors.inkMuted,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SOS
// ---------------------------------------------------------------------------

/// Opens the booking-scoped live tracking map. Both parties can navigate to the
/// meeting point and watch each other move in real time (opt-in sharing).
class _LiveLocationButton extends StatelessWidget {
  const _LiveLocationButton({required this.booking, required this.peerName});

  final BookingModel booking;
  final String? peerName;

  @override
  Widget build(BuildContext context) {
    return GradientButton(
      label: 'Share & track live location',
      icon: Icons.share_location_rounded,
      gradient: AppGradients.accent,
      onPressed: () => context.push(
        Routes.liveTrackingPath(booking.id),
        extra: peerName,
      ),
    );
  }
}

class _SosButton extends ConsumerStatefulWidget {
  const _SosButton({required this.booking});

  final BookingModel booking;

  @override
  ConsumerState<_SosButton> createState() => _SosButtonState();
}

class _SosButtonState extends ConsumerState<_SosButton> {
  bool _sending = false;

  Future<void> _trigger() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send SOS alert?'),
        content: const Text(
          'This immediately alerts our safety team with your booking details '
          'and current location. Only use this if you feel unsafe — in a real '
          'emergency, also call 112.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send SOS'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // Urgent siren the moment the user commits — confirms the alert fired
    // even before the network round-trip completes.
    AppSounds.sosAlert();
    setState(() => _sending = true);
    // Best-effort location — never block the alert if it's unavailable.
    final pos = await _currentPosition();
    try {
      await ref.read(bookingDetailActionsProvider).raiseSos(
            bookingId: widget.booking.id,
            latitude: pos?.latitude,
            longitude: pos?.longitude,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SOS sent. Help is on the way. Stay where you are.'),
          backgroundColor: AppColors.danger,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final message =
          e is ApiException ? e.message : 'Could not send SOS. Try calling 112.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Current GPS position for the SOS alert. Returns null on any failure
  /// (permission denied, service off, timeout) so the alert is never blocked.
  Future<Position?> _currentPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null;
      }
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 6),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.danger,
          foregroundColor: Colors.white,
        ),
        onPressed: _sending ? null : _trigger,
        icon: _sending
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              )
            : const Icon(Icons.sos_rounded),
        label: Text(_sending ? 'Sending…' : 'Emergency SOS'),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Actions (role-aware)
// ---------------------------------------------------------------------------

class _Actions extends ConsumerWidget {
  const _Actions({
    required this.booking,
    required this.isCompanion,
    required this.party,
  });

  final BookingModel booking;
  final bool isCompanion;
  final BookingParty? party;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actionState = ref.watch(bookingActionsProvider(booking.id));
    final controller = ref.read(bookingActionsProvider(booking.id).notifier);
    final busy = actionState.isLoading;

    final children = <Widget>[];

    // Chat shortcut to the other party (available unless the booking is closed).
    if (party != null && !booking.isCancelled && !booking.isRefunded) {
      children.add(
        AppButton.outline(
          label: 'Message ${isCompanion ? 'customer' : 'companion'}',
          icon: Icons.chat_bubble_outline_rounded,
          onPressed: busy
              ? null
              : () => _openChat(context, ref, party!.id, booking.id),
        ),
      );
    }

    // Customer: pay (if awaiting) then cancel (before completion).
    if (!isCompanion) {
      if (booking.awaitingPayment) {
        children.add(
          GradientButton(
            label: 'Complete payment',
            icon: Icons.lock_rounded,
            onPressed:
                busy ? null : () => context.go(Routes.paymentPath(booking.id)),
          ),
        );
      }
      if (booking.isPending || booking.isConfirmed) {
        children.add(
          AppButton.outline(
            label: 'Cancel booking',
            icon: Icons.close_rounded,
            color: AppColors.danger,
            onPressed:
                busy ? null : () => _cancel(context, controller),
          ),
        );
      }
    } else {
      // Companion: accept / start / complete depending on status.
      if (booking.isPending) {
        children.add(
          GradientButton(
            label: 'Accept booking',
            icon: Icons.check_rounded,
            isLoading: busy,
            onPressed: busy
                ? null
                : () => _runAction(context, controller.accept,
                    success: 'Booking accepted.'),
          ),
        );
        children.add(
          AppButton.outline(
            label: 'Decline',
            icon: Icons.close_rounded,
            color: AppColors.danger,
            onPressed: busy
                ? null
                : () => _runAction(context, controller.reject,
                    success: 'Booking declined.'),
          ),
        );
      } else if (booking.isConfirmed) {
        children.add(
          GradientButton(
            label: 'Start meeting',
            icon: Icons.play_arrow_rounded,
            isLoading: busy,
            onPressed: busy
                ? null
                : () => _startWithCode(context, ref, controller, booking.id),
          ),
        );
      } else if (booking.isInProgress) {
        children.add(
          GradientButton(
            label: 'Complete meeting',
            icon: Icons.flag_rounded,
            isLoading: busy,
            onPressed: busy
                ? null
                : () => _runAction(context, controller.complete,
                    success: 'Booking completed.'),
          ),
        );
      }
    }

    if (children.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          children[i],
        ],
      ],
    );
  }

  Future<void> _runAction(
    BuildContext context,
    Future<BookingModel?> Function() action, {
    required String success,
  }) async {
    final result = await action();
    if (!context.mounted) return;
    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Action failed. Please try again.')),
      );
    }
  }

  /// Companion enters the customer's 6-digit start code to begin the meetup.
  /// The dialog stays open on a wrong code so they can re-try, surfacing the
  /// exact server message (e.g. "Incorrect start code. 6 attempts left.").
  Future<void> _startWithCode(
    BuildContext context,
    WidgetRef ref,
    BookingActionsController controller,
    String id,
  ) async {
    final started = await showStartCodeDialog(
      context,
      onSubmit: (code) async {
        final result = await controller.start(code);
        if (result != null) return null; // success → close
        final state = ref.read(bookingActionsProvider(id));
        final err = state.hasError ? state.error : null;
        return err is ApiException
            ? err.message
            : 'Could not start the meeting. Check the code and try again.';
      },
    );
    if (started && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Meeting started. Stay safe!')),
      );
    }
  }

  Future<void> _cancel(
    BuildContext context,
    BookingActionsController controller,
  ) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => const _CancelDialog(),
    );
    if (reason == null) return;
    final result = await controller.cancel(reason);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result != null
              ? 'Booking cancelled.'
              : 'Could not cancel. Please try again.',
        ),
      ),
    );
  }

  Future<void> _openChat(
    BuildContext context,
    WidgetRef ref,
    String peerUserId,
    String bookingId,
  ) async {
    try {
      final conversationId = await ref
          .read(bookingDetailActionsProvider)
          .openConversation(peerUserId: peerUserId, bookingId: bookingId);
      if (!context.mounted) return;
      if (conversationId.isNotEmpty) {
        context.go(Routes.chatThreadPath(conversationId));
      }
    } catch (e) {
      if (!context.mounted) return;
      final message =
          e is ApiException ? e.message : 'Could not open chat. Try again.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }
}

class _CancelDialog extends StatefulWidget {
  const _CancelDialog();

  @override
  State<_CancelDialog> createState() => _CancelDialogState();
}

class _CancelDialogState extends State<_CancelDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cancel booking'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tell us why you\'re cancelling. Refunds follow our policy.',
            style: TextStyle(color: AppColors.inkMuted, fontSize: 13.5),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _controller,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Reason for cancellation',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Keep booking'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: () {
            final reason = _controller.text.trim();
            Navigator.pop(
              context,
              reason.isEmpty ? 'Cancelled by customer' : reason,
            );
          },
          child: const Text('Cancel booking'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Meet-at-location start code
// ---------------------------------------------------------------------------

/// Shown to the CUSTOMER on a confirmed booking: the 6-digit code they reveal to
/// the companion in person so the meetup can be started. Pink gradient hero card.
class _StartCodeCard extends StatelessWidget {
  const _StartCodeCard({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final spaced = code.split('').join('  ');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF6FA0), Color(0xFFE63B5E)],
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.32),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.vpn_key_rounded, color: Colors.white, size: 18),
              const SizedBox(width: AppSpacing.sm),
              const Expanded(
                child: Text(
                  'Your start code',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15.5,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Copy',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.copy_rounded,
                    color: Colors.white, size: 18),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: code));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Start code copied.')),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: Text(
              spaced,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 34,
                letterSpacing: 2,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Show this code to your companion when you meet, so they can start '
            'the booking. Never share it before meeting in person.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown to the COMPANION on a confirmed booking — they must obtain the code
/// from the customer at the meeting point (they can never see it themselves).
class _CompanionStartHint extends StatelessWidget {
  const _CompanionStartHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.vpn_key_rounded,
              color: AppColors.primary, size: 18),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: RichText(
              text: const TextSpan(
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 13,
                  height: 1.4,
                ),
                children: [
                  TextSpan(
                    text: 'When you meet the customer, ',
                  ),
                  TextSpan(
                    text: 'ask for their 6-digit start code',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  TextSpan(
                    text: ', then tap “Start meeting” and enter it to begin.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small shared pieces
// ---------------------------------------------------------------------------

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: Border.all(color: AppColors.line),
      ),
      child: child,
    );
  }
}

class _IconRow extends StatelessWidget {
  const _IconRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: AppSpacing.md),
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: const TextStyle(color: AppColors.inkMuted, fontSize: 13),
          ),
        ),
        Expanded(
          child: Text(
            value.isEmpty ? '—' : value,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
          ),
        ),
      ],
    );
  }
}

class _PriceRow extends StatelessWidget {
  const _PriceRow({
    required this.label,
    required this.value,
    this.emphasised = false,
    this.muted = false,
  });

  final String label;
  final String value;
  final bool emphasised;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final weight = emphasised ? FontWeight.w800 : FontWeight.w500;
    final size = emphasised ? 17.0 : 14.0;
    final color = muted
        ? AppColors.inkMuted
        : (emphasised ? AppColors.primary : AppColors.ink);
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
              color: muted ? AppColors.inkMuted : AppColors.ink,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontWeight: weight, fontSize: size, color: color),
        ),
      ],
    );
  }
}
