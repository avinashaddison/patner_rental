import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:companion_ranchi/features/companion_dashboard/application/companion_dashboard_providers.dart';
import 'package:companion_ranchi/features/companion_dashboard/data/companion_dashboard_repository.dart';

/// UI state for the companion online presence toggle.
class OnlineState {
  const OnlineState({
    this.isOnline = false,
    this.isSaving = false,
    this.hydrated = false,
  });

  final bool isOnline;
  final bool isSaving;

  /// Whether the toggle has been seeded from the profile yet.
  final bool hydrated;

  OnlineState copyWith({bool? isOnline, bool? isSaving, bool? hydrated}) =>
      OnlineState(
        isOnline: isOnline ?? this.isOnline,
        isSaving: isSaving ?? this.isSaving,
        hydrated: hydrated ?? this.hydrated,
      );
}

/// Drives the `PATCH /companions/me/online` toggle. Optimistically flips the
/// switch, then reconciles with the server response (reverting on failure).
///
/// AutoDispose so it re-seeds from the freshly-loaded profile each time the
/// dashboard mounts, rather than holding a stale toggle across sessions.
class OnlineController extends AutoDisposeNotifier<OnlineState> {
  CompanionDashboardRepository get _repo =>
      ref.read(companionDashboardRepositoryProvider);

  @override
  OnlineState build() => const OnlineState();

  /// Seed the toggle from the loaded companion profile (only once, and never
  /// while a save is in flight, so optimistic updates are not clobbered).
  void hydrate(bool isOnline) {
    if (!state.hydrated && !state.isSaving) {
      state = state.copyWith(isOnline: isOnline, hydrated: true);
    }
  }

  /// Toggle and persist. Returns the new value; throws on network error after
  /// reverting the optimistic state.
  Future<bool> toggle(bool next) async {
    final previous = state.isOnline;
    state = state.copyWith(isOnline: next, isSaving: true);
    try {
      final saved = await _repo.setOnline(next);
      state = state.copyWith(isOnline: saved, isSaving: false);
      // The profile carries the canonical isOnline; refresh it.
      ref.invalidate(myCompanionProfileProvider);
      return saved;
    } catch (e) {
      state = state.copyWith(isOnline: previous, isSaving: false);
      rethrow;
    }
  }
}

final onlineControllerProvider =
    NotifierProvider.autoDispose<OnlineController, OnlineState>(
  OnlineController.new,
);
