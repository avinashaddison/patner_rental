import 'package:flutter/material.dart';

import 'package:companion_ranchi/core/theme/app_theme.dart';

/// Small presence indicator. Green when online, muted grey when offline.
/// Optionally renders a label ("Online" / "Offline").
class OnlineDot extends StatelessWidget {
  const OnlineDot({
    super.key,
    required this.isOnline,
    this.size = 10,
    this.showLabel = false,
    this.withBorder = true,
  });

  final bool isOnline;
  final double size;
  final bool showLabel;
  final bool withBorder;

  @override
  Widget build(BuildContext context) {
    final color = isOnline ? AppColors.online : AppColors.inkMuted;
    final dot = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: withBorder
            ? Border.all(color: Theme.of(context).colorScheme.surface, width: 2)
            : null,
      ),
    );

    if (!showLabel) return dot;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dot,
        const SizedBox(width: 6),
        Text(
          isOnline ? 'Online' : 'Offline',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}
