import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:companion_ranchi/core/auth/auth_controller.dart';
import 'package:companion_ranchi/core/network/api_exception.dart';
import 'package:companion_ranchi/core/theme/app_theme.dart';
import 'package:companion_ranchi/core/utils/formatters.dart';
import 'package:companion_ranchi/features/support/application/support_providers.dart';
import 'package:companion_ranchi/features/support/data/support_repository.dart';
import 'package:companion_ranchi/features/support/presentation/support_screen.dart';
import 'package:companion_ranchi/shared/widgets/widgets.dart';

/// A single support ticket thread: the original request, the message history and
/// a reply composer (`GET /support/tickets/:id` + `POST .../messages`).
class TicketThreadScreen extends ConsumerStatefulWidget {
  const TicketThreadScreen({super.key, required this.ticketId});

  final String ticketId;

  @override
  ConsumerState<TicketThreadScreen> createState() =>
      _TicketThreadScreenState();
}

class _TicketThreadScreenState extends ConsumerState<TicketThreadScreen> {
  final _replyController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _replyController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _replyController.text.trim();
    if (text.isEmpty) return;
    final ok = await ref.read(ticketReplyControllerProvider.notifier).send(
          ticketId: widget.ticketId,
          message: text,
        );
    if (!mounted) return;
    if (ok) {
      _replyController.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    } else {
      final error = ref.read(ticketReplyControllerProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is ApiException ? error.message : 'Could not send reply.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ticketAsync = ref.watch(ticketDetailProvider(widget.ticketId));
    final currentUserId = ref.watch(currentUserProvider)?.id;
    final replyState = ref.watch(ticketReplyControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Ticket')),
      body: ticketAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () =>
              ref.invalidate(ticketDetailProvider(widget.ticketId)),
        ),
        data: (ticket) {
          final closed = !ticket.isOpen;
          return Column(
            children: [
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async =>
                      ref.invalidate(ticketDetailProvider(widget.ticketId)),
                  child: ListView(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    children: [
                      _TicketHeaderCard(ticket: ticket),
                      const SizedBox(height: AppSpacing.lg),
                      _OriginalMessage(ticket: ticket),
                      const SizedBox(height: AppSpacing.md),
                      ...ticket.messages.map(
                        (m) => _MessageBubble(
                          message: m,
                          isMine: currentUserId != null &&
                              m.senderId == currentUserId,
                        ),
                      ),
                      if (closed) ...[
                        const SizedBox(height: AppSpacing.lg),
                        Center(
                          child: Text(
                            'This ticket is ${SupportTicket.statusLabel(ticket.status).toLowerCase()}.',
                            style: const TextStyle(
                              color: AppColors.inkMuted,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (!closed)
                _Composer(
                  controller: _replyController,
                  isSending: replyState.isLoading,
                  onSend: _send,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _TicketHeaderCard extends StatelessWidget {
  const _TicketHeaderCard({required this.ticket});

  final SupportTicket ticket;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark
              ? AppColors.darkLine
              : AppColors.line,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  ticket.subject,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              TicketStatusChip(status: ticket.status),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.flag_outlined,
                  size: 14, color: AppColors.inkMuted),
              const SizedBox(width: 4),
              Text(
                '${SupportTicket.priorityLabel(ticket.priority)} priority',
                style:
                    const TextStyle(color: AppColors.inkMuted, fontSize: 12),
              ),
              if (ticket.createdAt != null) ...[
                const SizedBox(width: 12),
                const Icon(Icons.schedule_rounded,
                    size: 14, color: AppColors.inkMuted),
                const SizedBox(width: 4),
                Text(
                  Formatters.dateTime(ticket.createdAt!),
                  style:
                      const TextStyle(color: AppColors.inkMuted, fontSize: 12),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _OriginalMessage extends StatelessWidget {
  const _OriginalMessage({required this.ticket});

  final SupportTicket ticket;

  @override
  Widget build(BuildContext context) {
    return _MessageBubble(
      message: TicketMessage(
        id: 'original',
        message: ticket.description,
        createdAt: ticket.createdAt,
      ),
      isMine: true,
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.isMine});

  final TicketMessage message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isMine
        ? AppColors.primary
        : (isDark ? AppColors.darkField : AppColors.field);
    final fg = isMine ? Colors.white : (isDark ? AppColors.darkInk : AppColors.ink);

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(AppSpacing.radius),
            topRight: const Radius.circular(AppSpacing.radius),
            bottomLeft: Radius.circular(isMine ? AppSpacing.radius : 4),
            bottomRight: Radius.circular(isMine ? 4 : AppSpacing.radius),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMine)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  'Support',
                  style: TextStyle(
                    color: fg.withValues(alpha: 0.7),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            Text(message.message, style: TextStyle(color: fg, height: 1.35)),
            if (message.createdAt != null) ...[
              const SizedBox(height: 4),
              Text(
                Formatters.relative(message.createdAt),
                style: TextStyle(
                  color: fg.withValues(alpha: 0.7),
                  fontSize: 10,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.isSending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool isSending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: isDark ? AppColors.darkLine : AppColors.line,
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  hintText: 'Type your reply…',
                ),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: AppColors.primary,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: isSending ? null : onSend,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: isSending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            valueColor:
                                AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : const Icon(Icons.send_rounded,
                          color: Colors.white, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
