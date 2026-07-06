import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:companion_ranchi/core/network/api_exception.dart';
import 'package:companion_ranchi/core/theme/app_theme.dart';
import 'package:companion_ranchi/features/settings/application/settings_providers.dart';
import 'package:companion_ranchi/features/settings/data/settings_repository.dart';
import 'package:companion_ranchi/shared/widgets/widgets.dart';

/// Lists the users this account has blocked (`GET /users/blocks`) and lets the
/// user unblock them (`DELETE /users/block/:blockedId`).
class BlockedUsersScreen extends ConsumerWidget {
  const BlockedUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocked = ref.watch(blockedUsersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Blocked users')),
      body: blocked.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(blockedUsersProvider),
        ),
        data: (users) {
          if (users.isEmpty) {
            return const EmptyView(
              icon: Icons.shield_outlined,
              title: 'No blocked users',
              message:
                  'People you block won\'t be able to message or book you, and '
                  'won\'t appear in your search results.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(blockedUsersProvider),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              itemCount: users.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) =>
                  _BlockedTile(user: users[index]),
            ),
          );
        },
      ),
    );
  }
}

class _BlockedTile extends ConsumerWidget {
  const _BlockedTile({required this.user});

  final BlockedUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unblockState = ref.watch(unblockControllerProvider);
    final isBusy = unblockState.isLoading;

    return ListTile(
      leading: UserAvatar(
        photoUrl: user.profilePhotoUrl,
        name: user.fullName,
        radius: 22,
      ),
      title: Text(
        user.fullName ?? 'Blocked user',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: user.createdAt != null
          ? Text('Blocked on ${_date(user.createdAt!)}')
          : null,
      trailing: OutlinedButton(
        onPressed: isBusy ? null : () => _confirmUnblock(context, ref),
        child: const Text('Unblock'),
      ),
    );
  }

  Future<void> _confirmUnblock(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Unblock ${user.fullName ?? 'this user'}?'),
        content: const Text(
          'They will be able to message and book you again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Unblock'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final ok =
        await ref.read(unblockControllerProvider.notifier).unblock(user.blockedId);
    if (!context.mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User unblocked.')),
      );
    } else {
      final error = ref.read(unblockControllerProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is ApiException ? error.message : 'Could not unblock.',
          ),
        ),
      );
    }
  }

  String _date(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
}
