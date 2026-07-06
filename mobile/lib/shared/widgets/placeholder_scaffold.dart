import 'package:flutter/material.dart';

import 'package:companion_ranchi/core/theme/app_theme.dart';

/// Thin placeholder body used by the skeleton screens that feature agents will
/// later replace with real implementations. Renders the screen title and a
/// short note so the app is navigable and compiles today.
class PlaceholderScaffold extends StatelessWidget {
  const PlaceholderScaffold({
    super.key,
    required this.title,
    this.subtitle,
    this.icon = Icons.construction_rounded,
    this.showAppBar = true,
    this.actions,
    this.bottom,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final bool showAppBar;
  final List<Widget>? actions;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: showAppBar
          ? AppBar(title: Text(title), actions: actions)
          : null,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  gradient: AppGradients.primary,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                ),
                child: Icon(icon, size: 44, color: Colors.white),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle ?? 'This screen is coming soon.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.inkMuted,
                    ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: bottom,
    );
  }
}
