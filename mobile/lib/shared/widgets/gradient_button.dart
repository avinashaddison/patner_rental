import 'package:flutter/material.dart';

import 'package:companion_ranchi/core/theme/app_theme.dart';

/// Full-width primary CTA painted with the brand violet gradient. Used for the
/// most important action on a screen (Continue, Pay, Confirm booking).
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.trailingIcon,
    this.isLoading = false,
    this.gradient,
    this.height = 54,
    this.expanded = true,
    this.dimmed = false,
  });

  final String label;
  final VoidCallback? onPressed;

  /// Icon shown BEFORE the label.
  final IconData? icon;

  /// Icon shown AFTER the label (e.g. a "›" chevron on a Next button).
  final IconData? trailingIcon;
  final bool isLoading;
  final Gradient? gradient;
  final double height;
  final bool expanded;

  /// Looks disabled (grey, no glow) but stays TAPPABLE — so the tap handler
  /// can explain what's missing instead of silently ignoring the user.
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final disabled = isLoading || onPressed == null;
    final off = disabled || dimmed;

    final button = AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        gradient: off ? null : (gradient ?? AppGradients.primary),
        // Clearly-off grey when unusable, instead of a faded pink lookalike.
        color: off ? const Color(0xFFDCC9D1) : null,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        boxShadow: off
            ? null
            : [
                // Bright pink glow once the button becomes actionable.
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.55),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.25),
                  blurRadius: 40,
                  spreadRadius: 1,
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          onTap: disabled ? null : onPressed,
          child: Container(
            height: height,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _content(),
          ),
        ),
      ),
    );

    return expanded ? SizedBox(width: double.infinity, child: button) : button;
  }

  Widget _content() {
    if (isLoading) {
      return const SizedBox(
        height: 22,
        width: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2.4,
          valueColor: AlwaysStoppedAnimation(Colors.white),
        ),
      );
    }
    const style = TextStyle(
      color: Colors.white,
      fontSize: 16,
      fontWeight: FontWeight.w700,
    );
    if (icon == null && trailingIcon == null) {
      return Text(label, style: style);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            label,
            style: style,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (trailingIcon != null) ...[
          const SizedBox(width: 8),
          Icon(trailingIcon, color: Colors.white, size: 18),
        ],
      ],
    );
  }
}
