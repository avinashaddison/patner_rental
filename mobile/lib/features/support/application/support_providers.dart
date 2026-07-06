import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:companion_ranchi/features/support/data/support_repository.dart';

/// The signed-in user's support tickets (`GET /support/tickets`).
final supportTicketsProvider =
    FutureProvider.autoDispose<List<SupportTicket>>((ref) async {
  final repo = ref.watch(supportRepositoryProvider);
  return repo.fetchTickets();
});

/// A single ticket with its message thread (`GET /support/tickets/:id`).
final ticketDetailProvider = FutureProvider.autoDispose
    .family<SupportTicket, String>((ref, ticketId) async {
  final repo = ref.watch(supportRepositoryProvider);
  return repo.fetchTicket(ticketId);
});

/// Creates a new support ticket and refreshes the list on success.
class CreateTicketController extends AutoDisposeAsyncNotifier<void> {
  SupportRepository get _repo => ref.read(supportRepositoryProvider);

  @override
  Future<void> build() async {}

  /// Returns the created [SupportTicket] on success, or null on failure.
  Future<SupportTicket?> submit({
    required String subject,
    required String description,
    String? priority,
  }) async {
    state = const AsyncLoading();
    try {
      final ticket = await _repo.createTicket(
        subject: subject,
        description: description,
        priority: priority,
      );
      ref.invalidate(supportTicketsProvider);
      state = const AsyncData(null);
      return ticket;
    } catch (e, st) {
      state = AsyncError(e, st);
      return null;
    }
  }
}

final createTicketControllerProvider =
    AutoDisposeAsyncNotifierProvider<CreateTicketController, void>(
  CreateTicketController.new,
);

/// Posts a reply on a ticket thread and refreshes that ticket on success.
class TicketReplyController extends AutoDisposeAsyncNotifier<void> {
  SupportRepository get _repo => ref.read(supportRepositoryProvider);

  @override
  Future<void> build() async {}

  Future<bool> send({
    required String ticketId,
    required String message,
  }) async {
    state = const AsyncLoading();
    try {
      await _repo.postMessage(ticketId: ticketId, message: message);
      ref.invalidate(ticketDetailProvider(ticketId));
      ref.invalidate(supportTicketsProvider);
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }
}

final ticketReplyControllerProvider =
    AutoDisposeAsyncNotifierProvider<TicketReplyController, void>(
  TicketReplyController.new,
);
