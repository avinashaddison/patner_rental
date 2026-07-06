import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:companion_ranchi/core/network/api_exception.dart';
import 'package:companion_ranchi/core/socket/socket_client.dart';
import 'package:companion_ranchi/core/theme/app_theme.dart';
import 'package:companion_ranchi/features/support/data/support_repository.dart';

const Color _kLive = Color(0xFF22C55E);

/// Live Support Chat — a continuous, chat-style conversation between the user
/// and the support team. Backed by `GET /support/chat` + `POST /support/chat/
/// messages`; admin replies arrive in realtime via the `support:message` socket
/// event. Surfaced from the Chat tab's pinned "Support" tile.
class SupportChatScreen extends ConsumerStatefulWidget {
  const SupportChatScreen({super.key});

  @override
  ConsumerState<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends ConsumerState<SupportChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<SupportChatMessage> _messages = [];
  StreamSubscription<SupportSocketMessage>? _sub;

  bool _loading = true;
  bool _sending = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    // Ensure realtime is connected, then listen for staff replies.
    ref.read(socketClientProvider).connect();
    _sub = ref.read(socketClientProvider).onSupportMessage.listen(_onSupportPush);
    _load();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final chat = await ref.read(supportRepositoryProvider).fetchSupportChat();
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(chat.messages);
        _loading = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (mounted) setState(() => _error = e);
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSupportPush(SupportSocketMessage m) {
    // Staff reply pushed in realtime — append unless we already have it.
    if (_messages.any((x) => x.id == m.id)) return;
    setState(() {
      _messages.add(SupportChatMessage(
        id: m.id,
        message: m.message,
        isMine: false,
        role: m.role,
        createdAt: m.createdAt,
      ));
    });
    _scrollToBottom();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    _input.clear();
    setState(() => _sending = true);
    // Optimistic append.
    final tempId = 'temp-${text.hashCode}-${_messages.length}';
    setState(() {
      _messages.add(SupportChatMessage(
        id: tempId,
        message: text,
        isMine: true,
        role: 'USER',
        createdAt: null,
      ));
    });
    _scrollToBottom();
    try {
      final saved =
          await ref.read(supportRepositoryProvider).sendSupportMessage(text);
      if (!mounted) return;
      // Swap the optimistic message for the persisted one.
      final i = _messages.indexWhere((x) => x.id == tempId);
      if (i != -1) setState(() => _messages[i] = saved);
    } catch (e) {
      if (mounted) {
        setState(() => _messages.removeWhere((x) => x.id == tempId));
        final msg = e is ApiException ? e.message : 'Could not send. Try again.';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
        _input.text = text; // let the user retry
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent + 80,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(
                gradient: AppGradients.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.headset_mic_rounded,
                  color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Companion Ranchi Support',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: _kLive,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      const Text(
                        'Live • usually replies in minutes',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.inkMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(child: _buildBody()),
          _InputBar(
            controller: _input,
            sending: _sending,
            onSend: _send,
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _ErrorView(error: _error!, onRetry: _load);
    }
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.lg, AppSpacing.md, AppSpacing.md),
      children: [
        const _WelcomeCard(),
        const SizedBox(height: AppSpacing.md),
        for (final m in _messages) _Bubble(message: m),
      ],
    );
  }
}

/// Intro card shown at the top of the thread.
class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          const Icon(Icons.support_agent_rounded,
              color: AppColors.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Hi! 👋 Ask us anything — bookings, payments, safety or your '
              'account. Our team replies right here.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: AppColors.ink.withValues(alpha: 0.8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A single chat bubble — mine (right, pink) or support (left, surface).
class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final SupportChatMessage message;

  @override
  Widget build(BuildContext context) {
    final mine = message.isMine;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.76,
        ),
        decoration: BoxDecoration(
          gradient: mine ? AppGradients.primary : null,
          color: mine ? null : AppColors.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
          border: mine ? null : Border.all(color: AppColors.line),
        ),
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!mine)
              const Padding(
                padding: EdgeInsets.only(bottom: 2),
                child: Text(
                  'Support',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            Text(
              message.message,
              style: TextStyle(
                fontSize: 14,
                height: 1.3,
                color: mine ? Colors.white : AppColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: 'Message support…',
                  isDense: true,
                  filled: true,
                  fillColor: AppColors.field,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                    borderSide: const BorderSide(color: AppColors.line),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                    borderSide: const BorderSide(color: AppColors.line),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                onSend();
              },
              child: Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(
                  gradient: AppGradients.primary,
                  shape: BoxShape.circle,
                ),
                child: sending
                    ? const Padding(
                        padding: EdgeInsets.all(13),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_rounded,
                        color: Colors.white, size: 21),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final msg = error is ApiException
        ? (error as ApiException).message
        : 'Couldn\'t load the chat.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: 48, color: AppColors.inkMuted),
            const SizedBox(height: AppSpacing.md),
            Text(msg, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
