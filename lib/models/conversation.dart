import 'package:flutter/foundation.dart';

enum MessageRole {
  user,
  assistant,
  system,
}

@immutable
class ConversationMessage {
  final String id;
  final MessageRole role;
  final String content;
  final DateTime timestamp;

  const ConversationMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'role': role.name,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory ConversationMessage.fromJson(Map<String, dynamic> json) {
    return ConversationMessage(
      id: json['id'] as String,
      role: MessageRole.values.firstWhere(
        (e) => e.name == json['role'],
        orElse: () => MessageRole.user,
      ),
      content: json['content'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  /// Convert to format expected by LLM APIs
  Map<String, String> toLLMFormat() {
    return {
      'role': role.name,
      'content': content,
    };
  }
}

@immutable
class Conversation {
  final String id;
  final String agentId;
  final List<ConversationMessage> messages;
  final DateTime startedAt;
  final DateTime? endedAt;

  const Conversation({
    required this.id,
    required this.agentId,
    required this.messages,
    required this.startedAt,
    this.endedAt,
  });

  Conversation copyWith({
    String? id,
    String? agentId,
    List<ConversationMessage>? messages,
    DateTime? startedAt,
    DateTime? endedAt,
  }) {
    return Conversation(
      id: id ?? this.id,
      agentId: agentId ?? this.agentId,
      messages: messages ?? this.messages,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
    );
  }

  Conversation addMessage(ConversationMessage message) {
    return copyWith(
      messages: [...messages, message],
    );
  }

  /// Get messages in LLM API format
  List<Map<String, String>> toLLMMessages() {
    return messages.map((m) => m.toLLMFormat()).toList();
  }

  factory Conversation.start(String agentId) {
    return Conversation(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      agentId: agentId,
      messages: [],
      startedAt: DateTime.now(),
    );
  }
}

