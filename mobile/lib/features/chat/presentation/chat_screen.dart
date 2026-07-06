import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import 'package:companion_ranchi/core/auth/auth_controller.dart';
import 'package:companion_ranchi/core/models/conversation_model.dart';
import 'package:companion_ranchi/core/models/message_model.dart';
import 'package:companion_ranchi/core/router/routes.dart';
import 'package:companion_ranchi/core/theme/app_theme.dart';
import 'package:companion_ranchi/core/utils/app_sounds.dart';
import 'package:companion_ranchi/features/calls/presentation/call_screen.dart';
import 'package:companion_ranchi/features/chat/application/chat_controller.dart';
import 'package:companion_ranchi/features/chat/presentation/widgets/chat_bubble.dart';
import 'package:companion_ranchi/features/chat/presentation/widgets/chat_date_separator.dart';
import 'package:companion_ranchi/features/chat/presentation/widgets/chat_input_bar.dart';
import 'package:companion_ranchi/features/chat/presentation/widgets/typing_indicator.dart';
import 'package:companion_ranchi/features/safety/presentation/safety_actions.dart';
import 'package:companion_ranchi/shared/widgets/widgets.dart';

/// One-to-one realtime chat thread.
///
/// History loads via REST (paginated, infinite scroll upward); live messages,
/// typing indicators and read receipts arrive over Socket.IO. Supports text and
/// image sharing (image_picker -> presign upload -> IMAGE message). The peer's
/// display info is passed via GoRouter `extra` (a [ConversationModel]); the
/// screen still works without it (deep-link from a notification).
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _input = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  int _lastMessageCount = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  void _onScroll() {
    // The list is reversed, so reaching the *max* extent means the user
    // scrolled to the oldest messages -> load more history.
    if (_scroll.hasClients &&
        _scroll.position.pixels >=
            _scroll.position.maxScrollExtent - 80) {
      ref
          .read(chatControllerProvider(widget.conversationId).notifier)
          .loadMore();
    }
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    // Reversed list: bottom is offset 0.
    _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  ConversationModel? get _conversation {
    final extra = GoRouterState.of(context).extra;
    return extra is ConversationModel ? extra : null;
  }

  /// Start a voice or video call with the conversation peer. The peer's phone
  /// rings via the socket (`call:invite`); media flows over Agora.
  void _startCall({required bool video}) {
    AppSounds.pop();
    final convo = _conversation;
    // Unique per attempt; both sides key their signaling on this id.
    final callId =
        'call_${widget.conversationId}_${DateTime.now().millisecondsSinceEpoch}';
    context.push(
      Routes.call,
      extra: CallScreenArgs(
        conversationId: widget.conversationId,
        callId: callId,
        isCaller: true,
        video: video,
        peerName: convo?.peerName ?? 'Companion',
        peerPhotoUrl: convo?.peerPhotoUrl,
      ),
    );
  }

  Future<void> _send() async {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    AppSounds.whoosh();
    _input.clear();
    await ref
        .read(chatControllerProvider(widget.conversationId).notifier)
        .sendText(text);
    _scrollToBottom();
  }

  Future<void> _pickImage(ImageSource source) async {
    final XFile? file = await _picker.pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 82,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final contentType = _contentTypeFor(file.name);
    if (!mounted) return;
    await ref
        .read(chatControllerProvider(widget.conversationId).notifier)
        .uploadAndSendImage(
          bytes: bytes,
          fileName: file.name,
          contentType: contentType,
        );
    _scrollToBottom();
  }

  String _contentTypeFor(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  void _showAttachSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickImage(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final conversation = _conversation;
    final myUserId = ref.watch(currentUserProvider)?.id ?? '';
    final async = ref.watch(chatControllerProvider(widget.conversationId));

    // Auto-scroll to bottom when new messages arrive.
    ref.listen(chatControllerProvider(widget.conversationId), (prev, next) {
      final count = next.valueOrNull?.messages.length ?? 0;
      if (count > _lastMessageCount) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
      _lastMessageCount = count;

      // Surface image-upload / send errors as a snackbar.
      final err = next.valueOrNull?.error;
      if (err != null && prev?.valueOrNull?.error != err) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('Could not send. Please try again.')),
          );
      }
    });

    final state = async.valueOrNull;
    final peerTyping = state?.peerTyping ?? false;

    return Scaffold(
      appBar: _ChatAppBar(
        conversation: conversation,
        peerTyping: peerTyping,
        onVoiceCall: () => _startCall(video: false),
        onVideoCall: () => _startCall(video: true),
      ),
      body: Column(
        children: [
          const _SafetyStrip(),
          Expanded(
            child: async.when(
              loading: () => const LoadingView(message: 'Loading messages…'),
              error: (err, _) => ErrorView(
                error: err,
                onRetry: () => ref.invalidate(
                  chatControllerProvider(widget.conversationId),
                ),
              ),
              data: (chat) => _MessageList(
                chat: chat,
                myUserId: myUserId,
                scroll: _scroll,
                conversation: conversation,
                onRetry: (m) => ref
                    .read(chatControllerProvider(widget.conversationId)
                        .notifier)
                    .retry(m),
              ),
            ),
          ),
          ChatInputBar(
            controller: _input,
            sending: state?.sending ?? false,
            onSend: _send,
            onAttach: _showAttachSheet,
            onChanged: (text) => ref
                .read(chatControllerProvider(widget.conversationId).notifier)
                .onInputChanged(text),
          ),
        ],
      ),
    );
  }
}

