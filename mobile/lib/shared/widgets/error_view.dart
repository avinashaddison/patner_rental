import 'package:flutter/material.dart';

import 'package:companion_ranchi/core/network/api_exception.dart';
import 'package:companion_ranchi/core/theme/app_theme.dart';

/// Error state with a retry action. Accepts a raw [Object] error and renders a
/// friendly message, unwrapping [ApiException] when possible.
class ErrorView extends StatelessWidget {
  const ErrorView({
    super.key,
    this.error,
    this.message,
    this.onRetry,
    this.icon = Icons.error_outline_rounded,
  });

  final Object? error;
  final String? message;
  final VoidCallback? onRetry;
  final IconData icon;

  String get _resolvedMessage {
    if (message != null) return message!;
    final err = error;
    if (err is ApiException) return err.message;
    if (err != null) return 'Something went wrong. Please try again.';
    return 'Something went wrong.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: AppColors.danger),
            ),
            const SizedBox(height: 20),
            Text(
              'Oops!',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _resolvedMessage,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.inkMuted,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
