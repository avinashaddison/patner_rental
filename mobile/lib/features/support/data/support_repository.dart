import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:companion_ranchi/core/models/json_utils.dart';
import 'package:companion_ranchi/core/network/api_client.dart';

/// A single message inside a support ticket thread (`ticket_messages`).
class TicketMessage {
  const TicketMessage({
    required this.id,
    required this.message,
    this.senderId,
    this.createdAt,
  });

  final String id;
  final String message;
  final String? senderId;
  final DateTime? createdAt;

  factory TicketMessage.fromJson(Map<String, dynamic> json) => TicketMessage(
        id: J.asString(json['id']),
        message: J.asString(json['message']),
        senderId: J.asStringOrNull(json['senderId']),
        createdAt: J.asDate(json['createdAt']),
      );
}

/// A support ticket (`support_tickets`) with its optional message thread.
class SupportTicket {
  const SupportTicket({
    required this.id,
    required this.subject,
    required this.description,
    required this.status,
    required this.priority,
    this.messages = const [],
    this.createdAt,
    this.updatedAt,
    this.resolvedAt,
  });

  final String id;
  final String subject;
  final String description;

  /// `OPEN` | `IN_PROGRESS` | `RESOLVED` | `CLOSED`.
  final String status;

  /// `LOW` | `MEDIUM` | `HIGH` | `URGENT`.
  final String priority;
  final List<TicketMessage> messages;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? resolvedAt;

  bool get isOpen => status == 'OPEN' || status == 'IN_PROGRESS';

  factory SupportTicket.fromJson(Map<String, dynamic> json) {
    final rawMessages = json['messages'];
    return SupportTicket(
      id: J.asString(json['id']),
      subject: J.asString(json['subject']),
      description: J.asString(json['description']),
      status: J.asString(json['status'], 'OPEN'),
      priority: J.asString(json['priority'], 'MEDIUM'),
      messages: (rawMessages is List ? rawMessages : const [])
          .whereType<Map>()
          .map((e) => TicketMessage.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false),
      createdAt: J.asDate(json['createdAt']),
      updatedAt: J.asDate(json['updatedAt']),
      resolvedAt: J.asDate(json['resolvedAt']),
    );
  }

  static String statusLabel(String status) {
    switch (status) {
      case 'OPEN':
        return 'Open';
      case 'IN_PROGRESS':
        return 'In progress';
      case 'RESOLVED':
        return 'Resolved';
      case 'CLOSED':
        return 'Closed';
      default:
        return status;
    }
  }

  static String priorityLabel(String priority) {
    switch (priority) {
      case 'LOW':
        return 'Low';
      case 'MEDIUM':
        return 'Medium';
      case 'HIGH':
        return 'High';
      case 'URGENT':
        return 'Urgent';
      default:
        return priority;
    }
  }
}

/// A single message in the live support chat (mapped server-side to a chat
/// shape with `isMine` / `role` so the UI doesn't need the user id).
class SupportChatMessage {
  const SupportChatMessage({
    required this.id,
    required this.message,
    required this.isMine,
    required this.role,
    this.createdAt,
  });

  final String id;
  final String message;
  final bool isMine;

  /// `USER` | `SUPPORT`.
  final String role;
  final DateTime? createdAt;

  factory SupportChatMessage.fromJson(Map<String, dynamic> json) =>
      SupportChatMessage(
        id: J.asString(json['id']),
        message: J.asString(json['message']),
        isMine: J.asBool(json['isMine']),
        role: J.asString(json['role'], 'SUPPORT'),
        createdAt: J.asDate(json['createdAt']),
      );
}

/// The live support chat thread (a single continuous conversation with staff).
class SupportChat {
  const SupportChat({this.ticketId, required this.status, required this.messages});

  final String? ticketId;
  final String status;
  final List<SupportChatMessage> messages;

  factory SupportChat.fromJson(Map<String, dynamic> json) => SupportChat(
        ticketId: J.asStringOrNull(json['ticketId']),
        status: J.asString(json['status'], 'OPEN'),
        messages: (json['messages'] is List ? json['messages'] as List : const [])
            .whereType<Map>()
            .map((e) => SupportChatMessage.fromJson(Map<String, dynamic>.from(e)))
            .toList(growable: false),
      );
}

/// Data access for the support domain (`/support/*`, API.md section 14).
class SupportRepository {
  SupportRepository(this._api);

  final ApiClient _api;

  // ---- Live support chat ----------------------------------------------------

  /// `GET /support/chat` → the signed-in user's live support chat thread.
  Future<SupportChat> fetchSupportChat() async {
    final data = await _api.getJson('/support/chat');
    return SupportChat.fromJson(J.asMap(data));
  }

  /// `POST /support/chat/messages` → send a message to support.
  Future<SupportChatMessage> sendSupportMessage(String message) async {
    final data = await _api.postJson(
      '/support/chat/messages',
      body: {'message': message},
    );
    final map = J.asMap(data);
    final messageJson = map['message'] is Map ? J.asMap(map['message']) : map;
    return SupportChatMessage.fromJson(messageJson);
  }

  /// `GET /support/tickets` → the signed-in user's tickets.
  Future<List<SupportTicket>> fetchTickets() async {
    final data = await _api.getJson('/support/tickets');
    final list = data is List
        ? data
        : (data is Map && data['items'] is List
            ? data['items'] as List
            : const []);
    return list
        .whereType<Map>()
        .map((e) => SupportTicket.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  /// `GET /support/tickets/:id` → a ticket with its message thread.
  Future<SupportTicket> fetchTicket(String id) async {
    final data = await _api.getJson('/support/tickets/$id');
    final map = J.asMap(data);
    final ticketJson = map['ticket'] is Map ? J.asMap(map['ticket']) : map;
    return SupportTicket.fromJson(ticketJson);
  }

  /// `POST /support/tickets` → open a new ticket.
  Future<SupportTicket> createTicket({
    required String subject,
    required String description,
    String? priority,
  }) async {
    final data = await _api.postJson(
      '/support/tickets',
      body: {
        'subject': subject,
        'description': description,
        if (priority != null) 'priority': priority,
      },
    );
    final map = J.asMap(data);
    final ticketJson = map['ticket'] is Map ? J.asMap(map['ticket']) : map;
    return SupportTicket.fromJson(ticketJson);
  }

  /// `POST /support/tickets/:id/messages` → reply on a ticket thread.
  Future<TicketMessage> postMessage({
    required String ticketId,
    required String message,
  }) async {
    final data = await _api.postJson(
      '/support/tickets/$ticketId/messages',
      body: {'message': message},
    );
    final map = J.asMap(data);
    final messageJson = map['message'] is Map ? J.asMap(map['message']) : map;
    return TicketMessage.fromJson(messageJson);
  }
}

/// App-wide [SupportRepository] provider, wired to the shared [ApiClient].
final supportRepositoryProvider = Provider<SupportRepository>((ref) {
  return SupportRepository(ref.watch(apiClientProvider));
});
