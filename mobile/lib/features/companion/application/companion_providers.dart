import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:companion_ranchi/core/models/companion_model.dart';
import 'package:companion_ranchi/core/models/review_model.dart';
import 'package:companion_ranchi/features/companion/data/companion_repository.dart';

/// Keep an autoDispose provider's result cached for [d] after its last listener
/// drops, so the common browse loop (open profile → back → reopen) doesn't
/// refetch the slow backend every time. Bounded so data doesn't go stale.
void cacheFor(Ref ref, Duration d) {
  final link = ref.keepAlive();
  final timer = Timer(d, link.close);
  ref.onDispose(timer.cancel);
}

/// Full profile for a companion id (`GET /companions/:id`).
final companionProfileProvider =
    FutureProvider.autoDispose.family<CompanionModel, String>((ref, id) async {
  cacheFor(ref, const Duration(minutes: 3));
  final repo = ref.watch(companionRepositoryProvider);
  return repo.fetchProfile(id);
});

/// A short reviews preview shown on the profile screen. Falls back to any
/// reviews embedded in the profile payload when the dedicated call returns
/// nothing.
final companionReviewsPreviewProvider =
    FutureProvider.autoDispose.family<List<ReviewModel>, String>((ref, id) async {
  final repo = ref.watch(companionRepositoryProvider);
  final preview = await repo.fetchReviewsPreview(id);
  if (preview.isNotEmpty) return preview;

  // Fallback: reviews embedded in the full profile.
  final profile = await ref.watch(companionProfileProvider(id).future);
  return profile.reviews.take(3).toList(growable: false);
});
