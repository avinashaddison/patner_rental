import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:companion_ranchi/core/theme/app_theme.dart';
import 'package:companion_ranchi/core/utils/formatters.dart';
import 'package:companion_ranchi/features/support/application/support_providers.dart';
import 'package:companion_ranchi/features/support/data/support_repository.dart';
import 'package:companion_ranchi/features/support/presentation/create_ticket_sheet.dart';
import 'package:companion_ranchi/features/support/presentation/ticket_thread_screen.dart';
import 'package:companion_ranchi/shared/widgets/widgets.dart';

/// Help & Support hub: a quick help banner plus the user's tickets, and an entry
/// point to raise a new ticket (`/support/tickets`).
class SupportScreen extends ConsumerWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tickets = ref.watch(supportTicketsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Help & Support')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _newTicket(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New ticket'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(supportTicketsProvider),
        child: tickets.when(
          loading: () => ListView(
            children: const [
              _HelpHeader(),
              SizedBox(height: 80),
              LoadingView(),
            ],
          ),
          error: (e, _) => ListView(
            children: [
              const _HelpHeader(),
              const SizedBox(height: 40),
              ErrorView(
                error: e,
                onRetry: () => ref.invalidate(supportTicketsProvider),
              ),
            ],
          ),
          data: (list) => ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              const _HelpHeader(),
              const SectionHeader(
                title: 'Your tickets',
                subtitle: 'Conversations with our support team',
              ),
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: EmptyView(
                    icon: Icons.confirmation_number_outlined,
                    title: 'No tickets yet',
                    message:
                        'Tap “New ticket” to ask a question or report an issue.',
                  ),
                )
              else
                ...list.map((t) => _TicketTile(ticket: t)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _newTicket(BuildContext context) async {
    final created = await showModalBottomSheet<SupportTicket>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const CreateTicketSheet(),
    );
    if (created != null && context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TicketThreadScreen(ticketId: created.id),
        ),
      );
    }
  }
}

class _HelpHeader extends StatelessWidget {
  const _HelpHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          gradient: AppGradients.primary,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.support_agent_rounded, color: Colors.white),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "We're here to help",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Questions about a booking, payment or safety? Raise a ticket and '
              'our team will respond. For emergencies during a meeting, use SOS.',
              style:
                  TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: _QuickAction(
                    icon: Icons.call_rounded,
                    label: 'Call us',
                    onTap: () => _dial(context, '+911234567890'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _QuickAction(
                    icon: Icons.mail_rounded,
                    label: 'Email',
                    onTap: () => _email(context),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _dial(BuildContext context, String number) async {
    final uri = Uri(scheme: 'tel', path: number);
    if (!await launchUrl(uri) && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start the call.')),
      );
    }
  }

  Future<void> _email(BuildContext context) async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'support@companionranchi.com',
      query: 'subject=Support request',
    );
    if (!await launchUrl(uri) && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open your email app.')),
      );
    }
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(AppSpacing.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TicketTile extends StatelessWidget {
  const _TicketTile({required this.ticket});

  final SupportTicket ticket;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TicketThreadScreen(ticketId: ticket.id),
        ),
      ),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
        child: const Icon(Icons.chat_bubble_outline_rounded,
            color: AppColors.primary, size: 20),
      ),
      title: Text(
        ticket.subject,
        style: const TextStyle(fontWeight: FontWeight.w600),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        ticket.createdAt != null
            ? 'Opened ${Formatters.dateShort(ticket.createdAt!)}'
            : ticket.description,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppColors.inkMuted, fontSize: 12),
      ),
      trailing: TicketStatusChip(status: ticket.status),
    );
  }
}

/// Small coloured pill showing a ticket's status. Reused by the thread screen.
class TicketStatusChip extends StatelessWidget {
  const TicketStatusChip({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = _color(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: Text(
        SupportTicket.statusLabel(status),
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Color _color(String status) {
    switch (status) {
      case 'OPEN':
        return AppColors.goldDeep;
      case 'IN_PROGRESS':
        return AppColors.warning;
      case 'RESOLVED':
        return AppColors.success;
      case 'CLOSED':
        return AppColors.inkMuted;
      default:
        return AppColors.inkMuted;
    }
  }
}
