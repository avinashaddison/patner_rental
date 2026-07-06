import 'package:flutter/material.dart';

import 'package:companion_ranchi/core/theme/app_theme.dart';

/// Primary solid button with an integrated loading state. Use [AppButton.outline]
/// for the secondary (outlined) variant and [AppButton.text] for low-emphasis.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.expanded = true,
    this.variant = AppButtonVariant.solid,
    this.color,
  });

  const AppButton.outline({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.expanded = true,
    this.color,
  }) : variant = AppButtonVariant.outline;

  const AppButton.text({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.expanded = false,
    this.color,
  }) : variant = AppButtonVariant.text;

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final bool expanded;
  final AppButtonVariant variant;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final disabled = isLoading || onPressed == null;
    final child = _content(context);

    final Widget button;
    switch (variant) {
      case AppButtonVariant.solid:
        button = ElevatedButton(
          onPressed: disabled ? null : onPressed,
          style: color != null
              ? ElevatedButton.styleFrom(backgroundColor: color)
              : null,
          child: child,
        );
        break;
      case AppButtonVariant.outline:
        button = OutlinedButton(
          onPressed: disabled ? null : onPressed,
          style: color != null
              ? OutlinedButton.styleFrom(
                  foregroundColor: color,
                  side: BorderSide(color: color!, width: 1.4),
                )
              : null,
          child: child,
        );
        break;
      case AppButtonVariant.text:
        button = TextButton(
          onPressed: disabled ? null : onPressed,
          style: color != null
              ? TextButton.styleFrom(foregroundColor: color)
              : null,
          child: child,
        );
        break;
    }

    return expanded ? SizedBox(width: double.infinity, child: button) : button;
  }

  Widget _content(BuildContext context) {
    if (isLoading) {
      final indicatorColor =
          variant == AppButtonVariant.solid ? Colors.white : AppColors.primary;
      return SizedBox(
        height: 22,
        width: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2.4,
          valueColor: AlwaysStoppedAnimation(indicatorColor),
        ),
      );
    }
    if (icon == null) return Text(label);
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}

enum AppButtonVariant { solid, outline, text }
