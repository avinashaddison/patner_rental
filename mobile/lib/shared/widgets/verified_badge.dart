import 'package:flutter/material.dart';

import 'package:companion_ranchi/core/theme/app_theme.dart';

/// Trust badge shown on verified companion profiles/cards. A companion is
/// "verified" only when APPROVED + KYC approved (SAFETY.md rule #4).
class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({
    super.key,
    this.label = 'Verified',
    this.compact = false,
  });

  final String label;

  /// Compact = just the check icon chip (for cards); full = icon + label.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Container(
        padding: const EdgeInsets.all(3),
        decoration: const BoxDecoration(
          color: AppColors.verified,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check, size: 12, color: Colors.white),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.verified.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        border: Border.all(color: AppColors.verified.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.verified_rounded,
              size: 14, color: AppColors.verified),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.verified,
            ),
          ),
        ],
      ),
    );
  }
}
