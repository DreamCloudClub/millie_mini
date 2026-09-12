import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

@immutable
class ConversationReport {
  final String id;
  final String templateId;
  final String templateName; // Snapshot of name at time of report
  final Map<String, String> responses; // slotName -> captured response
  final DateTime startedAt;
  final DateTime? completedAt;
  final bool isComplete;

  const ConversationReport({
    required this.id,
    required this.templateId,
    required this.templateName,
    required this.responses,
    required this.startedAt,
    this.completedAt,
    required this.isComplete,
  });

  ConversationReport copyWith({
    String? id,
    String? templateId,
    String? templateName,
    Map<String, String>? responses,
    DateTime? startedAt,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    bool? isComplete,
  }) {
    return ConversationReport(
      id: id ?? this.id,
      templateId: templateId ?? this.templateId,
      templateName: templateName ?? this.templateName,
      responses: responses ?? this.responses,
      startedAt: startedAt ?? this.startedAt,
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
      isComplete: isComplete ?? this.isComplete,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'templateId': templateId,
      'templateName': templateName,
      'responses': responses,
      'startedAt': startedAt.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
      'isComplete': isComplete,
    };
  }

  factory ConversationReport.fromJson(Map<String, dynamic> json) {
    return ConversationReport(
      id: json['id'] as String,
      templateId: json['templateId'] as String,
      templateName: json['templateName'] as String,
      responses: Map<String, String>.from(json['responses'] as Map),
      startedAt: DateTime.parse(json['startedAt'] as String),
      completedAt: json['completedAt'] != null
          ? DateTime.parse(json['completedAt'] as String)
          : null,
      isComplete: json['isComplete'] as bool,
    );
  }

  factory ConversationReport.start({
    required String templateId,
    required String templateName,
  }) {
    return ConversationReport(
      id: const Uuid().v4(),
      templateId: templateId,
      templateName: templateName,
      responses: {},
      startedAt: DateTime.now(),
      isComplete: false,
    );
  }

  /// Add or update a response
  ConversationReport addResponse(String key, String value) {
    final newResponses = Map<String, String>.from(responses);
    newResponses[key] = value;
    return copyWith(responses: newResponses);
  }

  /// Mark as complete
  ConversationReport complete() {
    return copyWith(
      isComplete: true,
      completedAt: DateTime.now(),
    );
  }

  /// Get duration if completed
  Duration? get duration {
    if (completedAt == null) return null;
    return completedAt!.difference(startedAt);
  }
}
