import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:companion_ranchi/core/constants/app_constants.dart';
import 'package:companion_ranchi/core/network/api_exception.dart';
import 'package:companion_ranchi/core/theme/app_theme.dart';
import 'package:companion_ranchi/features/safety/data/reports_repository.dart';
import 'package:companion_ranchi/features/settings/data/settings_repository.dart';

/// Shared trust-and-safety actions (Report / Block) that can be surfaced from
/// any screen showing another user — companion profile, chat, booking detail.
///
/// Backed by `POST /reports` and `POST /users/block`. Use [SafetyMenuButton] in
/// a standard AppBar, or [CircleSafetyButton] over a photo header.
Future<void> showSafetyActionsSheet(
  BuildContext context,
  WidgetRef ref, {
  required String userId,
  required String name,
  String? bookingId,
}) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _Grabber(),
          ListTile(
            leading: const Icon(Icons.flag_outlined, color: AppColors.danger),
            title: Text('Report $name'),
            subtitle: const Text(
              'Harassment, a fake profile, abuse or spam',
            ),
            onTap: () => Navigator.pop(ctx, 'report'),
          ),
          ListTile(
            leading: const Icon(Icons.block_rounded, color: AppColors.danger),
            title: Text('Block $name'),
            subtitle: const Text(
              "They won't be able to message or book you",
            ),
            onTap: () => Navigator.pop(ctx, 'block'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.close_rounded),
            title: const Text('Cancel'),
            onTap: () => Navigator.pop(ctx),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );

  if (!context.mounted) return;
  if (action == 'report') {
    await _openReportSheet(context, ref,
        userId: userId, name: name, bookingId: bookingId);
  } else if (action == 'block') {
    await _confirmBlock(context, ref, userId: userId, name: name);
  }
}

Future<void> _openReportSheet(
  BuildContext context,
  WidgetRef ref, {
  required String userId,
  required String name,
  String? bookingId,
}) async {
  final result = await showModalBottomSheet<({String category, String note})>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(ctx).viewInsets.bottom,
      ),
      child: _ReportSheet(name: name),
    ),
  );
  if (result == null || !context.mounted) return;

  try {
    await ref.read(reportsRepositoryProvider).createReport(
          reportedUserId: userId,
          category: result.category,
          description: result.note,
          bookingId: bookingId,
        );
    if (context.mounted) {
      _snack(context, 'Report submitted. Our team will review it.');
    }
  } catch (e) {
    if (context.mounted) {
      _snack(
        context,
        e is ApiException ? e.message : 'Could not submit the report.',
      );
    }
  }
}

Future<void> _confirmBlock(
  BuildContext context,
  WidgetRef ref, {
  required String userId,
  required String name,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Block $name?'),
      content: const Text(
        "They won't be able to message or book you, and they'll be hidden "
        'from your chats. You can unblock anytime from Settings.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Block'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;

  try {
    await ref.read(settingsRepositoryProvider).block(userId);
    if (context.mounted) _snack(context, 'You blocked $name.');
  } catch (e) {
    if (context.mounted) {
      _snack(context, e is ApiException ? e.message : 'Could not block $name.');
    }
  }
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// The report form: pick a category, add an optional note, submit. Pops a
/// `(category, note)` record on submit, or null on cancel.
class _ReportSheet extends StatefulWidget {
  const _ReportSheet({required this.name});

  final String name;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  final _note = TextEditingController();
  String? _category;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(child: _Grabber()),
            Text(
              'Report ${widget.name}',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            const Text(
              'Reports are confidential. Our safety team reviews every one.',
              style: TextStyle(color: AppColors.inkMuted, fontSize: 13),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text(
              'Reason',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final c in ReportCategories.all)
                  ChoiceChip(
                    label: Text(ReportCategories.label(c)),
                    selected: _category == c,
                    onSelected: (_) => setState(() => _category = c),
                    labelStyle: TextStyle(
                      color: _category == c ? Colors.white : null,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _note,
              minLines: 2,
              maxLines: 5,
              maxLength: 2000,
              decoration: const InputDecoration(
                labelText: 'What happened? (optional)',
                hintText: 'Add any details that help us review this.',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.danger),
                onPressed: _category == null
                    ? null
                    : () => Navigator.pop(
                          context,
                          (category: _category!, note: _note.text),
                        ),
                child: const Text('Submit report'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Grabber extends StatelessWidget {
  const _Grabber();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 4,
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.line,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

/// `more_vert` overflow button for standard AppBars that opens the safety sheet.
class SafetyMenuButton extends ConsumerWidget {
  const SafetyMenuButton({
    super.key,
    required this.userId,
    required this.name,
    this.bookingId,
    this.color,
  });

  final String userId;
  final String name;
  final String? bookingId;
  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      icon: Icon(Icons.more_vert_rounded, color: color),
      tooltip: 'Safety options',
      onPressed: () => showSafetyActionsSheet(
        context,
        ref,
        userId: userId,
        name: name,
        bookingId: bookingId,
      ),
    );
  }
}

/// Frosted circular safety button for use over a photo header (matches the
/// circular back button on the companion profile).
class CircleSafetyButton extends ConsumerWidget {
  const CircleSafetyButton({
    super.key,
    required this.userId,
    required this.name,
    this.bookingId,
  });

  final String userId;
  final String name;
  final String? bookingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Material(
        color: Colors.black.withValues(alpha: 0.38),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showSafetyActionsSheet(
            context,
            ref,
            userId: userId,
            name: name,
            bookingId: bookingId,
          ),
          child: const SizedBox(
            width: 40,
            height: 40,
            child: Icon(Icons.more_vert_rounded, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }
}