/// The reversed message list with date separators and a leading typing bubble.
class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.chat,
    required this.myUserId,
    required this.scroll,
    required this.conversation,
    required this.onRetry,
  });

  final ChatState chat;
  final String myUserId;
  final ScrollController scroll;
  final ConversationModel? conversation;
  final ValueChanged<MessageModel> onRetry;

  @override
  Widget build(BuildContext context) {
    if (chat.messages.isEmpty) {
      return const EmptyView(
        icon: Icons.waving_hand_rounded,
        title: 'No messages yet',
        message: 'Send a message to start the conversation. '
            'Keep it friendly and public-place focused.',
      );
    }

    // Display order is reversed: newest at the bottom (index 0).
    final reversed = chat.messages.reversed.toList();

    return ListView.builder(
      controller: scroll,
      reverse: true,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      // +1 leading slot for typing indicator, +1 trailing slot for load-more.
      itemCount: reversed.length + 2,
      itemBuilder: (context, index) {
        // index 0 -> typing indicator (bottom of reversed list).
        if (index == 0) {
          return chat.peerTyping
              ? const Padding(
                  padding: EdgeInsets.only(top: 4, bottom: 4),
                  child: TypingIndicator(),
                )
              : const SizedBox(height: 4);
        }
        // Last slot -> load-more spinner / start-of-conversation header.
        if (index == reversed.length + 1) {
          if (chat.isLoadingMore) {
            return const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
              ),
            );
          }
          // We've reached the true start of the thread: show a friendly header
          // that frames the conversation and fills the space above short chats.
          if (!chat.hasMore) {
            return _ConversationStart(conversation: conversation);
          }
          return const SizedBox(height: 12);
        }

        final msgIndex = index - 1;
        final message = reversed[msgIndex];
        final isMine = message.senderId == myUserId;

        // The chronologically-previous message (older) for date-separator logic.
        final olderMessage =
            msgIndex + 1 < reversed.length ? reversed[msgIndex + 1] : null;
        final showDateSeparator =
            _needsDateSeparator(message, olderMessage);

        final bubble = ChatBubble(
          message: message,
          isMine: isMine,
          isPending: chat.isPending(message),
          isFailed: chat.isFailed(message),
          onRetry: () => onRetry(message),
        );

        if (!showDateSeparator) return bubble;
        return Column(
          children: [
            ChatDateSeparator(date: message.createdAt ?? DateTime.now()),
            bubble,
          ],
        );
      },
    );
  }

  bool _needsDateSeparator(MessageModel current, MessageModel? older) {
    final cur = current.createdAt;
    if (cur == null) return false;
    if (older == null) return true;
    final prev = older.createdAt;
    if (prev == null) return true;
    return cur.year != prev.year ||
        cur.month != prev.month ||
        cur.day != prev.day;
  }
}

/// Friendly header shown at the very start of a thread: peer avatar, name and a
/// short, safety-minded intro. Frames the conversation and fills the empty space
/// above short chats.
class _ConversationStart extends StatelessWidget {
  const _ConversationStart({required this.conversation});

  final ConversationModel? conversation;

  @override
  Widget build(BuildContext context) {
    final name = conversation?.peerName;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 14),
      child: Column(
        children: [
          UserAvatar(
            photoUrl: conversation?.peerPhotoUrl,
            name: name ?? 'C',
            radius: 34,
          ),
          const SizedBox(height: 12),
          Text(
            name ?? 'Companion',
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'This is the start of your conversation with ${name ?? 'your companion'}.\n'
            'Say hi 👋 — keep it friendly and public-place focused.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: AppColors.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _ChatAppBar({
    required this.conversation,
    required this.peerTyping,
    required this.onVoiceCall,
    required this.onVideoCall,
  });

  final ConversationModel? conversation;
  final bool peerTyping;
  final VoidCallback onVoiceCall;
  final VoidCallback onVideoCall;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = conversation?.peerName ?? 'Companion';
    final online = conversation?.peerIsOnline ?? false;

    final subtitle = peerTyping
        ? 'typing…'
        : online
            ? 'Online'
            : 'Offline';
    final subtitleColor = peerTyping || online
        ? AppColors.online
        : AppColors.inkMuted;

    return AppBar(
      titleSpacing: 0,
      title: Row(
        children: [
          UserAvatar(
            photoUrl: conversation?.peerPhotoUrl,
            name: name,
            radius: 18,
            isOnline: online,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: subtitleColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          onPressed: onVoiceCall,
          tooltip: 'Voice call',
          icon: const Icon(Icons.call_rounded, color: AppColors.primary),
        ),
        IconButton(
          onPressed: onVideoCall,
          tooltip: 'Video call',
          icon: const Icon(Icons.videocam_rounded, color: AppColors.primary),
        ),
        if (conversation?.peerUserId != null)
          SafetyMenuButton(
            userId: conversation!.peerUserId!,
            name: conversation?.peerName ?? 'this user',
            bookingId: conversation?.bookingId,
          ),
      ],
    );
  }
}

/// Thin reminder banner: meetings are public-places-only, companionship only.
class _SafetyStrip extends StatelessWidget {
  const _SafetyStrip();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.primary.withValues(alpha: 0.07),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: 6,
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shield_rounded, size: 14, color: AppColors.primary),
          SizedBox(width: 6),
          Flexible(
            child: Text(
              'Keep it friendly. Meet only in public places.',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
