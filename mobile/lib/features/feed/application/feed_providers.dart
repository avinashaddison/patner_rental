import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:companion_ranchi/core/models/post_model.dart';
import 'package:companion_ranchi/core/models/post_comment_model.dart';
import 'package:companion_ranchi/features/companion/application/companion_providers.dart';
import 'package:companion_ranchi/features/companion_dashboard/application/companion_dashboard_providers.dart';
import 'package:companion_ranchi/features/feed/data/feed_repository.dart';

/// Following feed — posts from companions the signed-in user follows.
final feedProvider = FutureProvider.autoDispose<List<PostModel>>((ref) async {
  return ref.watch(feedRepositoryProvider).feed();
});

/// Explore feed — all published posts (discovery).
final exploreProvider =
    FutureProvider.autoDispose<List<PostModel>>((ref) async {
  return ref.watch(feedRepositoryProvider).explore();
});

/// A single companion's posts grid.
final companionPostsProvider = FutureProvider.autoDispose
    .family<List<PostModel>, String>((ref, companionId) async {
  return ref.watch(feedRepositoryProvider).companionPosts(companionId);
});

/// Single post detail.
final postDetailProvider =
    FutureProvider.autoDispose.family<PostModel, String>((ref, id) async {
  return ref.watch(feedRepositoryProvider).detail(id);
});

/// Comments for a post (newest first).
final postCommentsProvider = FutureProvider.autoDispose
    .family<List<PostComment>, String>((ref, postId) async {
  return ref.watch(feedRepositoryProvider).comments(postId);
});

/// Refresh every list that could contain [companionId]'s posts, plus that
/// companion's profile (so postCount/followerCount labels stay in sync).
/// Takes a [WidgetRef] — call it from screens/widgets after a mutation.
void invalidateFeeds(WidgetRef ref, {String? companionId}) {
  ref.invalidate(feedProvider);
  ref.invalidate(exploreProvider);
  // The companion dashboard reads its own post count from this provider.
  ref.invalidate(myCompanionProfileProvider);
  if (companionId != null) {
    ref.invalidate(companionPostsProvider(companionId));
    ref.invalidate(companionProfileProvider(companionId));
  }
}

/// Drives the post composer (multi-image upload + publish). The [AsyncValue]
/// tracks the in-flight publish so the UI can show progress + disable the button.
class PostComposeController extends StateNotifier<AsyncValue<void>> {
  PostComposeController(this._ref) : super(const AsyncData(null));

  final Ref _ref;

  /// Publishes a post. Returns the created [PostModel] on success, else null.
  /// The caller (a screen with a WidgetRef) is responsible for invalidating the
  /// feeds afterwards via [invalidateFeeds].
  Future<PostModel?> publish({
    String? caption,
    required List<File> images,
  }) async {
    state = const AsyncLoading();
    try {
      final post = await _ref
          .read(feedRepositoryProvider)
          .createPost(caption: caption, images: images);
      state = const AsyncData(null);
      return post;
    } catch (e, st) {
      state = AsyncError(e, st);
      return null;
    }
  }
}

final postComposeControllerProvider =
    StateNotifierProvider.autoDispose<PostComposeController, AsyncValue<void>>(
  (ref) => PostComposeController(ref),
);
