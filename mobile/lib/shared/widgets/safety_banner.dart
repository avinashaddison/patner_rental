import 'package:flutter/material.dart';

import 'package:companion_ranchi/core/theme/app_theme.dart';

/// Reusable safety reminder strip surfaced on booking / profile / chat screens.
/// Reinforces the platform's hard rules (public places, companionship only,
/// 18+, no escort services) — SAFETY.md.
class SafetyBanner extends StatelessWidget {
  const SafetyBanner({
    super.key,
    this.message =
        'Meetings happen in public places only. This is a companionship service — '
            'no adult or escort services. Use SOS if you ever feel unsafe.',
    this.icon = Icons.shield_outlined,
  });

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.success),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: AppColors.success,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
