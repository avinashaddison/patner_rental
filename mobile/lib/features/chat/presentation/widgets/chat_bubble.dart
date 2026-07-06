import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:companion_ranchi/core/models/message_model.dart';
import 'package:companion_ranchi/core/theme/app_theme.dart';
import 'package:companion_ranchi/core/utils/formatters.dart';

/// A single chat message bubble (sent vs received), supporting TEXT and IMAGE.
///
/// Sent bubbles use the brand gradient and align right; received bubbles use a
/// neutral surface and align left. The sent-bubble footer shows the time plus a
/// delivery state: a clock while pending, a single tick when delivered, double
/// ticks (coloured) once the peer has read it, and a retry control on failure.
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.isPending = false,
    this.isFailed = false,
    this.onRetry,
  });

  final MessageModel message;
  final bool isMine;
  final bool isPending;
  final bool isFailed;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final radius = BorderRadius.only(
      topLeft: const Radius.circular(AppSpacing.radius),
      topRight: const Radius.circular(AppSpacing.radius),
      bottomLeft: Radius.circular(isMine ? AppSpacing.radius : 4),
      bottomRight: Radius.circular(isMine ? 4 : AppSpacing.radius),
    );

    final bubbleColor = isMine
        ? null
        : (isDark ? AppColors.darkField : AppColors.surface);
    final textColor = isMine
        ? Colors.white
        : (isDark ? AppColors.darkInk : AppColors.ink);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment:
            isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (isMine && isFailed) ...[
            _RetryButton(onRetry: onRetry),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.74,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: bubbleColor,
                  gradient: isMine ? AppGradients.primary : null,
                  borderRadius: radius,
                  border: isMine
                      ? null
                      : Border.all(
                          color: isDark
                              ? AppColors.darkLine
                              : AppColors.line,
                        ),
                  // Lift received (white) bubbles off the pink-tinted scaffold so
                  // they read as distinct cards. Sent bubbles get a soft glow.
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary
                          .withValues(alpha: isMine ? 0.18 : 0.07),
                      blurRadius: isMine ? 10 : 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: message.isImage
                    ? _ImageContent(
                        message: message,
                        isMine: isMine,
                        textColor: textColor,
                        isPending: isPending,
                        isFailed: isFailed,
                      )
                    : _TextContent(
                        message: message,
                        isMine: isMine,
                        textColor: textColor,
                        isPending: isPending,
                        isFailed: isFailed,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TextContent extends StatelessWidget {
  const _TextContent({
    required this.message,
    required this.isMine,
    required this.textColor,
    required this.isPending,
    required this.isFailed,
  });

  final MessageModel message;
  final bool isMine;
  final Color textColor;
  final bool isPending;
  final bool isFailed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message.content ?? '',
            style: TextStyle(
              color: textColor,
              fontSize: 15,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 3),
          _BubbleMeta(
            message: message,
            isMine: isMine,
            onLight: !isMine,
            isPending: isPending,
            isFailed: isFailed,
          ),
        ],
      ),
    );
  }
}

class _ImageContent extends StatelessWidget {
  const _ImageContent({
    required this.message,
    required this.isMine,
    required this.textColor,
    required this.isPending,
    required this.isFailed,
  });

  final MessageModel message;
  final bool isMine;
  final Color textColor;
  final bool isPending;
  final bool isFailed;

  @override
  Widget build(BuildContext context) {
    final url = message.imageUrl;
    return Stack(
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(
            maxHeight: 260,
            minWidth: 160,
          ),
          child: (url != null && url.isNotEmpty)
              ? CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => const _ImagePlaceholder(),
                  errorWidget: (_, __, ___) => const _ImageBroken(),
                )
              : const _ImagePlaceholder(),
        ),
        Positioned(
          right: 8,
          bottom: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            ),
            child: _BubbleMeta(
              message: message,
              isMine: isMine,
              onLight: false,
              isPending: isPending,
              isFailed: isFailed,
              forceLightText: true,
            ),
          ),
        ),
      ],
    );
  }
}

/// Time + delivery-state footer.
class _BubbleMeta extends StatelessWidget {
  const _BubbleMeta({
    required this.message,
    required this.isMine,
    required this.onLight,
    required this.isPending,
    required this.isFailed,
    this.forceLightText = false,
  });

  final MessageModel message;
  final bool isMine;

  /// True when the bubble background is light (received text), so meta text
  /// must be muted ink rather than translucent white.
  final bool onLight;
  final bool isPending;
  final bool isFailed;
  final bool forceLightText;

  @override
  Widget build(BuildContext context) {
    final metaColor = forceLightText
        ? Colors.white.withValues(alpha: 0.9)
        : isMine
            ? Colors.white.withValues(alpha: 0.85)
            : AppColors.inkMuted;

    final time = message.createdAt != null
        ? Formatters.timeOfDay(message.createdAt!)
        : '';

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          time,
          style: TextStyle(
            color: metaColor,
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (isMine) ...[
          const SizedBox(width: 4),
          _StatusIcon(
            isPending: isPending,
            isFailed: isFailed,
            isRead: message.isRead,
            color: metaColor,
          ),
        ],
      ],
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({
    required this.isPending,
    required this.isFailed,
    required this.isRead,
    required this.color,
  });

  final bool isPending;
  final bool isFailed;
  final bool isRead;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (isFailed) {
      return const Icon(
        Icons.error_outline_rounded,
        size: 13,
        color: Color(0xFFFFD2D2),
      );
    }
    if (isPending) {
      return Icon(Icons.access_time_rounded, size: 12, color: color);
    }
    // Read -> bright white double tick; delivered -> muted single tick.
    if (isRead) {
      return const Icon(
        Icons.done_all_rounded,
        size: 14,
        color: Colors.white,
      );
    }
    return Icon(Icons.done_rounded, size: 13, color: color);
  }
}

class _RetryButton extends StatelessWidget {
  const _RetryButton({required this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onRetry,
      radius: 22,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.refresh_rounded,
          size: 18,
          color: AppColors.danger,
        ),
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      height: 200,
      color: Colors.black.withValues(alpha: 0.06),
      alignment: Alignment.center,
      child: const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2.4),
      ),
    );
  }
}

class _ImageBroken extends StatelessWidget {
  const _ImageBroken();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      height: 160,
      color: Colors.black.withValues(alpha: 0.06),
      alignment: Alignment.center,
      child: const Icon(
        Icons.broken_image_rounded,
        color: AppColors.inkMuted,
        size: 32,
      ),
    );
  }
}
